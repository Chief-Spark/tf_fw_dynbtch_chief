"""
Redshift Target Resolver (Escenario C - multicluster genérico).

Este módulo centraliza la resolución del destino Redshift (cluster aprovisionado
o workgroup serverless) al que debe enviarse cada stored procedure.

Diseño retrocompatible:
- Si la variable de entorno REDSHIFT_TARGETS_JSON está presente y no vacía, se usa
  como registro de destinos.
- Si NO está presente, el registro se reconstruye a partir de las variables clásicas
  (ALPHA/NEDA/HYBRID). Esto preserva el comportamiento actual sin exigir cambios en
  la configuración de Terraform (tfvars) ni en los YAML existentes.

Resolución del destino para un step (en orden de prioridad):
  1. `pipeline` definido a nivel de procedimiento (por-step).
  2. `pipeline` definido a nivel de proceso (global del YAML).
  3. Destino por defecto: ALPHA (cluster aprovisionado), igual que hoy.

Cross-account:
- Si un destino define `assume_role_arn`, el builder agrega un campo `Credentials`
  al *state* (hermano de `Resource`/`Arguments`, no anidado dentro de `Arguments`;
  ASL no admite `Credentials` ahí). Step Functions asume ese rol (en la cuenta
  destino) antes de invocar el Data API, permitiendo ejecutar el SP en un
  cluster/workgroup de otra cuenta AWS. Sin `assume_role_arn` el comportamiento es
  same-account (sin cambios).
"""

import json
import logging

from config.config import settings

logger = logging.getLogger(__name__)

# Nombre del destino por defecto cuando el YAML no especifica `pipeline`.
# Mantiene el comportamiento histórico (cluster aprovisionado).
DEFAULT_TARGET_NAME = "ALPHA"

# Tipos de destino soportados
TYPE_PROVISIONED = "provisioned"
TYPE_SERVERLESS = "serverless"


class RedshiftTargetError(Exception):
    """Error al resolver o validar un destino Redshift."""


def _build_registry_from_settings() -> dict:
    """
    Reconstruye el registro de destinos a partir de las variables clásicas.

    Se usa como fallback cuando REDSHIFT_TARGETS no está configurado, garantizando
    que el sistema siga comportándose exactamente como antes (ALPHA/NEDA/HYBRID).

    Los destinos serverless (NEDA/HYBRID) solo se incluyen si tienen workgroup y
    database definidos, para no generar entradas inválidas en entornos que no los usan.
    """
    registry: dict = {
        DEFAULT_TARGET_NAME: {
            "type": TYPE_PROVISIONED,
            "database": settings.redshift_database,
            "cluster_id": settings.redshift_cluster_id,
            "user": settings.redshift_user,
        }
    }

    if settings.redshift_workgroup_name_neda and settings.redshift_database_neda:
        registry["NEDA"] = {
            "type": TYPE_SERVERLESS,
            "database": settings.redshift_database_neda,
            "workgroup_name": settings.redshift_workgroup_name_neda,
        }

    if settings.redshift_workgroup_name_hybrid and settings.redshift_database_hybrid:
        registry["HYBRID"] = {
            "type": TYPE_SERVERLESS,
            "database": settings.redshift_database_hybrid,
            "workgroup_name": settings.redshift_workgroup_name_hybrid,
        }

    return registry


def _normalize_registry(raw: dict) -> dict:
    """
    Normaliza las claves del registro a MAYÚSCULAS para que la resolución del
    `pipeline` sea case-insensitive (igual que el código original que hacía
    `.upper()` sobre el pipeline).
    """
    return {str(name).upper(): cfg for name, cfg in raw.items()}


