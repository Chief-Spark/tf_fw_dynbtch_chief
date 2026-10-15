# AWS Step functions Module MT version

## Macondotek AWS Step functions module

Macondotek Terraform module for Step Functions. with this module you can:
 - Provides a Step Function State Machine resource
  > We highly recommend that in your code you pin the version to the exact version you are using so that your infrastructure remains stable, and update versions in a systematic way so that they do not catch you by surprise.


## Usage
### Step function machine

```hcl

module "step_function" {
  source         = "../../modules/eits-tf-aws-step-functions-mt" or "git::yourrepo/eits-tf-aws-step-functions-mt" 
  prefix         = <prefix of the queue>
  function_scope = <function scope>
  role_arn =  <role arn that will use the stepfunctions>
  log_level      = "ALL"
  cloudwatch_arn = <arn of cloudwatch to log>
  type           = "EXPRESS"
  definition     = <<EOF
{
  "Comment": "A description of my state machine",
  "StartAt": "Decodificador",
  "States": {
    "Decodificador": {
      "Type": "Pass",
      "Parameters": {
        "appAuthZ.$": "States.StringToJson(States.Base64Decode($.appAuthZ))",
        "userInfo.$": "States.StringToJson(States.Base64Decode($.userInfo))"
      },
      "ResultPath": "$.headers",
      "Next": "Consult"
    }
  }
}
EOF
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 3.0 |
| <a name="requirement_validation"></a> [validation](#requirement\_validation) | 1.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 3.0 |
| <a name="provider_validation"></a> [validation](#provider\_validation) | 1.0.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eits_vars"></a> [eits\_vars](#module\_eits\_vars) | git::https://code.experian.local/scm/EUCES/eits-tf-aws-vars.git | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_sfn_state_machine](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sfn_state_machine) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Used for naming your cloud resources, if this is specified your api gateway name will be '{prefix}-{function_scope}-sqs' | `string` | n/a | yes |
| <a name="input_function_scope"></a> [function_scope](#input\_function_scope) | A mandatory input used for differentiating between different step functions created | `string` | n/a | yes |
| <a name="input_type"></a> [type](#input\_type) | Determines whether a Standard or Express state machine is created. Valid Values: STANDARD and EXPRESS | `string` | STANDARD | no |
| <a name="input_role_arn"></a> [role_arn](#input\_role_arn) | The Amazon Resource Name (ARN) of the IAM role to use for this Step Function | `string` | n/a | yes |
| <a name="input_definition"></a> [definition](#input\_definition) | JSON Object, The Amazon States Language definition of the Step Function [statements](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-amazon-states-language.html) | `string` | no | yes |
| <a name="input_log_level"></a> [log_level](#input\_log_level) | Defines which category of execution history events are logged. Valid values: ALL, ERROR, FATAL, OFF  | `string` | ALL | no |
| <a name="input_cloudwatch_arn"></a> [cloudwatch_arn](#input\_cloudwatch_arn) | Amazon Resource Name (ARN) of a CloudWatch log group. Make sure the State Machine has the correct IAM policies for logging. The ARN must end with :*  | `string` | n/a | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_arn"></a> [arn](#output\_arn) | The ARN of the state machine |
<!-- END_TF_DOCS -->

## Metadata
```discoveryhub
summary: Terraform module for AWS Step functions
region: ?????
bu: EITS
contacts:
  technical: EITS UK&I Cloud Enablement Team ?????@experian.com
  product: 
```
