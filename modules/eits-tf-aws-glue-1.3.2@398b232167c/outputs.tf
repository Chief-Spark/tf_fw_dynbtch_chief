### CATALOG DATABASE OUTPUTS ###

output "database_arn" {
  value       = aws_glue_catalog_database.this.arn
  description = "ARN of the Glue Catalog Database"
}

output "database_id" {
  value       = aws_glue_catalog_database.this.id
  description = "Catalog ID and name of the database"
}

output "cloudwatch_log_group" {
  value       = try(module.cloudwatch_logs[0].log_group_name, "")
  description = "Cloudwatch group name"
}

### CRAWLER VARIABLES ###

output "crawler_arns" {
  value       = try(aws_glue_crawler.this[*].arn, null)
  description = "List of ARNs of the Glue Crawlers"
}

output "crawler_ids" {
  value       = try(aws_glue_crawler.this[*].id, null)
  description = "List of names of the Glue Crawlers"
}

### IAM ROLE VARIABLES ###

output "role_arn" {
  value       = try(module.glue_service_role.role_arn, null)
  description = "ARN of the created IAM role"
}

output "role_id" {
  value       = try(module.glue_service_role.role_id, null)
  description = "The name of the IAM role created"
}

### JOB VARIABLES ###

output "job_arns" {
  value       = try(aws_glue_job.this[*].arn, null)
  description = "List of ARNs of the Glue Jobs"
}

output "job_ids" {
  value       = try(aws_glue_crawler.this[*].id, null)
  description = "List of names of the Glue Jobs"
}
