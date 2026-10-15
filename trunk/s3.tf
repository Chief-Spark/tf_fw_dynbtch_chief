module "s3_dynamic_batch_source_repository" {
  source                    = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-s3.git?ref=2.15.0"
  bucket_name               = local.s3_source_repository_name
  versioning_enabled        = true
  disable_default_alarms    = var.disable_default_alarms
  alarm_sns_topics          = local.cloudwatch_alarm_sns_topics
  disable_source_vpce_check = var.disable_source_vpce_check
  disable_source_ip_check   = var.disable_source_ip_check
  sse_algorithm             = "aws:kms"
  kms_key_arn               = module.kms.key_arn
  tags                      = local.combined_tags
  bucket_policy             = data.aws_iam_policy_document.source_repository_bucket_policy.json


  lifecycle_rules = [
    {
      id     = "ExpireDynamicBatch7d_AllObjects"
      status = "Enabled"

      expiration = {
        days = 60
      }

      abort_incomplete_multipart_upload_days = 1
    }
  ]

  intelligent_tiering = {
    default = {
      status = "Enabled"
      tiering = {
        ARCHIVE_ACCESS = {
          days = 90
        }
        DEEP_ARCHIVE_ACCESS = {
          days = 180
        }
      }
    }
  }
}

module "s3_dynamic_batch_definition_repository" {
  source                    = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-s3.git?ref=2.15.0"
  bucket_name               = local.s3_definition_repository_name
  versioning_enabled        = true
  disable_default_alarms    = var.disable_default_alarms
  alarm_sns_topics          = local.cloudwatch_alarm_sns_topics
  disable_source_vpce_check = var.disable_source_vpce_check
  disable_source_ip_check   = var.disable_source_ip_check
  sse_algorithm             = "aws:kms"
  kms_key_arn               = module.kms.key_arn
  tags                      = local.combined_tags
  bucket_policy             = data.aws_iam_policy_document.administrator_bucket_access["definition"].json

  lifecycle_rules = []

  intelligent_tiering = {
    default = {
      status = "Enabled"
      tiering = {
        ARCHIVE_ACCESS = {
          days = 90
        }
        DEEP_ARCHIVE_ACCESS = {
          days = 180
        }
      }
    }
  }

}

resource "aws_s3_object" "dynamic_process_definitions" {
  for_each = fileset("${path.module}/../src/dynamicProcessDefinitions/", "*")
  bucket   = module.s3_dynamic_batch_definition_repository.s3_bucket_id
  key      = each.value
  source   = "${path.module}/../src/dynamicProcessDefinitions/${each.value}"
  etag     = filemd5("${path.module}/../src/dynamicProcessDefinitions/${each.value}")
  depends_on = [
    module.s3_dynamic_batch_definition_repository,
    //aws_kms_key_policy.project_roles_policy
  ]
}

module "s3_dynamic_batch_result_repository" {
  source                    = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-s3.git?ref=2.15.0"
  bucket_name               = local.s3_result_repository_name
  versioning_enabled        = true
  disable_default_alarms    = var.disable_default_alarms
  alarm_sns_topics          = local.cloudwatch_alarm_sns_topics
  disable_source_vpce_check = var.disable_source_vpce_check
  disable_source_ip_check   = var.disable_source_ip_check
  sse_algorithm             = "aws:kms"
  kms_key_arn               = module.kms.key_arn
  tags                      = local.combined_tags
  bucket_policy             = data.aws_iam_policy_document.result_repository_bucket_policy.json

  lifecycle_rules = [
    {
      id     = "ExpireDynamicBatch7d_AllObjects"
      status = "Enabled"

      expiration = {
        days = 60
      }

      abort_incomplete_multipart_upload_days = 1
    }
  ]

  intelligent_tiering = {
    default = {
      status = "Enabled"
      tiering = {
        ARCHIVE_ACCESS = {
          days = 90
        }
        DEEP_ARCHIVE_ACCESS = {
          days = 180
        }
      }
    }
  }
}

# Cola SQS para archivos YAML (pesvno)
data "aws_sqs_queue" "pesvno_cloud_queue" {
  name = "${var.env_pesvno}-${data.aws_caller_identity.current.account_id}-${var.name_sqs_pesvno}"
}

# Espera para garantizar que la SQS se creo y se pudo adjuntar su policy
resource "time_sleep" "wait_sqs_policy" {
  depends_on      = [module.source_initiator_sqs]
  create_duration = "30s"
}

resource "aws_s3_bucket_notification" "send_to_sqs" {
  bucket = module.s3_dynamic_batch_source_repository.s3_bucket_id
  queue {
    queue_arn     = module.source_initiator_sqs.queue_arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = ""
    filter_suffix = ".val"
  }
  queue {
    queue_arn     = data.aws_sqs_queue.pesvno_cloud_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = ""
    filter_suffix = ".yaml"
  }
  depends_on = [module.source_initiator_sqs, data.aws_sqs_queue.pesvno_cloud_queue, aws_sqs_queue_policy.pesvno_cloud_queue, time_sleep.wait_sqs_policy]
}

module "s3_error_files" {
  source                    = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-s3.git?ref=2.15.0"
  bucket_name               = local.s3_error_files_name
  disable_default_alarms    = var.disable_default_alarms
  alarm_sns_topics          = local.cloudwatch_alarm_sns_topics
  disable_source_vpce_check = var.disable_source_vpce_check
  disable_source_ip_check   = var.disable_source_ip_check
  sse_algorithm             = "aws:kms"
  kms_key_arn               = module.kms.key_arn
  tags                      = local.combined_tags
  bucket_policy             = data.aws_iam_policy_document.administrator_bucket_access["error"].json

  lifecycle_rules = [
    {
      id     = "abort-incomplete-multipart-uploads"
      status = "Enabled"

      abort_incomplete_multipart_upload_days = 1
    }
  ]
}

# POC Anonimizador: bucket de salida en esta cuenta, escrito por la EC2 de la otra cuenta

# Translator S3 artifacts module moved to `develop/translator_s3.tf`.
