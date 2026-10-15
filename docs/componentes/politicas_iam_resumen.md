# Resumen de Políticas IAM

## Políticas Comunes

### commonLogsPolicy

| Servicio         | Acción                |
|------------------|----------------------|
| CloudWatch Logs  | logs:CreateLogGroup  |
|                  | logs:CreateLogStream |
|                  | logs:PutLogEvents    |

### commonS3DefinitionAndResult

| Servicio | Acción         | Recurso (ejemplo)                                      |
|----------|---------------|--------------------------------------------------------|
| S3       | s3:GetObject  | dynamicBatchDefinitionRepository, dynamicBatchResultRepository (y sus objetos) |
|          | s3:PutObject  | dynamicBatchDefinitionRepository, dynamicBatchResultRepository (y sus objetos) |
|          | s3:ListBucket | dynamicBatchDefinitionRepository, dynamicBatchResultRepository                |

### commonS3Source

| Servicio | Acción         | Recurso (ejemplo)                        |
|----------|---------------|------------------------------------------|
| S3       | s3:GetObject  | dynamicBatchSourceRepository (y sus objetos) |
|          | s3:ListBucket | dynamicBatchSourceRepository             |

### commonDynamoFileInventory

| Servicio  | Acción                | Recurso (ejemplo)                |
|-----------|----------------------|----------------------------------|
| DynamoDB  | dynamodb:GetItem     | dynamicBatchFileInventory        |
|           | dynamodb:PutItem     | dynamicBatchFileInventory        |
|           | dynamodb:UpdateItem  | dynamicBatchFileInventory        |
|           | dynamodb:Query       | dynamicBatchFileInventory        |
|           | dynamodb:Scan        | dynamicBatchFileInventory        |

### commonDynamoMainBatchEventRecord

| Servicio  | Acción                | Recurso (ejemplo)                |
|-----------|----------------------|----------------------------------|
| DynamoDB  | dynamodb:GetItem     | mainBatchEventRecord             |
|           | dynamodb:PutItem     | mainBatchEventRecord             |
|           | dynamodb:UpdateItem  | mainBatchEventRecord             |
|           | dynamodb:Query       | mainBatchEventRecord             |
|           | dynamodb:Scan        | mainBatchEventRecord             |

### commonDynamoDynamicBatchEventRecord

| Servicio  | Acción                | Recurso (ejemplo)                |
|-----------|----------------------|----------------------------------|
| DynamoDB  | dynamodb:GetItem     | dynamicBatchEventRecord          |
|           | dynamodb:PutItem     | dynamicBatchEventRecord          |
|           | dynamodb:UpdateItem  | dynamicBatchEventRecord          |
|           | dynamodb:Query       | dynamicBatchEventRecord          |
|           | dynamodb:Scan        | dynamicBatchEventRecord          |

### commonRedshiftDataApi

| Servicio           | Acción                          |
|--------------------|---------------------------------|
| Redshift Data API  | redshift-data:ExecuteStatement  |
|                    | redshift-data:GetStatementResult|

### common_kms_decrypt_dynamo

| Servicio | Acción      | Recurso                              |
|----------|------------|--------------------------------------|
| KMS      | kms:Decrypt | ARN de clave KMS para DynamoDB (existente) |

**Propósito**: Permite descifrar datos encriptados con KMS en la tabla DynamoDB de logs de ejecución. Esta clave KMS ya existe y no es creada por este proyecto.

**Recurso**: Variable `kms_key_arn_dynamo`

### common_kms_decrypt_s3

| Servicio | Acción      | Recurso                              |
|----------|------------|--------------------------------------|
| KMS      | kms:Decrypt | ARN de clave KMS para S3 (creada por el proyecto) |

**Propósito**: Permite descifrar datos encriptados con KMS en todos los buckets S3 del sistema. Esta clave KMS es creada por el módulo `kms.tf`.

**Recurso**: `local.kms_alias_arn` (ARN construido determinísticamente)

**Buckets encriptados**:
* Repositorio de fuentes (`dynamic-batch-source-repository`)
* Repositorio de definiciones (`dynamic-batch-definition-repository`)
* Repositorio de resultados (`dynamic-batch-result-repository`)
* Archivos de error (`error-files`)

**Aplicación**: Todos los roles IAM del proyecto tienen acceso a ambas políticas KMS para garantizar acceso a datos encriptados

---

## Políticas Específicas de Lambdas y Step Functions

### policyDynamicBatchSourceValidator

