"""
Settings configuration for the application.
"""

from zoneinfo import ZoneInfo

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    definition_bucket: str
    main_batch_event_table: str
    dynamic_notifier_arn: str
    step_function_role_arn: str
    glue_job_name: str
    log_level: str = "INFO"
    aws_log_level: str = "WARNING"
    aws_region: str = "us-east-1"
    stage: str
    project_name: str
    
    # Redshift - Cluster Aprovisionado (ALPHA)
    redshift_cluster_id: str
    redshift_database: str
    redshift_user: str
    
    # Redshift - Serverless (NEDA)
    redshift_workgroup_name_neda: str
    redshift_database_neda: str

    # Redshift - Serverless (HYBRID)
    redshift_workgroup_name_hybrid: str
    redshift_database_hybrid: str

    # Redshift - Registro genérico de destinos multicluster (Escenario C).
    # JSON string opcional: mapa de "nombre_pipeline" -> configuración del destino.
    # Si está vacío, el builder reconstruye ALPHA/NEDA/HYBRID desde las variables de arriba,
    # preservando el comportamiento actual sin cambios en tfvars.
    #
    # Estructura esperada por entrada:
    #   {
    #     "ALPHA":  {"type": "provisioned", "database": "...", "cluster_id": "...", "user": "..."},
    #     "NEDA":   {"type": "serverless",  "database": "...", "workgroup_name": "..."},
    #     "OTRO":   {"type": "serverless",  "database": "...", "workgroup_name": "..."}
    #   }
    # Mapea a la env var REDSHIFT_TARGETS_JSON (patrón del repo: campo -> NOMBRE_CAMPO).
    # Debe coincidir con el nombre de la env var inyectada en lambda.tf.
    redshift_targets_json: str = ""

    timezone: ZoneInfo = ZoneInfo("America/Bogota")
    aws_lambda_function_name: str


settings = Settings()
