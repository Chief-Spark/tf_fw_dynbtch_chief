# =============================================================================
# Cross-account: permite que las cuentas remotas de los destinos Redshift
# (redshift_targets[*].assume_role_arn) reenvíen al bus "default" de esta
# cuenta el evento "Redshift Data Statement Status Change".
# =============================================================================
# Motivo: cuando Step Functions ejecuta redshiftdata:executeStatement con
# Credentials.RoleArn (rol remoto), AWS publica ese evento en la cuenta que
# hizo la llamada (la cuenta remota), NO en esta cuenta. Ver:
# https://docs.aws.amazon.com/redshift/latest/mgmt/data-api-monitoring-events.html
#   "Events are sent to the account that contains the Amazon Redshift
#    database. For example, if you assume a role in another account, events
#    are sent to that account."
#
# La cuenta remota reenvía ese evento hacia este bus mediante su propia regla
# de EventBridge (definida en su Terraform, p.ej. tf_rcncr_cld_trrfrm:
# redshift_crossaccount_eventbridge.tf, usando el mismo rol cross-account que
# ya asume el child_batch de este Framework). Esta policy es la contraparte
# que autoriza esa entrega en el bus "default" de esta cuenta; sin ella, el
# reenvío recibe AccessDenied.
#
# Se deriva de local.redshift_targets_assume_role_arns (ya existente en
# locals.tf) - no se agrega ninguna variable nueva. Si ningún destino de
# redshift_targets define assume_role_arn, no se crea ninguna policy.
# =============================================================================

locals {
  redshift_targets_assume_role_account_ids = distinct([
    for arn in local.redshift_targets_assume_role_arns : split(":", arn)[4]
  ])
}

data "aws_iam_policy_document" "redshift_crossaccount_eventbridge_bus" {
  count = length(local.redshift_targets_assume_role_account_ids) > 0 ? 1 : 0

  statement {
    sid       = "AllowRedshiftCrossAccountPutEvents"
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = ["arn:aws:events:${var.region}:${local.account_id}:event-bus/default"]

    principals {
      type        = "AWS"
      identifiers = [for id in local.redshift_targets_assume_role_account_ids : "arn:aws:iam::${id}:root"]
    }
  }
}

resource "aws_cloudwatch_event_bus_policy" "redshift_crossaccount_forward" {
  count          = length(local.redshift_targets_assume_role_account_ids) > 0 ? 1 : 0
  event_bus_name = "default"
  policy         = data.aws_iam_policy_document.redshift_crossaccount_eventbridge_bus[0].json
}
