# backend/app/services/notify/mailer.py
# Modo soportados:
# - resend  (API HTTP; recomendado en hosting con SMTP bloqueado)
# - console (solo imprime el correo en logs; útil en dev)
# - smtp    (opcional; solo si tu hosting permite 587/465)
#
# Variables mínimas para Resend:
#   MAIL_MODE=resend
#   RESEND_API_KEY=...
#   MAIL_FROM="LuckyApp <onboarding@resend.dev>"  # o remitente de tu dominio verificado
#   MAIL_DEFAULT_SENDER_EMAIL=onboarding@resend.dev
#   MAIL_DEFAULT_SENDER_NAME=LuckyApp
#
# Asegúrate de tener: requests en requirements.txt

from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Optional
import os
import ssl
import smtplib
import threading
import traceback
import requests
from flask import current_app

# =========================
# Utilidades internas
# =========================
def _require(val: Optional[str], name: str):
    if not val:
        raise RuntimeError(f"Falta configurar {name}")

def _build_message(cfg, to_email: str, subject: str, html: str) -> MIMEMultipart:
    sender_name = cfg.get("MAIL_DEFAULT_SENDER_NAME", "Mi App")
    sender_email = cfg.get("MAIL_DEFAULT_SENDER_EMAIL") or cfg.get("MAIL_USERNAME")
    _require(sender_email, "MAIL_DEFAULT_SENDER_EMAIL o MAIL_USERNAME")

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = f"{sender_name} <{sender_email}>"
    msg["To"] = to_email
    msg.attach(MIMEText(html, "html", "utf-8"))
    return msg

def _log_cfg(app, cfg):
    app.logger.debug(
        "[MAIL cfg] mode=%s server=%s port=%s tls=%s ssl=%s user_tail=%s timeout=%s",
        (cfg.get("MAIL_MODE") or os.getenv("MAIL_MODE") or "resend"),
        cfg.get("MAIL_SERVER", "smtp.gmail.com"),
        cfg.get("MAIL_PORT", 587),
        cfg.get("MAIL_USE_TLS", True),
        cfg.get("MAIL_USE_SSL", False),
        (cfg.get("MAIL_USERNAME")[-4:] if cfg.get("MAIL_USERNAME") else None),
        cfg.get("SMTP_TIMEOUT", 12),
    )

# =========================
# Backends de envío
# =========================
def _send_console(app, to_email: str, subject: str, html: str) -> None:
    app.logger.info("[MAIL console] to=%s subj=%s\n%s", to_email, subject, html)

def _send_resend(app, cfg, to_email: str, subject: str, html: str) -> None:
    """
    Envío por API HTTP (Resend).
    Requiere:
      RESEND_API_KEY
      MAIL_FROM (o MAIL_DEFAULT_SENDER_EMAIL)
    """
    api_key = os.getenv("RESEND_API_KEY") or cfg.get("RESEND_API_KEY")
    _require(api_key, "RESEND_API_KEY")

    sender = cfg.get("MAIL_FROM") or cfg.get("MAIL_DEFAULT_SENDER_EMAIL")
    _require(sender, "MAIL_FROM/MAIL_DEFAULT_SENDER_EMAIL")

    try:
        r = requests.post(
            "https://api.resend.com/emails",
            headers={"Authorization": f"Bearer {api_key}"},
            json={"from": sender, "to": [to_email], "subject": subject, "html": html},
            timeout=int(cfg.get("MAIL_HTTP_TIMEOUT", 10)),
        )
        if r.status_code >= 400:
            app.logger.error("Resend error %s: %s", r.status_code, r.text)  # 👈 imprime el motivo real


        r.raise_for_status()
        app.logger.info("Correo ENVIADO (Resend) a %s (asunto: %s)", to_email, subject)
    except Exception:
        app.logger.exception("Error enviando correo con Resend a %s", to_email)
        raise

def _send_smtp(app, cfg, to_email: str, subject: str, html: str) -> None:
    """
    Opcional: SMTP (Gmail con App Password). No se usa si MAIL_MODE != 'smtp'.
    """
    server = cfg.get("MAIL_SERVER", "smtp.gmail.com")
    port = int(cfg.get("MAIL_PORT", 587))
    use_tls = bool(cfg.get("MAIL_USE_TLS", True))
    use_ssl = bool(cfg.get("MAIL_USE_SSL", False))
    username = cfg.get("MAIL_USERNAME")
    password = cfg.get("MAIL_PASSWORD")
    timeout = int(cfg.get("SMTP_TIMEOUT", 12))

    _require(username, "MAIL_USERNAME")
    _require(password, "MAIL_PASSWORD")

    msg = _build_message(cfg, to_email, subject, html)

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

        app.logger.info("Correo ENVIADO (SMTP) a %s (asunto: %s)", to_email, subject)

    except Exception as e:
        app.logger.error("Error enviando correo SMTP a %s: %s", to_email, e)
        app.logger.debug("Trace:\n%s", traceback.format_exc())
        raise

# =========================
# API pública
# =========================
def send_html(to_email: str, subject: str, html: str, *, async_: bool = True) -> None:
    """
    Envía un correo con el modo seleccionado:
      - resend  (HTTP; recomendado) -> usa _send_resend
      - console (logs)              -> usa _send_console
      - smtp    (opcional)          -> usa _send_smtp

    async_ = True -> dispara en background para no bloquear la request.
    """
    app = current_app._get_current_object()
    cfg = app.config

    # Prioridad: config > env > default(resend)
    mode = (cfg.get("MAIL_MODE") or os.getenv("MAIL_MODE") or "resend").lower()

    def _dispatch():
        try:
            if mode == "resend":
                _send_resend(app, cfg, to_email, subject, html)
            elif mode == "smtp":
                _log_cfg(app, cfg)
                _send_smtp(app, cfg, to_email, subject, html)
            else:
                _send_console(app, to_email, subject, html)
        except Exception:
            # En async registramos y NO propagamos; en sync sí levantamos excepción.
            if async_:
                app.logger.exception("Fallo envío email (async) a %s", to_email)
            else:
                raise

    if async_:
        # Asegura contexto dentro del hilo
        def _runner():
            with app.app_context():
                _dispatch()
        threading.Thread(target=_runner, daemon=True).start()
    else:
        _dispatch()

# =========================
# Alias legacy (si tu código lo llama)
# =========================
def send_html_async(to_email: str, subject: str, html: str) -> None:
    """Alias para compatibilidad. Envía en background."""
    send_html(to_email, subject, html, async_=True)
