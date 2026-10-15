# Documentación de Ambientes - Framework Procesos Batch

## Resumen de Ambientes

El Framework de Procesos Batch utiliza una arquitectura multi-ambiente para garantizar la calidad, seguridad y estabilidad de las operaciones. Cada ambiente tiene un propósito específico y configuraciones optimizadas para su función.

## Mapa de Ambientes

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     DEVELOP     │    │       QA        │    │      DEMO       │    │   PRODUCTION    │
│                 │    │                 │    │                 │    │                 │
│ • Desarrollo    │───▶│ • Testing       │───▶│ • Demostración  │───▶│ • Operaciones   │
│ • Integración   │    │ • Validación    │    │ • Pre-Prod      │    │ • Crítico       │
│ • CI/CD         │    │ • Performance   │    │ • Aprobación    │    │ • Alta Dispon.  │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
         1                      2                      3                      4
                                 
                    ┌───────────────────────────────────────────────────────────┐
                    │                   WORKFLOW DE PROMOCIÓN                   │
                    │                                                           │
                    │  Develop → QA → Demo → Production                        │
                    │     ↓       ↓      ↓         ↓                            │
                    │  Testing  Valid. Demos   Producción                      │
                    └───────────────────────────────────────────────────────────┘
                                                        
                    ┌───────────────────────────────────────────────────────────┐
                    │                        PROMOCIÓN                          │
                    │                                                           │
                    │ 1. Desarrollo y Testing en Develop                       │
                    │ 2. Validación exhaustiva en QA                           │
                    │ 3. Demostración y aprobación en Demo                     │
                    │ 4. Despliegue controlado a Production                    │
                    └───────────────────────────────────────────────────────────┘
