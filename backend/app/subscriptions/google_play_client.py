# app/subscriptions/google_play_client.py
import os, json
from google.oauth2 import service_account
from googleapiclient.discovery import build

SCOPES = ['https://www.googleapis.com/auth/androidpublisher']

def build_android_publisher():
    """
    Inicializa el cliente de Google Play Android Publisher.
    Lee credenciales desde:
      - GOOGLE_CREDENTIALS_JSON (contenido del JSON), o
      - GOOGLE_APPLICATION_CREDENTIALS (ruta a archivo .json)
    """
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
        creds = service_account.Credentials.from_service_account_file(
            path, scopes=SCOPES
        )

    # cache_discovery=False evita warnings en algunos entornos
    return build('androidpublisher', 'v3', credentials=creds, cache_discovery=False)
