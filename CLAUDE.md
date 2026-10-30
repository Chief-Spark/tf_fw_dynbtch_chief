# Framework Batch dinamico (tf_fw_dynbtch_chief)

Infraestructura y codigo del Framework que orquesta los SP de Reconocer en
Redshift. Este repo **no tiene logica de negocio**: resuelve un archivo
disparador en S3, elige una definicion YAML y arma una Step Function que hace
`CALL` a los procedimientos.

Los tres repos de Reconocer que consume son `db_rcncr_btch_rdshft_{strct,pgm,dt}_full_delta`,
y su bitacora de negocio esta en el `CLAUDE.md` de cada uno.

## Reglas que no se negocian

1. **La firma de los orquestadores son 6 parametros VARCHAR**, en este orden:
   `in_solicitud`, `in_nit_suscriptor`, `in_path_archivo`, `in_nemotecnico`
   (= MODO), `in_id_facturacion` (= LOTE), `in_fecha_ejecucion` (= FECHA). Los
   tres primeros no se usan y aun asi forman parte de la firma. Lo fija
   `src/dynamicBatchBuilder/domain/services/step_function_definition_builder.py:93`, que construye el `CALL` posicional:
   cambiar el orden del `CALL` cambia el significado de cada parametro.
2. **Rama `claude/happy-einstein-k6okvc`.** Nunca empujar a otra sin permiso
   explicito.
3. **No crear pull requests** salvo peticion expresa.

## El nombre del archivo ES el que lleva los parametros

No hay un campo de configuracion. Todo sale del nombre del `.val` y de la
carpeta que lo contiene, via `FILE_NAME_PATTERN` y `FOLDER_PATTERN`
(`src/dynamicBatchMainBatchInitiator/domain/constants.py:5-6`):

```
FILE_NAME_PATTERN = r"([\D]+val)([\d]+)-([\d]+)-([\d]+)\.([\S]+)"
FOLDER_PATTERN    = r"([\S]*)([pePE]{2}[\d]+)([\S]*)"
```

| Trozo de `reconocerfullval1-20261028-2610.val` | Slot | Parametro |
|---|---|---|
| `reconocerfullval` | 4 | `in_nemotecnico` -> MODO |
| `1` | 1 | `in_solicitud` |
| `20261028` | 5 | `in_id_facturacion` -> LOTE |
| `2610` | 6 | `in_fecha_ejecucion` -> FECHA (YYMM) |

**DOS PARSERS COMPARTEN LA MISMA REGEX Y REPARTEN LOS GRUPOS DISTINTO**, y es la
trampa principal de este diseno: el Initiator **descarta** el grupo 3
(`dynamicBatchMainBatchInitiator/domain/parsers.py:38`) y el Builder lo lee como
`billing_id` (`dynamicBatchBuilder/domain/parsers.py:37`). Leer solo el Initiator
hace creer que el LOTE no viaja.

**La carpeta elige el YAML.** `FOLDER_PATTERN` exige `[pePE]{2}[\d]+` en la ruta
y el Builder busca la definicion como `f"{product_id}.yml"` (`src/dynamicBatchBuilder/handler.py:63`),
sin prefijo: el YAML va en la **raiz** del bucket de definiciones.

**Dos trampas de nombre ya pagadas en DEV:** `[\D]+` no admite digitos antes de
`val` (`reconocer1val` no casa), y la fecha es **YYMM y no MMYY** -- `0826` da
cadena vacia porque el mes 26 no existe.

**PERO LA VIA REAL SOLO HA CORRIDO EN FULL, Y ESO NO ESTABA ESCRITO.**
`run_reconocer_e2e_real_full.sql:60,63,69` pasa `'FULL'` en los tres `CALL`, de
modo que **el DELTA con dato real nunca ha corrido**: del modo incremental lo
unico ejercitado es el mock. Dos cosas antes de medirlo:

- **El watermark NO esta acotado por lote.** Se lee como
  `MAX(watermark_nuevo) WHERE estado = 'completado'`
  (`16_sp_unificacion_ciclo.sql:160-169`), de modo que un DELTA disparado desde
  el Framework con SU lote si ve la frontera que dejo el FULL de `deploy.par`.
  La medicion seria barata y el disparador ya existe:
  `dt/docs/framework_batch/reconocerdeltaval1-20261028-2610.val`.
  **PERO NO SE VA A MEDIR, Y ES DECISION, NO OLVIDO (usuario, 2026-10-30):**
  *"para datos reales solo tenemos datos de FULL y eso esta bien"*. Con dato
  real el alcance es la carga completa; el modo incremental queda certificado
  con el mock, que es donde se pueden provocar los cambios que lo prueban. Lo
  de esta vineta se queda escrito porque sigue siendo cierto el dia que se
  retome, no porque este abierto.
