### COMMON VARIABLES ###

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags for all created AWS resources. See [Cloud Tagging Strategy & Standards](https://pages.experian.com/pages/viewpage.action?pageId=400041906) for available tags"
}

### CATALOG DATABASE VARIABLES ###

variable "database_name" {
  type        = string
  description = "The name of the Glue catalog database to create"

  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.database_name))
    error_message = "The database name must only contain lowercase letters, numbers, or underscores"
  }
}

variable "database_description" {
  type        = string
  default     = null
  description = "Description of the database"
}

variable "database_catalog_id" {
  type        = string
  default     = null
  description = "The ID of the Glue Catalog in which to create the database. If none is provided, the AWS account ID is used"
}

variable "database_location_uri" {
  type        = string
  default     = null
  description = "The location of the database (e.g. S3 or HDFS path)"
}

variable "database_parameters" {
  type        = map(string)
  default     = {}
  description = "A map of key-value pairs that define parameters and properties of the database"
}

variable "create_table_default_permission" {
  type = object({
    permissions = optional(list(string))
    principal = optional(object({
      data_lake_principal_identifier = optional(string)
    }))
  })
  default     = null
  description = "Creates a set of default permissions on the table for principals. See [Glue Catalog Database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_database#create_table_default_permission) for values"
}

variable "target_database" {
  type = object({
    catalog_id    = string
    database_name = string
    region        = optional(string)
  })
  default     = null
  description = "The target database for resource linking. See [Glue Catalog Database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_database#target_database) for values"
}

variable "federated_database" {
  type = object({
    connection_name = optional(string)
    identifier      = optional(string)
  })
  default     = null
  description = "The federated database that references an entity outside the AWS Glue Data Catalog. See [Glue Catalog Database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_database#federated_database) for values"
}

### CATALOG TABLE VARIABLES ###

variable "tables" {
  type = map(object({
    description        = optional(string)
    owner              = optional(string)
    parameters         = optional(map(string))
    retention          = optional(number)
    table_type         = optional(string)
    view_expanded_text = optional(string)
    view_original_text = optional(string)
    partition_index = optional(list(object({
      index_name = string
      keys       = list(string)
    })))
    partition_keys = optional(list(object({
      name    = string
      type    = optional(string)
      comment = optional(string)
    })))
    target_table = optional(object({
      catalog_id    = string
      database_name = string
      name          = string
      region        = optional(string)
    }))
    storage_descriptor = optional(object({
      additional_locations      = optional(list(string))
      bucket_columns            = optional(list(string))
      compressed                = optional(bool)
      location                  = string
      input_format              = optional(string)
      output_format             = optional(string)
      number_of_buckets         = optional(number)
      parameters                = optional(map(string))
      stored_as_sub_directories = optional(bool)
      columns = optional(list(object({
        name       = string
        comment    = optional(string)
        parameters = optional(map(string))
        type       = optional(string)
      })))
      schema_reference = optional(object({
        schema_version_number = number
        schema_version_id     = optional(string)
        schema_id = optional(object({
          registry_name = string
          schema_arn    = string
          schema_name   = string
        }))
      }))
      ser_de_info = optional(object({
        name                  = optional(string)
        parameters            = optional(map(string))
        serialization_library = optional(string)
      }))
      skewed_info = optional(object({
        skewed_column_names               = optional(list(string))
        skewed_column_values              = optional(list(string))
        skewed_column_value_location_maps = optional(list(string))
      }))
      sort_columns = optional(list(object({
        column     = string
        sort_order = number
      })))
    }))
  }))
  default     = {}
  description = "A map of Glue Tables to create. The `name` of the table will be the name of the map key. Note `database_name` is automatically populated using the module's created resources. See [Glue Catalog Table](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_table) for guidance on values, and [AWS Docs](https://docs.aws.amazon.com/glue/latest/dg/tables-described.html) for more information"

}

### IAM ROLE VARIABLES ###

variable "create_service_role" {
  type        = bool
  default     = true
  description = "Whether to create a new IAM role to be used for the Glue service role. If set to `false`, you must provide an existing role ARN to `service_role_arn`"
}

variable "service_role_arn" {
  type        = string
  default     = null
  description = "The ARN of an existing IAM role to use for the Glue service role, see [AWS Glue Service Role](https://docs.aws.amazon.com/glue/latest/dg/create-an-iam-role.html) for requirements. Only used when `create_service_role` is `false`"
}

variable "service_role_name" {
  type        = string
  default     = null
  description = "The name of the Glue service IAM role, appended to prefix 'BURoleFor'. If left `null` then role name will default to `BURoleForAWSGlueServiceRole-<database_name>`. Only used when `create_service_role` is `true`"
}

variable "service_role_permissions_boundary" {
  type        = string
  default     = null
  description = "ARN of the policy that is used to set the permissions boundary for the Glue service IAM role. Only used when `create_service_role` is `true`"
}

variable "service_role_policy_documents" {
  type        = list(string)
  default     = []
  description = "A list of policy documents to attach to the Glue service IAM role. Only used when `create_service_role` is `true`"
}

