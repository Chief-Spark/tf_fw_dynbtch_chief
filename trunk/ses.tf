resource "aws_ses_configuration_set" "ses_configuration_set" {
  name = "${local.resource_prefix}-${var.ses_config_email_name}"
}

resource "aws_ses_email_identity" "ses_sender_email_identity" {
  email = var.ses_sender_email

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_object" "ses_email_templates" {
  for_each = fileset("${path.module}/../src/templatesSES/", "*")
  bucket   = module.s3_error_files.s3_bucket_id
  key      = "templates_ses/${each.value}"
  source   = "${path.module}/../src/templatesSES/${each.value}"
  etag     = filemd5("${path.module}/../src/templatesSES/${each.value}")
  depends_on = [
    module.s3_error_files,
    //aws_kms_key_policy.project_roles_policy
  ]
}
