# backend/app/__init__.py
from flask import Flask
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from .routes import register_routes
from .db.database import init_db
from dotenv import load_dotenv
import os

def _as_bool(v, default=False):
    if v is None:
        return default
    return str(v).lower() in ("1", "true", "yes", "y", "on")

def create_app():
    load_dotenv()

    app = Flask(__name__)
    CORS(app)

    # =========================
    # Base de Datos
    # =========================
    app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL')
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    # =========================
    # JWT y Secret Keys
    # =========================
    app.config['JWT_SECRET_KEY'] = os.getenv('JWT_SECRET_KEY', 'cambia-esta-clave-en-produccion')
    app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', app.config['JWT_SECRET_KEY'])

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

    JWTManager(app)

    # Registra TODOS los blueprints desde routes/__init__.py
    register_routes(app)

       # =========================
    # DEBUG GLOBAL
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

    app.register_blueprint(debug_bp)
    
    @app.get("/healthz")
    def healthz():
        return {"ok": True}, 200

    from app.observability.metrics import metrics_http_response

    @app.get("/metrics")
    def metrics():
        return metrics_http_response()

    return app
