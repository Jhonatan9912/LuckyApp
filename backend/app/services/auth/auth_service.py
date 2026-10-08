# backend/app/services/auth/auth_service.py
import re
from flask import current_app
from werkzeug.security import check_password_hash, generate_password_hash
from app.models.user import User

class AuthError(Exception):
    """Excepción personalizada para errores de autenticación."""
    pass

def _created_at_iso(u) -> str | None:
    try:
        value = getattr(u, "created_at", None)
        return value.isoformat() if value else None
    except Exception:
        return None

# Hash ficticio para igualar el tiempo de respuesta cuando el usuario no existe
_DUMMY_HASH = generate_password_hash("dummy-password-for-timing")


def _password_is_valid(u, raw_password: str) -> bool:
    # Solo contraseñas con hash (nunca texto plano)
    if getattr(u, "password_hash", None):
        try:
            return check_password_hash(u.password_hash, raw_password)
        except Exception:
            return False
    return False

def _safe_role_id(u) -> int:
    """Devuelve role_id como entero; por defecto 2."""
    try:
        val = getattr(u, "role_id", None)
        return int(val) if val is not None else 2
    except Exception:
        return 2

def _candidate_phones(raw: str) -> list[str]:
    """Genera variantes razonables del número para hacer match con DB."""
    cc = (current_app.config.get('DEFAULT_COUNTRY_CODE') or '').strip()
    digits = re.sub(r'\D', '', raw or '')
    cands: list[str] = []
    if not digits:
        return cands

    # si vienen 10 dígitos, prefija CC por defecto (ej: 57)
    if cc and len(digits) == 10:
        cands.append(f"{cc}{digits}")
    # el original “solo dígitos”, por si ya trae CC
    cands.append(digits)
    # si viene cc+10, agrega variante de 10 (usuarios antiguos)
    if cc and digits.startswith(cc) and len(digits) == len(cc) + 10:
        cands.append(digits[len(cc):])

    # quitar duplicados preservando orden
    seen = set()
    uniq: list[str] = []
    for p in cands:
        if p not in seen:
            uniq.append(p); seen.add(p)
    return uniq
def _digits(s: str) -> str:
    """Deja solo dígitos."""
    return ''.join(ch for ch in str(s) if ch.isdigit())

def _candidate_phones(raw: str) -> list[str]:
    """
    Genera variantes del teléfono para buscar en DB.
    - Guardamos en DB 'phone' como solo dígitos (eso ya lo haces en registro).
    - Probamos: tal cual (solo dígitos), sin prefijo 57, y con prefijo 57.
    """
    d = _digits(raw)
    if not d:
        return []

    candidates = []
    # 1) tal cual (ej: "3192156745" ó "573192156745")
    candidates.append(d)

    # 2) si viene con prefijo '57', probar sin '57'
    if d.startswith('57') and len(d) > 2:
        candidates.append(d[2:])

    # 3) si viene sin prefijo y parece un celular local de 10 dígitos, probar con '57' al inicio
    if len(d) == 10 and not d.startswith('57'):
        candidates.append('57' + d)

    # quitar duplicados manteniendo orden
    seen = set()
    uniq = []
    for x in candidates:
        if x not in seen:
            seen.add(x)
            uniq.append(x)
    return uniq

def login_with_phone(phone: str, password: str) -> dict:
    # Normaliza y prueba variantes
    candidates = _candidate_phones(phone)

    user = None
    matched_phone = None
    for p in candidates:
        u = User.query.filter_by(phone=p).first()
        if u:
            user = u
            matched_phone = p
            break

    if not user:
        check_password_hash(_DUMMY_HASH, password or "")
        raise AuthError("Número de celular o contraseña inválidos")
    if getattr(user, "deleted_at", None) is not None:
        raise AuthError("Número de celular o contraseña inválidos")
    if not _password_is_valid(user, password):
        raise AuthError("Número de celular o contraseña inválidos")

    current_app.logger.info("[AUTH] Login OK user_id=%s", user.id)

    return {
        "id": user.id,
        "name": getattr(user, "name", None),
        "phone": getattr(user, "phone", None),
        "role_id": getattr(user, "role_id", None),
        "created_at": _created_at_iso(user),
    }


def get_profile(user_id: int) -> dict | None:
    u = User.query.get(user_id)
    if not u:
        return None
    return {
        "id": u.id,
        "name": getattr(u, "name", None),
        "phone": getattr(u, "phone", None),
        "role_id": _safe_role_id(u),
        "created_at": _created_at_iso(u),
        "public_code": getattr(u, "public_code", None),   # 👈 IMPORTANTE
        "referral_code": getattr(u, "public_code", None), # (alias opcional)
    }