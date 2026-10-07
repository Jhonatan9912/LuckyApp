# backend/app/__init__.py
from flask import Flask, request
from flask_cors import CORS
from werkzeug.middleware.proxy_fix import ProxyFix
from flask_jwt_extended import JWTManager
from .routes import register_routes
from .db.database import init_db
from dotenv import load_dotenv
import os
from .cli import register_cli
from apscheduler.schedulers.background import BackgroundScheduler

def _as_bool(v, default=False):
    if v is None:
        return default
    return str(v).lower() in ("1", "true", "yes", "y", "on")

def create_app():
    load_dotenv()

    app = Flask(__name__)

    # Railway pone un proxy delante: tomamos la IP real del cliente del
    # último salto (X-Forwarded-For) para el limitador de intentos.
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

    # CORS: orígenes permitidos para la web (coma-separados).
    # La app móvil no usa CORS, así que esto solo afecta a navegadores.
    cors_origins = [o.strip() for o in os.getenv("CORS_ORIGINS", "").split(",") if o.strip()]
    if not cors_origins:
        cors_origins = "*"
        app.logger.warning("CORS_ORIGINS no definido: se permite cualquier origen.")
    CORS(
        app,
        resources={r"/api/.*": {"origins": cors_origins}},
        allow_headers=["Authorization", "Content-Type", "Accept"],
        methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        max_age=600,
    )

    # Tamaño máximo de petición (adjuntos de pagos incluidos)
    app.config['MAX_CONTENT_LENGTH'] = int(os.getenv('MAX_CONTENT_LENGTH_MB', '20')) * 1024 * 1024

    # =========================
    # Base de Datos
    # =========================
    app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL')
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    # =========================
    # JWT y Secret Keys
    # =========================
    jwt_secret = os.getenv('JWT_SECRET_KEY') or ''
    is_dev = _as_bool(os.getenv('ALLOW_INSECURE_DEV_SECRET'))
    if not jwt_secret.strip() or jwt_secret.strip() == 'cambia-esta-clave-en-produccion':
        if not is_dev:
            raise RuntimeError(
                "JWT_SECRET_KEY no está configurado (o usa el valor por defecto). "
                "Defínelo en las variables de entorno antes de arrancar."
            )
        app.logger.warning("⚠ Usando JWT_SECRET_KEY de desarrollo (ALLOW_INSECURE_DEV_SECRET).")
        jwt_secret = 'dev-only-secret-not-for-production-use-0000'
    elif len(jwt_secret) < 32:
        app.logger.warning("⚠ JWT_SECRET_KEY es corto (<32 caracteres); se recomienda uno más largo.")
    app.config['JWT_SECRET_KEY'] = jwt_secret
    app.config['SECRET_KEY'] = os.getenv('SECRET_KEY') or jwt_secret
    app.config['JWT_ALGORITHM'] = 'HS256'
    app.config['JWT_DECODE_ALGORITHMS'] = ['HS256']
    # Los tiempos reales se fijan al emitir cada token (access 12h, refresh largo)
    app.config['JWT_ACCESS_TOKEN_EXPIRES'] = False
    app.config['JWT_REFRESH_TOKEN_EXPIRES'] = False
    app.config['JWT_COOKIE_CSRF_PROTECT'] = False
    app.config['JWT_TOKEN_LOCATION'] = ['headers']
        # Config de suscripciones / RTDN / reconciliación
    app.config["RECONCILE_TOKEN"] = os.getenv("RECONCILE_TOKEN")                # usado por /api/subscriptions/reconcile
    app.config["PUBSUB_PUSH_AUDIENCE"] = os.getenv("PUBSUB_PUSH_AUDIENCE", "")  # opcional, para verificar OIDC en /rtdn
    app.config["GOOGLE_PLAY_PACKAGE_NAME"] = os.getenv("GOOGLE_PLAY_PACKAGE_NAME", "")

    # =========================
    # Correo (SOLO Resend)
    # =========================
    # Forzamos el modo resend; no se usa SMTP.
    app.config['MAIL_MODE'] = 'resend'  # fijo
    app.config['RESEND_API_KEY'] = os.getenv('RESEND_API_KEY')
    # Remitente para Resend. Idealmente usar dominio verificado.
    app.config['MAIL_FROM'] = os.getenv('MAIL_FROM', 'LuckyApp <onboarding@resend.dev>')
    app.config['MAIL_DEFAULT_SENDER_EMAIL'] = os.getenv('MAIL_DEFAULT_SENDER_EMAIL', 'onboarding@resend.dev')
    app.config['MAIL_DEFAULT_SENDER_NAME'] = os.getenv('MAIL_DEFAULT_SENDER_NAME', 'LuckyApp')

    # Timeout HTTP para Resend
    app.config['MAIL_HTTP_TIMEOUT'] = int(os.getenv('MAIL_HTTP_TIMEOUT', '10'))

    # Logs de configuración de mail
    if not app.config['RESEND_API_KEY']:
        app.logger.warning("⚠ Resend no configurado: falta RESEND_API_KEY.")
    else:
        app.logger.info("✅ Configuración Resend cargada (MAIL_MODE=resend).")

    # =========================
    # Reset Password
    # =========================
    app.config['DEFAULT_COUNTRY_CODE'] = os.getenv('DEFAULT_COUNTRY_CODE', '')
    app.config['RESET_CODE_TTL_MIN'] = int(os.getenv('RESET_CODE_TTL_MIN', '10'))
    app.config['RESET_TOKEN_TTL_MIN'] = int(os.getenv('RESET_TOKEN_TTL_MIN', '30'))

    # =========================
    # Inicialización segura de dependencias
    # =========================
    try:
        init_db(app)
    except Exception as e:
        app.logger.error("❌ init_db() falló al arrancar: %s", e)


    jwt = JWTManager(app)

    from app.security.guards import ensure_security_tables, token_issued_before_epoch
    ensure_security_tables(app)

    @jwt.token_in_blocklist_loader
    def _is_token_revoked(jwt_header, jwt_payload):
        # Revocado si su JTI está en la lista (logout) o si fue emitido antes
        # de un cambio de contraseña (revocación global del usuario).
        from app.models.token_blocklist import TokenBlocklist
        jti = jwt_payload.get("jti")
        if TokenBlocklist.query.filter_by(jti=jti).first() is not None:
            return True
        return token_issued_before_epoch(jwt_payload.get("sub"), jwt_payload.get("iat"))

    @app.after_request
    def _security_headers(resp):
        h = resp.headers
        h.setdefault("X-Content-Type-Options", "nosniff")
        h.setdefault("X-Frame-Options", "DENY")
        h.setdefault("Referrer-Policy", "no-referrer")
        h.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        h.setdefault("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
        if request.path.startswith("/api/"):
            h.setdefault("Cache-Control", "no-store")
        return resp

    @app.before_request
    def _reject_oversized():
        # Rechaza antes de que cualquier ruta intente leer el cuerpo.
        cl = request.content_length
        if cl is not None and cl > app.config['MAX_CONTENT_LENGTH']:
            return {"ok": False, "error": "Archivo o petición demasiado grande"}, 413
        return None

    @app.errorhandler(413)
    def _too_large(_e):
        return {"ok": False, "error": "Archivo o petición demasiado grande"}, 413

    # Registra TODOS los blueprints desde routes/__init__.py
    register_routes(app)

    # =========================
    # DEBUG GLOBAL (solo si ENABLE_DEBUG_ROUTES=true)
    # =========================
    from flask import Blueprint, jsonify, current_app
    debug_bp = Blueprint("debug_global", __name__, url_prefix="/api/debug")

    @debug_bp.get("/version")
    def debug_version():
        # Cambia el sello cuando hagas nuevos cambios para confirmar que el deploy tomó esta versión
        return jsonify({"stamp": "deploy_referrals_v2"}), 200

    @debug_bp.get("/routes")
    def debug_routes():
        rules = []
        for r in current_app.url_map.iter_rules():
            rules.append({
                "rule": str(r),
                "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS"))
            })
        return jsonify(routes=sorted(rules, key=lambda x: x["rule"])), 200

    # Log: ¿desde qué archivo se cargaron los services?
    try:
        import app.services.referrals.referral_service as rs
        import app.services.referrals.payouts_service as ps
        app.logger.info("referral_service loaded from: %s", getattr(rs, "__file__", None))
        app.logger.info("payouts_service  loaded from: %s", getattr(ps, "__file__", None))
    except Exception as e:
        app.logger.error("debug import failed: %s", e)

    if _as_bool(os.getenv("ENABLE_DEBUG_ROUTES")):
        app.register_blueprint(debug_bp)
    
    @app.get("/healthz")
    def healthz():
        return {"ok": True}, 200

    from app.observability.metrics import metrics_http_response

    @app.get("/metrics")
    def metrics():
        # Solo con token: Authorization: Bearer <METRICS_TOKEN>
        import hmac
        expected = (os.getenv("METRICS_TOKEN") or "").strip()
        given = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
        if not expected or not hmac.compare_digest(expected, given):
            return {"ok": False, "error": "Not found"}, 404
        return metrics_http_response()

    # Registrar comandos CLI (mature-commissions)
    register_cli(app)

    # Limpiar suscripciones vencidas al arrancar
    with app.app_context():
        try:
            from app.subscriptions.service import expire_all_stale
            count = expire_all_stale()
            app.logger.info("startup_expire_stale: %d suscripciones expiradas al arrancar", count)
        except Exception as e:
            app.logger.error("startup_expire_stale falló (no bloquea arranque): %s", e)

    # APScheduler: solo en el servidor web (gunicorn), no en el CLI del cron de Railway
    # El cron de Railway llama expire_all_stale() directamente en cli.py cada 5 min
    if not os.environ.get("FLASK_RUN_FROM_CLI"):
        def _cron_expire():
            with app.app_context():
                try:
                    from app.subscriptions.service import expire_all_stale
                    count = expire_all_stale()
                    if count:
                        app.logger.info("cron_expire_stale: %d suscripciones expiradas", count)
                except Exception as e:
                    app.logger.error("cron_expire_stale falló: %s", e)

        scheduler = BackgroundScheduler(daemon=True)
        scheduler.add_job(_cron_expire, "interval", hours=1)
        scheduler.start()
        app.logger.info("cron_expire_stale: scheduler iniciado (cada hora)")

    return app
