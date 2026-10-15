"""
Módulo de infraestructura para interactuar con SES de AWS.
"""

import boto3
import json
import logging
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication
from email.mime.base import MIMEBase
from email import encoders
import os
from config.config import settings
from .s3_client import S3Client
from .email_templates import EmailTemplateManager

logger = logging.getLogger(__name__)

class SESClient:
    """
    Cliente para interactuar con SES de AWS.
    """

    def __init__(self):
        self.client = boto3.client("ses")
        self.s3_client = S3Client()
        self.template_manager = EmailTemplateManager()

    def sendMessage(self, emails: list, subject: str, body: str):
        
        #Envía un mensaje a través de SES.
        
        template_name = 'mail_to_batch_template' # Name of your SES template
        template_data = {
            "subject": subject,
            "body": body
        }

        try:
            self.client.send_templated_email(
                Source=settings.email_sender,
                Destination={
                    'ToAddresses': emails
                },
                Template=template_name,
                TemplateData=json.dumps(template_data)
            )
            logger.info("sendMessage enviado correctamente")

        except Exception as e:
            logger.error(f"Error enviando sendMessage: {str(e)}")
            raise

    def send_email_with_s3_attachments(self, emails: list, subject: str, body: str, s3_attachments: list = None):
        """
        Envía un email con archivos adjuntos descargados desde S3.
        
        Args:
            emails (list): Lista de direcciones de email destinatarias
            subject (str): Asunto del email
            body (str): Cuerpo del email (puede ser HTML o texto plano)
            s3_attachments (list): Lista de diccionarios con información de archivos S3
                Formato: [{"bucket": "bucket_name", "key": "file_path", "filename": "display_name"}]
        """
        try:
            logger.info(f"Iniciando envío de email - Destinatarios: {len(emails)}, Asunto: {subject[:50]}...")
            
            # Crear el mensaje MIME con codificación UTF-8
            msg = MIMEMultipart()
            msg['From'] = settings.email_sender
            msg['To'] = ', '.join(emails)
            # Asegurar codificación UTF-8 para el subject
            from email.header import Header
            msg['Subject'] = Header(subject, 'utf-8').encode()
            
            logger.info(f"Email configurado - From: {settings.email_sender}, To: {', '.join(emails)}")

            # Agregar el cuerpo del email con codificación UTF-8 explícita
            # Detectar si el cuerpo es HTML
            if body.strip().startswith('<') and body.strip().endswith('>'):
                msg.attach(MIMEText(body, 'html', 'utf-8'))
                logger.debug("Cuerpo del email configurado como HTML con UTF-8")
            else:
                msg.attach(MIMEText(body, 'plain', 'utf-8'))
                logger.debug("Cuerpo del email configurado como texto plano con UTF-8")

            # Procesar archivos adjuntos desde S3 usando S3Client
            attachment_count = 0
            if s3_attachments:
                logger.info(f"Procesando {len(s3_attachments)} archivo(s) adjunto(s)")
                for attachment in s3_attachments:
                    try:
                        bucket = attachment['bucket']
                        key = attachment['key']
                        filename = attachment.get('filename', os.path.basename(key))
                        
                        logger.info(f"Descargando adjunto desde S3: {bucket}/{key}")
                        
                        # Usar S3Client para descargar archivo
                        file_info = self.s3_client.download_file_for_attachment(bucket, key)
                        
                        # Crear el adjunto basado en el tipo de contenido
                        if file_info['content_type'].startswith('text/'):
                            attachment_part = MIMEText(file_info['content'].decode('utf-8'))
                            attachment_part.add_header('Content-Disposition', f'attachment; filename="{filename}"')
                        else:
                            attachment_part = MIMEApplication(file_info['content'])
                            attachment_part.add_header('Content-Disposition', f'attachment; filename="{filename}"')
                        
                        msg.attach(attachment_part)
                        attachment_count += 1
                        logger.info(f"Archivo adjunto agregado: {filename} ({file_info['size']} bytes, tipo: {file_info['content_type']})")
                        
                    except Exception as attachment_error:
                        logger.error(f"Error procesando adjunto {attachment.get('filename', 'unknown')} desde {attachment.get('bucket', 'unknown')}/{attachment.get('key', 'unknown')}: {str(attachment_error)}", exc_info=True)
                        # Continuar con otros adjuntos en caso de error

            # Enviar el email
            logger.info(f"Enviando email a través de SES - Destinatarios: {', '.join(emails)}, Adjuntos: {attachment_count}")
            
            response = self.client.send_raw_email(
                Source=settings.email_sender,
                Destinations=emails,
                RawMessage={'Data': msg.as_string()}
            )
            
            message_id = response['MessageId']
            logger.info(f"Email enviado exitosamente - MessageId: {message_id}, Destinatarios: {', '.join(emails)}, Adjuntos: {attachment_count}")
            return message_id

        except Exception as e:
            logger.error(f"Error enviando email con adjuntos - Destinatarios: {', '.join(emails)}, Error: {str(e)}", exc_info=True)
            raise

    def send_email_with_s3_attachment(self, emails: list, subject: str, body: str, bucket: str, key: str, filename: str = None):
        """
        Método conveniente para enviar un email con un solo archivo adjunto desde S3.
        
        Args:
            emails (list): Lista de direcciones de email destinatarias
            subject (str): Asunto del email
            body (str): Cuerpo del email
            bucket (str): Nombre del bucket S3
            key (str): Ruta del archivo en S3
            filename (str): Nombre del archivo a mostrar (opcional, usa el nombre del archivo en S3 si no se especifica)
        """
        if filename is None:
            filename = os.path.basename(key)
            
        s3_attachments = [{"bucket": bucket, "key": key, "filename": filename}]
        return self.send_email_with_s3_attachments(emails, subject, body, s3_attachments)

    def send_templated_email_with_s3_attachments(self, emails: list, template_name: str, s3_attachments: list = None, **template_params):
        """
        Envía un email usando una plantilla HTML con archivos adjuntos desde S3.
        
        Args:
            emails (list): Lista de direcciones de email destinatarias
            template_name (str): Nombre de la plantilla a usar ('batch_notification', 'batch_success', 'batch_error')
            s3_attachments (list): Lista de diccionarios con información de archivos S3
            **template_params: Parámetros para renderizar la plantilla
        """
        try:
            logger.info(f"Preparando email con plantilla '{template_name}' - Destinatarios: {len(emails)}")
            
            # Validar que hay destinatarios
            if not emails or len(emails) == 0:
                raise ValueError("La lista de destinatarios está vacía")
            
            # Preparar información de adjuntos para la plantilla
            attachment_info = []
            if s3_attachments:
                for attachment in s3_attachments:
                    attachment_info.append({
                        'filename': attachment.get('filename', os.path.basename(attachment['key']))
                    })
                logger.info(f"Plantilla incluirá información de {len(attachment_info)} adjunto(s)")
            
            # Agregar información de adjuntos a los parámetros de la plantilla
            template_params['attachments'] = attachment_info
            
            # Renderizar la plantilla
            logger.info(f"Renderizando plantilla '{template_name}' con parámetros: {list(template_params.keys())}")
            html_body = self.template_manager.render_template(template_name, **template_params)
            subject = template_params.get('subject', 'Notificación del Sistema')
            
            logger.info(f"Plantilla renderizada - Asunto: {subject[:50]}...")
            
            # Enviar el email usando la función existente
            message_id = self.send_email_with_s3_attachments(emails, subject, html_body, s3_attachments)
            
            logger.info(f"Email con plantilla '{template_name}' enviado exitosamente - MessageId: {message_id}")
            return message_id
            
        except Exception as e:
            logger.error(f"Error enviando email con plantilla '{template_name}' - Destinatarios: {', '.join(emails) if emails else 'None'}, Error: {str(e)}", exc_info=True)
            raise

    def send_batch_success_notification(self, emails: list, batch_id: str, message: str = None, s3_attachments: list = None):
        """
        Envía una notificación de éxito de procesamiento por lotes.
        
        Args:
            emails (list): Lista de destinatarios
            batch_id (str): ID del lote procesado
            message (str): Mensaje adicional opcional
            s3_attachments (list): Archivos adjuntos desde S3
        """
        template_params = {
            'subject': f'Procesamiento Completado - Lote {batch_id}',
            'batch_id': batch_id,
            'body': message or f'<p>El lote <strong>{batch_id}</strong> se ha procesado correctamente.</p>'
        }
        
        return self.send_templated_email_with_s3_attachments(
            emails, 'batch_success', s3_attachments, **template_params
        )

    def send_batch_error_notification(self, emails: list, batch_id: str, error_details: str, message: str = None, s3_attachments: list = None):
        """
        Envía una notificación de error en procesamiento por lotes.
        
        Args:
            emails (list): Lista de destinatarios
            batch_id (str): ID del lote que falló
            error_details (str): Detalles del error
            message (str): Mensaje adicional opcional
            s3_attachments (list): Archivos adjuntos desde S3 (logs, etc.)
        """
        template_params = {
            'subject': f'Error en Procesamiento - Lote {batch_id}',
            'batch_id': batch_id,
            'error_details': error_details,
            'body': message or f'<p>Se ha producido un error en el procesamiento del lote <strong>{batch_id}</strong>.</p>'
        }
        
        return self.send_templated_email_with_s3_attachments(
            emails, 'batch_error', s3_attachments, **template_params
        )

    def send_batch_notification(self, emails: list, subject: str, message: str, s3_attachments: list = None, **extra_params):
        """
        Envía una notificación general con plantilla personalizable.
        
        Args:
            emails (list): Lista de destinatarios
            subject (str): Asunto del email
            message (str): Mensaje del cuerpo
            s3_attachments (list): Archivos adjuntos desde S3
            **extra_params: Parámetros adicionales para la plantilla
        """
        template_params = {
            'subject': subject,
            'body': message,
            **extra_params
        }
        
        return self.send_templated_email_with_s3_attachments(
            emails, 'batch_notification', s3_attachments, **template_params
        )

    def send_task_failure(self, task_token: str, error: str, cause: str):
        """
        Envía un mensaje de error.
        """
        try:
            self.client.send_task_failure(
                taskToken=task_token, error=error, cause=cause
            )
            logger.info("send_task_failure enviado correctamente")
        except Exception as e:
            logger.error(f"Error enviando send_task_failure: {str(e)}")
            raise
