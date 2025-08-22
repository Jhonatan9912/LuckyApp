# app/services/mailer.py
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import smtplib
from flask import current_app

def _build_message(to_email: str, subject: str, html: str) -> MIMEMultipart:
    sender_name = current_app.config.get('MAIL_DEFAULT_SENDER_NAME', 'Mi App')
    sender_email = current_app.config.get('MAIL_DEFAULT_SENDER_EMAIL') or current_app.config.get('MAIL_USERNAME')

    if not sender_email:
        raise RuntimeError("MAIL_DEFAULT_SENDER_EMAIL o MAIL_USERNAME no configurados")

    msg = MIMEMultipart('alternative')
    msg['Subject'] = subject
    msg['From'] = f"{sender_name} <{sender_email}>"
    msg['To'] = to_email

    # Parte HTML (si quieres, agrega también versión de texto plano)
    html_part = MIMEText(html, 'html', 'utf-8')
    msg.attach(html_part)
    return msg

def send_html(to_email: str, subject: str, html: str) -> None:
    """
    Envía correo HTML via SMTP (Gmail).
    Requiere en app.config:
      MAIL_SERVER, MAIL_PORT, MAIL_USE_TLS/SSL, MAIL_USERNAME, MAIL_PASSWORD,
      MAIL_DEFAULT_SENDER_NAME, MAIL_DEFAULT_SENDER_EMAIL
    """
    cfg = current_app.config
    server = cfg.get('MAIL_SERVER', 'smtp.gmail.com')
    port = int(cfg.get('MAIL_PORT', 587))
    use_tls = bool(cfg.get('MAIL_USE_TLS', True))
    use_ssl = bool(cfg.get('MAIL_USE_SSL', False))
    username = cfg.get('MAIL_USERNAME')
    password = cfg.get('MAIL_PASSWORD')

    # Fallback seguro: si no hay credenciales, log y no enviar (evita crash en dev)
    if not username or not password:
        current_app.logger.warning("Mailer deshabilitado: faltan MAIL_USERNAME/MAIL_PASSWORD. NO se envía el correo a %s", to_email)
        current_app.logger.debug("Asunto: %s\nHTML:\n%s", subject, html)
        return

    msg = _build_message(to_email, subject, html)

    try:
        if use_ssl:
            with smtplib.SMTP_SSL(server, port) as smtp:
                smtp.login(username, password)
                smtp.send_message(msg)
        else:
            with smtplib.SMTP(server, port) as smtp:
                if use_tls:
                    smtp.starttls()
                smtp.login(username, password)
                smtp.send_message(msg)

        # Log sin exponer contenido sensible
        current_app.logger.info("Correo enviado a %s (asunto: %s)", to_email, subject)
    except Exception as e:
        # Nunca loggear password; sólo error y destino
        current_app.logger.exception("Error enviando correo a %s: %s", to_email, str(e))
        raise
