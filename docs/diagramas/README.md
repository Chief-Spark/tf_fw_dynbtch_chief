# Diagramas de Arquitectura - Framework de Procesos Batch Dinámicos

## Diagramas Actualizados Disponibles

Esta sección documenta los diagramas creados con iconos oficiales de AWS usando Draw.io, siguiendo la metodología C4 y estrategia anti-superposición.

### 1. Diagrama C4 Nivel 1 - Contexto del Sistema ✅ CREADO

**Archivo**: `deployment/c1-contexto-framework-batch.drawio`  
**Exportar a**: `docs/assets/c1-contexto-framework-batch.png`

**Descripción**: Vista de alto nivel del sistema mostrando actores externos y el framework como caja negra.

### 2. Diagrama C4 Nivel 2 - Contenedores AWS ✅ CREADO

**Archivo**: `deployment/c2-contenedores-aws-batch.drawio`  
**Exportar a**: `docs/assets/c2-contenedores-aws-batch.png`

**Descripción**: Servicios AWS principales organizados por capas funcionales (Storage, Messaging, Compute, Data).

### 3. Diagrama C4 Nivel 3 - Componentes Lambda ✅ CREADO

**Archivo**: `components/c3-componentes-lambda-functions.drawio`  
**Exportar a**: `docs/assets/c3-componentes-lambda-functions.png`

**Descripción**: Detalle de las 8 funciones Lambda, sus responsabilidades, roles IAM y configuraciones técnicas.

### 4. Diagrama de Flujo Detallado - Ejecución Exitosa ✅ CREADO

**Archivo**: `sequence/flujo-detallado-ejecucion-exitosa.drawio`  
**Exportar a**: `docs/assets/flujo-detallado-ejecucion-exitosa.png`

**Descripción**: Secuencia completa de mensajes y interacciones para una ejecución exitosa del framework.

**Componentes a incluir**:

#### Usuarios y Sistemas Externos
- **Desarrollador** (User icon)
- **Operador** (User icon)  
- **Cluster Redshift** (Redshift icon) - Sistema externo

#### Almacenamiento S3 (4 buckets)
- **Bucket Fuentes** (S3 icon) - Archivos .val, .par, .inc
- **Bucket Definiciones** (S3 icon) - Archivos .yml, scripts
- **Bucket Resultados** (S3 icon) - Outputs procesados
- **Bucket Errores** (S3 icon) - Logs de error

#### Mensajería y Eventos
- **Cola SQS** (SQS icon) - Source Initiator Queue
- **EventBridge** (EventBridge icon) - Eventos de Redshift
- **SES** (SES icon) - Servicio de notificaciones

#### Funciones Lambda (8 funciones)
- **Main Batch Initiator** (Lambda icon)
- **Source Validator** (Lambda icon)
- **Batch Builder** (Lambda icon)
- **Stored Procedure Proxy** (Lambda icon)
- **Status Updater** (Lambda icon)
- **Notifier** (Lambda icon)
- **Error Log Generator** (Lambda icon)
- **Email Sender** (Lambda icon)

#### Orquestación
- **Step Function Principal** (StepFunctions icon) - 17 estados
- **Step Functions Dinámicas** (StepFunctions icon) - Creadas bajo demanda

#### Procesamiento y Datos
- **Glue Job** (Glue icon) - Output Merge
- **DynamoDB** (DynamoDB icon) - Logs de ejecución

**Flujo de conexiones**:
```
Desarrollador → Bucket Definiciones
Operador → Bucket Fuentes → Cola SQS → Main Batch Initiator → Step Function Principal
Step Function Principal → Source Validator ↔ Buckets S3
Step Function Principal → Batch Builder → Step Functions Dinámicas
Step Functions Dinámicas → Stored Procedure Proxy → Cluster Redshift
Cluster Redshift → EventBridge → Status Updater → DynamoDB
Step Functions Dinámicas → Glue Job → Bucket Resultados
Step Function Principal → Notifier → Email Sender → SES
Step Function Principal → Error Log Generator → Bucket Errores
Todas las Lambdas → DynamoDB (logging)
```

### 2. Diagrama de Flujo de Ejecución

**Archivo**: `execution-flow.drawio`  
**Exportar a**: `docs/assets/execution-flow.png`

**Estados de la Step Function Principal (17 estados)**:

#### Estados Principales (6)
1. **SendEmailOnStart** - Notificación de inicio
2. **DynamicBatchSourceValidator** - Validación de archivos
3. **DynamicBatchBuilder** - Construcción de SF dinámica
4. **DynamicBatchLauncher** - Ejecución del lote
5. **DynamicBatchCollector** - Limpieza de recursos
6. **LogBatchToDynamo** - Registro final

#### Estados de Manejo de Errores (6)
1. **NotifyLauncherTimeout** - Error de timeout
2. **SendEmailOnError_LauncherTimeout** - Email de timeout
3. **NotifyLauncherFailure** - Error de ejecución
4. **SendEmailOnError_LauncherFailure** - Email de error
5. **NotifyCollectorFailure** - Error de limpieza
6. **SendEmailOnError_CollectorFailure** - Email de error limpieza

