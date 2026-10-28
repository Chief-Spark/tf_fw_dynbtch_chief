#!/usr/bin/env python3
"""Verifica definiciones de proceso contra las regex REALES del Builder.

El Builder hace yaml.safe_load y accede a las claves directamente: no hay
validacion de esquema en ninguna parte, asi que una definicion mal formada no
se descubre hasta que un .val la dispara en DEV. Este script adelanta esos
fallos.

Importa constants.py del propio framework y no una transcripcion: si el
Builder cambia una regex, este chequeo cambia con ella.

Comprueba, por cada definicion:
  * que las claves que el Builder lee con acceso directo existen
  * que ninguna clave de procedimientos es desconocida (step_type, job_name y
    compania no existen: el Builder renderiza TODO procedimiento como un
    executeStatement de Redshift, y sin step_procedure muere con KeyError)
  * que el fichero es alcanzable: FOLDER_PATTERN sobre directorio.ruta tiene
    que devolver el product_id, que es el nombre del fichero
  * que salidas.aplica y salidas.carpetas permiten que el Glue corra
  * que cada origen casa ORIGIN_FOLDER_SUFFIX_PATTERN y produce una carpeta
    que casa GLUE_FOLDER_PATTERN
  * que cabeceras es true, que es lo que corresponde a un UNLOAD con HEADER
  * que cada step_procedure existe como CREATE en el paquete pgm indicado

Uso:
    python3 scripts/verificar_definiciones.py . <ruta_al_repo_pgm> [CODIGO ...]

Sin codigos, verifica los siete de la Explotacion Reconocer.
"""
import os
import re
import sys

import yaml

FW = sys.argv[1]
PGM = sys.argv[2]
sys.path.insert(0, os.path.join(FW, "src/dynamicBatchBuilder"))
from domain.constants import (FOLDER_PATTERN, GLUE_FOLDER_PATTERN,   # noqa: E402
                              ORIGIN_FOLDER_SUFFIX_PATTERN,
                              SOURCE_FOLDER_PATTERN, FILE_NAME_PATTERN)

# Un .val de ejemplo, con el mismo nemotecnico que usan los runners del repo dt
VAL = "reconocerval1-20261028-2610.val"
fallos = []

# Procedimientos realmente creados en el paquete pgm
creados = set()
for raiz, _, ficheros in os.walk(os.path.join(PGM, "deploy/redshift/SQL")):
    for f in ficheros:
        with open(os.path.join(raiz, f), encoding="utf-8") as fichero:
            for m in re.finditer(r"CREATE OR REPLACE PROCEDURE\s+([a-z0-9_.]+)\(",
                                 fichero.read(), re.IGNORECASE):
                creados.add(m.group(1).lower())

m_val = re.match(FILE_NAME_PATTERN, VAL)
if not m_val:
    raise SystemExit(f"el .val de ejemplo no casa FILE_NAME_PATTERN: {VAL}")
client_id, execution_id, billing_id, year_month, _ = m_val.groups()
print(f"  .val de ejemplo {VAL} -> client_id={client_id} solicitud={execution_id} "
      f"facturacion={billing_id} fecha={year_month}\n")

CODIGOS = sys.argv[3:] or [f"PP50000{n}" for n in range(1, 8)]

for codigo in CODIGOS:
    ruta_yml = os.path.join(FW, "src/dynamicProcessDefinitions", f"{codigo}.yml")
    with open(ruta_yml, encoding="utf-8") as fichero:
        cfg = yaml.safe_load(fichero)          # igual que el Builder

    # Las claves que el Builder lee con acceso directo: si faltan, KeyError
    procesos = cfg["procesos"]
    niveles = procesos["niveles"]
    procesos["directorio"]["ruta"]
    salidas = procesos["salidas"]
    pasos = []
    for nivel in niveles:
        nivel["nivel"]
        for proc in nivel.get("procedimientos", []):
            proc["step_name"]
            pasos.append(proc["step_procedure"])

    # El fichero tiene que ser alcanzable: product_id sale de la carpeta
    m = re.search(FOLDER_PATTERN, procesos["directorio"]["ruta"])
    if not m or m.group(2).upper() != codigo:
        fallos.append(f"{codigo}: la ruta {procesos['directorio']['ruta']!r} no "
                      f"resuelve el product_id {codigo}")

    # Claves que el Builder NO conoce y que romperian el render
    for nivel in niveles:
        for proc in nivel.get("procedimientos", []):
            desconocidas = set(proc) - {"step_name", "step_procedure",
                                        "step_description", "pipeline"}
            if desconocidas:
                fallos.append(f"{codigo}: claves que el Builder ignora o "
                              f"rompen: {sorted(desconocidas)}")

    if not salidas.get("aplica"):
        fallos.append(f"{codigo}: salidas.aplica es falso, el Glue no correria")
    if not salidas.get("carpetas"):
        fallos.append(f"{codigo}: sin salidas.carpetas, el Glue no correria")

    sufijos = []
    for carpeta in salidas.get("carpetas", []):
        origen = carpeta["origen"]
        if not re.search(ORIGIN_FOLDER_SUFFIX_PATTERN, origen):
            fallos.append(f"{codigo}: origen {origen!r} no casa "
                          f"ORIGIN_FOLDER_SUFFIX_PATTERN -> FolderPathSuffixBuildError")
            continue
        sufijo = "".join(re.findall(SOURCE_FOLDER_PATTERN, origen))
        carpeta_glue = (f"mergeTemp/{client_id}{execution_id}-{billing_id}-"
                        f"{year_month}_{sufijo}")
        if not re.fullmatch(GLUE_FOLDER_PATTERN, carpeta_glue):
            fallos.append(f"{codigo}: {carpeta_glue!r} no casa GLUE_FOLDER_PATTERN")
        if carpeta.get("cabeceras") is not True:
            fallos.append(f"{codigo}: {origen} sin cabeceras: true, "
                          f"pero el UNLOAD lleva HEADER")
        sufijos.append((sufijo, carpeta_glue))

    faltan = [p for p in pasos if p.lower() not in creados]
    estado = "PENDIENTE" if faltan else "OK"
    print(f"  {estado:9s} {codigo}.yml  {len(pasos)} pasos, {len(sufijos)} salidas")
    for sufijo, carpeta_glue in sufijos:
        print(f"            {sufijo:20s} -> {carpeta_glue}/")
    if faltan:
        print(f"            procedimientos sin CREATE en pgm: {faltan}")

print()
if fallos:
    print("\n".join(f"FALLO : {f}" for f in fallos))
    raise SystemExit(1)
print(f"{len(CODIGOS)} definicion(es) pasan las regex del Builder y el "
      f"contrato de carpetas del Glue")
