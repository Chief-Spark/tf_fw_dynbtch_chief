"""
Ejemplo de uso del SESClient mejorado con plantillas HTML y archivos adjuntos desde S3.
"""

from infrastructure.ses import SESClient

def ejemplo_uso_ses_client():
    """
    Ejemplos de uso del SESClient con las nuevas funcionalidades.
    """
    
    # Inicializar el cliente
    ses_client = SESClient()
    
    # Lista de destinatarios
    emails = ["usuario1@ejemplo.com", "usuario2@ejemplo.com"]
    
    # ==============================================
    # EJEMPLO 1: Email con adjunto único desde S3
    # ==============================================
    print("=== Ejemplo 1: Email con adjunto único ===")
    try:
        message_id = ses_client.send_email_with_s3_attachment(
            emails=emails,
            subject="Reporte de procesamiento",
            body="<h2>Reporte Adjunto</h2><p>Encuentra el reporte solicitado en el archivo adjunto.</p>",
            bucket="mi-bucket-reportes",
            key="reportes/2025/agosto/reporte_mensual.pdf",
            filename="Reporte_Agosto_2025.pdf"
        )
        print(f"Email enviado exitosamente. Message ID: {message_id}")
    except Exception as e:
        print(f"Error enviando email: {e}")
    
    # ==============================================
    # EJEMPLO 2: Email con múltiples adjuntos desde S3
    # ==============================================
    print("\n=== Ejemplo 2: Email con múltiples adjuntos ===")
    s3_attachments = [
        {"bucket": "mi-bucket-reportes", "key": "reportes/2025/agosto/ventas.xlsx", "filename": "Ventas_Agosto.xlsx"},
        {"bucket": "mi-bucket-logs", "key": "logs/proceso_batch_001.log", "filename": "Log_Proceso.txt"},
        {"bucket": "mi-bucket-reportes", "key": "reportes/2025/agosto/resumen.pdf", "filename": "Resumen_Ejecutivo.pdf"}
    ]
    
    try:
        message_id = ses_client.send_email_with_s3_attachments(
            emails=emails,
            subject="Reportes completos del mes",
            body="<h2>Reportes Mensuales</h2><p>Adjunto los reportes completos del procesamiento mensual.</p>",
            s3_attachments=s3_attachments
        )
        print(f"Email con múltiples adjuntos enviado. Message ID: {message_id}")
    except Exception as e:
        print(f"Error enviando email con múltiples adjuntos: {e}")
    
    # ==============================================
    # EJEMPLO 3: Notificación de éxito con plantilla
    # ==============================================
    print("\n=== Ejemplo 3: Notificación de éxito con plantilla ===")
    success_attachments = [
        {"bucket": "mi-bucket-resultados", "key": "batch_001/resultado_final.csv", "filename": "Resultado_Final.csv"}
    ]
    
    try:
        message_id = ses_client.send_batch_success_notification(
            emails=emails,
            batch_id="BATCH_001_2025",
            message="<p>El procesamiento se completó sin errores. Se procesaron <strong>1,250 registros</strong> exitosamente.</p>",
            s3_attachments=success_attachments
        )
        print(f"Notificación de éxito enviada. Message ID: {message_id}")
    except Exception as e:
        print(f"Error enviando notificación de éxito: {e}")
    
    # ==============================================
    # EJEMPLO 4: Notificación de error con plantilla
    # ==============================================
    print("\n=== Ejemplo 4: Notificación de error con plantilla ===")
    error_attachments = [
        {"bucket": "mi-bucket-logs", "key": "errors/batch_002_error.log", "filename": "Error_Log.txt"},
        {"bucket": "mi-bucket-logs", "key": "errors/stacktrace.txt", "filename": "Stack_Trace.txt"}
    ]
    
    try:
        message_id = ses_client.send_batch_error_notification(
            emails=emails,
            batch_id="BATCH_002_2025",
            error_details="Error de conexión a la base de datos durante el procesamiento del registro 450",
            message="<p>El procesamiento falló después de procesar <strong>449 registros</strong>.</p>",
            s3_attachments=error_attachments
        )
        print(f"Notificación de error enviada. Message ID: {message_id}")
    except Exception as e:
        print(f"Error enviando notificación de error: {e}")
    
    # ==============================================
    # EJEMPLO 5: Notificación personalizada con plantilla
    # ==============================================
    print("\n=== Ejemplo 5: Notificación personalizada ===")
    custom_attachments = [
        {"bucket": "mi-bucket-config", "key": "configuraciones/nueva_config.json", "filename": "Nueva_Configuracion.json"}
    ]
    
    try:
        message_id = ses_client.send_batch_notification(
            emails=emails,
            subject="Actualización de Configuración",
            message="<p>Se ha actualizado la configuración del sistema. Por favor revisa los cambios en el archivo adjunto.</p>",
            s3_attachments=custom_attachments,
            batch_id="CONFIG_UPDATE_001"
        )
        print(f"Notificación personalizada enviada. Message ID: {message_id}")
    except Exception as e:
        print(f"Error enviando notificación personalizada: {e}")
    
    # ==============================================
    # EJEMPLO 6: Usar plantilla con parámetros adicionales
    # ==============================================
    print("\n=== Ejemplo 6: Plantilla con parámetros personalizados ===")
    try:
        message_id = ses_client.send_templated_email_with_s3_attachments(
            emails=emails,
            template_name="batch_success",
            s3_attachments=[{"bucket": "mi-bucket", "key": "reports/custom_report.pdf", "filename": "Reporte_Personalizado.pdf"}],
            subject="Procesamiento Personalizado Completado",
            batch_id="CUSTOM_BATCH_001",
            body="<p>El procesamiento personalizado se ejecutó con parámetros especiales y completó exitosamente.</p>"
        )
        print(f"Email con plantilla personalizada enviado. Message ID: {message_id}")
    except Exception as e:
        print(f"Error enviando email con plantilla personalizada: {e}")

if __name__ == "__main__":
    ejemplo_uso_ses_client()
