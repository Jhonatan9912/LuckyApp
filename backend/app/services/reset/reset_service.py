# backend/app/services/reset/reset_service.py
from dataclasses import dataclass
from datetime import datetime, timedelta
import secrets, string, threading
from app.db.database import db
from app.models.user import User
from werkzeug.security import generate_password_hash
from sqlalchemy import text
from flask import current_app

# IMPORTA EL MAILER SEGÚN TU PATH REAL:
# Si usas app/services/notify/mailer.py:
from app.services.notify.mailer import send_html_async
# Si tu archivo está en app/services/mailer.py, usa en su lugar:
# from app.services.mailer import send_html_async

@dataclass
class ResetError(Exception):
    message: str
    def __str__(self): return self.message

CODE_TTL_MIN = 10          # minutos
TOKEN_TTL_MIN = 30         # minutos
CODE_LEN = 6               # 6 dígitos

def _gen_code() -> str:
    return ''.join(secrets.choice(string.digits) for _ in range(CODE_LEN))

def _gen_token() -> str:
    return secrets.token_urlsafe(32)

def request_password_reset_by_email(email: str) -> None:
    user: User | None = db.session.query(User).filter(User.email == email).first()
    if not user:
        # Mantiene semántica actual (no revelar existencia)
        raise ResetError("No existe un usuario con ese correo")

    code = _gen_code()
    ttl_code = current_app.config.get('RESET_CODE_TTL_MIN', CODE_TTL_MIN)
    expires_at = datetime.utcnow() + timedelta(minutes=ttl_code)

    # invalida códigos previos no usados (opcional)
    db.session.execute(text("""
        UPDATE reset_tokens
           SET used = TRUE
         WHERE user_id = :uid AND used = FALSE
    """), {"uid": user.id})

    db.session.execute(text("""
        INSERT INTO reset_tokens (user_id, code, token, expires_at, used, created_at)
        VALUES (:uid, :code, NULL, :exp, FALSE, NOW())
    """), {"uid": user.id, "code": code, "exp": expires_at})
    db.session.commit()

    # En DEBUG, loguea el código para probar sin depender del correo
    if current_app.debug:
        current_app.logger.warning("DEBUG RESET CODE for %s: %s", user.email, code)

    subject = "Tu código de restablecimiento"
    html = f"""
    <p>Hola {user.name},</p>
    <p>Tu código para restablecer la contraseña es: <b>{code}</b></p>
    <p>Expira en {ttl_code} minutos.</p>
    """

    # ⬇️ Envío asíncrono: no bloquea el request → evita 502 en Railway
    send_html_async(user.email, subject, html)

def verify_reset_code_by_email(email: str, code: str) -> str:
    user: User | None = db.session.query(User).filter(User.email == email).first()
    if not user:
        raise ResetError("Correo no encontrado")

    row = db.session.execute(text("""
        SELECT id, expires_at, used
          FROM reset_tokens
         WHERE user_id = :uid AND code = :code
         ORDER BY id DESC
         LIMIT 1
    """), {"uid": user.id, "code": code}).mappings().first()

    if not row:
        raise ResetError("Código inválido")
    if row["used"]:
        raise ResetError("Código ya usado")
    if row["expires_at"] < datetime.utcnow():
        raise ResetError("Código expirado")

    token = _gen_token()
    ttl_token = current_app.config.get('RESET_TOKEN_TTL_MIN', TOKEN_TTL_MIN)
    token_exp = datetime.utcnow() + timedelta(minutes=ttl_token)

    # Invalida el código y fija token + nueva expiración
    db.session.execute(text("""
        UPDATE reset_tokens
           SET token = :token,
               expires_at = :texp,
               code = NULL
         WHERE id = :rid
    """), {"token": token, "texp": token_exp, "rid": row["id"]})

    db.session.commit()
    return token

def set_new_password_by_token(reset_token: str, new_password: str) -> None:
    row = db.session.execute(text("""
        SELECT r.user_id, r.expires_at, r.used
          FROM reset_tokens r
         WHERE r.token = :tok
         ORDER BY id DESC
         LIMIT 1
    """), {"tok": reset_token}).mappings().first()

    if not row:
        raise ResetError("Token inválido")
    if row["used"]:
        raise ResetError("Token ya usado")
    if row["expires_at"] < datetime.utcnow():
        raise ResetError("Token expirado")

    password_hash = generate_password_hash(new_password)
    db.session.execute(text("""
        UPDATE users SET password_hash = :ph WHERE id = :uid
    """), {"ph": password_hash, "uid": row["user_id"]})

    # marca token como usado para no reutilizar
    db.session.execute(text("""
        UPDATE reset_tokens SET used = TRUE WHERE token = :tok
    """), {"tok": reset_token})

    db.session.commit()
