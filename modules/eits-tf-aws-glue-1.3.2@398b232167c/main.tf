module "eits_ce_common" {
  source = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-ce-common.git?ref=1.3.0"

  module_repo = "eits-tf-aws-glue"
  tags        = local.tags
}

locals {
  tags     = merge(var.tags, module.eits_ce_common.tags)
  role_arn = var.create_service_role ? module.glue_service_role[0].role_arn : var.service_role_arn

  #If the log group is to be created, populate these arguments, otherwise empty it out
  logging_arguments = var.create_cloudwatch_logs == true ? {
    "--continuous-log-logGroup"          = module.cloudwatch_logs[0].log_group_name
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = ""
  } : {}
}

# create glue database
resource "aws_glue_catalog_database" "this" {
  name         = var.database_name
  description  = var.database_description
  catalog_id   = var.database_catalog_id
  location_uri = var.database_location_uri
  parameters   = var.database_parameters

  dynamic "create_table_default_permission" {
    for_each = var.create_table_default_permission != null ? [true] : []

    content {
      permissions = var.create_table_default_permission.permissions

      dynamic "principal" {
        for_each = var.create_table_default_permission.principal != null ? [true] : []

        content {
          data_lake_principal_identifier = var.create_table_default_permission.principal.data_lake_principal_identifier
        }
      }
    }
  }

  dynamic "target_database" {
    for_each = var.target_database != null ? [true] : []

    content {
      catalog_id    = var.target_database.catalog_id
      database_name = var.target_database.database_name
      region        = var.target_database.region
    }
  }

  dynamic "federated_database" {
    for_each = var.federated_database != null ? [true] : []

    content {
      connection_name = var.federated_database.connection_name
      identifier      = var.federated_database.identifier
    }
  }

  tags = local.tags
}

# create glue catalog tables, if required
resource "aws_glue_catalog_table" "this" {
  for_each = var.tables

  name               = each.key
  description        = each.value.description
  database_name      = aws_glue_catalog_database.this.name
  catalog_id         = aws_glue_catalog_database.this.catalog_id
  owner              = each.value.owner
  parameters         = each.value.parameters
  retention          = each.value.retention
  table_type         = each.value.table_type
  view_expanded_text = each.value.view_expanded_text
  view_original_text = each.value.view_original_text

  dynamic "partition_keys" {
    for_each = each.value.partition_keys != null ? each.value.partition_keys : []

    content {
      name    = partition_keys.value.name
      comment = partition_keys.value.comment
      type    = partition_keys.value.type
    }
  }

  dynamic "target_table" {
    for_each = each.value.target_table != null ? [each.value.target_table] : []

    content {
      catalog_id    = target_table.value.target_table.catalog_id
      database_name = target_table.value.target_table.database_name
      name          = target_table.value.target_table.name
      region        = target_table.value.target_table.region
    }
  }

  dynamic "storage_descriptor" {
    for_each = each.value.storage_descriptor != null ? [each.value.storage_descriptor] : []

    content {
      additional_locations      = storage_descriptor.value.additional_locations
      bucket_columns            = storage_descriptor.value.bucket_columns
      compressed                = storage_descriptor.value.compressed
      location                  = storage_descriptor.value.location
      input_format              = storage_descriptor.value.input_format
      output_format             = storage_descriptor.value.output_format
      number_of_buckets         = storage_descriptor.value.number_of_buckets
      parameters                = storage_descriptor.value.parameters
      stored_as_sub_directories = storage_descriptor.value.stored_as_sub_directories

      dynamic "columns" {
        for_each = storage_descriptor.value.columns != null ? storage_descriptor.value.columns : []

        content {
          name       = columns.value.name
          comment    = columns.value.comment
          parameters = columns.value.parameters
          type       = columns.value.type
        }
      }

      dynamic "schema_reference" {
        for_each = storage_descriptor.value.schema_reference != null ? [storage_descriptor.value.schema_reference] : []

        content {
          schema_version_number = schema_reference.value.schema_version_number
          schema_version_id     = schema_reference.value.schema_version_id

          dynamic "schema_id" {
            for_each = schema_reference.value.schema_id != null ? [schema_reference.value.schema_id] : []

            content {
              registry_name = schema_id.value.registry_name
              schema_arn    = schema_id.value.schema_arn
              schema_name   = schema_id.value.schema_name
            }
          }
        }
      }

      dynamic "ser_de_info" {
        for_each = storage_descriptor.value.ser_de_info != null ? [storage_descriptor.value.ser_de_info] : []

        content {
          name                  = ser_de_info.value.name
          parameters            = ser_de_info.value.parameters
          serialization_library = ser_de_info.value.serialization_library
        }
      }

      dynamic "skewed_info" {
        for_each = storage_descriptor.value.skewed_info != null ? [storage_descriptor.value.skewed_info] : []

        content {
          skewed_column_names               = skewed_info.value.skewed_column_names
          skewed_column_value_location_maps = skewed_info.value.skewed_column_value_location_maps
          skewed_column_values              = skewed_info.value.skewed_column_values
        }
      }

      dynamic "sort_columns" {
        for_each = storage_descriptor.value.sort_columns != null ? storage_descriptor.value.sort_columns : []

        content {
          column     = sort_columns.value.column
          sort_order = sort_columns.value.sort_order
        }
      }
    }
  }
}

