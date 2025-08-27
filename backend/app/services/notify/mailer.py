# backend/app/services/notify/mailer.py
# Si tu path real es app/services/mailer.py, mueve este archivo allí y ajusta el import.

from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import smtplib
import ssl
from flask import current_app
import threading

def _build_message(to_email: str, subject: str, html: str) -> MIMEMultipart:
    sender_name = current_app.config.get('MAIL_DEFAULT_SENDER_NAME', 'Mi App')
    sender_email = current_app.config.get('MAIL_DEFAULT_SENDER_EMAIL') or current_app.config.get('MAIL_USERNAME')

    if not sender_email:
        raise RuntimeError("MAIL_DEFAULT_SENDER_EMAIL o MAIL_USERNAME no configurados")

    msg = MIMEMultipart('alternative')
    msg['Subject'] = subject
    msg['From'] = f"{sender_name} <{sender_email}>"
    msg['To'] = to_email

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
    server = (cfg.get('MAIL_SERVER') or 'smtp.gmail.com')
    port = int(cfg.get('MAIL_PORT') or 587)
    use_tls = bool(cfg.get('MAIL_USE_TLS') if cfg.get('MAIL_USE_TLS') is not None else True)
    use_ssl = bool(cfg.get('MAIL_USE_SSL') if cfg.get('MAIL_USE_SSL') is not None else False)
    username = cfg.get('MAIL_USERNAME') or ''
    password = cfg.get('MAIL_PASSWORD') or ''
    timeout = int(cfg.get('SMTP_TIMEOUT') or 12)  # segundos

    # Log de config (seguro; no muestra pass)
    current_app.logger.debug(
        "SMTP cfg -> server=%s port=%d tls=%s ssl=%s user_tail=%s pass_len=%d timeout=%s",
        server, port, use_tls, use_ssl, (username[-4:] if username else None), len(password), timeout
    )

    # Fallback seguro: si no hay credenciales, no enviar (evita crash en dev)
    if not username or not password:
        current_app.logger.warning("Mailer deshabilitado: faltan MAIL_USERNAME/MAIL_PASSWORD. NO se envía el correo a %s", to_email)
        current_app.logger.debug("Asunto: %s\nHTML:\n%s", subject, html)
        return

    msg = _build_message(to_email, subject, html)

    try:
        if use_ssl:
            context = ssl.create_default_context()
            with smtplib.SMTP_SSL(server, port, context=context, timeout=timeout) as smtp:
                smtp.login(username, password)
                smtp.send_message(msg)
        else:
            with smtplib.SMTP(server, port, timeout=timeout) as smtp:
                if use_tls:
                    smtp.starttls(context=ssl.create_default_context())
                smtp.login(username, password)
                smtp.send_message(msg)

        current_app.logger.info("Correo ENVIADO a %s (asunto: %s)", to_email, subject)
    except Exception as e:
        current_app.logger.exception("Error enviando correo a %s: %s", to_email, str(e))
        raise

def send_html_async(to_email: str, subject: str, html: str) -> None:
    """
    Dispara el envío en un hilo aparte para no bloquear el request HTTP.
    """
    def job():
        try:
            send_html(to_email, subject, html)
        except Exception as e:
            current_app.logger.error("Error en envío async a %s: %s", to_email, str(e))
    threading.Thread(target=job, daemon=True).start()