variable "service_role_tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to the Glue service IAM role. Only used when `create_service_role` is `true`"
}

### CRAWLER VARIABLES ###

variable "crawlers" {
  type = map(object({
    description            = optional(string)
    schedule               = optional(string)
    classifiers            = optional(list(string))
    configuration          = optional(string)
    security_configuration = optional(string)
    table_prefix           = optional(string)
    schema_change_policy = optional(object({
      delete_behavior = string
      update_behavior = string
    }))
    lineage_configuration = optional(object({
      crawler_lineage_settings = string
    }))
    recrawl_policy = optional(object({
      recrawl_behavior = string
    }))
    catalog_targets = optional(list(object({
      database_name       = string
      tables              = list(string)
      connection_name     = optional(string)
      event_queue_arn     = optional(string)
      dlq_event_queue_arn = optional(string)
    })))
    delta_targets = optional(list(object({
      connection_name = string
      delta_tables    = list(string)
      write_manifest  = bool
    })))
    dynamodb_targets = optional(list(object({
      path      = string
      scan_all  = optional(bool, true)
      scan_rate = optional(number)
    })))
    jdbc_targets = optional(list(object({
      connection_name            = string
      path                       = string
      exclusions                 = optional(list(string))
      enable_additional_metadata = optional(string)
    })))
    mongodb_targets = optional(list(object({
      connection_name = string
      path            = string
      scan_all        = optional(bool, true)
    })))
    s3_targets = optional(list(object({
      path                = string
      connection_name     = optional(string)
      exclusions          = optional(list(string))
      sample_size         = optional(number)
      event_queue_arn     = optional(string)
      dlq_event_queue_arn = optional(string)
    })))
    tags = optional(map(string), {})
  }))
  default     = {}
  description = "A map of Glue Crawlers to create. The `name` of the crawler will be the name of the map key. Note `database_name` and `role` are automatically populated using the module's created resources. See [Glue Crawler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_crawler) for guidance on values, and [AWS Docs](https://docs.aws.amazon.com/glue/latest/dg/add-crawler.html) for more information"
}


### JOB VARIABLES ###

variable "jobs" {
  type = map(object({
    command = object({
      name            = optional(string)
      script_location = string
      python_version  = optional(string)
    })
    description               = optional(string)
    connections               = optional(list(string))
    default_arguments         = optional(map(string))
    non_overridable_arguments = optional(map(string))
    execution_class           = optional(string)
    glue_version              = optional(string)
    maintenance_window        = optional(string)
    max_capacity              = optional(number)
    max_retries               = optional(number)
    timeout                   = optional(number)
    security_configuration    = optional(string)
    worker_type               = optional(string)
    number_of_workers         = optional(number)
    execution_property = optional(object({
      max_concurrent_runs = optional(number)
    }))
    notification_property = optional(object({
      notify_delay_after = optional(number)
    }))
    tags = optional(map(string), {})
  }))
  default     = {}
  description = "A map of Glue Jobs to create. The `name` of the job will be the name of the map key. Note `role_arn` is automatically populated using the module's created resources. See [Glue Job](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_job) for guidance on values, and [AWS Docs](https://docs.aws.amazon.com/glue/latest/dg/add-job.html) for more information"
}

variable "create_cloudwatch_logs" {
  type        = bool
  default     = true
  description = "Should a cloudwatch log group be created for jobs? Default is true."
}

variable "configure_encryption_settings" {
  type        = bool
  default     = false
  description = "If enabled, this module will configure account wide encryption settings for Glue. This only needs to be done once per account to protect all glue projects."
}

# We are leaving the `DISABLED` option off because if we're configuring these settings, that would defeat the purpose.
variable "catalog_encryption_mode" {
  type        = string
  default     = "SSE-KMS"
  description = "The encryption-at-rest mode for encrypting Data Catalog data. Valid values: `SSE-KMS`, `SSE-KMS-WITH-SERVICE-ROLE`. Only used if `configure_encryption_settings` is `true`."
  validation {
    condition     = contains(["SSE-KMS", "SSE-KMS-WITH-SERVICE-ROLE"], var.catalog_encryption_mode)
    error_message = "`catalog_encryption_mode` must be one of: `SSE-KMS`, or `SSE-KMS-WITH-SERVICE-ROLE`."
  }
}

variable "metadata_encryption_kms_key_id" {
  type        = string
  default     = null
  description = "The ARN of the AWS KMS key to use for encryption at rest. Will use AWS managed key if omitted."
}

variable "connection_password_kms_key_id" {
  type        = string
  default     = null
  description = <<EOF
The ARN of the AWS KMS key to use to encrypt the connection password. 
The caller of CreateConnection and UpdateConnection needs at least `kms:Encrypt` permission. 
Will use AWS managed key if omitted. Will use AWS managed key if omitted."
EOF
}

variable "catalog_encryption_service_role" {
  type        = string
  default     = null
  description = "Optional ARN of an AWS IAM role used for accessing encrypted Data Catalog data."
}
