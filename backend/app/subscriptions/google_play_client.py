# app/subscriptions/google_play_client.py
import os, json
from google.oauth2 import service_account
from googleapiclient.discovery import build

SCOPES = ['https://www.googleapis.com/auth/androidpublisher']

def _safe_log(event: str, **fields):
    """Log seguro: usa Flask logger si existe; si no, print."""
    payload = {"event": event, **fields}
    try:
        from flask import current_app
        current_app.logger.info(json.dumps(payload))
    except Exception:
        print(json.dumps(payload))

def build_android_publisher():
    """
    Inicializa el cliente de Google Play Android Publisher.
    Lee credenciales desde:
      - GOOGLE_CREDENTIALS_JSON (contenido del JSON), o
      - GOOGLE_APPLICATION_CREDENTIALS (ruta a archivo .json)
    """
    info = None
    raw = os.environ.get('GOOGLE_CREDENTIALS_JSON')

    if raw:
        info = json.loads(raw)
        creds = service_account.Credentials.from_service_account_info(
            info, scopes=SCOPES
        )
    else:
        path = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
        if not path:
            raise RuntimeError(
                'Faltan credenciales: define GOOGLE_CREDENTIALS_JSON '
                'o GOOGLE_APPLICATION_CREDENTIALS'
            )
        # Cargamos el archivo también en "info" para loguear email/proyecto
        with open(path, 'r', encoding='utf-8') as f:
            info = json.load(f)
        creds = service_account.Credentials.from_service_account_file(
            path, scopes=SCOPES
        )

    # ---- LOG CLAVE PARA DIAGNÓSTICO ----
    sa_email = (info or {}).get("client_email")
    project_id = (info or {}).get("project_id")
    pkg = os.environ.get('GOOGLE_PLAY_PACKAGE_NAME')
    _safe_log(
        "gp_sa_in_use",
        service_account_email=sa_email,
        project_id=project_id,
        package_env=pkg,
        scopes=SCOPES,
    )
    # ------------------------------------

    # cache_discovery=False evita warnings en algunos entornos
    return build('androidpublisher', 'v3', credentials=creds, cache_discovery=False)
