# app/core/auth/entitlements.py
from functools import wraps
from flask import jsonify, request, current_app
from flask_jwt_extended import get_jwt_identity
from app.subscriptions.service import get_status

def requires_entitlement(entitlement: str):
    """
    Decorador de uso simple:
        @jwt_required()
        @requires_entitlement("pro")
        def endpoint(...):

    REGLA DE ORDEN: pon siempre @jwt_required() ENCIMA de este decorador
    para que el identity ya exista cuando validemos el entitlement.
    """
    def _decorator(fn):
        @wraps(fn)
        def _wrapped(*args, **kwargs):
            user_id = get_jwt_identity()
            if not user_id:
                # No debería ocurrir si usas @jwt_required(), pero por seguridad:
                return jsonify({
                    "ok": False,
                    "error": "UNAUTHENTICATED",
                    "message": "Login requerido.",
                }), 401

            status = get_status(user_id)
            allowed = (status.entitlement == entitlement) and bool(status.is_premium)

            if not allowed:
                # Log estructurado mínimo para auditoría
                try:
                    current_app.logger.info(
                        "entitlement_denied",
                        extra={
                            "user_id": int(user_id),
                            "endpoint": request.endpoint,
                            "ip": request.headers.get("X-Forwarded-For", request.remote_addr),
                            "required": entitlement,
                            "status": status.status,
                            "isPremium": status.is_premium,
                        },
                    )
                except Exception:
                    pass

                return jsonify({
                    "ok": False,
                    "error": "ENTITLEMENT_REQUIRED",
                    "entitlement": entitlement,
                    "status": status.status,
                    "isPremium": status.is_premium,
                }), 403

            return fn(*args, **kwargs)
        return _wrapped
    return _decorator