def load_target_registry() -> dict:
    """
    Carga el registro de destinos Redshift.

    Returns:
        dict: mapa {NOMBRE_MAYUS: config_dict}.
    """
    raw_json = (settings.redshift_targets_json or "").strip()
    if not raw_json:
        registry = _build_registry_from_settings()
        logger.info(
            "REDSHIFT_TARGETS no configurado; usando registro derivado de settings: %s",
            list(registry.keys()),
        )
        return _normalize_registry(registry)

    try:
        parsed = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        raise RedshiftTargetError(
            f"REDSHIFT_TARGETS no es un JSON válido: {exc}"
        ) from exc

    if not isinstance(parsed, dict) or not parsed:
        raise RedshiftTargetError(
            "REDSHIFT_TARGETS debe ser un objeto JSON no vacío (mapa de destinos)."
        )

    registry = _normalize_registry(parsed)

    # Garantiza que siempre exista el destino por defecto para no romper YAMLs
    # sin `pipeline`. Si el JSON no lo trae, se deriva de las variables clásicas.
    if DEFAULT_TARGET_NAME not in registry:
        fallback = _normalize_registry(_build_registry_from_settings())
        registry[DEFAULT_TARGET_NAME] = fallback[DEFAULT_TARGET_NAME]

    logger.info("REDSHIFT_TARGETS cargado; destinos: %s", list(registry.keys()))
    return registry


def resolve_target_name(step_pipeline, process_pipeline) -> str:
    """
    Resuelve el nombre del destino según la prioridad definida.

    Args:
        step_pipeline: valor de `pipeline` a nivel de procedimiento (o None).
        process_pipeline: valor de `pipeline` a nivel de proceso (o None).

    Returns:
        str: nombre del destino en MAYÚSCULAS.
    """
    chosen = step_pipeline or process_pipeline or DEFAULT_TARGET_NAME
    return str(chosen).strip().upper()


def build_redshift_arguments(
    registry: dict, target_name: str, stored_procedure_call: str
) -> dict:
    """
    Construye los Arguments para redshiftdata:executeStatement según el destino.

    Args:
        registry (dict): registro de destinos ya normalizado.
        target_name (str): nombre del destino resuelto (MAYÚSCULAS).
        stored_procedure_call (str): SQL/CALL a ejecutar.

    Returns:
        dict: Arguments para el estado de Step Functions.
    """
    target = registry.get(target_name)
    if target is None:
        raise RedshiftTargetError(
            f"El destino Redshift '{target_name}' no existe en el registro. "
            f"Destinos disponibles: {sorted(registry.keys())}"
        )

    target_type = str(target.get("type", TYPE_PROVISIONED)).lower()

    arguments = {
        "Sql": stored_procedure_call,
        "WithEvent": True,
    }

    if target_type == TYPE_SERVERLESS:
        arguments["Database"] = target["database"]
        arguments["WorkgroupName"] = target["workgroup_name"]
    elif target_type == TYPE_PROVISIONED:
        arguments["Database"] = target["database"]
        arguments["ClusterIdentifier"] = target["cluster_id"]
        arguments["DbUser"] = target["user"]
    else:
        raise RedshiftTargetError(
            f"Tipo de destino Redshift no soportado para '{target_name}': '{target_type}'. "
            f"Use '{TYPE_PROVISIONED}' o '{TYPE_SERVERLESS}'."
        )

    return arguments


def get_assume_role_arn(registry: dict, target_name: str) -> str | None:
    """
    Devuelve el `assume_role_arn` del destino (o None si es same-account).

    Cross-account: Step Functions debe asumir este rol (en la cuenta destino)
    antes de invocar el Data API. El valor se coloca en el campo `Credentials`
    del *state*, hermano de `Resource`/`Arguments` (nunca dentro de `Arguments`,
    ASL rechaza `Credentials` ahí con SCHEMA_VALIDATION_FAILED).

    Args:
        registry (dict): registro de destinos ya normalizado.
        target_name (str): nombre del destino resuelto (MAYÚSCULAS).

    Returns:
        str | None: ARN del rol a asumir, o None si el destino es same-account.
    """
    target = registry.get(target_name)
    if target is None:
        raise RedshiftTargetError(
            f"El destino Redshift '{target_name}' no existe en el registro. "
            f"Destinos disponibles: {sorted(registry.keys())}"
        )

    assume_role_arn = (target.get("assume_role_arn") or "").strip()
    return assume_role_arn or None
