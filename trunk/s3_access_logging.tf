# Server access logging: destino = result-repository (lifecycle 7d ya definido en s3.tf).
# No se modifica access_logging_bucket_name en los módulos EITS (evita ciclos/count).

resource "aws_s3_bucket_logging" "fwdynbtch" {
  for_each = local.s3_access_log_source_buckets

  bucket        = each.value
  target_bucket = local.s3_access_logs_target_bucket_id
  target_prefix = "${local.s3_access_logs_prefix}/${each.value}/"

  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}