```

## Comparación de Ambientes

| Característica | Develop | QA | Demo | Production |
|----------------|---------|----|----|------------|
| **Orden en Flujo** | 1° | 2° | 3° | 4° |
| **Propósito** | Desarrollo | Testing | Demostración | Operaciones |
| **Acceso** | Equipo Dev | QA Team | Stakeholders | Solo Autorizados |
| **Cambios** | Controlado | Aprobado | Validado | Crítico |
| **Datos** | Test | Test | Test/Mock | Real |
| **Monitoreo** | Detallado | Completo | Completo | Crítico |
| **Backup** | Básico | Completo | Completo | Automático |
| **Seguridad** | Estándar | Estricta | Estricta | Máxima |

## Configuraciones por Ambiente

### 1. Develop (Primer Ambiente)

- **Stage**: `dev`
- **Environment**: `dev`
- **Backend**: `339712808864-develop-dynamicbatchframework-terraform-state`
- **Propósito**: Desarrollo activo e integración continua
- **Flujo**: Primer ambiente del ciclo de vida

### 2. QA (Segundo Ambiente)

- **Stage**: `qa`
- **Environment**: `qa`
- **Backend**: `339712808864-qa-dynamicbatchframework-terraform-state`
- **Propósito**: Testing exhaustivo y validación
- **Flujo**: Promoción desde Develop

### 3. Demo (Tercer Ambiente)

- **Stage**: `demo`
- **Environment**: `demo`
- **Backend**: `339712808864-demo-frameworkprocesosbatch-terraform-state`
- **Propósito**: Demostraciones y validación pre-producción
- **Flujo**: Promoción desde QA

### 4. Production (Ambiente Final)

- **Stage**: `production`
- **Environment**: `prd`
- **Backend**: `339712808864-production-dynamicbatchframework-terraform-state`
- **Propósito**: Operaciones críticas de negocio
- **Flujo**: Promoción final desde Demo

## Recursos Compartidos

Todos los ambientes comparten los siguientes recursos:

### Infraestructura Base

- **Redshift Cluster**: `dev-339712808864-redshift-redshift-cluster`
- **Base de Datos**: `dynamicbatch`
- **Usuario DB**: `lambda_user`
- **Tabla Logs**: `dev-339712808864-fwdynbtch-logs`
- **KMS Key**: `339712808864-fwdynbtch-kms`

### Configuraciones Comunes

- **Región AWS**: `us-east-1`
- **Proyecto**: `fwdynbtch`
- **Tags Base**: Environment, Project, ManagedBy, CostString, AppID

### Configuraciones de Roles Externos y SQS por Ambiente

**Rol de Procesos Especiales Batch** (`proc-esp-batch-project-name`):
- **Todos los ambientes**: `"procs-espec-batch"`
- **ARN resultante**: `arn:aws:iam::[account_id]:role/BURoleFor-[stage]-[account_id]-procs-espec-batch`

**Rol de Cargue de Bases** (`carguedebases_account_id`) - Cross-account:
- **Develop**: `"470008751117"`
- **QA**: `"738272403214"`
- **Demo**: `"160125787052"` (stg)
- **Production**: `"031471595101"`
- **ARN resultante**: `arn:aws:iam::[carguedebases_account_id]:role/BURoleFor-[stage]-[carguedebases_account_id]-carguedebases-GlueDataInPutRole`
- **Nota**: Cada ambiente tiene un `account_id` diferente para la cuenta de cargue de bases

**Cola SQS PESVNO** (`name_sqs_pesvno`):
- **Todos los ambientes**: `"pesvno-cloud-queue"` (valor por defecto)
- **Nombre completo de cola**: `[stage]-[account_id]-pesvno-cloud-queue`
- **Propósito**: Cola externa para recibir notificaciones de archivos `.yaml` desde el bucket source

## Workflow de Promoción

### 1. Desarrollo Activo (Develop)

**Primer paso del ciclo de vida**

- Implementación de nuevas funcionalidades
- Testing de integración
- Validación de configuraciones
- CI/CD automatizado
- **Promoción a**: QA (después de testing exitoso)

### 2. Control de Calidad (QA)

**Segundo paso del ciclo de vida**

- Testing exhaustivo de funcionalidades
- Validación de rendimiento
- Testing de integración con sistemas externos
- Pruebas de carga y escalabilidad
- **Promoción a**: Demo (después de validación completa)

### 3. Demostración (Demo)

**Tercer paso del ciclo de vida**

- Demostraciones a stakeholders
- Validación final pre-producción
- Aprobación de negocio
- Simulación de escenarios productivos
- **Promoción a**: Production (después de aprobación)

### 4. Producción (Production)

**Ambiente final del ciclo de vida**

- Operaciones de negocio en tiempo real
- Alta disponibilidad y seguridad
- Monitoreo continuo 24/7
- **Sin promoción adicional**: Ambiente terminal

## Procedimientos de Control

### Cambios en Develop (1er Ambiente)

- ✅ Requiere code review
- ✅ Testing automático en CI/CD
- ✅ Validación antes de promoción a QA
- ✅ Ambiente más flexible para desarrollo

### Cambios en QA (2do Ambiente)

- ✅ Requiere aprobación de QA
- ✅ Testing completo obligatorio
- ✅ Validación de rendimiento
- ✅ Promoción a Demo solo con aprobación

### Cambios en Demo (3er Ambiente)

- ⚠️ Requiere validación de stakeholders
- ⚠️ Demostraciones planificadas
- ⚠️ Aprobación de negocio necesaria
- ⚠️ Promoción a Production solo con aprobación completa

### Cambios en Production (4to Ambiente - CRÍTICO)

- 🔒 Requiere aprobación múltiple
- 🔒 Plan de rollback obligatorio
- 🔒 Ventana de mantenimiento programada
- 🔒 Monitoreo adicional durante cambios
- 🔒 Equipo de soporte disponible

## Monitoreo y Alertas

### Develop (1er Ambiente)

- Alertas de errores y warnings
- Métricas de rendimiento
- Logs detallados
- Monitoreo para desarrollo

### QA (2do Ambiente)

- Alertas completas
- Métricas de rendimiento
- Testing automático
- Reportes de calidad
- Análisis de performance

### Demo (3er Ambiente)

- Alertas configuradas
- Métricas completas
- Monitoreo similar a producción
- Logs para demostraciones

### Production (4to Ambiente - CRÍTICO)

- Alertas críticas 24/7
- Métricas en tiempo real
- Escalación automática
- Monitoreo continuo
- SLA garantizado

## Troubleshooting por Ambiente

### Problemas Comunes

#### Develop (1er Ambiente)

- Problemas de integración
- Errores de configuración
- Testing de funcionalidades
- Debugging activo

#### QA (2do Ambiente)

- Problemas de rendimiento
- Testing de escalabilidad
- Validación de casos edge
- Análisis de bottlenecks

#### Demo (3er Ambiente)

- Validación pre-producción
- Ajustes de configuración
- Preparación de demostraciones
- Sincronización con stakeholders

#### Production (4to Ambiente - CRÍTICO)

- Problemas críticos de servicio
- Interrupciones de negocio
- Escalación de incidentes
- Recuperación ante desastres

## Contactos por Ambiente

### Develop (1er Ambiente)

- **Equipo**: Desarrollo + DevOps
- **Responsabilidad**: Equipo de desarrollo
- **Escalación**: A QA después de validación

### QA (2do Ambiente)

- **Equipo**: QA + DevOps
- **Responsabilidad**: Equipo de QA
- **Escalación**: A Demo después de testing

### Demo (3er Ambiente)

- **Equipo**: Desarrollo + QA + Negocio
- **Responsabilidad**: Equipo de validación
- **Escalación**: A Production después de aprobación

### Production (4to Ambiente - CRÍTICO)

- **Equipo**: DevOps + SRE + Arquitectura
- **Responsabilidad**: Equipo de producción
- **Escalación**: Según severidad del incidente

## Documentación Específica

Para información detallada de cada ambiente (en orden de promoción), consultar:

1. **[Develop](./../develop/README.md)**: Documentación completa del ambiente develop (1er ambiente)
2. **[QA](./../qa/README.md)**: Documentación completa del ambiente QA (2do ambiente)
3. **[Demo](./../demo/README.md)**: Documentación completa del ambiente demo (3er ambiente)
4. **[Production](./../production/README.md)**: Documentación completa del ambiente production (4to ambiente - CRÍTICO)

## Encriptación y Seguridad por Ambiente

### Encriptación en Reposo

Todos los ambientes implementan encriptación en reposo con AWS KMS:

**Recursos encriptados**:
* **Buckets S3**: Todos los buckets del sistema
  * Repositorio de fuentes
  * Repositorio de definiciones
  * Repositorio de resultados
  * Archivos de error
* **DynamoDB**: Tabla de logs de ejecución

**Clave KMS**:
* **Tipo**: Clave maestra creada por el módulo Terraform
* **Alias**: `[account_id]-s3-[project_name]`
* **Gestión**: Módulo `eits-tf-aws-kms-1.8.1`
* **Políticas**: Organizadas por stage con roles específicos

### Roles de Seguridad por Ambiente

#### Desarrollo (dev)

**Roles de Jenkins**:
* `BURoleForJenkinsGlobalSpLatamdev`

**Roles de DTO**:
* `BURoleForDTODev-NonProd`

**Acceso a KMS**:
* Key Owners: Roles administrativos + Jenkins dev
* Key Users: Roles del proyecto + DTO dev

#### QA (qa)

**Roles de Jenkins**:
* `BURoleForJenkinsGlobalSpLatamqa`

**Roles de DTO**:
* `BURoleForDTOQa-NonProd`

**Acceso a KMS**:
* Key Owners: Roles administrativos + Jenkins qa
* Key Users: Roles del proyecto + DTO qa

#### Demo (stg)

**Roles de Jenkins**:
* `BURoleForJenkinsGlobalSpLatamstg`

**Roles de DTO**:
* `BURoleForDTOUat-NonProd`

**Acceso a KMS**:
* Key Owners: Roles administrativos + Jenkins stg
* Key Users: Roles del proyecto + DTO stg

#### Production (prd - CRÍTICO)

**Roles de Jenkins**:
* `BURoleForJenkinsGlobalSpLatampro`

**Roles de DTO**:
* `BURoleForDTOProd`

**Acceso a KMS**:
* Key Owners: Roles administrativos + Jenkins prd
* Key Users: Roles del proyecto + DTO prd

**Seguridad adicional**:
* Máximos controles de acceso
* Auditoría completa habilitada
* Políticas de KMS más restrictivas

### Configuraciones de Validación

**Variables configurables por ambiente** (típicamente solo para Macondo):

```terraform
disable_source_vpce_check = false  # Validación de VPC Endpoint
disable_source_ip_check   = false  # Validación de IP de origen
disable_default_alarms    = false  # Alarmas por defecto
```

**Recomendaciones**:
* **Desarrollo**: Validaciones pueden ser flexibles
* **QA**: Validaciones completas habilitadas
* **Demo**: Configuración similar a producción
* **Production**: Todas las validaciones habilitadas obligatoriamente

## Notas Importantes

### Seguridad

- Cada ambiente tiene configuraciones de seguridad apropiadas
- Production tiene controles de seguridad máximos
- Todos los accesos están auditados
- **Encriptación KMS obligatoria** en todos los ambientes
- Roles de seguridad específicos por ambiente (Jenkins, DTO)

### Cumplimiento

- Production cumple con todas las políticas corporativas
- Auditorías regulares en todos los ambientes
- Documentación completa de controles
- **Encriptación en reposo** cumple con requisitos de compliance
- CloudTrail registra todos los usos de claves KMS

### Mantenimiento

- Actualizaciones programadas en ventanas de mantenimiento
- Backup automático de configuraciones
- Procedimientos de recuperación documentados
- **Rotación automática de claves KMS** gestionada por AWS
