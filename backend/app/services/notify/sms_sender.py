# backend/app/services/notify/sms_sender.py
from __future__ import annotations

import os
import typing
from dataclasses import dataclass
from typing import Protocol, Optional

if typing.TYPE_CHECKING:
    # Solo para type-checkers; NO se ejecuta en runtime
    from app.services.notify.providers.colombiared_provider import ColombiaRedProvider


class SmsProvider(Protocol):
    def send_sms(self, to: str, body: str) -> None: ...


@dataclass
class ConsoleSmsProvider:
    """Proveedor para desarrollo: imprime en consola."""
    def send_sms(self, to: str, body: str) -> None:
        print(f"[SMS:DEV] to={to} | body={body}")


@dataclass
class ColombiaRedAdapter:
    """Adaptador para cumplir la interfaz SmsProvider."""
    provider: "ColombiaRedProvider"

    def send_sms(self, to: str, body: str) -> None:
        self.provider.send_sms(to=to, body=body)


def _build_colombiared_provider() -> Optional[SmsProvider]:
    """
    Intenta construir el proveedor ColombiaRED.
    Si el módulo no existe o faltan credenciales, devuelve None.
    """
    try:
        from app.services.notify.providers.colombiared_provider import ColombiaRedProvider
    except Exception as e:
        print(f"[SMS] Proveedor ColombiaRED no disponible: {e}")
        return None

    base_url = os.getenv("COLOMBIARED_BASE_URL", "").strip()
    user     = os.getenv("COLOMBIARED_USER", "").strip()
    password = os.getenv("COLOMBIARED_PASSWORD", "").strip()
    sender   = (os.getenv("COLOMBIARED_SENDER") or "").strip() or None

    if not (base_url and user and password):
        print("[SMS] Faltan COLOMBIARED_BASE_URL / COLOMBIARED_USER / COLOMBIARED_PASSWORD. Usando consola.")
        return None

    provider = ColombiaRedProvider(
        base_url=base_url,
        user=user,
        password=password,
        sender=sender,
    )
    return ColombiaRedAdapter(provider=provider)


def get_sms_provider() -> SmsProvider:
    """
    Control por variable de entorno SMS_PROVIDER:
      - 'colombiared' => intenta proveedor real; si falla, cae a consola.
      - 'console' (default) => imprime en consola.
    """
    chosen = (os.getenv("SMS_PROVIDER") or "console").lower()
    if chosen == "colombiared":
        p = _build_colombiared_provider()
        if p:
            return p
        print("[SMS] Fallback a ConsoleSmsProvider.")
        return ConsoleSmsProvider()

    return ConsoleSmsProvider()