# create seperate partition index resource (to avoid table recreation), if required
resource "aws_glue_partition_index" "this" {
  for_each = { for k, v in var.tables : k => v if v.partition_index != null }

  table_name    = each.key
  database_name = aws_glue_catalog_database.this.name
  catalog_id    = aws_glue_catalog_database.this.catalog_id

  dynamic "partition_index" {
    for_each = each.value.partition_index

    content {
      index_name = partition_index.value.index_name
      keys       = partition_index.value.keys
    }
  }

  depends_on = [aws_glue_catalog_table.this]
}

# create AWSGlueServiceRole IAM role
data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    sid     = "AllowGlueAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

module "glue_service_role" {
  source = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-iam?ref=1.9.1"
  count  = var.create_service_role ? 1 : 0

  role_name            = var.service_role_name == null ? format("AWSGlueServiceRole-%s", var.database_name) : var.service_role_name
  role_description     = format("Role for AWS Glue, used for database %s", var.database_name)
  assume_role_policy   = data.aws_iam_policy_document.assume_role_policy.json
  permissions_boundary = var.service_role_permissions_boundary
  managed_policy_arns  = ["arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"]
  policy_documents     = var.service_role_policy_documents
  policy_name          = var.service_role_name == null ? format("AWSGlueServiceRole-%s", var.database_name) : var.service_role_name
  disable_org_check    = true

  tags = merge(local.tags, var.service_role_tags)
}

# create glue crawlers, if required
resource "aws_glue_crawler" "this" {
  for_each = var.crawlers

  name                   = each.key
  description            = each.value.description
  database_name          = aws_glue_catalog_database.this.name
  role                   = local.role_arn
  schedule               = each.value.schedule
  classifiers            = each.value.classifiers
  configuration          = each.value.configuration
  security_configuration = each.value.security_configuration
  table_prefix           = each.value.table_prefix

  dynamic "schema_change_policy" {
    for_each = each.value.schema_change_policy != null ? [each.value.schema_change_policy] : []

    content {
      delete_behavior = schema_change_policy.value.delete_behavior
      update_behavior = schema_change_policy.value.update_behavior
    }
  }

  dynamic "lineage_configuration" {
    for_each = each.value.lineage_configuration != null ? [each.value.lineage_configuration] : []

    content {
      crawler_lineage_settings = lineage_configuration.value.crawler_lineage_settings
    }
  }

  dynamic "recrawl_policy" {
    for_each = each.value.recrawl_policy != null ? [each.value.recrawl_policy] : []

    content {
      recrawl_behavior = recrawl_policy.value.recrawl_behavior
    }
  }

  dynamic "catalog_target" {
    for_each = each.value.catalog_targets != null ? each.value.catalog_targets : []

    content {
      database_name       = catalog_target.value.database_name
      tables              = catalog_target.value.tables
      connection_name     = catalog_target.value.connection_name
      event_queue_arn     = catalog_target.value.event_queue_arn
      dlq_event_queue_arn = catalog_target.value.dlq_event_queue_arn
    }
  }

  dynamic "delta_target" {
    for_each = each.value.delta_targets != null ? each.value.delta_targets : []

    content {
      connection_name = delta_target.value.connection_name
      delta_tables    = delta_target.value.delta_tables
      write_manifest  = delta_target.value.write_manifest
    }
  }

  dynamic "dynamodb_target" {
    for_each = each.value.dynamodb_targets != null ? each.value.dynamodb_targets : []

    content {
      path      = dynamodb_target.value.path
      scan_all  = dynamodb_target.value.scan_all
      scan_rate = dynamodb_target.value.scan_rate
    }
  }

  dynamic "jdbc_target" {
    for_each = each.value.jdbc_targets != null ? each.value.jdbc_targets : []

    content {
      connection_name            = jdbc_target.value.connection_name
      path                       = jdbc_target.value.path
      exclusions                 = jdbc_target.value.exclusions
      enable_additional_metadata = jdbc_target.value.enable_additional_metadata
    }
  }

  dynamic "mongodb_target" {
    for_each = each.value.mongodb_targets != null ? each.value.mongodb_targets : []

    content {
      connection_name = mongodb_target.value.connection_name
      path            = mongodb_target.value.path
      scan_all        = mongodb_target.value.scan_all
    }
  }

  dynamic "s3_target" {
    for_each = each.value.s3_targets != null ? each.value.s3_targets : []

    content {
      path                = s3_target.value.path
      connection_name     = s3_target.value.connection_name
      exclusions          = s3_target.value.exclusions
      sample_size         = s3_target.value.sample_size
      event_queue_arn     = s3_target.value.event_queue_arn
      dlq_event_queue_arn = s3_target.value.dlq_event_queue_arn
    }
  }

  tags = merge(local.tags, each.value.tags)
}

