# app/security/auth_utils.py
import os, jwt, logging
from flask import request, session, current_app

def _jwt_secret():
    return (
        current_app.config.get("JWT_SECRET_KEY")
        or os.getenv("JWT_SECRET")
        or current_app.config.get("SECRET_KEY")
    )

def resolve_user_id() -> int | None:
    # 1) session
    uid = session.get("user_id")
    if uid: return int(uid)
    # 2) bearer (PyJWT)
    auth = request.headers.get("Authorization","")
    if auth.startswith("Bearer "):
        token = auth.split(" ",1)[1]
        try:
            payload = jwt.decode(token, _jwt_secret(), algorithms=["HS256"])
            sub = payload.get("sub")
            return int(sub) if sub is not None else None
        except Exception:
            pass
    # 3) X-USER-ID
    xuid = request.headers.get("X-USER-ID")
    if xuid and str(xuid).isdigit():
        return int(xuid)
    return None
