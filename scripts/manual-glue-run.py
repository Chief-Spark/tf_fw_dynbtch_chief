"""
Script para ejecución manual del proceso de copia a destino final + tracking en DynamoDB,
cuando los archivos ya están concatenados en el bucket de resultados.

Uso:
  python manual-glue-run.py

Requisitos:
  - Credenciales AWS configuradas (aws configure / SSO / env vars)
  - boto3 instalado (pip install boto3)
  - Permisos sobre S3 (source + destino), DynamoDB (business + object-tracking), y KMS

Este script hace lo mismo que la segunda mitad del Glue job output_merge.py:
  1. Lee la tabla business para resolver el destino S3 de cada archivo
  2. Copia los archivos concatenados al bucket destino final (cross-account)
  3. Actualiza la tabla object-tracking en DynamoDB
"""

import json
import re
import math
import time
import sys
from typing import List, Dict, Any, Tuple, Optional

import boto3
from botocore.exceptions import ClientError

# ============================================================================
# CONFIGURACIÓN - AJUSTAR SEGÚN EL CASO
# ============================================================================

# Bucket donde están los archivos ya concatenados
S3_SOURCE_BUCKET = "dev-651706752126-fwdynbtch-dynamic-batch-result-repository"

# Prefijo (carpeta) donde están los archivos concatenados
OUTPUT_BASE_PREFIX = "pp0989daviviendamensual"

# Nombre del producto en la tabla business (ej: "PP0989")
NOMBRE_PRODUCTO = "PP0989"

# ID del paquete para object-tracking (nombre del archivo .val sin extensión)
# Ejemplo: "PP0989daviviendamensual202506"
PAQUETE_ID = ""  # <-- COMPLETAR si se quiere actualizar object-tracking

# KMS_DESTINO y DESTINO salen de la tabla business (filas OUT). Sin regla, se omite el archivo.

# Tablas DynamoDB
BUSINESS_TABLE = "eec-aws-us-eits-procesosbatch-dev-business"
OBJECT_TRACKING_TABLE = "eec-aws-us-eits-procesosbatch-dev-object-tracking"

# Tabla de logs DynamoDB (para registrar la ejecución manual)
DYNAMO_LOGS_TABLE = "eec-aws-us-eits-procesosbatch-dev-fwdynbtch_logs"

# Región AWS
REGION = "us-east-1"

# Bucket del trigger (donde están .val/.inc)
S3_TRIGGER_BUCKET = "dev-651706752126-fwdynbtch-dynamic-batch-source-repository"
TRIGGER_KEY = ""  # Ej: "pp0989daviviendamensual/PP0989daviviendamensual202506.val"

# Modo dry-run: si es True, solo muestra qué haría sin ejecutar
DRY_RUN = True

# ============================================================================
# FIN CONFIGURACIÓN
# ============================================================================

MAX_TRACKING_RETRIES = 5


def setup_clients():
    session = boto3.session.Session(region_name=REGION)
    s3 = session.client("s3")
    dynamodb = session.resource("dynamodb", region_name=REGION)
    return s3, dynamodb


# ========== BUSINESS TABLE ==========

def cargar_reglas_out(tabla, producto: str) -> List[Dict[str, Any]]:
    reglas = []
    scan_kwargs = {
        "FilterExpression": "TIPO = :tipo AND NOMBRE_PRODUCTO = :prod",
        "ExpressionAttributeValues": {":tipo": "OUT", ":prod": producto},
    }
    while True:
        response = tabla.scan(**scan_kwargs)
        reglas.extend(response.get("Items", []))
        if "LastEvaluatedKey" not in response:
            break
        scan_kwargs["ExclusiveStartKey"] = response["LastEvaluatedKey"]
    return reglas


def resolver_regla_out(nombre_archivo: str, reglas: list) -> Optional[Dict[str, Any]]:
    for regla in reglas:
        pattern = regla.get("NOMBRE_ARCHIVO", "")
        if pattern and re.search(pattern, nombre_archivo):
            return regla
    return None


