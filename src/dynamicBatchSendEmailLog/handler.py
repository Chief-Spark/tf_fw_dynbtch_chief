"""
Handler for the dynamicBatchSendEmailLog Lambda function.
"""

import logging
import json

import boto3
from botocore.exceptions import ClientError

from domain.models import FileInfo
from domain.parsers import parse_filename
from domain.schemas import StepFunctionEvent
from domain.services.error_handling_service import ErrorHandlingService
from domain.services.result_processor import ResultProcessor
from infrastructure.dynamodb import DynamoDBClient
from infrastructure.step_function import StepFunctionClient
from infrastructure.ses import SESClient
from config.config import settings
from config.logger import setup_logging

setup_logging()
logger = logging.getLogger(__name__)

# SSM parameter path for notification emails by process type
NOTIFICATIONS_EMAILS_PARAMETER = "/redshift/procesosbatch/notifications-emails"

# Cache for SSM parameter value (reused across warm invocations)
_ssm_notifications_cache = None


def _get_notifications_emails_from_ssm():
    """
    Read the notifications-emails SSM parameter and return the parsed dict.
    Returns None if the parameter cannot be read.
    Result is cached for the lifetime of the Lambda container.
    """
    global _ssm_notifications_cache
    if _ssm_notifications_cache is not None:
        return _ssm_notifications_cache

    try:
        ssm_client = boto3.client("ssm")
        response = ssm_client.get_parameter(Name=NOTIFICATIONS_EMAILS_PARAMETER)
        value = json.loads(response["Parameter"]["Value"])
        _ssm_notifications_cache = value
        logger.info(f"SSM parameter '{NOTIFICATIONS_EMAILS_PARAMETER}' loaded successfully")
        return value
    except ClientError as e:
        logger.warning(f"Could not read SSM parameter '{NOTIFICATIONS_EMAILS_PARAMETER}': {e}")
        return None
    except (json.JSONDecodeError, KeyError) as e:
        logger.warning(f"Could not parse SSM parameter '{NOTIFICATIONS_EMAILS_PARAMETER}': {e}")
        return None


def _resolve_recipient_emails(event, default_emails):
    """
    Determine the recipient emails based on the event payload.

    Priority:
    1. If 'recipient_emails' is explicitly provided in the event, use those.
    2. If 'process_type' is provided (or defaults to 'batch'), look up emails
       from the SSM parameter /redshift/procesosbatch/notifications-emails.
    3. Fall back to the default EMAIL_RECEPTORS env var.

    Returns:
        tuple: (emails list, error_msg or None)
    """
    payload_emails = event.get('recipient_emails')

    if payload_emails:
        if not isinstance(payload_emails, list):
            return None, "El campo 'recipient_emails' debe ser una lista de correos"
        emails = [e for e in payload_emails if e and isinstance(e, str) and e.strip()]
        if not emails:
            return None, "La lista 'recipient_emails' no contiene correos válidos"
        return emails, None

    # Determine process type: defaults to 'batch' if not specified
    process_type = event.get('process_type', 'batch')
    logger.info(f"Process type resolved: '{process_type}'")

    # Try to get emails from SSM parameter
    ssm_config = _get_notifications_emails_from_ssm()
    if ssm_config and process_type in ssm_config:
        ssm_emails = ssm_config[process_type]
        if isinstance(ssm_emails, list) and ssm_emails:
            logger.info(f"Using emails from SSM for process_type='{process_type}': {ssm_emails}")
            return ssm_emails, None
        else:
            logger.warning(f"SSM emails for process_type='{process_type}' is empty or invalid, falling back")

    # Fall back to default EMAIL_RECEPTORS
    if not default_emails:
        return None, "No hay correos configurados en la variable de entorno EMAIL_RECEPTORS"
    emails = [default_emails[0]]
    logger.info(f"Fallback to default email: {emails[0]}")
    return emails, None

def normalize_text(text):
    """
    Normaliza texto asegurando que sea una cadena UTF-8 válida.
    Si es bytes, decodifica. Si es string, lo devuelve tal cual.
    """
    try:
        if isinstance(text, bytes):
            return text.decode('utf-8')
        return str(text)
    except (UnicodeDecodeError, UnicodeEncodeError) as e:
        logger.warning(f"Error normalizando texto: {e}")
        return text


def _is_cloudwatch_alarm_payload(event):
    """Detecta el JSON que CloudWatch publica en SQS cuando dispara una alarma."""
    return isinstance(event, dict) and "AlarmName" in event and "NewStateValue" in event



