# backend/app/models/user.py
from sqlalchemy import Date, ForeignKey, DateTime
from sqlalchemy.sql import func
from app.db.database import db

class User(db.Model):
    __tablename__ = 'users'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)

    identification_type_id = db.Column(
        db.Integer,
        ForeignKey('identification_types.id'),
        nullable=False
    )
    identification_number = db.Column(db.String(20), unique=True, nullable=False)

    birthdate = db.Column(Date, nullable=False)

    # Credenciales / contacto
    password_hash = db.Column(db.Text, nullable=False)
    phone = db.Column(db.String(20), unique=True, nullable=False)
    email = db.Column(db.String(255), unique=True, nullable=False, index=True)

    # Rol y código público
    role_id = db.Column(db.Integer, nullable=False, server_default="2")
    public_code = db.Column(db.String(20), unique=True, nullable=False)

    # 👇 Campos que faltaban y ya están en la DB
    country_code = db.Column(db.String(5), nullable=True)  # ej: +57
    accepted_terms_at = db.Column(DateTime(timezone=True), nullable=True)
    accepted_data_at  = db.Column(DateTime(timezone=True), nullable=True)
    consent_version   = db.Column(db.String(20), nullable=False, server_default='v1')

    # Auditoría
    created_at = db.Column(DateTime(timezone=True), nullable=False, server_default=func.now())
