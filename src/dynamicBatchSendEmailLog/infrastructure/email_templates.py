"""
Módulo para manejar plantillas de email HTML.
"""

import logging
from typing import Dict, Any
from .s3_client import S3Client
from config.config import settings

logger = logging.getLogger(__name__)
bucket = settings.error_files_bucket

class EmailTemplateManager:
    """
    Gestor de plantillas de email HTML.
    """

    def __init__(self):
        self.s3_client = S3Client()

    def _load_templates(self, bucket: str, template_name: str) -> Dict[str, str]:
        """
        Carga las plantillas de email disponibles.
        
        Args:
            bucket (str): Nombre del bucket S3
            template (str): Nombre de la plantilla
            
        Returns:
            string: Contenido de la plantilla HTML
        """
        template = None
        try:
            file_info = self.s3_client.download_file_for_attachment(bucket, f"templates_ses/{template_name}.html")
            template = file_info['content'].decode('utf-8')
        except Exception as e:
            logger.error(f"Error leyendo contenido del objeto {bucket}/templates_ses/{template_name}.html: {str(e)}")

        logger.info(f"Plantilla cargada exitosamente")
        return template

    def get_template(self, bucket: str, template_name: str) -> str:
        """
        Obtiene una plantilla específica por nombre.
        
        Args:
            bucket (str): Nombre del bucket S3
            template_name (str): Nombre de la plantilla
            
        Returns:
            str: Plantilla HTML
            
        Raises:
            ValueError: Si la plantilla no existe
        """
        template = self._load_templates(bucket, template_name)
        if template == None:
            logger.error(f"Plantilla '{template_name}' no encontrada.")
            raise ValueError(f"Plantilla '{template_name}' no encontrada.")
        
        logger.info(f"Plantilla '{template_name}' obtenida exitosamente")
        return template

    def render_template(self, template_name: str, **kwargs) -> str:
        """
        Renderiza una plantilla con los parámetros proporcionados.
        
        Args:
            template_name (str): Nombre de la plantilla
            **kwargs: Parámetros para renderizar la plantilla
            
        Returns:
            str: HTML renderizado
        """
        try:
            template = self.get_template(bucket, template_name)
            
            # Agregar valores por defecto
            from datetime import datetime, timezone, timedelta
            # Crear timezone para Colombia (UTC-5)
            colombia_tz = timezone(timedelta(hours=-5))
            default_values = {
                'timestamp': datetime.now(colombia_tz).strftime('%d/%m/%Y %H:%M:%S'),
                'attachment_section': '',
                'body': '',
                'subject': 'Notificación del Sistema',
                'batch_id': 'N/A',
                'error_details': 'No especificado'
            }
            
            # Combinar valores por defecto con los proporcionados
            render_params = {**default_values, **kwargs}
            
            # Generar sección de adjuntos si hay archivos
            if render_params.get('attachments'):
                attachments = render_params['attachments']
                if isinstance(attachments, list) and len(attachments) > 0:
                    attachment_list = '<ul>'
                    for att in attachments:
                        filename = att.get('filename', 'archivo')
                        attachment_list += f'<li>📎 {filename}</li>'
                    attachment_list += '</ul>'
                    
                    render_params['attachment_section'] = f'''
                    <div class="attachment-notice">
                        <strong>📎 Archivos adjuntos:</strong>
                        {attachment_list}
                    </div>
                    '''
            
            rendered_html = template.format(**render_params)
            logger.info(f"Plantilla '{template_name}' renderizada exitosamente")
            return str(rendered_html)
            
        except KeyError as e:
            logger.error(f"Parámetro faltante en plantilla '{template_name}': {str(e)}")
            raise ValueError(f"Parámetro requerido faltante: {str(e)}")
        except Exception as e:
            logger.error(f"Error renderizando plantilla '{template_name}': {str(e)}")
            raise

    def list_templates(self) -> list:
        """
        Lista todas las plantillas disponibles.
        
        Returns:
            list: Lista de nombres de plantillas disponibles
        """
        return list(self.templates.keys())
