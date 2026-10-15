"""
Módulo de infraestructura para interactuar con S3 de AWS.
"""

import boto3
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

class S3Client:
    """
    Cliente para interactuar con S3 de AWS.
    """

    def __init__(self):
        self.client = boto3.client("s3")

    def get_object(self, bucket: str, key: str):
        """
        Obtiene un objeto desde S3.
        
        Args:
            bucket (str): Nombre del bucket S3
            key (str): Ruta del archivo en S3
            
        Returns:
            dict: Respuesta de S3 con el objeto
            
        Raises:
            ClientError: Si hay error al acceder al objeto
        """
        try:
            logger.info(f"Descargando objeto desde S3: s3://{bucket}/{key}")
            response = self.client.get_object(Bucket=bucket, Key=key)
            logger.info(f"Objeto descargado exitosamente: {key}")
            return response
        except ClientError as e:
            logger.error(f"Error descargando objeto de S3 {bucket}/{key}: {str(e)}")
            raise
        except Exception as e:
            logger.error(f"Error inesperado descargando objeto de S3: {str(e)}")
            raise

    def get_object_content(self, bucket: str, key: str):
        """
        Obtiene el contenido de un objeto desde S3.
        
        Args:
            bucket (str): Nombre del bucket S3
            key (str): Ruta del archivo en S3
            
        Returns:
            bytes: Contenido del archivo
        """
        try:
            s3_object = self.get_object(bucket, key)
            content = s3_object['Body'].read()
            logger.info(f"Contenido leído exitosamente para {key}, tamaño: {len(content)} bytes")
            return content
        except Exception as e:
            logger.error(f"Error leyendo contenido del objeto {bucket}/{key}: {str(e)}")
            raise

    def get_object_metadata(self, bucket: str, key: str):
        """
        Obtiene los metadatos de un objeto desde S3.
        
        Args:
            bucket (str): Nombre del bucket S3
            key (str): Ruta del archivo en S3
            
        Returns:
            dict: Metadatos del objeto
        """
        try:
            logger.info(f"Obteniendo metadatos para: s3://{bucket}/{key}")
            response = self.client.head_object(Bucket=bucket, Key=key)
            logger.info(f"Metadatos obtenidos exitosamente para {key}")
            return {
                'ContentType': response.get('ContentType', 'application/octet-stream'),
                'ContentLength': response.get('ContentLength', 0),
                'LastModified': response.get('LastModified'),
                'ETag': response.get('ETag'),
                'Metadata': response.get('Metadata', {})
            }
        except ClientError as e:
            logger.error(f"Error obteniendo metadatos de S3 {bucket}/{key}: {str(e)}")
            raise
        except Exception as e:
            logger.error(f"Error inesperado obteniendo metadatos de S3: {str(e)}")
            raise

    def object_exists(self, bucket: str, key: str):
        """
        Verifica si un objeto existe en S3.
        
        Args:
            bucket (str): Nombre del bucket S3
            key (str): Ruta del archivo en S3
            
        Returns:
            bool: True si el objeto existe, False en caso contrario
        """
        try:
            self.client.head_object(Bucket=bucket, Key=key)
            logger.info(f"Objeto confirmado existente: s3://{bucket}/{key}")
            return True
        except ClientError as e:
            if e.response['Error']['Code'] == '404':
                logger.warning(f"Objeto no encontrado: s3://{bucket}/{key}")
                return False
            else:
                logger.error(f"Error verificando existencia del objeto {bucket}/{key}: {str(e)}")
                raise
        except Exception as e:
            logger.error(f"Error inesperado verificando existencia del objeto: {str(e)}")
            raise

    def download_file_for_attachment(self, bucket: str, key: str):
        """
        Descarga un archivo de S3 específicamente para usar como adjunto en email.
        
        Args:
            bucket (str): Nombre del bucket S3
            key (str): Ruta del archivo en S3
            
        Returns:
            dict: Diccionario con información del archivo para adjunto
                {
                    'content': bytes,
                    'content_type': str,
                    'filename': str,
                    'size': int
                }
        """
        try:
            # Verificar que el objeto existe
            if not self.object_exists(bucket, key):
                raise FileNotFoundError(f"El archivo {key} no existe en el bucket {bucket}")

            # Obtener metadatos
            metadata = self.get_object_metadata(bucket, key)
            
            # Obtener contenido
            content = self.get_object_content(bucket, key)
            
            # Preparar información del adjunto
            attachment_info = {
                'content': content,
                'content_type': metadata['ContentType'],
                'filename': key.split('/')[-1],  # Nombre del archivo sin ruta
                'size': len(content)
            }
            
            logger.info(f"Archivo preparado para adjunto: {attachment_info['filename']} ({attachment_info['size']} bytes)")
            return attachment_info
            
        except Exception as e:
            logger.error(f"Error preparando archivo para adjunto {bucket}/{key}: {str(e)}")
            raise
