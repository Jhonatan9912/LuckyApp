from app.db.database import db

class UserSubscription(db.Model):
    __tablename__ = "user_subscriptions"
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    entitlement = db.Column(db.String, nullable=False)
    is_active = db.Column(db.Boolean, default=False, nullable=False)
    status = db.Column(db.String, nullable=False)
    # ← NUEVO: fecha de inicio del periodo vigente
    current_period_start = db.Column(db.DateTime(timezone=True))

    # ← NUEVO: bandera de auto-renovación
    auto_renewing = db.Column(db.Boolean, default=True, nullable=False)

    # ← NUEVO: últimos IDs de compra/producto (útil para auditoría)
    last_purchase_id = db.Column(db.String)
    last_product_id = db.Column(db.String)

    # ← NUEVO: token/recibo de Google (verification_data / purchaseToken)
    purchase_token = db.Column(db.Text)

    current_period_end = db.Column(db.DateTime(timezone=True))
    original_app_user_id = db.Column(db.String)
    updated_at = db.Column(db.DateTime(timezone=True),
                       server_default=db.func.now(),
                       onupdate=db.func.now())
    created_at = db.Column(db.DateTime(timezone=True), server_default=db.func.now())
    __table_args__ = (
    db.UniqueConstraint("user_id", "entitlement"),
    db.Index("ix_user_subscriptions_user_id", "user_id"),
    db.Index("ix_user_subscriptions_status", "status"),
)

