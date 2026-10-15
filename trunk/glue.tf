module "glue_dynamic_batch_output_merge" {
  source               = "../modules/eits-tf-aws-glue-1.3.2@398b232167c"
  create_service_role  = false
  create_cloudwatch_logs = false
  service_role_arn     = module.iam_dynamic_batch_glue.role_arn
  database_name        = "${var.stage}_${data.aws_caller_identity.current.account_id}_${var.project_name}_temp_db"
  database_description = "Base de datos dummy"
  tags                 = local.combined_tags
  jobs = {
    "${local.resource_prefix}-dynamic-batch-output-merge" = {
      description  = "Dynamic Batch Output Merge Job"
      glue_version = "5.0"
      max_capacity = 2
      timeout      = 360
      default_arguments = {
        "--S3_DESTINATION_BUCKET"        = module.s3_dynamic_batch_result_repository.s3_bucket_id
        "--S3_SOURCE_BUCKET"             = module.s3_dynamic_batch_result_repository.s3_bucket_id
        # Source repository bucket where PESVNO drops .val/.inc (trigger artifacts)
        "--S3_TRIGGER_BUCKET"            = module.s3_dynamic_batch_source_repository.s3_bucket_id
        "--MAX_WORKERS"                  = var.glue_max_workers
        "--BUSINESS_TABLE"               = var.business_table_name
        "--OBJECT_TRACKING_TABLE"        = var.object_tracking_table_name
        # Glue 5.0: --custom-logGroup-prefix reemplaza --continuous-log-logGroup
        "--custom-logGroup-prefix"       = "${local.resource_prefix}-glue-output-merge"
        "--DYNAMO_LOGS_TABLE"     = var.dynamo_logs_table_name
        "--extra-py-files"        = "s3://${module.s3_dynamic_batch_definition_repository.s3_bucket_id}/scripts/object_tracking_writer.py"
      }
      command = {
        script_location = "s3://${module.s3_dynamic_batch_definition_repository.s3_bucket_id}/scripts/output_merge.py"
        python_version  = "3"
        name            = "glueetl"
      }
      execution_property = {
        max_concurrent_runs = 30
      }
    }
  }
  depends_on = [aws_s3_object.glue_job_script, aws_s3_object.glue_object_tracking_writer]
}

resource "aws_s3_object" "glue_job_script" {
  bucket = module.s3_dynamic_batch_definition_repository.s3_bucket_id
  key    = "scripts/output_merge.py"
  source = "../src/dynamicBatchOutputMerge/output_merge.py"
  etag   = filemd5("../src/dynamicBatchOutputMerge/output_merge.py")
  depends_on = [
    module.s3_dynamic_batch_definition_repository,
    //aws_kms_key_policy.project_roles_policy
  ]
}

resource "aws_s3_object" "glue_object_tracking_writer" {
  bucket = module.s3_dynamic_batch_definition_repository.s3_bucket_id
  key    = "scripts/object_tracking_writer.py"
  source = "../src/dynamicBatchOutputMerge/object_tracking_writer.py"
  etag   = filemd5("../src/dynamicBatchOutputMerge/object_tracking_writer.py")
  depends_on = [
    module.s3_dynamic_batch_definition_repository,
  ]
}