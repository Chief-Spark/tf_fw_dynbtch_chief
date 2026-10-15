# Documentación de Arquitectura - Framework de Procesos Batch

## Índice Principal

Esta documentación proporciona una visión completa de la arquitectura, componentes y operación del Framework de Procesos Batch.

### 📋 Navegación Rápida

- [Estructura del Proyecto](project-structure.md)
- [Diagramas de Arquitectura](#diagramas-de-arquitectura)
- [Componentes del Sistema](#componentes-del-sistema)
- [Desarrollo y Testing](#desarrollo-y-testing)

## Diagramas de Arquitectura

### 🏗️ Diagramas de Despliegue

- [Vista General de Despliegue](diagramas/deployment/deployment-overview.png) | [Editable](diagramas/deployment/deployment-overview.drawio)
- [Arquitectura de Red](diagramas/deployment/network-architecture.png) | [Editable](diagramas/deployment/network-architecture.drawio)

### 🔄 Diagramas de Secuencia

- [Flujo Principal](diagramas/sequence/main-flow.png) | [Editable](diagramas/sequence/main-flow.drawio)
- [Manejo de Errores](diagramas/sequence/error-handling.png) | [Editable](diagramas/sequence/error-handling.drawio)

### 🧩 Diagramas de Componentes

- [Funciones Lambda](diagramas/components/lambda-functions.png) | [Editable](diagramas/components/lambda-functions.drawio)
- [Step Functions](diagramas/components/step-functions.png) | [Editable](diagramas/components/step-functions.drawio)

### 📊 Diagramas de Flujo de Datos

- [Pipeline de Datos](diagramas/data-flow/data-pipeline.png) | [Editable](diagramas/data-flow/data-pipeline.drawio)
- [Flujo de Notificaciones](diagramas/data-flow/notification-flow.png) | [Editable](diagramas/data-flow/notification-flow.drawio)

## Componentes del Sistema

### 🔧 [Componentes](componentes/README.md)

- [Flujos de Negocio](componentes/flujos/)
- [Funciones Lambda](componentes/lambda-functions/)
- [Step Functions](componentes/step-functions/)
- [Almacenamiento](componentes/storage/)
- [Mensajería](componentes/messaging/)
- [Procesamiento](componentes/processing/)
- [Definiciones de Procesos](componentes/definiciones/)

## Desarrollo y Testing

### 💻 [Desarrollo](desarrollo/README.md)

- [Estructura de Terraform](desarrollo/terraform-structure.md)
- [Gestión de Capas Lambda](desarrollo/layer-management.md)
- [Ambiente Trunk](desarrollo/environment-trunk.md)
- [Lógica de Procesamiento](desarrollo/resumen_logica_procesamiento.md)

## Resúmenes Ejecutivos

### 📊 Documentación de Infraestructura

- [Resumen de Ambientes](resumen_ambientes.md) - Ambientes de despliegue (demo, develop, qa, production)
- [Resumen de Infraestructura](resumen_infraestructura.md) - Resumen detallado de todos los archivos Terraform

### 🔒 Seguridad y Encriptación

- [KMS Encryption](componentes/security/kms-encryption.md) - Encriptación en reposo con AWS KMS
- [Security Overview](componentes/security/README.md) - Índice de documentación de seguridad

**Características de Seguridad**:
* **Encriptación KMS en reposo**: Todos los buckets S3 y tabla DynamoDB encriptados
* **Roles por ambiente**: Permisos específicos de Jenkins y DTO por stage
* **Versionamiento desde Terraform**: Definiciones de procesos gestionadas desde código

### 📦 Versionamiento de Definiciones

Las definiciones de procesos (PP*.yml, mnemotecnicos.csv) se versionan automáticamente desde el repositorio Terraform:
* **Fuente**: `src/dynamicProcessDefinitions/`
* **Destino**: Bucket S3 de definiciones
* **Control**: Git + Terraform para trazabilidad completa
* **Nuevos procesos**: PP0298-PP0307 (Sábanas), PP0742, y otros

## Convenciones de Documentación

- 📋 Documentos de índice y navegación
- 🏗️ Diagramas de arquitectura y despliegue
- 🔄 Diagramas de flujo y secuencia
- 🧩 Componentes y módulos
- 📊 Datos y métricas
- 🔧 Configuración y herramientas
- 🔒 Seguridad y compliance
- ⚙️ Operaciones y mantenimiento
- 💻 Desarrollo y código
- 📈 Performance y escalabilidad
