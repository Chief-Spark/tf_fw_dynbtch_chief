# Framework de Procesos Batch Dinámicos - Terraform

Sistema de procesamiento de lotes dinámicos en AWS que permite la ejecución flexible de procesos batch mediante definiciones YAML, orquestación con Step Functions y procesamiento paralelo con Redshift.

## 📑 Tabla de Contenidos

- [Características Principales](#características-principales)
- [Estructura del Proyecto](#estructura-del-proyecto)
- [Documentación Completa](#documentación-completa)
- [Ambientes](#ambientes)
- [Pipeline de CI/CD](#pipeline-de-cicd)
- [Inicio Rápido](#inicio-rápido)
- [Arquitectura](#arquitectura)
- [Recursos AWS Creados](#recursos-aws-creados)
- [Contribución](#contribución)
- [Contacto](#contacto)

## 🚀 Características Principales

- **Procesamiento Dinámico**: Definiciones YAML que generan Step Functions específicas para cada tipo de proceso
- **Orquestación Inteligente**: Main Batch Orchestrator con 17 estados y manejo robusto de errores
- **Integración con Redshift**: Ejecución de stored procedures mediante Data API con monitoreo en tiempo real
- **Consolidación Automática**: Glue Jobs optimizados para unificar archivos de salida
- **Monitoreo Completo**: EventBridge, CloudWatch y notificaciones SES integradas
- **Multi-Ambiente**: Soporte para demo, develop, qa y production con configuraciones independientes
- **CI/CD Automatizado**: Pipeline de Jenkins con análisis de calidad y seguridad

## 📂 Estructura del Proyecto

```
tf_fw_dynbtch_macondo_clean/
│
├── trunk/                          # Código principal de infraestructura Terraform
│   ├── data.tf                    # Políticas IAM y data sources
│   ├── eventbridge.tf             # Reglas de EventBridge para Redshift Data API
│   ├── glue.tf                    # Jobs de consolidación de archivos
│   ├── iam.tf                     # Roles y políticas IAM (12 roles especializados)
│   ├── lambda.tf                  # Funciones Lambda (7 funciones + layers)
│   ├── locals.tf                  # Variables locales y naming conventions
│   ├── outputs.tf                 # Outputs de recursos creados
│   ├── provider.tf                # Configuración del provider AWS
│   ├── s3.tf                      # Buckets S3 (4 buckets especializados)
│   ├── ses.tf                     # Configuración de SES y plantillas
│   ├── sqs.tf                     # Colas SQS para eventos
│   ├── stepfunction.tf            # Step Function principal (17 estados)
│   └── variables.tf               # Variables de entrada del módulo
│
├── demo/                          # 🎬 Ambiente de demostración
│   ├── backend.tf                 # Backend remoto S3 + DynamoDB
│   ├── main.tf                    # Configuración principal
│   ├── terraform.tfvars           # Variables específicas del ambiente
│   ├── variables.tf               # Definición de variables
│   └── README.md                  # 📖 Documentación completa del ambiente demo
│
├── develop/                       # 🔧 Ambiente de desarrollo
│   ├── backend.tf                 # Backend remoto S3 + DynamoDB
│   ├── main.tf                    # Configuración principal
│   ├── terraform.tfvars           # Variables específicas del ambiente
│   ├── variables.tf               # Definición de variables
│   └── README.md                  # 📖 Documentación completa del ambiente develop
│
├── qa/                            # ✅ Ambiente de control de calidad
│   ├── backend.tf                 # Backend remoto S3 + DynamoDB
│   ├── main.tf                    # Configuración principal
│   ├── terraform.tfvars           # Variables específicas del ambiente
│   ├── variables.tf               # Definición de variables
│   └── README.md                  # 📖 Documentación completa del ambiente qa
│
├── production/                    # 🔒 Ambiente de producción (CRÍTICO)
│   ├── backend.tf                 # Backend remoto S3 + DynamoDB
│   ├── main.tf                    # Configuración principal
│   ├── terraform.tfvars           # Variables específicas del ambiente
│   ├── variables.tf               # Definición de variables
│   └── README.md                  # 📖 Documentación completa del ambiente production
│
├── src/                           # Código fuente de funciones Lambda
│   ├── dynamicBatchBuilder/       # Constructor de Step Functions dinámicas
│   ├── dynamicBatchNotifier/      # Sistema de notificaciones
│   ├── dynamicBatchOutputMerge/   # Script de consolidación para Glue
│   ├── dynamicBatchSourceValidator/     # Validador de archivos fuente
│   ├── dynamicBatchStoredProcedureCallProxy/      # Proxy para Redshift
│   ├── dynamicBatchStoredProcedureStatusUpdater/  # Actualizador de estados
│   ├── dynamicBatchErrorLogFileGeneration/    # Generador de logs de error
│   ├── dynamicBatchMainBatchInitiator/        # Iniciador principal del sistema
│   ├── dynamicBatchSendEmailLog/   # Enviador de emails con adjuntos
│   ├── layers/                    # Dependencias compartidas (pydantic, pyyaml)
│   └── templatesSES/              # Plantillas HTML de notificaciones
│
├── scripts/                       # 🛠️ Scripts de utilidad
│   ├── install-layer-deps.sh      # Instalación de dependencias de layers (Linux)
│   ├── install-layer-deps.ps1     # Instalación de dependencias de layers (Windows)
│   ├── verify-versioned-layer.sh  # Verificación de layers (CI/CD Linux)
│   ├── verify-versioned-layer.ps1 # Verificación de layers (CI/CD Windows)
│   └── README.md                  # 📖 Documentación completa de scripts y layers
│
├── docs/                          # 📚 Documentación completa del proyecto
│   ├── componentes/               # Documentación de componentes del sistema
│   │   ├── definiciones/         # Esquemas YAML y guías de desarrollo
│   │   ├── flujos/               # Flujos de negocio y patrones arquitectónicos
│   │   ├── lambda-functions/     # Documentación de las 7 funciones Lambda
│   │   ├── messaging/            # SQS, EventBridge, SES
│   │   ├── processing/           # Glue Jobs y Redshift Data API
│   │   ├── step-functions/       # Orquestación y Step Functions dinámicas
│   │   ├── storage/              # Buckets S3, DynamoDB, Redshift
│   │   └── README.md             # 📖 Índice de componentes
│   │
│   ├── desarrollo/                # Documentación para desarrolladores
│   │   ├── terraform-structure.md      # Estructura de Terraform
│   │   ├── layer-management.md         # Gestión de Lambda layers
│   │   ├── environment-trunk.md        # Ambiente trunk
│   │   ├── resumen_logica_procesamiento.md  # Lógica de procesamiento
│   │   └── README.md              # 📖 Guía completa de desarrollo
│   │
│   ├── diagramas/                 # Diagramas de arquitectura (Draw.io)
│   ├── assets/                    # Assets y diagramas exportados
│   ├── resumen_ambientes.md       # 📖 Resumen ejecutivo de ambientes
│   ├── resumen_infraestructura.md # 📖 Resumen de todos los archivos Terraform
│   └── README.md                  # 📖 Índice principal de documentación
│
├── modules/                       # Módulos Terraform reutilizables (externos)
│   ├── eits-tf-aws-lambda/       # Módulo para funciones Lambda
│   ├── eits-tf-aws-iam/          # Módulo para roles y políticas IAM
│   ├── eits-tf-aws-s3/           # Módulo para buckets S3
│   ├── eits-tf-aws-sqs/          # Módulo para colas SQS
│   ├── eits-tf-aws-glue/         # Módulo para Glue jobs
│   └── [otros módulos...]
│
├── .jenkins.yml                   # Configuración del pipeline de CI/CD
└── README.md                      # Este archivo
```

## 📚 Documentación Completa

### Documentación Principal

La documentación completa del sistema está organizada en la carpeta `docs/`:

- **[Índice General de Documentación](./docs/README.md)** - Punto de entrada principal
- **[Resumen de Ambientes](./docs/resumen_ambientes.md)** - Comparación de ambientes y workflow de promoción
- **[Resumen de Infraestructura](./docs/resumen_infraestructura.md)** - Análisis detallado de todos los archivos Terraform

### Documentación por Categoría

#### Componentes del Sistema

- **[Componentes](./docs/componentes/README.md)** - Índice de todos los componentes
  - [Definiciones de Procesos](./docs/componentes/definiciones/README.md) - Esquemas YAML y guías
  - [Flujos de Negocio](./docs/componentes/flujos/README.md) - Patrones y separación de responsabilidades
  - [Funciones Lambda](./docs/componentes/lambda-functions/README.md) - 7 funciones especializadas
  - [Mensajería](./docs/componentes/messaging/README.md) - SQS, EventBridge, SES
  - [Procesamiento](./docs/componentes/processing/README.md) - Glue Jobs y Redshift
  - [Step Functions](./docs/componentes/step-functions/README.md) - Orquestación dinámica
  - [Almacenamiento](./docs/componentes/storage/README.md) - S3, DynamoDB, Redshift

#### Desarrollo

- **[Guía de Desarrollo](./docs/desarrollo/README.md)** - Documentación completa para desarrolladores
  - Estructura de Terraform
  - Gestión de Lambda layers
  - Flujo de trabajo de desarrollo
  - Mejores prácticas
  - Troubleshooting

## 🌍 Ambientes

El proyecto soporta 4 ambientes independientes con configuraciones específicas, siguiendo el siguiente flujo de promoción:

**Workflow**: Develop → QA → Demo → Production

### 1. Develop - Ambiente de Desarrollo

Ambiente principal de desarrollo activo e integración continua. **Primer ambiente** en el flujo de promoción.

- **Stage**: `dev`
- **Propósito**: Desarrollo activo y testing de integración
- **Promoción**: Cambios validados se promueven a QA
- **Documentación**: [develop/README.md](./develop/README.md)

```bash
cd develop
terraform init
terraform plan
terraform apply
```

### 2. QA - Ambiente de Control de Calidad

Ambiente para testing exhaustivo y validación. **Segundo ambiente** en el flujo de promoción.

- **Stage**: `qa`
- **Propósito**: Testing completo y validación de rendimiento
- **Promoción**: Después de QA exitoso se promueve a Demo
- **Documentación**: [qa/README.md](./qa/README.md)

```bash
cd qa
terraform init
terraform plan
terraform apply
```

### 3. Demo - Ambiente de Demostración

Ambiente para demostraciones a stakeholders con configuraciones cercanas a producción. **Tercer ambiente** en el flujo de promoción.

- **Stage**: `demo`
- **Propósito**: Demostraciones y validación final pre-producción
- **Promoción**: Después de aprobación de demos se promueve a Production
- **Documentación**: [demo/README.md](./demo/README.md)

```bash
cd demo
terraform init
terraform plan
terraform apply
```

### 4. Production - Ambiente de Producción (CRÍTICO)

Ambiente de producción con operaciones de negocio en tiempo real. **Ambiente final** en el flujo de promoción.

- **Stage**: `production`
- **Propósito**: Operaciones críticas de negocio
- **Promoción**: Ambiente final, sin promoción adicional
- **Documentación**: [production/README.md](./production/README.md)
- **⚠️ ADVERTENCIA**: Requiere aprobaciones y procedimientos estrictos

```bash
cd production
terraform init
terraform plan
# terraform apply - Solo con aprobación
```

### Comparación de Ambientes

Para una comparación detallada de todos los ambientes, consultar:

- **[Documentación General de Ambientes](./docs/resumen_ambientes.md)** - Workflow de promoción y criterios

## 🔄 Pipeline de CI/CD

El proyecto utiliza Jenkins para automatizar el proceso de construcción, validación y despliegue.

### Configuración del Pipeline

El archivo `.jenkins.yml` define la configuración completa:

```yaml
version: 1.0.1
global:
  application: "26099-Procesos-Especiales-Batch-AWS"
  tech: terraform
  language: terraform
  jdk: 8
```

### Etapas del Pipeline

#### 1. Before Build
- Verificación de versiones de Python y pip
- Validación de capas Lambda con `verify-versioned-layer.sh`

#### 2. Build
- Creación del paquete de despliegue: `eec-aws-us-eits-procesosbatch.zip`

#### 3. After Build
- **SonarQube**: Análisis de calidad de código
- **Veracode**: Análisis de seguridad

#### 4. Before Deploy
- Copia automática de archivos desde `trunk/` a `develop/`

#### 5. Deploy
- Despliegue automatizado con Terraform 1.7.2
- Account ID: 651706752126

### Herramientas Integradas

- **SonarQube**: Calidad de código Terraform y Python
- **Veracode**: Análisis de vulnerabilidades de seguridad
- **Terraform**: IaC con validación automática

## 🚀 Inicio Rápido

### Prerrequisitos

- **AWS CLI** configurado con credenciales apropiadas
- **Terraform** >= 1.7.2
- **Python** 3.13 (para desarrollo de Lambda functions)
- **Git** para control de versiones

### Instalación Inicial

1. **Clonar el repositorio**:
   ```bash
   git clone <repository-url>
   cd tf_fw_dynbtch_macondo_clean
   ```

2. **Instalar dependencias de Lambda layers** (si es necesario):
   ```bash
   # Linux/Mac
   sh scripts/install-layer-deps.sh
   
   # Windows
   powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1
   ```
   
   Ver documentación completa: [scripts/README.md](./scripts/README.md)

3. **Seleccionar ambiente** y configurar:
   ```bash
   cd develop  # o demo, qa, production
   terraform init
   ```

4. **Planificar cambios**:
   ```bash
   terraform plan
   ```

5. **Aplicar infraestructura**:
   ```bash
   terraform apply
   ```

### Despliegue por Ambiente

Cada ambiente tiene su propia documentación detallada con instrucciones específicas:

- **Demo**: [demo/README.md](./demo/README.md)
- **Develop**: [develop/README.md](./develop/README.md)
- **QA**: [qa/README.md](./qa/README.md)
- **Production**: [production/README.md](./production/README.md)

## 🏗️ Arquitectura

### Componentes Principales

El sistema implementa una arquitectura basada en eventos con los siguientes componentes:

#### Almacenamiento (4 Buckets S3)
- **Source Repository**: Archivos de entrada (.val, .par, .inc)
- **Definition Repository**: Definiciones YAML y scripts
- **Result Repository**: Archivos de salida procesados
- **Error Files**: Logs de error y debugging

#### Procesamiento (7 Funciones Lambda)
- **dynamicBatchMainBatchInitiator**: Punto de entrada del sistema
- **dynamicBatchSourceValidator**: Validación de archivos
- **dynamicBatchBuilder**: Generación de Step Functions dinámicas
- **storedProcedureCallProxy**: Ejecución en Redshift
- **storedProcedureStatusUpdater**: Actualización de estados
- **dynamicBatchNotifier**: Sistema de notificaciones
- **dynamicBatchErrorLogFileGeneration**: Generación de logs de error
- **dynamicBatchSendEmailLog**: Envío de emails

#### Orquestación
- **Main Batch Step Function**: 17 estados con manejo robusto de errores
- **Dynamic Step Functions**: Generadas bajo demanda por proceso
- **EventBridge**: Monitoreo de eventos Redshift Data API

#### Procesamiento de Datos
- **Glue Job**: Consolidación de múltiples archivos de salida
- **Redshift Data API**: Ejecución de stored procedures

#### Mensajería
- **SQS Queue**: Eventos de S3 → Lambda
- **EventBridge Rules**: Redshift → Lambda
- **SES**: Notificaciones por email

### Flujo de Datos Principal

```
Archivo .val → S3 → SQS → dynamicBatchMainBatchInitiator → Main Step Function
                                                      ↓
                                         dynamicBatchSourceValidator
                                                      ↓
                                          dynamicBatchBuilder
                                                      ↓
                                      Dynamic Step Function (generada)
                                                      ↓
                              Redshift Stored Procedures (paralelos)
                                                      ↓
                                      Glue Job (consolidación)
                                                      ↓
                                  Notificación + Limpieza de recursos
```

### Publicación al destino OUT (Business_Table)

Además del repositorio interno de resultados, al terminar un batch exitoso Glue copia las salidas unificadas (y, si aplica, `.val`/`.inc`) al **DESTINO** de las reglas OUT en Dynamo, cifrando con **KMS_DESTINO**. Ya no hay un bucket/KMS fijo de concatenar en el job: si un producto debe ir a “cargue de bases”, esa ruta y esa llave van en la fila OUT.

Para más detalles sobre la arquitectura, consultar:
- [Documentación de Componentes](./docs/componentes/README.md)
- [Flujos de Negocio](./docs/componentes/flujos/README.md)
- [Resumen de Infraestructura](./docs/resumen_infraestructura.md)

## 🔧 Recursos AWS Creados

### Por Ambiente

Cada ambiente crea los siguientes recursos:

#### Compute
- 7 Funciones Lambda (Python 3.13, ARM64)
- 1 Lambda Layer (dependencias comunes)
- 1 Step Function Principal (17 estados)
- N Step Functions Dinámicas (creadas bajo demanda)
- 1 Glue Job (consolidación de archivos)

#### Storage
- 4 Buckets S3 (source, definition, result, error)
- Tabla DynamoDB para logs (compartida)
- Integración con Redshift (externo)

#### Networking & Security
- 12 Roles IAM especializados
- Políticas IAM con principio de menor privilegio
- KMS Key para encriptación (compartida)
- Security Groups (cuando aplique)

#### Monitoring & Messaging
- 1 SQS Queue (eventos S3)
- 1 EventBridge Rule (Redshift Data API)
- Configuración SES (emails)
- CloudWatch Log Groups
- CloudWatch Alarms (configurable)

### Backend Remoto (por ambiente)

- Bucket S3 para estado de Terraform (con versionado)
- Tabla DynamoDB para bloqueo de estado
- Encriptación AES256

## 🛠️ Scripts de Utilidad

El directorio `scripts/` contiene herramientas para gestión de Lambda layers:

### Instalación de Dependencias

```bash
# Linux/Mac
sh scripts/install-layer-deps.sh

# Windows
powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1
```

### Verificación de Layers (CI/CD)

```bash
# Linux/Mac
sh scripts/verify-versioned-layer.sh

# Windows
powershell -ExecutionPolicy Bypass -File scripts/verify-versioned-layer.ps1
```

### Documentación Completa

Para información detallada sobre los scripts, incluyendo:
- Configuración de Windows PowerShell
- Troubleshooting
- Compatibilidad multiplataforma
- Normalización de ZIPs

Consultar: **[scripts/README.md](./scripts/README.md)**

## 📊 Comandos Útiles

### Terraform

```bash
# Formatear código
terraform fmt

# Validar configuración
terraform validate

# Ver estado actual
terraform show

# Listar recursos
terraform state list

# Verificar recurso específico
terraform state show aws_lambda_function.main_batch_initiator

# Importar recurso existente
terraform import aws_s3_bucket.example bucket-name
```

### AWS CLI

```bash
# Verificar logs de Lambda
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# Ver métricas de Lambda
aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Duration

# Listar ejecuciones de Step Functions
aws stepfunctions list-executions --state-machine-arn <arn>
```

## 🤝 Contribución

### Proceso de Desarrollo

1. **Crear rama feature**:
   ```bash
   git checkout -b feature/nombre-feature
   ```

2. **Desarrollo y testing**:
   - Hacer cambios en el código
   - Probar en ambiente `develop`
   - Ejecutar `terraform validate`
   - Ejecutar `terraform fmt`

3. **Commit con convenciones**:
   ```bash
   git add .
   git commit -m "feat: descripción del cambio"
   ```

4. **Push y Pull Request**:
   ```bash
   git push origin feature/nombre-feature
   ```

### Estándares de Código

- **Terraform**: Usar `terraform fmt` antes de commit
- **Python**: Seguir PEP 8
- **Documentación**: Actualizar README correspondiente
- **Testing**: Validar en develop antes de promover

### Workflow de Promoción

```
Develop → QA → Demo → Production
   ↓       ↓      ↓         ↓
Testing  Valid. Demos   Producción
```

Para más detalles, consultar:
- [Guía de Desarrollo](./docs/desarrollo/README.md)
- [Resumen de Ambientes](./docs/resumen_ambientes.md)

## 🔒 Seguridad

### Controles Implementados

- **Acceso S3**: Todos los buckets con acceso público bloqueado
- **Encriptación**: Estados de Terraform con AES256
- **IAM**: Roles con principio de menor privilegio
- **KMS**: Encriptación de datos sensibles
- **Auditoría**: Logs de acceso y cambios registrados
- **Boundary Policies**: Límites de permisos adicionales

### Análisis de Seguridad

- **Veracode**: Análisis automático en pipeline
- **SonarQube**: Escaneo de calidad y seguridad
- **AWS Security Best Practices**: Implementadas

## 📞 Contacto

### Equipos de Soporte

- **Desarrollo**: Consultas técnicas y nuevas funcionalidades
- **DevOps**: Infraestructura, despliegues y CI/CD
- **QA**: Testing, validación y control de calidad
- **Producción**: Incidentes críticos y soporte 24/7

### Recursos Adicionales

- **Documentación Completa**: [docs/README.md](./docs/README.md)
- **Ambientes**: [docs/resumen_ambientes.md](./docs/resumen_ambientes.md)
- **Infraestructura**: [docs/resumen_infraestructura.md](./docs/resumen_infraestructura.md)
- **Desarrollo**: [docs/desarrollo/README.md](./docs/desarrollo/README.md)
- **Scripts**: [scripts/README.md](./scripts/README.md)

### Documentación por Ambiente

- **Demo**: [demo/README.md](./demo/README.md)
- **Develop**: [develop/README.md](./develop/README.md)
- **QA**: [qa/README.md](./qa/README.md)
- **Production**: [production/README.md](./production/README.md)

---

**Proyecto**: Framework de Procesos Batch Dinámicos  
**Tecnología**: Terraform + AWS (Lambda, Step Functions, S3, Redshift, Glue)