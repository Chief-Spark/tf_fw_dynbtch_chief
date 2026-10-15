# EITS Cloud Enablement AWS Glue Module

EITS Terraform module for AWS Glue. This EITS Terraform module will:

- Create a Glue Catalog Database
- Create AWSGlueServiceRole IAM Role, by default
- Create Glue Catalog Tables, if required
- Create Glue Crawlers, if required
- Create Glue Jobs, if required

See CHANGELOG.md for the list of changes for each release.
*We highly recommend that in your code you pin the version to the exact version you are using so that your infrastructure remains stable, and update versions in a systematic way so that they do not catch you by surprise.*

## Encryption
Encryption settings are done account wide in Glue.  The new encryption feature added in 1.2.0 can be done once to protect all glue work in the AWS account.

Future state note:  Right now a database **must** be created for every use of the module.  A future enhancement that would help make this encryption setting even cleaner would be to rework that database code to be optional, so the module could be run with encryption settings alone.

## CloudWatch logs
Glue jobs now log to a cloudwatch log by default.  This can be disabled via the feature flag if it's unneeded for your use case.

## EITS Security & Compliance

**Last Module Review**: 2025-05-23

See below for the date and results of our EITS security and compliance scanning.
 
<!-- BEGIN_BENCHMARK_TABLE -->
| Benchmark | Date | Version | Description |
| --------- | ---- | ------- | ----------- |
| [![tflint](https://img.shields.io/badge/tflint-passed-green)](https://build.experian.local/job/UK-I/job/EITS/job/UKI-Cloud-Enablement/job/terraform-modules/job/eits-tf-aws-glue/7/) | 2025-09-22 | 0.58.1 | Enforces best practices, syntax, naming conventions |
| [![trivy](https://img.shields.io/badge/trivy-passed-green)](https://build.experian.local/job/UK-I/job/EITS/job/UKI-Cloud-Enablement/job/terraform-modules/job/eits-tf-aws-glue/7/) | 2025-09-22 | 0.61.0 | Detects misconfiguration in IaC files, such as Docker, Terraform, etc |
| [![wiz](https://img.shields.io/badge/wiz.io_iac-passed-green)](https://build.experian.local/job/UK-I/job/EITS/job/UKI-Cloud-Enablement/job/terraform-modules/job/eits-tf-aws-glue/7/) | 2025-09-22 | 0.84.0 | Scans tests directory plans for vulnerabilities and risks |
| [![validate](https://img.shields.io/badge/tf_validate-passed-green)](https://build.experian.local/job/UK-I/job/EITS/job/UKI-Cloud-Enablement/job/terraform-modules/job/eits-tf-aws-glue/7/) | 2025-09-22 | 1.13.3 | Validates terraform code using example test directories |
<!-- END_BENCHMARK_TABLE -->

## Features Not Appearing In This Module

The following Glue features are not present in this module:

- [Glue Classifier](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_classifier)
- [Glue Connection](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_connection)
- [Global Glue Encryption Config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_data_catalog_encryption_settings)
- [Glue Data Quality Ruleset](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_data_quality_ruleset)
- [Glue Development Endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_dev_endpoint)
- [Glue ML Transform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_ml_transform)
- [Glue Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_registry)
- [Glue Schema](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_schema)
- [Glue Trigger](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_trigger)
- [Glue User Defined Function](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_user_defined_function)
- [Glue Workflow](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_workflow)

If you wish to use these, use the separate terraform resource, or if you think they should be added to the module please [contact us](https://pages.experian.local/display/UCE/Contact+Us).

## Usage

See below for detailed usage of module. Please see Inputs further down for variable requirements and type declarations. For some examples of proper usage, please see `tests` directory.

```hcl
module "glue" {
  source = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-glue.git"

  # Required variable
  database_name = "<name>"

  # Optional Catalog Database config
  database_description  = "<description>"
  database_location_uri = "<uri>"
  database_catalog_id   = "<defaults to account id>"
  database_parameters   = {<key-value pairs>}

  # Optional config
  create_table_default_permission = {
    permissions = [<list of strings>]
    principal ={
      data_lake_principal_identifier = "<id>"
    }
  }
  target_database = {
    catalog_id    = "<catalog id of target database>"
    database_name = "<name of target database>"
    region        = "<region of target database>"
  }

  # Optional Service IAM Role config - role is automatically created by default
  service_role_name                 = "<override default role name>"
  service_role_permissions_boundary = "<role arn>"
  service_role_policy_documents     = [<list of json policy documents>]
  service_role_tags                 = {<key-value pairs>}
  # OR you may use existing IAM role (do not use above service_role_* args)
  create_service_role = false
  service_role_arn    = "<iam role arn>"

  # Optional Map of Glue Tables
  # This variable has many optional keys, please see type declaration in Inputs below for full breakdown
  tables = {
    <table name> = {
      description = "<description>"
      parameters  = {<key-value pairs>}
      storage_descriptor = {
        location = "<uri of data source>"
      }
    }
  }

  # Optional Map of Glue Crawlers
  # This variable has many optional keys, please see type declaration in Inputs below for full breakdown
  crawlers = {
    <crawler name> = {
      description   = "<description>"
      schedule      = "<cron expression>"
      configuration = "<JSON string>"
      schema_change_policy = {
        delete_behavior = "<LOG/DELETE_FROM_DATABASE/DEPRECATE_IN_DATABASE>"
        update_behavior = "<LOG/UPDATE_IN_DATABASE>"
      }

      # must specify one of the following lists:
      # catalog_targets, delta_targets, dynamodb_targets, jdbc_target, mongodb_target, s3_targets
      # they all share the same structure, for example:
      s3_targets = [
        {
          path       = "<bucket uri>"
          exclusions = ["*.py"]
        }
      ]

      # Crawler specific tags
      tags = {<key-value pairs>}
    }
  }

  # Optional Map of Glue Jobs
  # This variable has many optional keys, please see type declaration in Inputs below for full breakdown
  jobs = {
    <job name> = {
      description       = "<description>"
      worker_type       = "<Standard/G.1X/G.2X/G.025X>"
      number_of_workers = <number>
      glue_version      = "<see AWS Glue Release Notes>"
      timeout           = <number in minutes>
      command = {  
        script_location = "<script location uri>"
        python_version  = <number>
      }
      execution_property = {
        max_concurrent_runs = <number>
      }
      tags = {<key-value pairs>}
    }
  }

  # Required tags
  tags = {
    Environment = <env>
    CostString  = <CostString>
    AppID       = <AppID>
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.55 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.55 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_cloudwatch_logs"></a> [cloudwatch\_logs](#module\_cloudwatch\_logs) | git::https://code.experian.local/scm/EUCES/eits-tf-aws-cloudwatch-logs | 2.5.1 |
| <a name="module_eits_ce_common"></a> [eits\_ce\_common](#module\_eits\_ce\_common) | git::https://code.experian.local/scm/EUCES/eits-tf-aws-ce-common.git | v1 |
| <a name="module_glue_service_role"></a> [glue\_service\_role](#module\_glue\_service\_role) | git::https://code.experian.local/scm/EUCES/eits-tf-aws-iam | 1.7.1 |

## Resources

| Name | Type |
|------|------|
| [aws_glue_catalog_database.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_database) | resource |
| [aws_glue_catalog_table.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_table) | resource |
| [aws_glue_crawler.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_crawler) | resource |
| [aws_glue_data_catalog_encryption_settings.catalog_encryption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_data_catalog_encryption_settings) | resource |
| [aws_glue_job.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_job) | resource |
| [aws_glue_partition_index.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_partition_index) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.assume_role_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_catalog_encryption_mode"></a> [catalog\_encryption\_mode](#input\_catalog\_encryption\_mode) | The encryption-at-rest mode for encrypting Data Catalog data. Valid values: `SSE-KMS`, `SSE-KMS-WITH-SERVICE-ROLE`. Only used if `configure_encryption_settings` is `true`. | `string` | `"SSE-KMS"` | no |
| <a name="input_catalog_encryption_service_role"></a> [catalog\_encryption\_service\_role](#input\_catalog\_encryption\_service\_role) | Optional ARN of an AWS IAM role used for accessing encrypted Data Catalog data. | `string` | `null` | no |
| <a name="input_configure_encryption_settings"></a> [configure\_encryption\_settings](#input\_configure\_encryption\_settings) | If enabled, this module will configure account wide encryption settings for Glue. This only needs to be done once per account to protect all glue projects. | `bool` | `false` | no |
| <a name="input_connection_password_kms_key_id"></a> [connection\_password\_kms\_key\_id](#input\_connection\_password\_kms\_key\_id) | The ARN of the AWS KMS key to use to encrypt the connection password. <br/>The caller of CreateConnection and UpdateConnection needs at least `kms:Encrypt` permission. <br/>Will use AWS managed key if omitted. Will use AWS managed key if omitted." | `string` | `null` | no |
| <a name="input_crawlers"></a> [crawlers](#input\_crawlers) | A map of Glue Crawlers to create. The `name` of the crawler will be the name of the map key. Note `database_name` and `role` are automatically populated using the module's created resources. See [Glue Crawler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_crawler) for guidance on values, and [AWS Docs](https://docs.aws.amazon.com/glue/latest/dg/add-crawler.html) for more information | <pre>map(object({<br/>    description            = optional(string)<br/>    schedule               = optional(string)<br/>    classifiers            = optional(list(string))<br/>    configuration          = optional(string)<br/>    security_configuration = optional(string)<br/>    table_prefix           = optional(string)<br/>    schema_change_policy = optional(object({<br/>      delete_behavior = string<br/>      update_behavior = string<br/>    }))<br/>    lineage_configuration = optional(object({<br/>      crawler_lineage_settings = string<br/>    }))<br/>    recrawl_policy = optional(object({<br/>      recrawl_behavior = string<br/>    }))<br/>    catalog_targets = optional(list(object({<br/>      database_name       = string<br/>      tables              = list(string)<br/>      connection_name     = optional(string)<br/>      event_queue_arn     = optional(string)<br/>      dlq_event_queue_arn = optional(string)<br/>    })))<br/>    delta_targets = optional(list(object({<br/>      connection_name = string<br/>      delta_tables    = list(string)<br/>      write_manifest  = bool<br/>    })))<br/>    dynamodb_targets = optional(list(object({<br/>      path      = string<br/>      scan_all  = optional(bool, true)<br/>      scan_rate = optional(number)<br/>    })))<br/>    jdbc_targets = optional(list(object({<br/>      connection_name            = string<br/>      path                       = string<br/>      exclusions                 = optional(list(string))<br/>      enable_additional_metadata = optional(string)<br/>    })))<br/>    mongodb_targets = optional(list(object({<br/>      connection_name = string<br/>      path            = string<br/>      scan_all        = optional(bool, true)<br/>    })))<br/>    s3_targets = optional(list(object({<br/>      path                = string<br/>      connection_name     = optional(string)<br/>      exclusions          = optional(list(string))<br/>      sample_size         = optional(number)<br/>      event_queue_arn     = optional(string)<br/>      dlq_event_queue_arn = optional(string)<br/>    })))<br/>    tags = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_create_cloudwatch_logs"></a> [create\_cloudwatch\_logs](#input\_create\_cloudwatch\_logs) | Should a cloudwatch log group be created for jobs? Default is true. | `bool` | `true` | no |
| <a name="input_create_service_role"></a> [create\_service\_role](#input\_create\_service\_role) | Whether to create a new IAM role to be used for the Glue service role. If set to `false`, you must provide an existing role ARN to `service_role_arn` | `bool` | `true` | no |
| <a name="input_create_table_default_permission"></a> [create\_table\_default\_permission](#input\_create\_table\_default\_permission) | Creates a set of default permissions on the table for principals. See [Glue Catalog Database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_database#create_table_default_permission) for values | <pre>object({<br/>    permissions = optional(list(string))<br/>    principal = optional(object({<br/>      data_lake_principal_identifier = optional(string)<br/>    }))<br/>  })</pre> | `null` | no |
| <a name="input_database_catalog_id"></a> [database\_catalog\_id](#input\_database\_catalog\_id) | The ID of the Glue Catalog in which to create the database. If none is provided, the AWS account ID is used | `string` | `null` | no |
| <a name="input_database_description"></a> [database\_description](#input\_database\_description) | Description of the database | `string` | `null` | no |
| <a name="input_database_location_uri"></a> [database\_location\_uri](#input\_database\_location\_uri) | The location of the database (e.g. S3 or HDFS path) | `string` | `null` | no |
| <a name="input_database_name"></a> [database\_name](#input\_database\_name) | The name of the Glue catalog database to create | `string` | n/a | yes |
| <a name="input_database_parameters"></a> [database\_parameters](#input\_database\_parameters) | A map of key-value pairs that define parameters and properties of the database | `map(string)` | `{}` | no |
| <a name="input_federated_database"></a> [federated\_database](#input\_federated\_database) | The federated database that references an entity outside the AWS Glue Data Catalog. See [Glue Catalog Database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_database#federated_database) for values | <pre>object({<br/>    connection_name = optional(string)<br/>    identifier      = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_jobs"></a> [jobs](#input\_jobs) | A map of Glue Jobs to create. The `name` of the job will be the name of the map key. Note `role_arn` is automatically populated using the module's created resources. See [Glue Job](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_job) for guidance on values, and [AWS Docs](https://docs.aws.amazon.com/glue/latest/dg/add-job.html) for more information | <pre>map(object({<br/>    command = object({<br/>      name            = optional(string)<br/>      script_location = string<br/>      python_version  = optional(string)<br/>    })<br/>    description               = optional(string)<br/>    connections               = optional(list(string))<br/>    default_arguments         = optional(map(string))<br/>    non_overridable_arguments = optional(map(string))<br/>    execution_class           = optional(string)<br/>    glue_version              = optional(string)<br/>    maintenance_window        = optional(string)<br/>    max_capacity              = optional(number)<br/>    max_retries               = optional(number)<br/>    timeout                   = optional(number)<br/>    security_configuration    = optional(string)<br/>    worker_type               = optional(string)<br/>    number_of_workers         = optional(number)<br/>    execution_property = optional(object({<br/>      max_concurrent_runs = optional(number)<br/>    }))<br/>    notification_property = optional(object({<br/>      notify_delay_after = optional(number)<br/>    }))<br/>    tags = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_metadata_encryption_kms_key_id"></a> [metadata\_encryption\_kms\_key\_id](#input\_metadata\_encryption\_kms\_key\_id) | The ARN of the AWS KMS key to use for encryption at rest. Will use AWS managed key if omitted. | `string` | `null` | no |
| <a name="input_service_role_arn"></a> [service\_role\_arn](#input\_service\_role\_arn) | The ARN of an existing IAM role to use for the Glue service role, see [AWS Glue Service Role](https://docs.aws.amazon.com/glue/latest/dg/create-an-iam-role.html) for requirements. Only used when `create_service_role` is `false` | `string` | `null` | no |
| <a name="input_service_role_name"></a> [service\_role\_name](#input\_service\_role\_name) | The name of the Glue service IAM role, appended to prefix 'BURoleFor'. If left `null` then role name will default to `BURoleForAWSGlueServiceRole-<database_name>`. Only used when `create_service_role` is `true` | `string` | `null` | no |
| <a name="input_service_role_permissions_boundary"></a> [service\_role\_permissions\_boundary](#input\_service\_role\_permissions\_boundary) | ARN of the policy that is used to set the permissions boundary for the Glue service IAM role. Only used when `create_service_role` is `true` | `string` | `null` | no |
| <a name="input_service_role_policy_documents"></a> [service\_role\_policy\_documents](#input\_service\_role\_policy\_documents) | A list of policy documents to attach to the Glue service IAM role. Only used when `create_service_role` is `true` | `list(string)` | `[]` | no |
| <a name="input_service_role_tags"></a> [service\_role\_tags](#input\_service\_role\_tags) | Additional tags to apply to the Glue service IAM role. Only used when `create_service_role` is `true` | `map(string)` | `{}` | no |
| <a name="input_tables"></a> [tables](#input\_tables) | A map of Glue Tables to create. The `name` of the table will be the name of the map key. Note `database_name` is automatically populated using the module's created resources. See [Glue Catalog Table](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_table) for guidance on values, and [AWS Docs](https://docs.aws.amazon.com/glue/latest/dg/tables-described.html) for more information | <pre>map(object({<br/>    description        = optional(string)<br/>    owner              = optional(string)<br/>    parameters         = optional(map(string))<br/>    retention          = optional(number)<br/>    table_type         = optional(string)<br/>    view_expanded_text = optional(string)<br/>    view_original_text = optional(string)<br/>    partition_index = optional(list(object({<br/>      index_name = string<br/>      keys       = list(string)<br/>    })))<br/>    partition_keys = optional(list(object({<br/>      name    = string<br/>      type    = optional(string)<br/>      comment = optional(string)<br/>    })))<br/>    target_table = optional(object({<br/>      catalog_id    = string<br/>      database_name = string<br/>      name          = string<br/>      region        = optional(string)<br/>    }))<br/>    storage_descriptor = optional(object({<br/>      additional_locations      = optional(list(string))<br/>      bucket_columns            = optional(list(string))<br/>      compressed                = optional(bool)<br/>      location                  = string<br/>      input_format              = optional(string)<br/>      output_format             = optional(string)<br/>      number_of_buckets         = optional(number)<br/>      parameters                = optional(map(string))<br/>      stored_as_sub_directories = optional(bool)<br/>      columns = optional(list(object({<br/>        name       = string<br/>        comment    = optional(string)<br/>        parameters = optional(map(string))<br/>        type       = optional(string)<br/>      })))<br/>      schema_reference = optional(object({<br/>        schema_version_number = number<br/>        schema_version_id     = optional(string)<br/>        schema_id = optional(object({<br/>          registry_name = string<br/>          schema_arn    = string<br/>          schema_name   = string<br/>        }))<br/>      }))<br/>      ser_de_info = optional(object({<br/>        name                  = optional(string)<br/>        parameters            = optional(map(string))<br/>        serialization_library = optional(string)<br/>      }))<br/>      skewed_info = optional(object({<br/>        skewed_column_names               = optional(list(string))<br/>        skewed_column_values              = optional(list(string))<br/>        skewed_column_value_location_maps = optional(list(string))<br/>      }))<br/>      sort_columns = optional(list(object({<br/>        column     = string<br/>        sort_order = number<br/>      })))<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags for all created AWS resources. See [Cloud Tagging Strategy & Standards](https://pages.experian.com/pages/viewpage.action?pageId=400041906) for available tags | `map(string)` | `{}` | no |
| <a name="input_target_database"></a> [target\_database](#input\_target\_database) | The target database for resource linking. See [Glue Catalog Database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_database#target_database) for values | <pre>object({<br/>    catalog_id    = string<br/>    database_name = string<br/>    region        = optional(string)<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cloudwatch_log_group"></a> [cloudwatch\_log\_group](#output\_cloudwatch\_log\_group) | Cloudwatch group name |
| <a name="output_crawler_arns"></a> [crawler\_arns](#output\_crawler\_arns) | List of ARNs of the Glue Crawlers |
| <a name="output_crawler_ids"></a> [crawler\_ids](#output\_crawler\_ids) | List of names of the Glue Crawlers |
| <a name="output_database_arn"></a> [database\_arn](#output\_database\_arn) | ARN of the Glue Catalog Database |
| <a name="output_database_id"></a> [database\_id](#output\_database\_id) | Catalog ID and name of the database |
| <a name="output_job_arns"></a> [job\_arns](#output\_job\_arns) | List of ARNs of the Glue Jobs |
| <a name="output_job_ids"></a> [job\_ids](#output\_job\_ids) | List of names of the Glue Jobs |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the created IAM role |
| <a name="output_role_id"></a> [role\_id](#output\_role\_id) | The name of the IAM role created |
<!-- END_TF_DOCS -->

## Metadata
```discoveryhub
summary: Terraform module for AWS Glue
region: Global
bu: EITS
docs: https://pages.experian.local/display/UCE/InnerSource+Terraform+Modules
contacts:
  technical: EITS UK&I Cloud Enablement Team <eitsukicloud@experian.com>
```
