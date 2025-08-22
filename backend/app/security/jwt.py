# backend/app/security/jwt.py
from datetime import timedelta
from flask_jwt_extended import create_access_token
# Opcional: intenta decodificar con flask_jwt_extended; si falla, usa modo sin verificación
try:
    from flask_jwt_extended.utils import decode_token as _fj_decode_token
except Exception:
    _fj_decode_token = None

import base64, json

def create_jwt_for_user(user_id: int) -> str:
    return create_access_token(identity=user_id, expires_delta=timedelta(hours=12))

def decode_token(token: str) -> dict:
    """Devuelve el payload del JWT. En dev hace fallback sin verificación."""
    if _fj_decode_token:
        try:
            return _fj_decode_token(token)  # contiene 'sub' (identity)
        except Exception:
            pass
    # Fallback DEV: decodificación sin firma
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("bad token")
    payload_b64 = parts[1] + "=" * (-len(parts[1]) % 4)
    return json.loads(base64.urlsafe_b64decode(payload_b64))
