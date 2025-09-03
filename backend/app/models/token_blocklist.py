# backend/app/models/token_blocklist.py
from datetime import datetime
from app.db.database import db

class TokenBlocklist(db.Model):
    __tablename__ = "token_blocklist"

    id = db.Column(db.Integer, primary_key=True)
    # JWT ID único (jti)
    jti = db.Column(db.String(255), nullable=False, index=True, unique=True)
    # "access" o "refresh" (opcional, pero útil para auditoría)
    token_type = db.Column(db.String(20), nullable=True)
    # Usuario dueño del token (opcional, para trazabilidad)
    user_id = db.Column(db.Integer, nullable=True, index=True)

    # Cuándo se registró (emisión o revocación)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    # Cuándo debería expirar el token (opcional; ayuda a limpiar)
    expires_at = db.Column(db.DateTime, nullable=True)

    # Marcado explícito de revocado
    revoked = db.Column(db.Boolean, nullable=False, default=False)

    def __repr__(self) -> str:
        return f"<TokenBlocklist jti={self.jti} type={self.token_type} user={self.user_id}>"
