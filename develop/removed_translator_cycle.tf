# SLCOPRBA-1124 (cycle fix migración Translator → tf_trnsltr_btch).
#
# Los 6 recursos abajo participan en un ciclo de destroy junto con
# `module.kms.aws_kms_key.this`:
#   aws_api_gateway_integration.translator_bff_root  (destroy)
#   aws_api_gateway_integration.translator_bff_proxy (destroy)
#   aws_api_gateway_deployment.translator_bff        (destroy)
#   aws_api_gateway_stage.translator_bff             (destroy)
#   module.lambda_translator_bff                     (destroy)
#   aws_ecs_task_definition.translator_frontend      (destroy)
#   module.kms.aws_kms_key.this                      (referenciado)
#
# El ciclo es estructural: cada recurso translator referencia
# `module.kms.key_arn` desde state y Terraform no logra ordenar el destroy
# concurrente. Como el pipeline es automático y no admite `-target`, los
# sacamos del state sin destruir (`destroy = false`). Quedan huérfanos en
# AWS — el ECS ya está escalado a 0 y drenado del TG (commit 9d9e910); el
# resto (Lambda, API GW, ECS task def) no genera costo en reposo. Eliminar
# manualmente desde consola en una ventana de mantenimiento posterior.
#
# El resto de recursos translator (DynamoDB, Step Function, S3, IAM roles,
# ECR, layer, otras Lambdas) NO está en el ciclo y se destruye normalmente
# por estar fuera de configuración.

removed {
  from = module.lambda_translator_bff
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_api_gateway_integration.translator_bff_root
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_api_gateway_integration.translator_bff_proxy
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_api_gateway_deployment.translator_bff
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_api_gateway_stage.translator_bff
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_ecs_task_definition.translator_frontend
  lifecycle {
    destroy = false
  }
}

# ECR repo y S3 bucket de artifacts no se pueden destruir desde Terraform porque
# AWS rechaza DeleteRepository con imágenes y DeleteBucket con objetos versionados.
# Como no se requiere reciclar el contenido (Translator vive en tf_trnsltr_btch),
# los sacamos del state. Borrar manualmente desde consola cuando se desee.
removed {
  from = module.translator_frontend_ecr
  lifecycle {
    destroy = false
  }
}

removed {
  from = module.s3_translator_artifacts
  lifecycle {
    destroy = false
  }
}
