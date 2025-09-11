from typing import Optional
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from flask import current_app
from datetime import datetime, timezone
import requests, json

from app.db.database import db
from app.models.device_token import DeviceToken

ALLOWED = {"android","ios","web","unknown"}

def _plat(p: Optional[str]) -> str:
    p = (p or "").strip().lower()
    return p if p in ALLOWED else "unknown"

def _now(): return datetime.now(timezone.utc)

def register_device_token(*, user_id:int, device_token:str, platform:str|None) -> DeviceToken:
    if not device_token:
        raise ValueError("device_token requerido")
    platform = (platform or "unknown").strip().lower() or "unknown"

    existing = db.session.scalar(select(DeviceToken).where(DeviceToken.device_token == device_token))
    if existing:
        existing.user_id = user_id
        existing.platform = platform
        existing.revoked = False
        existing.last_seen_at = _now()
        existing.updated_at  = _now()
        db.session.add(existing)
        db.session.commit()
        return existing

    ent = DeviceToken(user_id=user_id, device_token=device_token, platform=platform,
                      last_seen_at=_now(), created_at=_now(), updated_at=_now())
    db.session.add(ent)
    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        again = db.session.scalar(select(DeviceToken).where(DeviceToken.device_token == device_token))
        if again is None: raise
        again.user_id = user_id
        again.platform = platform
        again.revoked = False
        again.last_seen_at = _now()
        again.updated_at  = _now()
        db.session.add(again)
        db.session.commit()
        return again
    return ent

def delete_device_token(*, user_id:int, device_token:str) -> bool:
    if not device_token:
        return False
    tok = db.session.scalar(
        select(DeviceToken).where(DeviceToken.device_token==device_token,
                                  DeviceToken.user_id==user_id)
    )
    if not tok:
        return False
    db.session.delete(tok)
    db.session.commit()
    return True

def send_test_push(*, device_token: str, title: str | None, body: str | None, data: dict | None) -> dict:
    # Opcional para dev (usa FCM legacy). Si no pones la clave, devuelve error informativo.
    server_key = current_app.config.get("FCM_SERVER_KEY") or ""
    if not server_key:
        return {"ok": False, "error": "FCM_SERVER_KEY no configurada"}
    headers = {"Authorization": f"key={server_key}", "Content-Type": "application/json"}
    payload = {
        "to": device_token,
        "notification": {"title": title or "Test", "body": body or "Notificación de prueba"},
        "data": data or {},
        "priority": "high",
    }
    resp = requests.post("https://fcm.googleapis.com/fcm/send", headers=headers, data=json.dumps(payload), timeout=7)
    try:
        j = resp.json()
    except Exception:
        j = {"status_code": resp.status_code, "text": resp.text}
    return {"ok": resp.ok, "status": resp.status_code, "response": j}
