# app/models/bank.py
from app.db.database import db

class Bank(db.Model):
    __tablename__ = "banks"
    __table_args__ = {"schema": "public"}  # usa el esquema real si no es 'public'

    id = db.Column(db.Integer, primary_key=True)
