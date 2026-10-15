# Contexto operativo: sync Translator / Dynamic Batch

## Objetivo

Integrar cambios funcionales desde `nu-migrator-agents-tools` hacia este repositorio cliente sin romper el formato de despliegue, Terraform ni convenciones Experian.

## Reglas de sync

- `nu-migrator-agents-tools` es referencia funcional; este repositorio manda en estructura y despliegue.
- No reemplazar carpetas completas sin comparar.
- Frontend cliente: `src/translatorFrontend/frontend/`.
- Dockerfile cliente: `src/translatorFrontend/Dockerfile`.
- Backend/layer cliente: `src/translatorBatchLib/backend/`.
- Lambdas cliente: carpetas bajo `src/` (código fuente; el deploy lo hace `tf_trnsltr_btch`).

## Separación de despliegue (develop)

| Responsabilidad | Repo |
|-----------------|------|
| Infra Translator (Lambdas, IAM, SFN, DDB, ECR repo, ECS service, API GW) | `tf_fw_dynbtch` |
| Código Lambdas, layer `translator_shared`, imagen frontend ECR/ECS | `tf_trnsltr_btch` (`scripts/deploy.py`) |
| Layer `common_python_dependencies` (batch dinámico) | `tf_fw_dynbtch` |

Terraform en `develop/translator_lambda.tf` usa ZIP bootstrap + `lifecycle.ignore_changes` para no pisar código/layers desplegados por `tf_trnsltr_btch`. La task definition ECS ignora cambios en `container_definitions` (imagen).

## Frontend y backend translator

Cambios sincronizados desde `nu` para SP Translator y validación de dependencias:

- `src/translatorFrontend/frontend/app.py`
- `src/translatorFrontend/frontend/utils/api_client.py`
- `src/translatorFrontend/frontend/views/sp_profiler_page.py`
- `src/translatorFrontend/frontend/views/sp_translator_page.py`
- `src/translatorBatchLib/backend/main.py`

Mantener el Dockerfile cliente. Usa ECR Public, puerto `8000`, healthcheck Streamlit y contexto `src/translatorFrontend`.

## Lambdas nuevas

Se integran como recursos propios del cliente:

- `src/translatorProcessBuilder/`
- `src/translatorQaProcessBuilder/`

Variables declaradas para `develop`:

- Translator Process Builder: `translator_process_builder_s3_input_bucket`, `translator_process_builder_s3_output_bucket`, `translator_process_builder_redshift_*`.
- Translator QA Process Builder: `translator_qa_process_builder_bucket_reglas`, `translator_qa_process_builder_bucket_definition`, `translator_qa_process_builder_bucket_source`.

Notas:

- `translatorProcessBuilder` acepta URIs `s3://bucket/prefix/`.
- El código fuente original de Process Builder venía con strings `urldefense.com`; fueron removidos en la copia integrada bajo `src/translatorProcessBuilder/`.
- Antes de aplicar Terraform, revisar IAM S3/KMS/Redshift Data API y riesgo de reemplazo.
- Jenkins `before_build` (develop): solo `verify-versioned-layer.sh` para el layer batch `common_python_dependencies`.
- Tras cambios de código translator: ejecutar pipeline de `tf_trnsltr_btch` (no depender de apply en este repo para publicar ZIP/layer/imagen).

## Despliegue frontend

En `develop`, la imagen y el rollout ECS los publica `tf_trnsltr_btch`:

- Build Docker + push ECR + register task definition + update ECS service (`scripts/deploy.py`).

Este repo mantiene el repo ECR, roles IAM, task definition base y ECS service. `translator_frontend_container_image_tag` en `develop/terraform.tfvars` sirve solo como valor inicial de bootstrap; los updates de imagen no requieren bump de `version` en `.jenkins.yml` de este repo.

`qa`, `demo` y `production` requieren revisión adicional: hoy no replican necesariamente el flujo de código translator de `develop` y pueden seguir apuntando a placeholder público.
