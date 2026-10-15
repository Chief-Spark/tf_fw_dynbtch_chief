# Desarrollo - Framework de Procesos Batch Dinámicos

## Índice de Documentación de Desarrollo

Esta sección contiene la documentación técnica necesaria para desarrolladores que trabajan en el Framework de Procesos Batch Dinámicos, incluyendo guías de estructura de código, gestión de dependencias y configuración de ambientes.

## Documentación Principal

### [Estructura de Terraform](terraform-structure.md)

Documentación completa de la organización del código Terraform del proyecto, incluyendo módulos, variables y mejores prácticas.

### [Gestión de Capas Lambda](layer-management.md)

Guía para la gestión de capas Lambda (layers), incluyendo instalación de dependencias, versionado y despliegue.

### [Ambiente Trunk](environment-trunk.md)

Documentación del ambiente trunk utilizado para desarrollo y pruebas de infraestructura.

### [Resumen de Lógica de Procesamiento](resumen_logica_procesamiento.md)

Resumen de la lógica de negocio implementada en el sistema de procesamiento de lotes dinámicos.

## Guías de Desarrollo

### Definiciones de Procesos

Para crear nuevas definiciones de procesos batch:

- **[Developer Guide](../componentes/definiciones/developer-guide.md)** - Guía paso a paso para desarrolladores
- **[Process Definition Schema](../componentes/definiciones/process-definition-schema.md)** - Esquema de archivos YAML
- **[Ejemplos](../componentes/definiciones/examples/README.md)** - Ejemplos de definiciones

### Código Python

El código fuente de las funciones Lambda se encuentra en el directorio `src/` del repositorio:

```
src/
├── dynamicBatchBuilder/          # Constructor de Step Functions dinámicas
├── dynamicBatchNotifier/         # Sistema de notificaciones
├── dynamicBatchOutputMerge/      # Glue job de consolidación
├── dynamicBatchSourceValidator/  # Validador de archivos fuente
├── dynamicBatchStoredProcedureCallProxy/  # Proxy para llamadas a Redshift
├── dynamicBatchStoredProcedureStatusUpdater/  # Actualizador de estados
├── dynamicBatchErrorLogFileGeneration/       # Generador de logs de error
├── layers/                       # Dependencias compartidas
├── dynamicBatchMainBatchInitiator/          # Iniciador principal del sistema
├── dynamicBatchSendEmailLog/     # Enviador de emails
└── templatesSES/                # Plantillas HTML de notificaciones
```

### Scripts de Utilidad

Los scripts de automatización se encuentran en el directorio `scripts/`:

- `install-layer-deps.ps1` / `install-layer-deps.sh` - Instalación de dependencias de layers
- `verify-versioned-layer.ps1` / `verify-versioned-layer.sh` - Verificación de layers versionadas

## Estructura de Ambientes

El proyecto soporta múltiples ambientes:

- **[Demo](../../demo/README.md)** - Ambiente de demostración
- **[Develop](../../develop/README.md)** - Ambiente de desarrollo
- **[QA](../../qa/README.md)** - Ambiente de testing
- **[Production](../../production/README.md)** - Ambiente productivo

Consulte **[Resumen de Ambientes](../resumen_ambientes.md)** para más detalles sobre cada ambiente.

## Infraestructura como Código

### Archivos Terraform Principales

En el directorio `trunk/` se encuentra la definición de la infraestructura:

- `data.tf` - Políticas IAM y data sources
- `eventbridge.tf` - Reglas de EventBridge
- `glue.tf` - Trabajos de Glue
- `iam.tf` - Roles y políticas IAM
- `lambda.tf` - Funciones Lambda
- `locals.tf` - Variables locales
- `outputs.tf` - Outputs del módulo
- `provider.tf` - Configuración del provider AWS
- `s3.tf` - Buckets S3
- `ses.tf` - Configuración de SES
- `sqs.tf` - Colas SQS
- `stepfunction.tf` - Step Functions
- `variables.tf` - Variables de entrada

Consulte **[Resumen de Infraestructura](../resumen_infraestructura.md)** para un análisis detallado de cada archivo.

## Flujo de Trabajo de Desarrollo

### 1. Configuración Inicial

1. Clonar el repositorio
2. Instalar dependencias de layers: `./scripts/install-layer-deps.sh`
3. Configurar credenciales AWS
4. Seleccionar ambiente de trabajo

### 2. Desarrollo de Funciones Lambda

1. Modificar código en `src/[función]/`
2. Actualizar `requirements.txt` si hay nuevas dependencias
3. Probar localmente cuando sea posible
4. Actualizar documentación correspondiente

### 3. Modificación de Infraestructura

1. Editar archivos `.tf` en `trunk/` o en directorio de ambiente
2. Ejecutar `terraform fmt` para formatear
3. Ejecutar `terraform validate` para validar sintaxis
4. Ejecutar `terraform plan` para revisar cambios
5. Aplicar cambios con `terraform apply`

### 4. Creación de Definiciones de Procesos

1. Crear archivo YAML siguiendo el esquema documentado
2. Validar sintaxis del YAML
3. Subir al bucket de definiciones del ambiente correspondiente
4. Probar con archivos de ejemplo

### 5. Testing

1. Probar en ambiente de desarrollo (`develop`)
2. Validar en ambiente de QA (`qa`)
3. Demostrar en ambiente demo si es necesario
4. Desplegar a producción después de aprobación

## Mejores Prácticas

### Código Python

- Usar type hints para claridad del código
- Implementar logging estructurado
- Manejar errores de forma explícita
- Documentar funciones complejas
- Mantener funciones pequeñas y enfocadas

### Terraform

- Usar variables para valores configurables
- Aplicar tags consistentes a todos los recursos
- Documentar módulos con comentarios
- Versionar módulos externos
- Mantener estado remoto en S3

### Definiciones YAML

- Seguir el esquema documentado estrictamente
- Usar nombres descriptivos para steps
- Documentar propósito de cada nivel
- Validar contra stored procedures existentes
- Probar con datos reales en ambiente de prueba

## Troubleshooting

### Problemas Comunes

#### Error al instalar layers
```bash
# Solución: Verificar versión de Python
python --version  # Debe ser 3.13 o compatible
./scripts/install-layer-deps.sh
```

#### Error de permisos en Terraform
```bash
# Solución: Verificar rol asumido
aws sts get-caller-identity
```

#### Función Lambda no se actualiza
```bash
# Solución: Forzar actualización del código
terraform taint module.lambda_[nombre].aws_lambda_function.this
terraform apply
```

## Enlaces Relacionados

### Documentación de Componentes

- **[Lambda Functions](../componentes/lambda-functions/README.md)** - Documentación de funciones
- **[Step Functions](../componentes/step-functions/README.md)** - Orquestación
- **[Almacenamiento](../componentes/storage/README.md)** - Buckets y bases de datos
- **[Procesamiento](../componentes/processing/README.md)** - Glue y Redshift

### Flujos de Negocio

- **[Flujo de Definición](../componentes/flujos/flujo-definicion.md)** - Flujo del desarrollador
- **[Flujo de Ejecución](../componentes/flujos/flujo-ejecucion.md)** - Flujo del operador
- **[Separación de Responsabilidades](../componentes/flujos/separacion-responsabilidades.md)** - Arquitectura
