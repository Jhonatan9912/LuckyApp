# backend/app/services/reset/reset_service.py
from dataclasses import dataclass
from datetime import datetime, timedelta
import secrets, string
from app.db.database import db
from app.models.user import User
from werkzeug.security import generate_password_hash
from sqlalchemy import text
from app.services.notify.mailer import send_html
# Asumimos una tabla reset_tokens (ver SQL más abajo).
# Campos: id, user_id, code, token, expires_at, used, created_at
from flask import current_app  # 👈 lo usaremos para leer TTL desde config
from html import escape
import hmac
from app.security.guards import rate_limited, reset_rate_limit, revoke_all_sessions

# Intentos fallidos permitidos para un código antes de anularlo
MAX_CODE_ATTEMPTS = 5

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

def _send_email(to_email: str, subject: str, html_body: str):
    send_html(to_email, subject, html_body)

    """
    Implementa aquí tu función real de envío (tu backend de correo ya es funcional).
    Por ejemplo: mailer.send(to=to_email, subject=subject, html=html_body)
    """
    # TODO: integra con tu mailer real
    pass

def request_password_reset_by_email(email: str) -> None:
    user: User | None = db.session.query(User).filter(User.email == email).first()
    if not user:
        raise ResetError("No existe un usuario con ese correo")

    code = _gen_code()
    ttl_code = current_app.config.get('RESET_CODE_TTL_MIN', 10)
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
    # Nuevo código: reinicia el contador de intentos fallidos
    reset_rate_limit(f"reset:verify:{user.id}")

    subject = "Tu código de restablecimiento"
    html = f"""
    <p>Hola {escape(user.name or "")},</p>
    <p>Tu código para restablecer la contraseña es: <b>{code}</b></p>
    <p>Expira en {ttl_code} minutos.</p>
    """
    _send_email(user.email, subject, html)


def verify_reset_code_by_email(email: str, code: str) -> str:
    user: User | None = db.session.query(User).filter(User.email == email).first()
    if not user:
        # Mismo mensaje que un código erróneo: no revela qué correos existen
        raise ResetError("Código inválido")

    # Solo el código vigente más reciente (no usado y con código pendiente)
    row = db.session.execute(text("""
        SELECT id, code, expires_at, used
          FROM reset_tokens
         WHERE user_id = :uid AND used = FALSE AND code IS NOT NULL
         ORDER BY id DESC
         LIMIT 1
    """), {"uid": user.id}).mappings().first()

    if not row or not hmac.compare_digest(str(row["code"]), str(code)):
        # Cuenta el intento fallido; al superar el máximo se anula el código
        # (evita adivinar el código de 6 dígitos por fuerza bruta).
        if row and rate_limited(f"reset:verify:{user.id}", MAX_CODE_ATTEMPTS - 1, 3600):
            db.session.execute(text("UPDATE reset_tokens SET used = TRUE WHERE id = :rid"),
                               {"rid": row["id"]})
            db.session.commit()
            raise ResetError("Demasiados intentos. Solicita un nuevo código.")
        raise ResetError("Código inválido")
    if row["used"]:
        raise ResetError("Código ya usado")
    if row["expires_at"] < datetime.utcnow():
        raise ResetError("Código expirado")

    token = _gen_token()
    ttl_token = current_app.config.get('RESET_TOKEN_TTL_MIN', 30)
    token_exp = datetime.utcnow() + timedelta(minutes=ttl_token)

    # 👇 NO marcar used=TRUE aquí. Solo invalidamos el código para que no se pueda reutilizar.
    db.session.execute(text("""
        UPDATE reset_tokens
           SET token = :token,
               expires_at = :texp,
               code = NULL     -- invalida el código para que no se reuse
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

    # Cierra todas las sesiones abiertas del usuario (incluida la de un atacante)
    revoke_all_sessions(int(row["user_id"]))
