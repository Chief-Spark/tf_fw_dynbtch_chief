module "kms" {
  source      = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-kms.git?ref=1.9.0"
  aliases     = [join("-", ["${local.account_id}", "s3", var.project_name])]
  description = "KMS for ${var.project_name}"
  tags        = local.combined_tags
  key_owners = concat(
    local.kms_common_admin_roles,
    lookup(local.kms_jenkins_roles_by_stage, var.stage, []),
    var.kms_key_owners_additional
  )
  
  key_administrators = concat(
    local.kms_common_admin_roles,
    [data.aws_iam_session_context.kms_current.issuer_arn],
    lookup(local.kms_jenkins_roles_by_stage, var.stage, []),
    lookup(local.kms_dto_roles_by_stage, var.stage, []),
    var.kms_key_owners_additional
  )
  
  key_users = concat(
    lookup(local.kms_dto_roles_by_stage, var.stage, []),
    tolist(local.project_roles_arns),
    ["arn:aws:iam::${local.account_id}:role/${var.kms_administrator_role_name}"],
    [
      module.iam_main_batch_initiator.role_arn,
      module.iam_dynamic_batch_builder.role_arn,
      module.iam_dynamic_batch_source_validator.role_arn,
      module.iam_dynamic_batch_stored_procedure_status_updater.role_arn,
      module.iam_dynamic_batch_child_batch.role_arn,
      module.iam_dynamic_batch_main_batch.role_arn,
      module.iam_dynamic_batch_glue.role_arn,
      module.iam_dynamic_batch_notifier.role_arn,
      local.iam_procs_espec_batch_role_arn,
      local.iam_carguedebases_role_arn,
      local.iam_procs_espec_batch_upload_role_arn,
      local.iam_carguedebases_output_role_arn,
      local.iam_neda_batch_redshift_role_arn,
      local.iam_edf_batch_redshift_role_arn
    ],
    # Cross-account: roles remotos de destinos Redshift (assume_role_arn de
    # redshift_targets). Necesitan Decrypt/GenerateDataKey para COPY/UNLOAD sobre
    # los buckets del framework cifrados con esta KMS. Dinámico: N destinos.
    local.redshift_targets_assume_role_arns,
    var.kms_key_users_additional
  )

  key_services = ["logging.s3"]

  # Dependencia explícita: los roles IAM deben existir antes de KMS
  depends_on = [
    module.iam_main_batch_initiator,
    module.iam_dynamic_batch_builder,
    module.iam_dynamic_batch_source_validator,
    module.iam_dynamic_batch_stored_procedure_status_updater,
    module.iam_dynamic_batch_child_batch,
    module.iam_dynamic_batch_main_batch,
    module.iam_dynamic_batch_glue,
    module.iam_dynamic_batch_notifier,
  ]
}

