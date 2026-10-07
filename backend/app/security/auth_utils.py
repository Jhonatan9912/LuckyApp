# app/security/auth_utils.py
#
# La identidad del usuario se obtiene SOLO de un JWT de acceso válido
# (firma, expiración y revocación verificadas). Ya no se aceptan
# cabeceras X-USER-ID ni ids en la sesión: permitían suplantar usuarios.
from app.security.guards import current_user_id


def resolve_user_id() -> int | None:
    return current_user_id(optional=True)