# create glue jobs, if required
resource "aws_glue_job" "this" {
  for_each = var.jobs

  name                      = each.key
  role_arn                  = local.role_arn
  description               = each.value.description
  connections               = each.value.connections
  default_arguments         = merge(local.logging_arguments, each.value.default_arguments)
  non_overridable_arguments = each.value.non_overridable_arguments
  execution_class           = each.value.execution_class
  glue_version              = each.value.glue_version
  maintenance_window        = each.value.maintenance_window
  max_capacity              = each.value.max_capacity
  max_retries               = each.value.max_retries
  timeout                   = each.value.timeout
  security_configuration    = each.value.security_configuration
  worker_type               = each.value.worker_type
  number_of_workers         = each.value.number_of_workers

  command {
    name            = each.value.command.name
    python_version  = each.value.command.python_version
    script_location = each.value.command.script_location
  }

  dynamic "execution_property" {
    for_each = each.value.execution_property != null ? [each.value.execution_property] : []

    content {
      max_concurrent_runs = execution_property.value.max_concurrent_runs
    }
  }

  dynamic "notification_property" {
    for_each = each.value.notification_property != null ? [each.value.notification_property] : []

    content {
      notify_delay_after = notification_property.value.notify_delay_after
    }
  }

  tags = merge(local.tags, each.value.tags)
}

# Because the aws managed key is not created until needed, if we tried to use a data here it would fail
#   on an account that had never used glue before.  This alias is the default that is assigned if you
#   left the key id's null, but what gets put in by glue automatically ("alias/aws/glue") confuses terraform
#   and results in it thinking things need to be changed back to null when it should be a consistant state.
#   To avoid this, we're building out the proper ARN to the same resource.
#
# This could also be done with lifecycle rules to ignore the changes if this is found to be undesireable for some reason.
#   A commented out version of that method is left below for the time being.

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_glue_data_catalog_encryption_settings" "catalog_encryption" {
  count = var.configure_encryption_settings == true ? 1 : 0
  data_catalog_encryption_settings {
    connection_password_encryption {
      return_connection_password_encrypted = true
      aws_kms_key_id                       = var.connection_password_kms_key_id != null ? var.connection_password_kms_key_id : "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alias/aws/glue"
    }
    encryption_at_rest {
      catalog_encryption_mode         = var.catalog_encryption_mode
      sse_aws_kms_key_id              = var.metadata_encryption_kms_key_id != null ? var.metadata_encryption_kms_key_id : "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alias/aws/glue"
      catalog_encryption_service_role = var.catalog_encryption_service_role
    }
  }

  # # If these values are left at the default of null,
  # lifecycle {
  #   ignore_changes = [ 
  #     data_catalog_encryption_settings[0].connection_password_encryption[0].aws_kms_key_id,
  #     data_catalog_encryption_settings[0].encryption_at_rest[0].sse_aws_kms_key_id  ]
  # }
}

module "cloudwatch_logs" {
  count  = var.create_cloudwatch_logs == true ? 1 : 0
  source = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-cloudwatch-logs?ref=2.5.2"

  logs_source  = "aws_glue"
  logs_context = "jobs"

  tags = var.tags
}
