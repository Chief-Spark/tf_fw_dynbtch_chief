# Ambiente QA - Framework Procesos Batch

## Descripción

El ambiente **QA** es el entorno de control de calidad del Framework de Procesos Batch. Este ambiente se utiliza para realizar pruebas exhaustivas de funcionalidades, validación de rendimiento y testing de integración antes de promover a producción.

## Características del Ambiente

### Configuración General

- **Stage**: `qa`
- **Región AWS**: `us-east-1`
- **Proyecto**: `fwdynbtch`
- **Environment Tag**: `qa`

### Backend de Terraform

- **Bucket S3**: `339712808864-qa-dynamicbatchframework-terraform-state`
- **Tabla DynamoDB**: `339712808864-qa-dynamicbatchframework-terraform-locks`
- **Key**: `framework-procesos-batch/qa/terraform.tfstate`

### Recursos Compartidos

- **Redshift Cluster**: `dev-339712808864-redshift-redshift-cluster`
- **Base de Datos**: `dynamicbatch`
- **Usuario DB**: `lambda_user`
- **Tabla Logs**: `dev-339712808864-fwdynbtch-logs`
- **KMS Key**: `339712808864-fwdynbtch-kms`

## Configuración de Seguridad

### Configuraciones Habilitadas

- ✅ `disable_source_vpce_check = true`
- ✅ `disable_source_ip_check = true`
- ✅ `disable_default_alarms = false`
- ✅ `enable_create_role = true`

### Tags de Recursos

```hcl
default_tags = {
  Environment = "qa"
  Project     = "fwdynbtch"
  ManagedBy   = "Terraform"
  CostString  = "1850.CO.135.601023"
  AppID       = "26099"
}
```

## Uso del Ambiente

### Inicialización

```bash
cd qa
terraform init
```

### Planificación

```bash
terraform plan
```

### Aplicación

```bash
terraform apply
```

### Destrucción (Cuidado)

```bash
terraform destroy
```

## Consideraciones Especiales

### Propósito

- Testing exhaustivo de funcionalidades
- Validación de rendimiento y escalabilidad
- Testing de integración con sistemas externos
- Validación de configuraciones de producción
- Testing de casos de uso complejos

### Características de QA

- Configuración similar a producción
- Datos de prueba representativos
- Monitoreo detallado de rendimiento
- Logs completos para análisis

### Workflow de QA

1. **Promoción desde Develop**: Cambios validados en develop
2. **Testing Funcional**: Validación de todas las funcionalidades
3. **Testing de Rendimiento**: Pruebas de carga y escalabilidad
4. **Testing de Integración**: Validación con sistemas externos
5. **Aprobación para Producción**: Después de QA exitoso

## Testing y Validación

### Tipos de Testing

- **Testing Funcional**: Validación de todas las funcionalidades
- **Testing de Rendimiento**: Pruebas de carga y escalabilidad
- **Testing de Integración**: Validación con Redshift y otros servicios
- **Testing de Seguridad**: Validación de configuraciones de seguridad
- **Testing de Recuperación**: Validación de procesos de backup/restore

### Criterios de Aprobación

- Todas las funcionalidades operativas
- Rendimiento dentro de parámetros esperados
- Sin errores críticos en logs
- Configuraciones de seguridad validadas
- Documentación actualizada

## Monitoreo y Alertas

### Métricas Críticas

- Tiempo de respuesta de Lambda
- Tasa de éxito de ejecuciones
- Uso de recursos de Redshift
- Latencia de operaciones S3
- Errores de autenticación/autorización

### Alertas Configuradas

- Errores de ejecución de Lambda
- Timeouts de funciones
- Errores de conexión a base de datos
- Uso excesivo de recursos
- Fallos de autenticación

## Troubleshooting

### Problemas Comunes

1. **Error de permisos en S3**
   - Verificar que el bucket del backend existe
   - Confirmar permisos de lectura/escritura
   - Validar configuración de IAM

2. **Error de conexión a Redshift**
   - Verificar que el cluster está activo
   - Confirmar configuración de seguridad
   - Validar credenciales de conexión

3. **Error de KMS**
   - Verificar que la clave KMS existe
   - Confirmar permisos de uso de la clave
   - Validar políticas de encriptación

4. **Problemas de Rendimiento**
   - Analizar logs de CloudWatch
   - Verificar configuración de timeout
   - Validar recursos asignados

### Comandos de Diagnóstico

```bash
# Verificar estado del backend
terraform show

# Listar recursos
terraform state list

# Verificar configuración
terraform validate

# Verificar logs de Lambda
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# Analizar métricas de rendimiento
aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Duration
```

### Debugging Avanzado

```bash
# Verificar recursos específicos
terraform state show aws_lambda_function.main_batch_initiator

# Analizar logs de CloudWatch
aws logs filter-log-events --log-group-name "/aws/lambda/dynamicBatchMainBatchInitiator"

# Verificar métricas de Redshift
aws cloudwatch get-metric-statistics --namespace AWS/Redshift
```

## Proceso de Promoción

### Criterios para Promoción a Producción

- ✅ Testing funcional completo
- ✅ Testing de rendimiento exitoso
- ✅ Testing de integración validado
- ✅ Configuraciones de seguridad aprobadas
- ✅ Documentación actualizada
- ✅ Aprobación del equipo de QA

### Checklist de Promoción

- [ ] Todas las funcionalidades operativas
- [ ] Rendimiento dentro de parámetros
- [ ] Sin errores críticos
- [ ] Configuraciones validadas
- [ ] Documentación actualizada
- [ ] Aprobación de stakeholders

## Contacto

Para problemas específicos del ambiente QA, contactar al equipo de QA o DevOps.