def parse_destino_bucket_prefix(destino_str: str) -> Tuple[str, str]:
    destino_str = destino_str.strip().strip("/")
    if not destino_str:
        raise ValueError("DESTINO vacío en regla de negocio")
    parts = destino_str.split("/", 1)
    return parts[0], parts[1] if len(parts) > 1 else ""


def build_destination_key(prefix: str, filename: str) -> str:
    if prefix:
        return f"{prefix.strip('/')}/{filename}"
    return filename


# ========== OBJECT TRACKING ==========

def parse_archivos_tracking(value):
    if not value:
        return []
    if isinstance(value, list):
        return list(value)
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, list) else []
        except json.JSONDecodeError:
            return []
    return []


def registrar_archivo_salida(tabla, regla_out, paquete_id, nombre_archivo):
    producto = regla_out.get("PRODUCTO", "")
    if not producto:
        print(f"  [WARN] Regla OUT sin PRODUCTO para tracking: {nombre_archivo}")
        return

    key = {"PRODUCTO": producto, "NOMBRE_ARCHIVO": paquete_id}
    origen_salida = str(regla_out.get("ORIGEN", "") or "").strip()
    destino_salida = str(regla_out.get("DESTINO", "") or "").strip()

    for attempt in range(1, MAX_TRACKING_RETRIES + 1):
        try:
            response = tabla.get_item(Key=key, ConsistentRead=True)
            item = response.get("Item")
            if not item:
                print(
                    f"  [WARN] object-tracking sin registro previo para {producto}/{paquete_id}. "
                    f"No se crea item nuevo para {nombre_archivo}."
                )
                return

            archivos_salida = parse_archivos_tracking(item.get("ARCHIVOS_SALIDA"))
            if nombre_archivo in archivos_salida:
                print(f"  [INFO] Archivo {nombre_archivo} ya registrado en object-tracking")
                return

            expected_revision = int(item.get("TRACKING_REVISION", 0))
            new_archivos = archivos_salida + [nombre_archivo]
            update_parts = [
                "ARCHIVOS_SALIDA = :archivos",
                "ARCHIVOS_RECIBIDOS_SALIDA = :recibidos",
                "ESTADO_SALIDA = :estado",
                "TRACKING_REVISION = :newrev",
            ]
            expression_values = {
                ":archivos": json.dumps(new_archivos, ensure_ascii=True),
                ":recibidos": len(new_archivos),
                ":estado": "COMPLETADO",
                ":expected_revision": expected_revision,
                ":newrev": expected_revision + 1,
                ":zero": 0,
            }
            if origen_salida:
                update_parts.append("ORIGEN_SALIDA = :origen_salida")
                expression_values[":origen_salida"] = origen_salida
            if destino_salida:
                update_parts.append("DESTINO_SALIDA = :destino_salida")
                expression_values[":destino_salida"] = destino_salida

            tabla.update_item(
                Key=key,
                UpdateExpression="SET " + ", ".join(update_parts),
                ConditionExpression=(
                    "TRACKING_REVISION = :expected_revision OR "
                    "(attribute_not_exists(TRACKING_REVISION) AND :expected_revision = :zero)"
                ),
                ExpressionAttributeValues=expression_values,
            )
            print(f"  [OK] object-tracking actualizado: {producto}/{paquete_id} -> {nombre_archivo}")
            return
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
                print(f"  [RETRY] Conflicto tracking intento {attempt}/{MAX_TRACKING_RETRIES}")
                time.sleep(0.2 * attempt)
                continue
            raise

    raise RuntimeError(f"No se pudo actualizar object-tracking tras {MAX_TRACKING_RETRIES} intentos")


# ========== S3 OPERATIONS ==========

def list_files_in_prefix(s3, bucket: str, prefix: str) -> List[str]:
    files = []
    prefix_clean = prefix.strip("/") + "/"
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix_clean):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if not key.endswith("/") and not key.endswith("_result.csv"):
                files.append(key)
    return files


def get_file_size(s3, bucket: str, key: str) -> int:
    response = s3.head_object(Bucket=bucket, Key=key)
    return response["ContentLength"]


