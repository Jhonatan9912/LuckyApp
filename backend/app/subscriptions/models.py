from app.db.database import db
from sqlalchemy.orm import synonym

class UserSubscription(db.Model):
    __tablename__ = "user_subscriptions"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    entitlement = db.Column(db.String, nullable=False)

    # Columna real + alias de compatibilidad
    is_premium = db.Column(db.Boolean, nullable=False, server_default=db.text('false'))
    is_active = synonym('is_premium')  # compat código viejo

    status = db.Column(db.String, nullable=False)

    current_period_start = db.Column(db.DateTime(timezone=True))

    auto_renewing = db.Column(db.Boolean, nullable=False, server_default=db.text('true'))

    last_purchase_id = db.Column(db.String)
    last_product_id = db.Column(db.String)

    purchase_token = db.Column(db.Text)

    # Fin de periodo REAL
    expires_at = db.Column(db.DateTime(timezone=True))

    # Alias lógico (NO columna nueva)
    current_period_end = synonym('expires_at')

    original_app_user_id = db.Column(db.String)

    updated_at = db.Column(
        db.DateTime(timezone=True),
        server_default=db.func.now(),
        onupdate=db.func.now(),
    )
    created_at = db.Column(
        db.DateTime(timezone=True),
        server_default=db.func.now(),
    )

    __table_args__ = (
        db.UniqueConstraint("user_id", "entitlement"),
        db.Index("ix_user_subscriptions_user_id", "user_id"),
        db.Index("ix_user_subscriptions_status", "status"),
    )
