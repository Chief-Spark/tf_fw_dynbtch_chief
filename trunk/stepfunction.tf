# CloudWatch Log Group for Step Function
resource "aws_cloudwatch_log_group" "dynamic_batch_main_batch_logs" {
  name              = "/aws/states/${local.resource_prefix}-dynamic-batch-main-batch"
  retention_in_days = 14
}

module "stepfunction_dynamic_batch_main_batch" {
  source         = "../modules/eits-tf-aws-step-functions-mt"
  prefix         = var.stage
  function_scope = "${var.project_name}-dynamic-batch-main-batch"
  type           = "STANDARD"
  role_arn       = module.iam_dynamic_batch_main_batch.role_arn
  cloudwatch_arn = "${aws_cloudwatch_log_group.dynamic_batch_main_batch_logs.arn}:*"
  log_level      = "ALL"
  enable_logging = false
  tags           = local.combined_tags
  definition = jsonencode({
    StartAt = "SendEmailOnStart",
    States = {
      SendEmailOnStart = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          "FunctionName" = module.lambda_dynamic_batch_send_email_log.arn,
          "Payload" = {
            "executionUUID.$" = "$.mainBatchUUID",
            "status"          = "STARTED",
            "fileName.$"      = "$.fullPath",
            "subject.$"       = "States.Format('EJECUCIÓN INICIADA - {}', $.fullPath)",
            "body.$"          = "States.Format('Inicio de proceso. fileName: {}, executionUUID: {}', $.fullPath, $.mainBatchUUID)",
            "template_name"   = "batch_notification",
            "batch_name.$"    = "States.ArrayGetItem(States.StringSplit(States.ArrayGetItem(States.StringSplit($.fullPath, '-'), 0), 'val'), 1)",
            "file_name"       = "",
            "key_file"        = ""
          }
        },
        ResultPath = "$.sendEmailStartResult",
        Catch = [
          { ErrorEquals = ["States.ALL"], ResultPath = "$.sendEmailStartError", Next = "DynamicBatchSourceValidator" }
        ],
        Next = "DynamicBatchSourceValidator"
      },

      DynamicBatchSourceValidator = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken",
        Parameters = {
          "FunctionName" = module.lambda_dynamic_batch_source_validator.arn,
          "Payload" = {
            "fullPath.$"      = "$.fullPath",
            "taskToken.$"     = "$$.Task.Token",
            "mainBatchUUID.$" = "$.mainBatchUUID"
          }
        },
        ResultPath     = "$.sourceValidatorResult",
        InputPath      = "$",
        TimeoutSeconds = var.lambda_timeout_source_validator,
        Catch = [
          { ErrorEquals = ["States.ALL"], ResultPath = "$.launcherError", Next = "NotifyLauncherFailure" }
        ],
        Next = "DynamicBatchBuilder"
      },

