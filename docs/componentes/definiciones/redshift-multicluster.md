# Enrutamiento Multicluster de Redshift (`pipeline` / `redshift_targets`)

## Metadata

- **Documento**: Enrutamiento multicluster de Redshift en definiciones YAML
- **Versión**: 1.0
- **Estado**: Retrocompatible (opt-in)

## Resumen

El framework permite enrutar cada stored procedure a un destino Redshift distinto
(cluster aprovisionado o workgroup serverless). El destino se selecciona con el campo
opcional `pipeline` en el YAML de definición del proceso.

Todo es **retrocompatible**: si no se define `pipeline` en el YAML ni se configura la
variable Terraform `redshift_targets`, el comportamiento es idéntico al histórico y
todos los procedimientos se ejecutan en el cluster aprovisionado por defecto (`ALPHA`).

## Modelo de resolución del destino

Para cada procedimiento, el destino se resuelve con esta prioridad:

1. `pipeline` a nivel de **procedimiento** (por-step).
2. `pipeline` a nivel de **proceso** (global del YAML).
3. Destino por defecto: **`ALPHA`** (cluster aprovisionado).

La comparación del nombre es **insensible a mayúsculas** (`neda`, `NEDA` y `Neda` son
equivalentes).

## Uso en el YAML

### Sin `pipeline` (comportamiento actual, sin cambios)

```yaml
procesos:
  directorio:
    ruta: PP0307
  niveles:
    - nivel: 1
      procedimientos:
        - step_name: "crear_tabla"
          step_procedure: bdm_datos.sp_crear_tabla
  salidas:
    aplica: false
```

Resultado: todos los steps se ejecutan en `ALPHA`.

### `pipeline` global (todos los steps al mismo destino)

```yaml
procesos:
  pipeline: NEDA          # <- opcional; aplica a todos los procedimientos
  directorio:
    ruta: PP0307
  niveles:
    - nivel: 1
      procedimientos:
        - step_name: "crear_tabla"
          step_procedure: bdm_datos.sp_crear_tabla
  salidas:
    aplica: false
```

### `pipeline` por-step (cada procedimiento a un destino distinto)

```yaml
procesos:
  pipeline: ALPHA         # <- destino por defecto del proceso
  directorio:
    ruta: PP0307
  niveles:
    - nivel: 1
      procedimientos:
        - step_name: "cargar_datos"
          step_procedure: bdm_datos.sp_cargar
          # sin pipeline -> hereda ALPHA del proceso
        - step_name: "calcular_analitica"
          step_procedure: bdm_datos.sp_calcular
          pipeline: ANALYTICS   # <- este step va a un destino distinto
  salidas:
    aplica: false
```

El `pipeline` del procedimiento **gana** sobre el del proceso.

## Configuración de destinos (Terraform)

Existen dos formas de definir los destinos disponibles:

### 1. Destinos clásicos (por defecto, sin configuración extra)

Si **no** se define la variable `redshift_targets`, el framework deriva automáticamente
los destinos `ALPHA`, `NEDA` y `HYBRID` a partir de las variables existentes
(`redshift_*`, `redshift_*_neda`, `redshift_*_hybrid`). No requiere cambios en `tfvars`.

Valores de `pipeline` válidos en este modo: `ALPHA`, `NEDA`, `HYBRID`.

### 2. Registro genérico `redshift_targets` (multicluster N destinos)

Para agregar destinos adicionales o personalizados sin tocar código, se define el mapa
`redshift_targets` en `terraform.tfvars`. Las **claves** del mapa son los valores válidos
de `pipeline`.

```hcl
redshift_targets = {
  ALPHA = {
    type       = "provisioned"
    database   = "dba_batch"
    cluster_id = "eec-aws-us-eits-procesosbatch-dev-redshift"
    user       = "user_sp"
    # ARNs para permisos IAM (GetClusterCredentials)
    database_arn      = "arn:aws:redshift:us-east-1:651706752126:dbname:*/dba_batch"
    database_user_arn = "arn:aws:redshift:us-east-1:651706752126:dbuser:*/user_sp"
  }

  ANALYTICS = {
    type           = "serverless"
    database       = "dba_analytics"
    workgroup_name = "analytics-wg"
    # ARNs para permisos IAM (GetCredentials/GetWorkgroup)
    workgroup_arn     = "arn:aws:redshift-serverless:us-east-1:651706752126:workgroup/xxxx"
    database_arn      = "arn:aws:redshift-serverless:us-east-1:651706752126:dbname:*/dba_analytics"
    database_user_arn = "arn:aws:redshift-serverless:us-east-1:651706752126:dbuser:*/user_sp"
    namespace_arn     = "arn:aws:redshift-serverless:us-east-1:651706752126:namespace/yyyy" # opcional
  }
}
```

Notas:

