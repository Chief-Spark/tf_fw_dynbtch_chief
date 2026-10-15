# Ambiente Demo - Framework Procesos Batch

## Descripción

El ambiente **demo** es un entorno de demostración y pruebas iniciales del Framework de Procesos Batch. Este ambiente se utiliza para validar funcionalidades básicas y realizar demostraciones a stakeholders.

## Características del Ambiente

### Configuración General

- **Stage**: `demo`
- **Región AWS**: `us-east-1`
- **Proyecto**: `fwdynbtch`
- **Environment Tag**: `demo`

### Backend de Terraform

- **Bucket S3**: `339712808864-demo-frameworkprocesosbatch-terraform-state`
- **Tabla DynamoDB**: `339712808864-demo-frameworkprocesosbatch-terraform-locks`
- **Key**: `framework-procesos-batch/demo/terraform.tfstate`

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
  Environment = "demo"
  Project     = "fwdynbtch"
  ManagedBy   = "Terraform"
  CostString  = "1850.CO.135.601023"
  AppID       = "26099"
}
```

## Uso del Ambiente

### Inicialización

```bash
cd demo
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

- Demostraciones a clientes
- Pruebas de funcionalidad básica
- Validación de configuraciones iniciales
- Testing de nuevos features

### Limitaciones

- No contiene datos de producción
- Recursos mínimos para funcionamiento básico
- Configuraciones de seguridad relajadas para facilitar pruebas

### Acceso

- Acceso limitado a equipo de desarrollo
- No requiere aprobaciones especiales para cambios
- Ideal para pruebas rápidas y experimentación

## Troubleshooting

### Problemas Comunes

1. **Error de permisos en S3**
   - Verificar que el bucket del backend existe
   - Confirmar permisos de lectura/escritura

2. **Error de conexión a Redshift**
   - Verificar que el cluster está activo
   - Confirmar configuración de seguridad

3. **Error de KMS**
   - Verificar que la clave KMS existe
   - Confirmar permisos de uso de la clave

### Comandos de Diagnóstico

```bash
# Verificar estado del backend
terraform show

# Listar recursos
terraform state list

# Verificar configuración
terraform validate
```

## Contacto

Para problemas específicos del ambiente demo, contactar al equipo de desarrollo.
