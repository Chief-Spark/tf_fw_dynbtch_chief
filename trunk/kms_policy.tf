# =====================================================================
# KMS Key Policy - Actualización para incluir roles del proyecto
# =====================================================================
# Este recurso actualiza la política de KMS DESPUÉS de que todos los
# recursos estén creados, evitando la dependencia circular entre:
# Roles IAM → Policy Documents (S3) → Buckets S3 (KMS) → KMS (Roles)
# =====================================================================

data "aws_iam_session_context" "kms_current" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_iam_policy_document" "kms_with_project_roles" {
  
  # Key owner - all key operations
  statement {
    sid       = "KeyOwner"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type = "AWS"
      identifiers = concat(
        local.kms_common_admin_roles,
        lookup(local.kms_jenkins_roles_by_stage, var.stage, []),
        var.kms_key_owners_additional
      )
    }
  }

  # Key administrators
  statement {
    sid = "KeyAdministration"
    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]
    resources = ["*"]

    principals {
      type = "AWS"
      identifiers = concat(
        local.kms_common_admin_roles,
        [data.aws_iam_session_context.kms_current.issuer_arn],
        lookup(local.kms_jenkins_roles_by_stage, var.stage, []),
        lookup(local.kms_dto_roles_by_stage, var.stage, []),
        var.kms_key_owners_additional
      )
    }
  }

  # Key users - INCLUYE los roles del proyecto
  statement {
    sid = "KeyUsageUsers"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type = "AWS"
      identifiers = concat(
        tolist(local.project_roles_arns),
        lookup(local.kms_dto_roles_by_stage, var.stage, []),
        ["arn:aws:iam::${local.account_id}:role/${var.kms_administrator_role_name}",
         local.iam_carguedebases_role_arn,
         local.iam_procs_espec_batch_role_arn,
         local.iam_carguedebases_output_role_arn,
         local.iam_neda_batch_redshift_role_arn,
         local.iam_edf_batch_redshift_role_arn],
        # Cross-account: roles remotos de destinos Redshift (assume_role_arn).
        local.redshift_targets_assume_role_arns,
        var.kms_key_users_additional
      )
    }
  }

}

# Aplicar la política actualizada DESPUÉS de que todos los recursos estén creados
/*resource "aws_kms_key_policy" "project_roles_policy" {
  key_id = module.kms.key_id
  policy = data.aws_iam_policy_document.kms_with_project_roles.json

  # Dependencias explícitas para garantizar el orden correcto
  depends_on = [
    module.kms,
    module.iam_main_batch_initiator,
    module.iam_dynamic_batch_builder,
    module.iam_dynamic_batch_source_validator,
    module.iam_dynamic_batch_stored_procedure_status_updater,
    module.iam_dynamic_batch_child_batch,
    module.iam_dynamic_batch_main_batch,
    module.iam_dynamic_batch_glue,
    module.iam_dynamic_batch_notifier
  ]
}
*/

 