def _parse_payload_from_sqs_body(raw_body):
    """Parse SQS body; unwrap SNS Notification envelope when present."""
    payload = json.loads(raw_body)
    if (
        isinstance(payload, dict)
        and payload.get("Type") == "Notification"
        and "Message" in payload
    ):
        message = payload["Message"]
        if isinstance(message, str):
            try:
                inner = json.loads(message)
                logger.info("Evento extraído desde SNS Notification envelope")
                return inner
            except json.JSONDecodeError:
                logger.warning("SNS Message no es JSON; se usa texto plano")
                subject = normalize_text(payload.get("Subject", "SNS Notification"))
                message_text = normalize_text(message)
                is_kiro = subject.lower().startswith("kiro transfer")
                error_markers = (
                    "error",
                    "fallo",
                    "incompleto",
                    "no encontrado",
                    "invalido",
                    "inválido",
                    "sin archivos",
                    "parcial",
                    "no verificado",
                )
                is_error = is_kiro and any(
                    marker in subject.lower() for marker in error_markers
                )
                return {
                    "subject": subject,
                    "body": f"<p>{message_text}</p>",
                    "batch_name": "KIRO_TRANSFER" if is_kiro else "sns-notification",
                    "template_name": "batch_error" if is_error else "batch_notification",
                    "process_type": "transfer batch" if is_kiro else "monitoring",
                    **({"error_details": message_text} if is_error else {}),
                }
        if isinstance(message, dict):
            return message
    return payload


