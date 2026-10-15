# Ambiente Develop - Framework Procesos Batch

## Descripción

El ambiente **develop** es el entorno de desarrollo principal del Framework de Procesos Batch. Este ambiente se utiliza para el desarrollo activo de nuevas funcionalidades, testing de integración y validación de cambios antes de promover a ambientes superiores.

## Características del Ambiente

### Configuración General

- **Stage**: `dev`
- **Región AWS**: `us-east-1`
- **Proyecto**: `fwdynbtch`
- **Environment Tag**: `dev`

### Backend de Terraform

- **Bucket S3**: `339712808864-develop-dynamicbatchframework-terraform-state`
- **Tabla DynamoDB**: `339712808864-develop-dynamicbatchframework-terraform-locks`
- **Key**: `framework-procesos-batch/develop/terraform.tfstate`

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
  Environment = "dev"
  Project     = "fwdynbtch"
  ManagedBy   = "Terraform"
  CostString  = "1850.CO.135.601023"
  AppID       = "26099"
}
```

## Uso del Ambiente

### Inicialización

```bash
cd develop
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

- Desarrollo activo de nuevas funcionalidades
- Testing de integración continua
- Validación de cambios antes de QA
- Experimentación con nuevas configuraciones

### Características de Desarrollo

- Recursos optimizados para desarrollo
- Configuraciones flexibles para testing
- Logs detallados para debugging
- Acceso directo para desarrolladores

### Workflow de Desarrollo

1. **Desarrollo Local**: Cambios en código fuente
2. **Testing en Develop**: Validación de funcionalidades
3. **Promoción a QA**: Después de validación exitosa
4. **Promoción a Producción**: Después de QA exitoso

## Integración Continua

### Pipeline de CI/CD

- Automatización de despliegues
- Testing automático de configuraciones
- Validación de sintaxis Terraform
- Notificaciones de cambios

### Prácticas de Desarrollo

- Branch-based development
- Code reviews obligatorios
- Testing antes de merge
- Documentación de cambios

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

4. **Error de Lambda**
   - Verificar logs de CloudWatch
   - Confirmar permisos de ejecución
   - Validar configuración de timeout

### Comandos de Diagnóstico

```bash
# Verificar estado del backend
terraform show

# Listar recursos
terraform state list

# Verificar configuración
terraform validate

# Verificar formato
terraform fmt -check

# Verificar logs de Lambda
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"
```

### Debugging Avanzado

```bash
# Verificar recursos específicos
terraform state show aws_lambda_function.main_batch_initiator

# Importar recursos existentes
terraform import aws_s3_bucket.example bucket-name

# Verificar variables
terraform console
```

## Monitoreo y Alertas

### Métricas Importantes

- Latencia de ejecución de Lambda
- Tasa de error de funciones
- Uso de recursos S3
- Conexiones a Redshift

### Alertas Configuradas

- Errores de ejecución de Lambda
- Timeouts de funciones
- Errores de conexión a base de datos
- Uso excesivo de recursos

## Contacto

Para problemas específicos del ambiente develop, contactar al equipo de desarrollo o DevOps.
