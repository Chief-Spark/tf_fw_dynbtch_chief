# Ambiente Trunk

## Metadata
- **Tipo**: ambiente
- **Última Actualización**: 2025-10-15
- **Responsable**: Equipo de Infraestructura
- **Versión**: 1.0.0
- **Estado**: activo

## Descripción

Documentación de infraestructura para el ambiente **trunk** del Framework de Procesos Batch.

## Recursos por Servicio AWS

### CloudWatch

#### aws_cloudwatch_log_group.dynamic_batch_main_batch_logs
- **Archivo**: `trunk\stepfunction.tf`

### SES

#### aws_ses_configuration_set.ses_configuration_set
- **Archivo**: `trunk\ses.tf`

### Unknown

#### aws_lambda_permission.allow_eventbridge_invoke_status_updater_proxy
- **Archivo**: `trunk\eventbridge.tf`

#### aws_s3_object.glue_job_script
- **Archivo**: `trunk\glue.tf`

#### aws_lambda_layer_version.common_python_dependencies
- **Archivo**: `trunk\lambda.tf`

#### aws_lambda_permission.allowS3
- **Archivo**: `trunk\lambda.tf`

#### aws_lambda_permission.allowStepFunctionInvokeSourceValidator
- **Archivo**: `trunk\lambda.tf`

#### aws_lambda_permission.allowStepFunctionInvokeBuilder
- **Archivo**: `trunk\lambda.tf`

#### aws_lambda_permission.allowEventBridgeInvokeStoredProcedureStatusUpdater
- **Archivo**: `trunk\lambda.tf`

#### aws_lambda_permission.allowStepFunctionInvokeStoredProcedureCallProxy
- **Archivo**: `trunk\lambda.tf`

#### aws_lambda_permission.allowStepFunctionInvokeNotifier
- **Archivo**: `trunk\lambda.tf`

#### time_sleep.wait_sqs_policy
- **Archivo**: `trunk\s3.tf`

#### aws_s3_bucket_notification.send_to_sqs
- **Archivo**: `trunk\s3.tf`

#### aws_ses_email_identity.ses_sender_email_identity
- **Archivo**: `trunk\ses.tf`

#### aws_ses_email_identity.ses_recipient_email_identities
- **Archivo**: `trunk\ses.tf`

#### aws_s3_object.ses_email_templates
- **Archivo**: `trunk\ses.tf`

#### aws_lambda_event_source_mapping.events_from_sqs
- **Archivo**: `trunk\sqs.tf`


## Estadísticas

- **Total de Recursos**: 17
- **Servicios AWS Utilizados**: 3
- **Archivos Terraform**: 7

---

**Generado automáticamente**: 2025-10-15 09:14:04