- Si el mapa está vacío (`{}`, valor por defecto), se usa el modo clásico.
- Se recomienda incluir siempre la clave `ALPHA`. Si no se incluye, el framework la
  agrega automáticamente derivándola de las variables clásicas para no romper los YAML
  sin `pipeline`.
- Los campos `*_arn` se usan **solo** para construir permisos IAM dinámicos; no se
  envían a la Lambda ni a la Step Function.

### Campos por tipo de destino

| Campo            | `provisioned` | `serverless` |
|------------------|:-------------:|:------------:|
| `type`           | requerido     | requerido    |
| `database`       | requerido     | requerido    |
| `cluster_id`     | requerido     | —            |
| `user`           | requerido     | —            |
| `workgroup_name` | —             | requerido    |

Estos requisitos se validan en Terraform (`variables.tf`).

## Destinos en otra cuenta AWS (cross-account)

El framework puede ejecutar stored procedures en un cluster o workgroup que vive en
**otra cuenta AWS**. Esto se logra con el campo opcional `assume_role_arn` en el destino:
la Step Function asume ese rol (en la cuenta destino) mediante `Credentials.RoleArn`
antes de invocar el Data API. No se requiere ninguna Lambda proxy adicional.

Si `assume_role_arn` está vacío o no se define, el destino es **same-account** (el
comportamiento por defecto, sin cambios).

### Referencia: `framework_stage` por ambiente

Al desplegar el rol cross-account, usa **siempre** uno de estos valores para
`framework_stage` (indexa los mapas del Framework). Úsalo aunque el token del rol en la
cuenta destino (`var.stage`) sea distinto (p. ej. `pro`):

| Ambiente Framework | `framework_stage` | Cuenta AWS Framework |
|--------------------|:-----------------:|----------------------|
| develop            | `dev`             | 651706752126         |
| qa                 | `qa`              | 124355679563         |
| demo               | `stg`             | 311141534073         |
| production         | `prd`             | 324037294240         |

> Si `framework_stage` se deja vacío, hereda el valor de `var.stage`. Solo funciona
> correctamente cuando ambos tokens coinciden; si difieren, define `framework_stage`
> explícitamente con uno de los valores de la tabla.

### 1. Definir el destino cross-account (tfvars)

```hcl
redshift_targets = {
  # ... ALPHA/NEDA/HYBRID same-account ...

  REMOTO = {
    type           = "serverless"
    database       = "dba_remota"
    workgroup_name = "remota-wg"
    # Rol a asumir en la CUENTA DESTINO (999999999999)
    assume_role_arn = "arn:aws:iam::999999999999:role/BURoleFor-...-redshift-crossaccount"
    # ARNs opcionales del recurso remoto (para trazabilidad; los permisos reales
    # sobre el cluster los concede el rol remoto, no el rol local).
    workgroup_arn = "arn:aws:redshift-serverless:us-east-1:999999999999:workgroup/zzzz"
    database_arn  = "arn:aws:redshift-serverless:us-east-1:999999999999:dbname:*/dba_remota"
  }
}
```

En el YAML del proceso se usa igual que cualquier otro destino: `pipeline: REMOTO`.

### 2. Rol remoto en la cuenta destino (requisito)

> **Terraform listo para usar:** hay un archivo autocontenido en
> [`examples/redshift-crossaccount-role.tf`](examples/redshift-crossaccount-role.tf)
> que crea este rol con su trust policy y permisos de Data API. Se despliega en la
> cuenta destino y su output `assume_role_arn` es el valor a colocar en el destino.
> Sigue la **misma estructura que los roles del repo**: usa el módulo interno
> `eits-tf-aws-iam` (no `aws_iam_role` nativo), con prefijo `BURoleFor`, permissions
> boundary y `policy_documents`. Requiere acceso al módulo interno (code.experian.local).
>
> El rol `child_batch` del Framework (el que asume el rol remoto) se selecciona por
> `framework_stage` desde un mapa de **ARN completos por ambiente**. Se usa el ARN literal
> (no se reconstruye) porque el **token de stage dentro del nombre del rol puede diferir**.
> Si el nombre real difiere, edita el mapa o usa `framework_child_batch_role_arn_override`.
>
> **Dos stages independientes** en la plantilla:
> - `var.stage`: NOMBRA el rol local en la cuenta destino (usa el token de esa cuenta, p. ej. `pro`).
> - `var.framework_stage`: INDEXA los mapas del Framework (dev/qa/stg/prd) y los nombres de
>   sus buckets/KMS. Si se omite, toma el valor de `var.stage`.
>
> Ejemplo producción con tokens distintos (destino usa `pro`, Framework usa `prd`):
> `-var 'stage=pro' -var 'framework_stage=prd'`.

En la cuenta destino debe existir un rol con:

- **Trust policy** que confíe en el rol `child_batch` de la cuenta del framework:

  ```json
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::<CUENTA_FRAMEWORK>:role/BURoleFor-<stage>-<CUENTA_FRAMEWORK>-<project>-chldbtchRole" },
      "Action": "sts:AssumeRole"
    }]
  }
  ```

