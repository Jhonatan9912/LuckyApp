from app.db.database import db

class UserSubscription(db.Model):
    __tablename__ = "user_subscriptions"
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    entitlement = db.Column(db.String, nullable=False)
    is_active = db.Column(db.Boolean, default=False, nullable=False)
    status = db.Column(db.String, nullable=False)
    current_period_end = db.Column(db.DateTime(timezone=True))
    original_app_user_id = db.Column(db.String)
    updated_at = db.Column(db.DateTime(timezone=True), server_default=db.func.now())

    __table_args__ = (db.UniqueConstraint("user_id", "entitlement"),)