      DynamicBatchBuilder = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken",
        Parameters = {
          "FunctionName" = module.lambda_dynamic_batch_builder.arn,
          "Payload" = {
            "fullPath.$"      = "$.fullPath",
            "taskToken.$"     = "$$.Task.Token",
            "mainBatchUUID.$" = "$.mainBatchUUID"
          }
        },
        ResultPath     = "$.builderResult",
        InputPath      = "$",
        TimeoutSeconds = var.lambda_timeout_builder,
        Catch = [
          { ErrorEquals = ["States.ALL"], ResultPath = "$.launcherError", Next = "NotifyLauncherFailure" }
        ],
        Next = "DynamicBatchLauncher"
      },

      DynamicBatchLauncher = {
        Type     = "Task",
        Resource = "arn:aws:states:::states:startExecution.waitForTaskToken",
        Parameters = {
          "StateMachineArn.$" = "$.builderResult.step_function_arn",
          "Input" = {
            "fileName.$"                                   = "$.fullPath",
            "mainBatchUUID.$"                              = "$.mainBatchUUID",
            "launcherTaskToken.$"                          = "$$.Task.Token",
            "AWS_STEP_FUNCTIONS_STARTED_BY_EXECUTION_ID.$" = "$$.Execution.Id",
            "productId.$"                                  = "States.ArrayGetItem(States.StringSplit(States.ArrayGetItem(States.StringSplit($.fullPath, '-'), 0), 'val'), 1)",
          }
        },
        ResultPath     = "$.launcherResult",
        InputPath      = "$",
        TimeoutSeconds = var.stepfunction_timeout_dynamic_batch_launcher,
        Catch = [
          { ErrorEquals = ["States.Timeout"], ResultPath = "$.launcherError", Next = "NotifyLauncherTimeout" },
          { ErrorEquals = ["States.ALL"], ResultPath = "$.launcherError", Next = "NotifyLauncherFailure" } # States.ALL al final
        ],
        Next = "DynamicBatchCollector"
      },

      DynamicBatchCollector = {
        Type     = "Task",
        Resource = "arn:aws:states:::aws-sdk:sfn:deleteStateMachine",
        Parameters = {
          "StateMachineArn.$" = "$.builderResult.step_function_arn",
        },
        ResultPath     = "$.collectorResult",
        TimeoutSeconds = var.stepfunction_timeout_dynamic_batch_collector,
        Catch = [
          { "ErrorEquals" : ["Sfn.InvalidArn"], "ResultPath" : "$.collectorError", "Next" : "NotifyCollectorFailure" },
          { "ErrorEquals" : ["Sfn.ValidationException"], "ResultPath" : "$.collectorError", "Next" : "NotifyCollectorFailure" },
          { "ErrorEquals" : ["States.ALL"], "ResultPath" : "$.collectorError", "Next" : "NotifyCollectorFailure" }
        ],
        Next = "LogBatchToDynamo"
      },

      LogBatchToDynamo = {
        Type     = "Task",
        Resource = "arn:aws:states:::aws-sdk:dynamodb:putItem",
        Parameters = {
          "TableName" = var.dynamo_logs_table_name,
          "Item" = {
            "PK" : { "S.$" : "States.Format('PROD#{}', $.mainBatchUUID)" },
            "SK" : { "S.$" : "States.Format('{}#{}#{}', $.mainBatchUUID, 'DynamicBatchCollector', $$.State.EnteredTime)" },
            "createdDate" : { "S.$" : "$$.State.EnteredTime" },
            "timeStampEvent" : { "S.$" : "$$.State.EnteredTime" },
            "executionUUID" : { "S.$" : "$.mainBatchUUID" },
            "logMessage" : { "S" : "Collector: delete child state machine requested" },
            "taskToken" : { "S" : "" },
            "bizagiID" : { "S.$" : "$.mainBatchUUID" },
            "BizagiIDTimeStamp" : { "S.$" : "States.Format('{}#{}', $.mainBatchUUID, $$.State.EnteredTime)" },
            "clientID" : { "S" : "client_id" },
            "stateMachineExecutionArn" : { "S" : "" },
            "resourceName" : { "S" : "arn:aws:states:::aws-sdk:sfn:deleteStateMachine" },
            "stateSFResult" : { "S" : "DELETE_REQUESTED" },
            "finalState" : { "S" : "FNSTATE" }
          },
          "ConditionExpression" = "attribute_not_exists(PK) AND attribute_not_exists(SK)",
          "ReturnValues"        = "NONE"
        },
        ResultPath = "$.dynamoLogResult",
        Next       = "SendEmailOnSuccess"
      },

      HandleLauncherTimeout = {
        Type      = "Fail",
        Error     = "States.Timeout",
        CausePath = "$.launcherError.Cause"
      },

      HandleLauncherFailure = {
        Type      = "Fail",
        ErrorPath = "$.launcherError.Error",
        CausePath = "$.launcherError.Cause"
      },

      HandleCollectorFailure = {
        Type      = "Fail",
        ErrorPath = "$.collectorError.Error",
        CausePath = "$.collectorError.Cause"
      },

      NotifyLauncherTimeout = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          "FunctionName" = module.lambda_dynamic_batch_error_log_file_generation.arn,
          "Payload"      = { "executionUUID.$" = "$.mainBatchUUID" }
        },
        ResultSelector = {
          "file_name.$"       = "$.Payload.body.file_name",
          "logFileLocation.$" = "$.Payload.body.logFileLocation"
        },
        ResultPath     = "$.errorLog",
        TimeoutSeconds = var.lambda_timeout_error_log_file_generation,
        Next           = "SendEmailOnError_LauncherTimeout"
      },

      SendEmailOnError_LauncherTimeout = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          "FunctionName" = module.lambda_dynamic_batch_send_email_log.arn,
          "Payload" = {
            "executionUUID.$" = "$.mainBatchUUID",
            "status"          = "ERROR",
            "fileName.$"      = "$.fullPath",
            "subject"         = "EJECUCIÓN CON ERROR",
            "body"            = "Se generó un log de error para la ejecución.",
            "template_name"   = "batch_error",
            "batch_name.$"    = "$.fullPath",
            "batch_id.$"      = "$.fullPath",
            "file_name.$"     = "$.errorLog.file_name",
            "key_file.$"      = "$.errorLog.logFileLocation"
          }
        },
        ResultPath     = "$.sendEmailErrorResult",
        TimeoutSeconds = var.lambda_timeout_send_email_log,
        Next           = "HandleLauncherTimeout"
      },

      NotifyLauncherFailure = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          "FunctionName" = module.lambda_dynamic_batch_error_log_file_generation.arn,
          "Payload"      = { "executionUUID.$" = "$.mainBatchUUID" }
        },
        ResultSelector = {
          "file_name.$"       = "$.Payload.body.file_name",
          "logFileLocation.$" = "$.Payload.body.logFileLocation"
        },
        ResultPath     = "$.errorLog",
        TimeoutSeconds = var.lambda_timeout_error_log_file_generation,
        Next           = "SendEmailOnError_LauncherFailure"
      },

      SendEmailOnError_LauncherFailure = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          "FunctionName" = module.lambda_dynamic_batch_send_email_log.arn,
          "Payload" = {
            "executionUUID.$" = "$.mainBatchUUID",
            "status"          = "ERROR",
            "fileName.$"      = "$.fullPath",
            "subject"         = "EJECUCIÓN CON ERROR",
            "body"            = "Se generó un log de error para la ejecución.",
            "template_name"   = "batch_error",
            "batch_name.$"    = "$.fullPath",
            "batch_id.$"      = "$.fullPath",
            "file_name.$"     = "$.errorLog.file_name",
            "key_file.$"      = "$.errorLog.logFileLocation",
            "error_details.$" = "States.Format('{} | {}', $.launcherError.Error, $.launcherError.Cause)"
          }
        },
        ResultPath     = "$.sendEmailErrorResult",
        TimeoutSeconds = var.lambda_timeout_send_email_log,
        Next           = "HandleLauncherFailure"
      },

      NotifyCollectorFailure = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          "FunctionName" = module.lambda_dynamic_batch_error_log_file_generation.arn,
          "Payload"      = { "executionUUID.$" = "$.mainBatchUUID" }
        },
        ResultSelector = {
          "file_name.$"       = "$.Payload.body.file_name",
          "logFileLocation.$" = "$.Payload.body.logFileLocation"
        },
        ResultPath     = "$.errorLog",
        TimeoutSeconds = var.lambda_timeout_error_log_file_generation,
        Next           = "SendEmailOnError_CollectorFailure"
      },

      SendEmailOnError_CollectorFailure = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          "FunctionName" = module.lambda_dynamic_batch_send_email_log.arn,
          "Payload" = {
            "executionUUID.$" = "$.mainBatchUUID",
            "status"          = "ERROR",
            "fileName.$"      = "$.fullPath",
            "subject"         = "EJECUCIÓN CON ERROR",
            "body"            = "Se generó un log de error para la ejecución.",
            "template_name"   = "batch_error",
            "batch_name.$"    = "States.ArrayGetItem(States.StringSplit(States.ArrayGetItem(States.StringSplit($.fullPath, '-'), 0), 'val'), 1)",
            "file_name.$"     = "$.errorLog.file_name",
            "key_file.$"      = "$.errorLog.logFileLocation",
            "error_details.$" = "States.Format('{} | {}', $.collectorError.Error, $.collectorError.Cause)"
          }
        },
        ResultPath     = "$.sendEmailErrorResult",
        TimeoutSeconds = var.lambda_timeout_send_email_log,
        Next           = "HandleCollectorFailure"
      },

      SendEmailOnSuccess = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          "FunctionName" = module.lambda_dynamic_batch_send_email_log.arn,
          "Payload" = {
            "executionUUID.$" = "$.mainBatchUUID",
            "status"          = "SUCCESS",
            "fileName.$"      = "$.fullPath",
            "subject"         = "EJECUCIÓN EXITOSA",
            "body"            = "El proceso finalizó exitosamente.",
            "template_name"   = "batch_success",
            "batch_name.$"    = "States.ArrayGetItem(States.StringSplit(States.ArrayGetItem(States.StringSplit($.fullPath, '-'), 0), 'val'), 1)",
            "file_name"       = "",
            "key_file"        = ""
          }
        },
        ResultPath     = "$.sendEmailSuccessResult",
        TimeoutSeconds = var.lambda_timeout_send_email_log,
        Catch = [
          { ErrorEquals = ["States.ALL"], ResultPath = "$.sendEmailSuccessError", Next = "SuccessTerminal" }
        ],
        End = true
      },

      SuccessTerminal = {
        Type = "Succeed"
      }
    }
  })
}

# Translator Step Function resources moved to `develop/translator_stepfunction.tf`.
