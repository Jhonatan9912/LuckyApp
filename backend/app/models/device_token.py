from datetime import datetime, timezone
from app.db.database import db

class DeviceToken(db.Model):
    __tablename__ = "device_tokens"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False
    )
    device_token = db.Column(db.String(255), nullable=False, unique=True)
    platform = db.Column(db.String(16), nullable=False, default="unknown")
    last_seen_at = db.Column(db.DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    created_at  = db.Column(db.DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    updated_at  = db.Column(db.DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    revoked     = db.Column(db.Boolean, nullable=False, default=False)

    def touch(self):
        self.last_seen_at = datetime.now(timezone.utc)
        self.updated_at = datetime.now(timezone.utc)
