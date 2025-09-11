# app/services/notify/push_sender.py
import json
import requests
from flask import current_app
from google.oauth2 import service_account
from google.auth.transport.requests import Request

# Scope requerido por FCM HTTP v1
_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

def _get_access_token(creds_path: str) -> str:
    """
    Obtiene un access token OAuth2 usando un Service Account JSON.
    """
    credentials = service_account.Credentials.from_service_account_file(
        creds_path, scopes=[_FCM_SCOPE]
    )
    credentials.refresh(Request())
    return credentials.token

def _v1_endpoint(project_id: str) -> str:
    return f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

def send_bulk_push(tokens, title, body, data=None, timeout=7):
    """
    Envía notificaciones usando FCM HTTP v1 (uno a uno para simplicidad).
    - Requiere:
        FIREBASE_PROJECT_ID en current_app.config
        GOOGLE_APPLICATION_CREDENTIALS (ruta al service account json) en env o current_app.config
    """
    if not tokens:
        return {"ok": False, "error": "no_tokens"}

    project_id = current_app.config.get("FIREBASE_PROJECT_ID")
    creds_path = current_app.config.get("GOOGLE_APPLICATION_CREDENTIALS")

    if not project_id:
        return {"ok": False, "error": "FIREBASE_PROJECT_ID not configured"}
    if not creds_path:
        return {"ok": False, "error": "GOOGLE_APPLICATION_CREDENTIALS not configured"}

    access_token = _get_access_token(creds_path)
    url = _v1_endpoint(project_id)
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json; UTF-8",
    }

    results = []
    for t in tokens:
        payload = {
            "message": {
                "token": t,
                "notification": {"title": title, "body": body},
                "data": data or {},
                "android": {
                    "priority": "HIGH"
                },
                "apns": {
                    "headers": {"apns-priority": "10"}
                },
            }
        }
        r = requests.post(url, headers=headers, data=json.dumps(payload), timeout=timeout)
        try:
            results.append(r.json())
        except Exception:
            results.append({"status": r.status_code, "text": r.text})

        # Log rápido para depurar (quítalo si no lo quieres en prod)
        print("[FCM v1] to=", t[:12], "...", "status=", r.status_code)

    return {"ok": True, "sent": len(tokens), "results": results}