def lambda_handler(event, context):
    """
    This lambda handler is responsible for notifying the completion or error of a dynamic batch
    to the main batch step function.

    Supports both direct invocation and SQS trigger.
    When triggered by SQS, the payload is extracted from the SQS record body.

    1. Validates the input event.
    2. Sends a notification success or error to the main batch step function.
    3. Notifies success and register event.
    """
    logger.info("Inicio de lambda dynamicBatchSendEmailLog")
    logger.info(f"Evento recibido: {json.dumps(event, default=str)}")
    
    # Si el evento viene de SQS, extraer el body del primer registro
    if 'Records' in event and len(event['Records']) > 0:
        sqs_record = event['Records'][0]
        if sqs_record.get('eventSource') == 'aws:sqs':
            try:
                event = _parse_payload_from_sqs_body(sqs_record['body'])
                logger.info("Evento extraído desde SQS record")
            except (json.JSONDecodeError, KeyError) as e:
                error_msg = f"Error al parsear el body del mensaje SQS: {str(e)}"
                logger.error(error_msg)
                return {
                    "statusCode": 400,
                    "body": json.dumps({'error': error_msg}),
                }

    if _is_cloudwatch_alarm_payload(event):
        alarm_name = event.get("AlarmName", "unknown")
        new_state = event.get("NewStateValue", "unknown")
        logger.info(
            f"Alarma CloudWatch detectada (alarm={alarm_name}, state={new_state}); "
            "se omite el envío de correo"
        )
        return {
            "statusCode": 200,
            "body": json.dumps({
                "status": "skipped",
                "reason": "CloudWatch Alarm events are ignored",
                "alarm_name": alarm_name,
                "state": new_state,
            }),
        }

    # Validar campos obligatorios
    required_fields = ['subject', 'body', 'batch_name', 'template_name']
    for field in required_fields:
        if field not in event:
            error_msg = f"Campo obligatorio '{field}' no encontrado en el evento"
            logger.error(error_msg)
            return {
                "statusCode": 400,
                "body": json.dumps({'error': error_msg}),
            }
        
        if not event[field] or (isinstance(event[field], str) and not event[field].strip()):
            error_msg = f"Campo obligatorio '{field}' está vacío o tiene valor nulo"
            logger.error(error_msg)
            return {
                "statusCode": 400,
                "body": json.dumps({'error': error_msg}),
            }
    
    # Extraer campos obligatorios
    subject = normalize_text(event['subject'])
    body = normalize_text(event['body'])
    batch_name = normalize_text(event['batch_name'])
    
    template_name = event['template_name']
    
    # Extraer campos opcionales de cluster (multicluster)
    cluster_identifier = event.get('cluster_identifier', '')
    cluster_type = event.get('cluster_type', '')
    
    # Si hay información de cluster, enriquecer el body del email
    if cluster_identifier and cluster_type:
        cluster_info_html = (
            f"<p><strong>Cluster:</strong> {cluster_identifier} "
            f"(<em>{cluster_type}</em>)</p>"
        )
        # Insertar la info del cluster al inicio del body si no la contiene ya
        if cluster_identifier not in body:
            body = cluster_info_html + body
    
    # Extraer campos opcionales para archivos adjuntos
    key_file = event.get('key_file')
    file_name = event.get('file_name')
    error_details = "No especificado"
    if(event.get('error_details')):
        error_details = event.get('error_details')
    
    # Validar si se debe incluir archivo adjunto
    include_attachment = (
        key_file and 
        file_name and 
        isinstance(key_file, str) and 
        isinstance(file_name, str) and 
        key_file.strip() and 
        file_name.strip()
    )
    
    # Cargar lista de correos por defecto desde la variable de entorno
    default_emails = json.loads(settings.email_receptors)
    
    # Resolver destinatarios según process_type, recipient_emails o fallback
    emails, email_error = _resolve_recipient_emails(event, default_emails)
    if email_error:
        logger.error(email_error)
        return {
            "statusCode": 400 if "recipient_emails" in email_error or "lista" in email_error else 500,
            "body": json.dumps({'error': email_error}),
        }
    
    logger.info(f"Destinatarios del email: {emails}")
    
    # Validar formato de emails
    import re
    email_pattern = re.compile(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
    invalid_emails = [email for email in emails if not email_pattern.match(email)]
    if invalid_emails:
        error_msg = f"Direcciones de email inválidas: {', '.join(invalid_emails)}"
        logger.error(error_msg)
        return {
            "statusCode": 400,
            "body": json.dumps({'error': error_msg}),
        }
    
    bucket = settings.error_files_bucket
    environment = settings.environment

    ses_client = SESClient()


    try:
        
        # Preparar adjuntos si están disponibles
        s3_attachments = None
        
        logger.info(f"Configuración de envío - bucket: {bucket}, key: {key_file}, filename: {file_name}")
        if include_attachment:
            s3_attachments = [{"bucket": bucket, "key": key_file, "filename": file_name}]
            logger.info(f"Archivo adjunto incluido: {file_name} desde {bucket}/{key_file}")
        else:
            logger.info("No se incluirán archivos adjuntos en el email")
        
        logger.info(f"Enviando email a: {', '.join(emails)} con plantilla: {template_name}")
        
        message_id = ses_client.send_templated_email_with_s3_attachments(
            emails=emails,
            template_name=template_name,
            s3_attachments=s3_attachments,
            subject=f"{environment.upper()} - {subject}",
            batch_id=batch_name,
            body=body,
            error_details=error_details
        )
        logger.info(f"Email enviado exitosamente. Message ID: {message_id}, Destinatarios: {', '.join(emails)}")

        return {
            "statusCode": 200,
            "body": json.dumps({
                'Status': 'Email enviado exitosamente',
                'MessageId': message_id,
                'Recipients': emails,
                'BatchName': batch_name
            }),
        }

    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        logger.error(f"Error de AWS SES ({error_code}): {error_message}")
        logger.error(f"Detalles del error SES - Destinatarios: {', '.join(emails)}, Plantilla: {template_name}")
        
        # Mensajes de error más descriptivos según el código de error
        if error_code == 'MessageRejected':
            user_message = f"El email fue rechazado por SES. Verifica que las direcciones estén verificadas en modo sandbox: {', '.join(emails)}"
        elif error_code == 'MailFromDomainNotVerified':
            user_message = "El dominio del remitente no está verificado en SES"
        elif error_code == 'ConfigurationSetDoesNotExist':
            user_message = "La configuración de SES no existe"
        else:
            user_message = f"Error de SES: {error_message}"
            
        return {
            "statusCode": 500,
            "body": json.dumps({
                'error': user_message,
                'errorCode': error_code,
                'recipients': emails
            }),
        }
    except Exception as e:
        logger.error(f"Error inesperado al enviar email: {str(e)}", exc_info=True)
        logger.error(f"Contexto del error - Destinatarios: {', '.join(emails)}, Batch: {batch_name}, Plantilla: {template_name}")
        return {
            "statusCode": 500,
            "body": json.dumps({
                'error': f'Error al enviar email: {str(e)}',
                'recipients': emails,
                'batch_name': batch_name
            }),
        }
    finally:
        logger.info(f"Finalización de lambda dynamicBatchSendEmailLog - Batch: {batch_name}")
