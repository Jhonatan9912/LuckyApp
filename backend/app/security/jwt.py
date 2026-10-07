# backend/app/security/jwt.py
from datetime import timedelta
from flask_jwt_extended import create_access_token
from flask_jwt_extended.utils import decode_token as _fj_decode_token


def create_jwt_for_user(user_id: int) -> str:
    return create_access_token(identity=str(user_id), expires_delta=timedelta(hours=12))


def decode_token(token: str) -> dict:
    """Devuelve el payload del JWT verificando firma y expiración (nunca sin verificar)."""
    return _fj_decode_token(token)