- **Un DELTA detras del FULL sobre dato que no se movio mide EL SUELO**, no la
  eficiencia: sin cambios en origen solo entra la rama `fecha IS NULL`. Es
  `NOV-UB-12` otra vez -- un DELTA en cero no prueba que no haya cambios --, asi
  que son dos cifras con etiqueta distinta y nunca una. La cifra CON cambios
  necesita que el datashare se mueva, y eso no lo controlamos nosotros. Razon
  estructural por la que el DELTA es mas barato, al margen del volumen: el FULL
  trunca `unificacion_direccion` en su paso 6 (`:204-214`) y el DELTA no.

## Los buckets, y de donde sale su nombre

`trunk/locals.tf:100,159,162`:

```
resource_prefix               = "${var.stage}-${local.account_id}-${var.project_name}"
s3_source_repository_name     = "${local.resource_prefix}-dynamic-batch-source-repository"
s3_definition_repository_name = "${local.resource_prefix}-dynamic-batch-definition-repository"
```

En DEV `stage = "dev"` y `project_name = "fwdynbtch"`, sobre la cuenta del
Framework `651706752126`. **Verificar en consola antes de subir**: el nombre es
derivado, no literal.

## EL BLOQUEO ABIERTO: el destino `RECONOCER` esta comentado

`develop/terraform.tfvars:79-89` trae el bloque escrito y **inactivo**:

```hcl
# RECONOCER = {
#   type            = "provisioned"
#   database        = "dba_rncr_batch"
#   cluster_id      = "eec-aws-us-eits-reconocerbatch-dev-redshift"
#   user            = "user_sp"
#   assume_role_arn = "arn:aws:iam::647096294147:role/BURoleFor-dev-647096294147-reconocerbatch-redshift-xacctRole"
#   ...
# }
```

Sin el, `pipeline: RECONOCER` no resuelve y el Builder cae al default `ALPHA`
(`src/dynamicBatchBuilder/domain/services/redshift_target_resolver.py:37`), que apunta a
`dba_batch` en la cuenta del propio Framework, **donde los SP de Reconocer no
existen**. El sintoma seria
`procedure bdm_datos.sp_unificacion_ciclo does not exist`.

Lo que hace falta: descomentar, que el rol remoto exista en `647096294147` y un
`terraform apply` sobre `develop`.

**Lo que NO es el problema, para no volver a investigarlo:** el cross-account si
esta soportado. `src/dynamicBatchBuilder/domain/services/step_function_definition_builder.py:263,290-291` resuelve el
`assume_role_arn` y lo inyecta como `state["Credentials"]`.

## El paralelismo: que permite el Framework y que no

**El Framework corre en paralelo los `procedimientos` del MISMO `nivel`, y en
serie los niveles.** Para la cadena de Reconocer eso hoy no sirve:

| Candidato | Paralelizable |
|---|---|
| Unificacion -> Ordenamiento -> Novedades | **No.** Ordenamiento lee la salida de Unificacion y Novedades filtra por el `orden_prioridad` que escribe Ordenamiento |
| Los cuatro `sp_ordenamiento_scoring_*_edf` | **Si en teoria** -- particiones disjuntas de `score_ordenamiento` por `canal` -- **pero no desde el YAML**: no llevan la firma de 6 VARCHAR y viven dentro de `sp_ordenamiento_ciclo` |

Exponerlos exige cuatro wrappers con la firma del Framework y partir el
orquestador en dos niveles, por ~25 s de ahorro sobre una cadena de 263 s.

## Convenciones

- **ASCII sin acentos** en este archivo, por consistencia con los tres repos de
  Reconocer, donde es obligatorio por el chequeo 2 de su `validar.sh`.
- Un hallazgo que no se escribe aqui se pierde al cerrar la sesion: el
  contenedor es efimero y la conversacion no viaja. Lo que se quiera conservar
  se commitea en el mismo turno en que se descubre.