| Servicio             | Acción                                 |
|----------------------|----------------------------------------|
| DynamoDB             | dynamodb:GetItem                       |
|                      | dynamodb:PutItem                       |
|                      | dynamodb:UpdateItem                    |
|                      | dynamodb:Query                         |
|                      | dynamodb:Scan                          |
| S3                   | s3:GetObject                           |
|                      | s3:PutObject                           |
|                      | s3:ListBucket                          |
| Step Functions       | states:SendTaskFailure                 |
|                      | states:SendTaskSuccess                 |
|                      | states:StartExecution                  |
|                      | states:DescribeExecution               |
|                      | states:StopExecution                   |
|                      | states:CreateStateMachine              |
|                      | states:DeleteStateMachine              |
|                      | states:TagResource                     |
| Redshift Data API    | redshift-data:ExecuteStatement         |
|                      | redshift-data:GetStatementResult       |

### policyDynamicBatchBuilder

| Servicio             | Acción                                 |
|----------------------|----------------------------------------|
| DynamoDB             | dynamodb:GetItem                       |
|                      | dynamodb:PutItem                       |
|                      | dynamodb:UpdateItem                    |
|                      | dynamodb:Query                         |
|                      | dynamodb:Scan                          |
| S3                   | s3:GetObject                           |
|                      | s3:PutObject                           |
|                      | s3:ListBucket                          |
| Step Functions       | states:SendTaskFailure                 |
|                      | states:SendTaskSuccess                 |
|                      | states:StartExecution                  |
|                      | states:DescribeExecution               |
|                      | states:StopExecution                   |
|                      | states:CreateStateMachine              |
|                      | states:DeleteStateMachine              |
|                      | states:TagResource                     |
| Redshift Data API    | redshift-data:ExecuteStatement         |
|                      | redshift-data:GetStatementResult       |
| IAM                  | iam:PassRole                           |

### policyDynamicBatchLauncher

| Servicio             | Acción                                 |
|----------------------|----------------------------------------|
| DynamoDB             | dynamodb:GetItem                       |
|                      | dynamodb:PutItem                       |
|                      | dynamodb:UpdateItem                    |
|                      | dynamodb:Query                         |
|                      | dynamodb:Scan                          |
| S3                   | s3:GetObject                           |
|                      | s3:PutObject                           |
|                      | s3:ListBucket                          |
| Step Functions       | states:SendTaskFailure                 |
|                      | states:SendTaskSuccess                 |
|                      | states:StartExecution                  |
|                      | states:DescribeExecution               |
|                      | states:StopExecution                   |
|                      | states:CreateStateMachine              |
|                      | states:DeleteStateMachine              |
|                      | states:TagResource                     |
| Redshift Data API    | redshift-data:ExecuteStatement         |
|                      | redshift-data:GetStatementResult       |

### policyDynamicBatchCollector

| Servicio             | Acción                                 |
|----------------------|----------------------------------------|
| DynamoDB             | dynamodb:GetItem                       |
|                      | dynamodb:PutItem                       |
|                      | dynamodb:UpdateItem                    |
|                      | dynamodb:Query                         |
|                      | dynamodb:Scan                          |
| S3                   | s3:GetObject                           |
|                      | s3:PutObject                           |
|                      | s3:ListBucket                          |
| Step Functions       | states:SendTaskFailure                 |
|                      | states:SendTaskSuccess                 |
|                      | states:StartExecution                  |
|                      | states:DescribeExecution               |
|                      | states:StopExecution                   |
|                      | states:CreateStateMachine              |
|                      | states:DeleteStateMachine              |
|                      | states:TagResource                     |
| Redshift Data API    | redshift-data:ExecuteStatement         |
|                      | redshift-data:GetStatementResult       |

### policyDynamicBatchSourceLoader

| Servicio             | Acción                                 |
|----------------------|----------------------------------------|
| DynamoDB             | dynamodb:GetItem                       |
|                      | dynamodb:PutItem                       |
|                      | dynamodb:UpdateItem                    |
|                      | dynamodb:Query                         |
|                      | dynamodb:Scan                          |
| S3                   | s3:GetObject                           |
|                      | s3:PutObject                           |
|                      | s3:ListBucket                          |
| Step Functions       | states:SendTaskFailure                 |
|                      | states:SendTaskSuccess                 |
|                      | states:StartExecution                  |
|                      | states:DescribeExecution               |
|                      | states:StopExecution                   |
|                      | states:CreateStateMachine              |
|                      | states:DeleteStateMachine              |
|                      | states:TagResource                     |
| Redshift Data API    | redshift-data:ExecuteStatement         |
|                      | redshift-data:GetStatementResult       |
