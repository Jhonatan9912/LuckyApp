from datetime import datetime, timezone
from sqlalchemy.sql import func
from app.db.database import db

class PasswordReset(db.Model):
    __tablename__ = "password_resets"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    phone = db.Column(db.String(32), nullable=False, index=True)
    code_hash = db.Column(db.String(255), nullable=False)
    expires_at = db.Column(db.DateTime(timezone=True), nullable=False, index=True)
    attempts = db.Column(db.Integer, nullable=False, default=0)
    max_attempts = db.Column(db.Integer, nullable=False, default=5)
    used = db.Column(db.Boolean, nullable=False, default=False)
    created_at = db.Column(
        db.DateTime(timezone=True),
        nullable=False,
        server_default=func.now()
    )

    def is_expired(self) -> bool:
        return datetime.now(timezone.utc) >= self.expires_at

    def can_attempt(self) -> bool:
        return (not self.used) and (not self.is_expired()) and (self.attempts < self.max_attempts)