def copy_file_to_destination(s3, source_bucket, source_key, dest_bucket, dest_key, kms_key_arn=""):
    max_copy_size = 5 * 1024 * 1024 * 1024  # 5GB
    file_size = get_file_size(s3, source_bucket, source_key)
    file_size_mb = file_size / 1024 / 1024

    if file_size >= max_copy_size:
        multipart_copy_large_file(
            s3, source_bucket, source_key, dest_bucket, dest_key, file_size, kms_key_arn
        )
    else:
        copy_args = {
            "CopySource": {"Bucket": source_bucket, "Key": source_key},
            "Bucket": dest_bucket,
            "Key": dest_key,
        }
        if kms_key_arn:
            copy_args["ServerSideEncryption"] = "aws:kms"
            copy_args["SSEKMSKeyId"] = kms_key_arn
        s3.copy_object(**copy_args)

    print(f"  [COPIED] s3://{source_bucket}/{source_key} -> s3://{dest_bucket}/{dest_key} ({file_size_mb:.2f} MB)")


def multipart_copy_large_file(s3, source_bucket, source_key, dest_bucket, dest_key, file_size, kms_key_arn=""):
    min_part_size = 100 * 1024 * 1024
    max_parts = 9500
    calculated_part_size = math.ceil(file_size / max_parts)
    part_size = max(min_part_size, calculated_part_size)
    part_size = math.ceil(part_size / (1024 * 1024)) * (1024 * 1024)

    upload_args = {"Bucket": dest_bucket, "Key": dest_key}
    if kms_key_arn:
        upload_args["ServerSideEncryption"] = "aws:kms"
        upload_args["SSEKMSKeyId"] = kms_key_arn

    mpu = s3.create_multipart_upload(**upload_args)
    upload_id = mpu["UploadId"]
    parts = []

    try:
        part_number = 1
        bytes_copied = 0
        while bytes_copied < file_size:
            start_byte = bytes_copied
            end_byte = min(bytes_copied + part_size - 1, file_size - 1)
            resp = s3.upload_part_copy(
                Bucket=dest_bucket,
                Key=dest_key,
                PartNumber=part_number,
                UploadId=upload_id,
                CopySource={"Bucket": source_bucket, "Key": source_key},
                CopySourceRange=f"bytes={start_byte}-{end_byte}",
            )
            parts.append({"PartNumber": part_number, "ETag": resp["CopyPartResult"]["ETag"]})
            bytes_copied += end_byte - start_byte + 1
            part_number += 1

        s3.complete_multipart_upload(
            Bucket=dest_bucket, Key=dest_key, UploadId=upload_id,
            MultipartUpload={"Parts": parts},
        )
    except Exception as e:
        s3.abort_multipart_upload(Bucket=dest_bucket, Key=dest_key, UploadId=upload_id)
        raise


# ========== DYNAMO LOGS (TRACKING DE EJECUCIÓN) ==========

def registrar_log_ejecucion(dynamodb, estado: str, mensaje: str, execution_uuid: str):
    """Registra en la tabla de logs que se hizo una ejecución manual."""
    from datetime import datetime, timezone

    tabla = dynamodb.Table(DYNAMO_LOGS_TABLE)
    now = datetime.now(timezone.utc)
    timestamp_str = now.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    date_str = now.strftime("%Y-%m-%d")

    item = {
        "PK": f"PROD#{NOMBRE_PRODUCTO}",
        "SK": f"{execution_uuid}#manualGlueRun#{timestamp_str}",
        "createdDate": date_str,
        "timeStampEvent": timestamp_str,
        "executionUUID": execution_uuid,
        "logMessage": mensaje,
        "resourceName": "manualGlueRun",
        "stateSFResult": estado,
        "finalState": estado == "SUCCESS",
    }

    if PAQUETE_ID:
        item["bizagiID"] = PAQUETE_ID

    tabla.put_item(Item=item)
    print(f"  [LOG] Registrado en DynamoDB logs: {estado} - {mensaje}")


