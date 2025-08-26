from sqlalchemy import Column, Integer, BigInteger, String, Text, ForeignKey, Numeric, DateTime, Enum
from sqlalchemy.sql import func
from app.db.database import db
import enum

# ===== Enums Python (mapean a los tipos ENUM que ya tienes en Postgres) =====
class ReferralStatus(str, enum.Enum):
    pending = "pending"
    registered = "registered"
    converted = "converted"
    blocked = "blocked"
    spam = "spam"

class RewardKind(str, enum.Enum):
    signup_bonus = "signup_bonus"
    pro_purchase = "pro_purchase"
    milestone = "milestone"

class RewardStatus(str, enum.Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"
    paid = "paid"

# ============================== Models ==============================

class Referral(db.Model):
    __tablename__ = "referrals"

    id = Column(BigInteger, primary_key=True)
    referrer_user_id  = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    referred_user_id  = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=True,  index=True)
    referral_code_used = Column(String(32))
    status = Column(
        Enum(ReferralStatus, name="referral_status"),
        nullable=False,
        default=ReferralStatus.pending,   # cliente; en BD ya tienes DEFAULT también
    )
    source = Column(Text)
    notes = Column(Text)
    created_at   = Column(DateTime(timezone=True), server_default=func.now())
    converted_at = Column(DateTime(timezone=True))
    updated_at   = Column(DateTime(timezone=True), onupdate=func.now())

class ReferralReward(db.Model):
    __tablename__ = "referral_rewards"

    id = Column(BigInteger, primary_key=True)
    referral_id = Column(BigInteger, ForeignKey("referrals.id", ondelete="CASCADE"), nullable=False, index=True)
    beneficiary_user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    kind = Column(
        Enum(RewardKind, name="reward_kind"),
        nullable=False,
        default=RewardKind.signup_bonus,
    )
    amount   = Column(Numeric(12, 2), nullable=False)
    currency = Column(String(3), nullable=False, default="COP")

    status = Column(
        Enum(RewardStatus, name="reward_status"),
        nullable=False,
        default=RewardStatus.pending,
    )

    triggered_by = Column(Text)
    external_ref = Column(Text)
    created_at   = Column(DateTime(timezone=True), server_default=func.now())
    approved_at  = Column(DateTime(timezone=True))
    paid_at      = Column(DateTime(timezone=True))