- **Permisos de Data API** sobre su propio cluster/workgroup:
  `redshift-data:ExecuteStatement`, `DescribeStatement`, y las credenciales
  correspondientes (`redshift:GetClusterCredentials` para provisioned o
  `redshift-serverless:GetCredentials` + `GetWorkgroup` para serverless).

### 3. Qué hace el framework automáticamente (dinámico por N destinos)

Todo lo siguiente se genera para **cada** `assume_role_arn` presente en `redshift_targets`,
sin listas manuales (usa `local.redshift_targets_assume_role_arns`):

- Agrega `Credentials.RoleArn` a los Arguments del `executeStatement` para ese destino.
- Concede `sts:AssumeRole` al rol `child_batch` (local) sobre los `assume_role_arn`.
- **Autoriza los roles remotos en las bucket policies del framework**:
  - `source-repository`: lectura (para `COPY`) — statement `AllowRedshiftTargetsCrossAccountRead`.
  - `result-repository`: lectura/escritura (para `UNLOAD`) — statement `AllowRedshiftTargetsCrossAccountRW`.
- **Agrega los roles remotos como `key_users` de la KMS de S3** (kms.tf + kms_policy.tf),
  para `Decrypt`/`GenerateDataKey` en `COPY`/`UNLOAD`.

Estos permisos aparecen solo cuando hay al menos un destino con `assume_role_arn`.

### UNLOAD/COPY: rol adjunto al cluster (lado cuenta destino)

Ejecutar el SP y hacer `COPY`/`UNLOAD` a S3 usan **roles distintos**:

- **Ejecución** (`assume_role_arn`): rol de identidad que asume la Step Function; NO
  necesita estar adjunto al cluster.
- **COPY/UNLOAD**: Redshift usa un rol **adjunto al cluster** (el que va en `IAM_ROLE`
  del UNLOAD/COPY). Ese rol necesita S3+KMS sobre los buckets del framework.

La plantilla `examples/redshift-crossaccount-role.tf` permite que **un mismo rol** cumpla
ambas funciones: incluye los permisos S3 (source+result) y KMS del framework
(`enable_framework_s3_access`, por defecto `true`) y sus ARN se derivan por `stage`. En ese
caso, **adjunta ese rol al cluster** y úsalo en el `IAM_ROLE` del UNLOAD/COPY. Como su ARN
está en `assume_role_arn`, el framework ya lo autoriza en las bucket/KMS policies.

### Consideraciones adicionales cross-account

- **Doble autorización S3**: cross-account requiere permiso en ambos lados. El framework
  ya pone la bucket policy (lado framework); la policy de identidad del rol remoto la
  aporta la plantilla (lado destino).
- **EventBridge / status updater**: el monitoreo de estado del Data API sigue ocurriendo
  en la cuenta del framework; el `WithEvent: true` se mantiene igual.
- **Networking**: no se requiere VPC peering para el Data API (es una API de control),
  pero sí para el acceso a datos del propio cluster remoto según su configuración.

## Cómo funciona internamente

- **Terraform** serializa `redshift_targets` (sin los `*_arn`) a la variable de entorno
  `REDSHIFT_TARGETS` (JSON) de la Lambda `dynamicBatchBuilder`, únicamente si el mapa no
  está vacío. Los permisos IAM adicionales se agregan al rol `child_batch` solo cuando
  hay destinos definidos.
- **La Lambda builder** (`redshift_target_resolver.py`) carga el registro desde
  `REDSHIFT_TARGETS` o, si no existe, lo reconstruye desde las variables clásicas.
  Luego arma los `Arguments` de `redshiftdata:executeStatement`:
  - `provisioned` → `Database` + `ClusterIdentifier` + `DbUser`
  - `serverless` → `Database` + `WorkgroupName`
  - cross-account (cualquier tipo) → agrega `Credentials.RoleArn` con el `assume_role_arn`.

## Errores frecuentes

- **`pipeline` con un nombre que no existe en el registro**: el builder lanza
  `RedshiftTargetError` indicando los destinos disponibles. Verifica que el nombre
  coincida con una clave de `redshift_targets` (o `ALPHA`/`NEDA`/`HYBRID` en modo clásico).
- **`REDSHIFT_TARGETS` con JSON inválido**: el builder falla con un mensaje explícito.
  Revisa el `jsonencode` generado por Terraform.
- **Permisos**: si un destino nuevo falla por credenciales, confirma que los `*_arn`
  correspondientes estén configurados en `redshift_targets`.
- **Cross-account `AccessDenied` al asumir el rol**: verifica que (a) el rol remoto tenga
  una trust policy que confíe en el rol `child_batch` local, y (b) el `assume_role_arn`
  del destino apunte exactamente a ese rol remoto.