#### Estados Terminales (4)
1. **HandleLauncherTimeout** (Fail)
2. **HandleLauncherFailure** (Fail)
3. **HandleCollectorFailure** (Fail)
4. **SuccessTerminal** (Succeed)

#### Estados de Notificación Final (1)
1. **SendEmailOnSuccess** - Notificación de éxito

### 3. Diagrama de Componentes AWS

**Archivo**: `aws-components.drawio`  
**Exportar a**: `docs/assets/aws-components.png`

**Agrupación por servicio AWS**:

#### Compute
- 8 Lambda Functions con sus roles IAM específicos
- Step Functions (principal + dinámicas)

#### Storage
- 4 S3 Buckets con políticas específicas
- DynamoDB con estructura de claves PK/SK

#### Integration
- SQS Queue con configuración FIFO=false
- EventBridge Rule para Redshift Data API
- SES con plantillas HTML

#### Analytics
- Glue Job para consolidación
- Redshift Cluster (externo)

#### Security
- 12 Roles IAM con políticas específicas
- KMS para encriptación
- Boundary policies

### 4. Diagrama de Flujo de Datos End-to-End

**Archivo**: `data-flow.drawio`  
**Exportar a**: `docs/assets/data-flow.png`

**Flujo completo de datos**:

1. **Entrada de Datos**
   - Desarrollador sube definiciones (.yml) → Bucket Definiciones
   - Operador sube archivos fuente (.val, .par, .inc) → Bucket Fuentes

2. **Disparo del Proceso**
   - Archivo .val → Evento S3 → SQS → Lambda Initiator

3. **Validación**
   - Source Validator verifica archivos vs definición
   - Genera inventario de archivos encontrados/faltantes

4. **Construcción Dinámica**
   - Batch Builder lee definición + parámetros
   - Crea Step Function específica para el proceso

5. **Ejecución**
   - Step Function dinámica ejecuta procedimientos en Redshift
   - Stored Procedure Proxy maneja llamadas a DB
   - Status Updater monitorea via EventBridge

6. **Consolidación**
   - Glue Job unifica outputs en archivo único
   - Resultado final en Bucket Resultados

7. **Notificación y Limpieza**
   - Notifier envía emails de estado
   - Collector elimina recursos temporales
   - Logging completo en DynamoDB

## Especificaciones Técnicas para Diagramas

### Herramientas Requeridas
- **Draw.io Desktop** con biblioteca oficial de iconos AWS
- **Iconos AWS oficiales** exclusivamente
- **Formato de exportación**: PNG y SVG
- **Resolución**: Mínimo 1920x1080 para PNG

### Estándares de Diseño
- **Colores**: Usar paleta oficial de AWS
- **Tipografía**: Arial o similar, tamaño mínimo 10pt
- **Espaciado**: Consistente entre elementos
- **Agrupación**: Usar clusters para organizar componentes relacionados
- **Flujo**: Flechas claras indicando dirección de datos
- **Etiquetas**: Descriptivas y concisas

### Convenciones de Nomenclatura
- **Archivos fuente**: `nombre-descriptivo.drawio`
- **Archivos exportados**: `nombre-descriptivo.png` y `nombre-descriptivo.svg`
- **Ubicación fuente**: `docs/arquitectura/diagramas/`
- **Ubicación exportada**: `docs/assets/`

### Metadatos de Diagramas
Cada diagrama debe incluir:
- **Título**: Descriptivo y específico
- **Fecha de creación**: En formato YYYY-MM-DD
- **Versión**: Número de versión semántica
- **Autor**: Responsable de la creación/actualización
- **Descripción**: Propósito y alcance del diagrama

## Diagramas Eliminados

Los siguientes diagramas fueron eliminados por estar obsoletos:

### Eliminados
- ~~`Diagrama de Despliegue.drawio`~~ - Desactualizado respecto al repositorio y AWS
- ~~`Diagrama de Secuencia.drawio`~~ - Desactualizado respecto al repositorio y AWS

### Movidos
- `Definicion de Salidas.drawio` → `docs/assets/Definicion de Salidas.drawio` (como base para actualización)

## Assets Conservados

Los siguientes assets se mantienen en `docs/assets/` por estar actuales y ser útiles:

- `descripcionBuckets.png` - Descripción general de buckets
- `descripcionBucketSourceRepository.png` - Bucket de fuentes
- `descripcionBucketDefinitionRepository.png` - Bucket de definiciones  
- `descripcionBucketResultRepository.png` - Bucket de resultados
- `currentSourceFilesExample.png` - Ejemplo de archivos fuente
- `procesoEjemplo.png` - Ejemplo de proceso completo

## Próximos Pasos

1. **Instalar Draw.io Desktop** con biblioteca de iconos AWS
2. **Crear diagramas fuente** en formato .drawio
3. **Exportar a PNG/SVG** en docs/assets/
4. **Validar consistencia** con documentación textual
5. **Actualizar referencias** en documentos markdown

---

**Última actualización**: Diciembre 2024  
**Responsable**: Equipo de Arquitectura  
**Versión**: 2.0