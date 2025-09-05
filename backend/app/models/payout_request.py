from datetime import datetime, timezone
from app.db.database import db

class PayoutRequest(db.Model):
    __tablename__ = "payout_requests"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, nullable=False, index=True)

    # En tu BD estos son enums; indicamos el nombre para que SQLAlchemy use el existente
    account_type = db.Column(
        db.Enum("bank", "nequi", "daviplata", "bancolombia_cell", "other",
                name="account_type", create_type=False),
        nullable=False,
    )
    account_kind = db.Column(
        db.Enum("savings", "checking", name="account_kind", create_type=False),
        nullable=True,
    )

    # Banco (solo si account_type == 'bank')
    bank_id = db.Column(
        db.Integer,
        db.ForeignKey("public.banks.id"),  # si usas schema 'public'
        nullable=True,
        index=True,
)

    account_number = db.Column(db.String(50), nullable=False)

    # ← estos dos campos faltaban en tu modelo
    amount_micros  = db.Column(db.BigInteger, nullable=False, default=0)
    currency_code  = db.Column(db.String(3), nullable=False, default="COP")

    status = db.Column(
        db.Enum("requested", "processing", "paid", "rejected",
                name="payout_status", create_type=False),
        nullable=False,
        default="requested",
    )

    observations = db.Column(db.Text, nullable=True)

    requested_at = db.Column(
        db.DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    created_at = db.Column(
        db.DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    updated_at = db.Column(
        db.DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    def to_dict(self):
        return {
            "id": self.id,
            "user_id": self.user_id,
            "account_type": self.account_type,
            "account_kind": self.account_kind,
            "bank_id": self.bank_id,
            "account_number": self.account_number,
            "amount_micros": self.amount_micros,
            "currency_code": self.currency_code,
            "status": self.status,
            "observations": self.observations,
            "requested_at": self.requested_at.isoformat() if self.requested_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
