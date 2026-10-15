# Ejecuciones batch recurrentes: EventBridge (cron UTC) → Step Function main batch (StartExecution).
# El input enviado al Step Function es { "fullPath": "<ruta>", "mainBatchUUID": "<id-evento>" },
# donde mainBatchUUID se toma del campo `id` (UUID) del evento de EventBridge.

resource "aws_cloudwatch_event_rule" "scheduled_batch" {
  for_each = local.scheduled_batch_items

  name                = "${local.resource_prefix}-sched-batch-${each.key}"
  description         = "Batch recurrente (${each.value.hora_ejecucion} COT): ${each.value.ruta}"
  schedule_expression = local.scheduled_batch_cron[each.key]
  state               = "ENABLED"
  tags                = local.combined_tags
}

# Rol asumido por EventBridge para ejecutar el Step Function principal.
# Se usa el módulo eits-tf-aws-iam (mismo patrón que las demás roles del proyecto)
# porque el rol Jenkins no tiene permiso para `iam:CreateRole` directo;
# el módulo crea el rol con prefijo `BURoleFor-` permitido por la guard rail.
module "iam_scheduled_batch_eventbridge" {
  count = length(var.scheduled_batch_executions) > 0 ? 1 : 0

  source               = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-iam.git?ref=1.9.1"
  create_role          = var.enable_create_role
  role_name            = "-${local.resource_prefix}-schedBatchEbRole"
  role_description     = "Role assumed by EventBridge to start the main batch Step Function on schedule"
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/BUPolicyForBoundaryDTO"
  policy_name          = "-${local.resource_prefix}-schedBatchEbPolicy"
  policy_description   = "Allows EventBridge to StartExecution on the main batch Step Function"
  tags                 = local.combined_tags
  assume_role_policy   = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "events.amazonaws.com" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "${data.aws_caller_identity.current.account_id}"
        }
      }
    }
  ]
}
EOF
  policy_documents = [
    data.aws_iam_policy_document.start_main_stepfunction.json,
  ]
}

resource "aws_cloudwatch_event_target" "scheduled_batch_sfn" {
  for_each = local.scheduled_batch_items

  rule      = aws_cloudwatch_event_rule.scheduled_batch[each.key].name
  target_id = "main-batch-stepfunction"
  arn       = module.stepfunction_dynamic_batch_main_batch.arn
  role_arn  = module.iam_scheduled_batch_eventbridge[0].role_arn

  # Usa input_transformer para inyectar el `id` del evento (UUID) como mainBatchUUID,
  # manteniendo `fullPath` fijo por regla.
  input_transformer {
    input_paths = {
      eventId = "$.id"
    }
    input_template = <<EOF
{
  "fullPath": "${each.value.ruta}",
  "mainBatchUUID": "<eventId>"
}
EOF
  }
}