# ========== MAIN ==========

def main():
    import uuid as uuid_mod

    print("=" * 70)
    print("EJECUCIÓN MANUAL - Copia a destino final + Tracking DynamoDB")
    print("=" * 70)
    print()
    print(f"  Source bucket:      s3://{S3_SOURCE_BUCKET}/{OUTPUT_BASE_PREFIX}/")
    print(f"  Producto:           {NOMBRE_PRODUCTO}")
    print(f"  Paquete ID:         {PAQUETE_ID or '(no configurado - sin object-tracking)'}")
    print(f"  Business table:     {BUSINESS_TABLE}")
    print(f"  Tracking table:     {OBJECT_TRACKING_TABLE}")
    print(f"  Logs table:         {DYNAMO_LOGS_TABLE}")
    print("  Destino/KMS:         DESTINO y KMS_DESTINO de Business_Table")
    print(f"  DRY_RUN:            {DRY_RUN}")
    print()

    s3, dynamodb = setup_clients()
    execution_uuid = str(uuid_mod.uuid4())

    # 1. Listar archivos en el prefijo
    print("[1/5] Listando archivos en el bucket de resultados...")
    files = list_files_in_prefix(s3, S3_SOURCE_BUCKET, OUTPUT_BASE_PREFIX)
    if not files:
        print("  [ERROR] No se encontraron archivos en el prefijo. Verificar la ruta.")
        return
    print(f"  Encontrados {len(files)} archivos:")
    for f in files:
        print(f"    - {f}")
    print()

    # 2. Cargar reglas business
    print("[2/5] Cargando reglas OUT de la tabla business...")
    use_business = bool(BUSINESS_TABLE and NOMBRE_PRODUCTO)
    reglas_out = []
    tabla_business = None
    tabla_tracking = None

    if use_business:
        tabla_business = dynamodb.Table(BUSINESS_TABLE)
        reglas_out = cargar_reglas_out(tabla_business, NOMBRE_PRODUCTO)
        print(f"  Cargadas {len(reglas_out)} reglas OUT para {NOMBRE_PRODUCTO}")
        for r in reglas_out:
            print(f"    ID={r.get('ID')} | NOMBRE_ARCHIVO={r.get('NOMBRE_ARCHIVO')} | DESTINO={r.get('DESTINO')}")
    else:
        print("  [ERROR] Sin tabla business: no hay DESTINO ni KMS_DESTINO. Abortando.")
        return
    print()

    tracking_enabled = bool(use_business and OBJECT_TRACKING_TABLE and PAQUETE_ID)
    if tracking_enabled:
        tabla_tracking = dynamodb.Table(OBJECT_TRACKING_TABLE)
        print(f"  Object tracking habilitado: {OBJECT_TRACKING_TABLE}")
    else:
        print(f"  [INFO] Object tracking deshabilitado (falta PAQUETE_ID o tabla)")
    print()

    # 3. Resolver destinos y mostrar plan
    print("[3/5] Resolviendo destinos para cada archivo...")
    plan = []
    for source_key in files:
        filename = source_key.split("/")[-1]
        dest_bucket = ""
        dest_prefix = ""
        regla = None

        if use_business and reglas_out:
            regla = resolver_regla_out(filename, reglas_out)
            if regla:
                destino_str = str(regla.get("DESTINO", "") or "").strip()
                if destino_str:
                    dest_bucket, dest_prefix = parse_destino_bucket_prefix(destino_str)
            else:
                print(f"  [SKIP] Sin regla OUT para: {filename}")
                continue

        if not dest_bucket:
            print(f"  [SKIP] DESTINO vacio para: {filename}")
            continue

        dest_key = build_destination_key(dest_prefix, filename)
        kms_key_arn = ""
        if regla:
            kms_key_arn = str(regla.get("KMS_DESTINO", "") or "").strip()
        if not kms_key_arn:
            print(f"  [SKIP] Sin KMS_DESTINO para: {filename}")
            continue
        plan.append({
            "source_key": source_key,
            "filename": filename,
            "dest_bucket": dest_bucket,
            "dest_key": dest_key,
            "regla": regla,
            "kms_key_arn": kms_key_arn,
        })
        print(f"  {filename} -> s3://{dest_bucket}/{dest_key} kms={kms_key_arn or '(sin KMS_DESTINO)'}")
    print()

    if DRY_RUN:
        print("=" * 70)
        print("DRY_RUN=True -> No se ejecutará ninguna acción.")
        print("Cambie DRY_RUN = False en el script para ejecutar de verdad.")
        print("=" * 70)
        return

    # 4. Ejecutar copias + tracking
    print("[4/5] Copiando archivos al destino final...")
    registrar_log_ejecucion(
        dynamodb, "STARTED",
        f"Ejecución manual iniciada: {len(files)} archivos desde {OUTPUT_BASE_PREFIX}",
        execution_uuid,
    )

    errores = []
    for item in plan:
        try:
            copy_file_to_destination(
                s3,
                S3_SOURCE_BUCKET,
                item["source_key"],
                item["dest_bucket"],
                item["dest_key"],
                item.get("kms_key_arn", ""),
            )
            # Actualizar tracking si está habilitado
            if tracking_enabled and item["regla"]:
                registrar_archivo_salida(tabla_tracking, item["regla"], PAQUETE_ID, item["filename"])
        except Exception as e:
            msg = f"Error copiando {item['filename']}: {e}"
            print(f"  [ERROR] {msg}")
            errores.append(msg)

    # 5. Registrar resultado en logs
    print()
    print("[5/5] Registrando resultado en DynamoDB logs...")
    if errores:
        registrar_log_ejecucion(
            dynamodb, "ERROR",
            f"Ejecución manual con {len(errores)} errores: {'; '.join(errores)}",
            execution_uuid,
        )
        print(f"\n  RESULTADO: {len(errores)} errores de {len(plan)} archivos")
    else:
        registrar_log_ejecucion(
            dynamodb, "SUCCESS",
            f"Ejecución manual exitosa: {len(plan)} archivos copiados desde {OUTPUT_BASE_PREFIX}",
            execution_uuid,
        )
        print(f"\n  RESULTADO: {len(plan)} archivos copiados exitosamente")

    # Copiar trigger artifacts (.val/.inc) si está configurado
    if TRIGGER_KEY:
        print("\n[EXTRA] Copiando trigger artifacts (.val/.inc)...")
        base_name = TRIGGER_KEY.rsplit(".", 1)[0]
        candidates = [TRIGGER_KEY, f"{base_name}.inc"]
        for key in candidates:
            filename = key.split("/")[-1]
            try:
                s3.head_object(Bucket=S3_TRIGGER_BUCKET, Key=key)
            except Exception:
                print(f"  [SKIP] No encontrado: s3://{S3_TRIGGER_BUCKET}/{key}")
                continue

            regla = resolver_regla_out(filename, reglas_out) if use_business else None
            if regla:
                destino_str = str(regla.get("DESTINO", "") or "").strip()
                dest_bucket, dest_prefix = parse_destino_bucket_prefix(destino_str)
            else:
                print(f"  [SKIP] Sin regla OUT para trigger {filename}")
                continue

            dest_key = build_destination_key(dest_prefix, filename)
            kms_key_arn = ""
            if regla:
                kms_key_arn = str(regla.get("KMS_DESTINO", "") or "").strip()
            if not kms_key_arn:
                print(f"  [SKIP] Sin KMS_DESTINO para trigger {filename}")
                continue
            try:
                copy_file_to_destination(
                    s3, S3_TRIGGER_BUCKET, key, dest_bucket, dest_key, kms_key_arn
                )
                if tracking_enabled and regla:
                    registrar_archivo_salida(tabla_tracking, regla, PAQUETE_ID, filename)
            except Exception as e:
                print(f"  [ERROR] Error copiando trigger artifact {key}: {e}")

    print("\n" + "=" * 70)
    print("EJECUCIÓN MANUAL COMPLETADA")
    print("=" * 70)


if __name__ == "__main__":
    main()
