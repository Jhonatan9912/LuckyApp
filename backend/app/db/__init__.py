# app/db/__init__.py
from .database import db  # el SQLAlchemy() que ya tienes

def get_db():
    """
    Devuelve una conexión DB-API cruda (psycopg2) desde el engine de SQLAlchemy.
    Úsala cuando necesites .cursor(), .execute(), commit(), etc.
    """
    return db.engine.raw_connection()

__all__ = ["db", "get_db"]
