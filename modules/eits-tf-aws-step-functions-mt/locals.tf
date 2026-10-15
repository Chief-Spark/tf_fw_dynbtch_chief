module "eits_vars" {
  source      = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-vars"
  module_repo = "eits-tf-aws-step-functions-mt"
  tags        = var.tags
}

locals {
  prefix   = length(var.prefix) > 0 ? var.prefix : module.eits_vars.prefix
  sfn_name = "${local.prefix}-${data.aws_caller_identity.current.account_id}-Sfn-${var.function_scope}"
  tags     = merge(var.tags, module.eits_vars.tags)
}
