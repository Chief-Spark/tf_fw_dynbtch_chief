
variable "definition" {
  description = "The Amazon States Language definition of the Step Function"
  type        = string
  default     = ""
}
variable "type" {
  description = "Determines whether a Standard or Express state machine is created. The default is STANDARD. Valid Values: STANDARD | EXPRESS"
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXPRESS"], upper(var.type))
    error_message = "Step Function type must be one of the following (STANDARD | EXPRESS)."
  }
}
variable "role_arn" {
  description = "The Amazon Resource Name (ARN) of the IAM role to use for this Step Function"
  type        = string
  default     = ""
}

variable "log_level" {
  description = "Defines which category of execution history events are logged. Valid values: ALL, ERROR, FATAL, OFF"
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], upper(var.log_level))
    error_message = "Valid values: ALL, ERROR, FATAL, OFF"
  }
}

variable "include_execution_data" {
  description = "Determines whether execution data is included in CloudWatch Logs. For STANDARD workflows, set to false to reduce log volume."
  type        = bool
  default     = false
}

variable "enable_logging" {
  description = "Enables logging_configuration for STANDARD type state machines. Requires the IAM role to have LogDelivery permissions with Resource=*."
  type        = bool
  default     = false
}

variable "cloudwatch_arn" {
  description = " Amazon Resource Name (ARN) of a CloudWatch log group. Make sure the State Machine has the correct IAM policies for logging. The ARN must end with :*"
  type        = string
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for AWS resources. See https://pages.experian.com/pages/viewpage.action?pageId=400041906 for all available tags"
}
variable "prefix" {
  type        = string
  description = "Used for naming your cloud resources, if this is specified your api gateway name will be '{prefix}-{function_scope}-api-gateway'"
  default     = ""
}

variable "function_scope" {
  type        = string
  description = <<EOF
  A mandatory input used for differentiating between different lambdas related to the same application, this will be interpolated
  into the function name.
  EOF
}
