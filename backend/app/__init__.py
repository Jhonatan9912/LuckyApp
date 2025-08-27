# backend/app/__init__.py
from flask import Flask
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from .routes import register_routes
from .db.database import init_db
from dotenv import load_dotenv
import os
from app.routes.health import health_bp  # <-- usa este SOLO si NO lo registras en register_routes

def _env(name: str, default=None, strip=True):
    v = os.getenv(name)
    if v is None:
        return default
    return v.strip() if strip and isinstance(v, str) else v

def _env_bool(name: str, default=False):
    v = _env(name, None)
    if v is None:
        return default
    return str(v).lower() in ("1", "true", "t", "yes", "y")

def create_app():
    # Cargar .env SOLO en local (evita pisar envs de Railway)
    if not os.getenv("RAILWAY_ENVIRONMENT"):
        load_dotenv()

    app = Flask(__name__)
    CORS(app)

    # =========================
    # Base de datos
    # =========================
    db_url = _env('SQLALCHEMY_DATABASE_URI') or _env('DATABASE_URL')
    if not db_url:
        # Falla temprano y claro si falta la DB
        raise RuntimeError("Falta SQLALCHEMY_DATABASE_URI o DATABASE_URL")
    app.config['SQLALCHEMY_DATABASE_URI'] = db_url
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    # =========================
    # JWT y Secret Keys
    # =========================
    app.config['JWT_SECRET_KEY'] = _env('JWT_SECRET_KEY', 'cambia-esta-clave-en-produccion')
    app.config['SECRET_KEY'] = _env('SECRET_KEY', app.config['JWT_SECRET_KEY'])

    # =========================
    # Correo (Gmail App Password)
    # =========================
    app.config['MAIL_SERVER'] = _env('MAIL_SERVER', 'smtp.gmail.com')
    app.config['MAIL_PORT'] = int(_env('MAIL_PORT', '587'))
    app.config['MAIL_USE_TLS'] = _env_bool('MAIL_USE_TLS', True)
    app.config['MAIL_USE_SSL'] = _env_bool('MAIL_USE_SSL', False)  # TLS en 587, SSL en 465 (no ambos)
    app.config['MAIL_USERNAME'] = _env('MAIL_USERNAME')
    app.config['MAIL_PASSWORD'] = _env('MAIL_PASSWORD')
    app.config['MAIL_DEFAULT_SENDER_NAME'] = _env('MAIL_DEFAULT_SENDER_NAME', 'Mi App')
    app.config['MAIL_DEFAULT_SENDER_EMAIL'] = _env('MAIL_DEFAULT_SENDER_EMAIL', app.config['MAIL_USERNAME'])

    # Logs seguros para verificar que Railway sí carga las env
    user = app.config['MAIL_USERNAME'] or ''
    pwd = app.config['MAIL_PASSWORD'] or ''
    app.logger.info("SMTP host=%s port=%s tls=%s ssl=%s user_tail=%s pass_len=%s",
                    app.config['MAIL_SERVER'],
                    app.config['MAIL_PORT'],
                    app.config['MAIL_USE_TLS'],
                    app.config['MAIL_USE_SSL'],
                    user[-6:] if user else None,
                    len(pwd))
    if not (user and pwd):
        app.logger.warning("⚠ Mail no configurado: faltan MAIL_USERNAME/MAIL_PASSWORD.")
    else:
        app.logger.info("✅ Configuración SMTP cargada.")

    # =========================
    # Reset Password
    # =========================
    app.config['DEFAULT_COUNTRY_CODE'] = _env('DEFAULT_COUNTRY_CODE', '')
    app.config['RESET_CODE_TTL_MIN'] = int(_env('RESET_CODE_TTL_MIN', '10'))
    app.config['RESET_TOKEN_TTL_MIN'] = int(_env('RESET_TOKEN_TTL_MIN', '30'))

    # =========================
    # Inicialización
    # =========================
    init_db(app)  # si falla, dejar que explote aquí para detectar rápido

    JWTManager(app)
    register_routes(app)  # <-- aquí dentro NO vuelvas a registrar health_bp

    # =========================
    # Endpoints de salud
    # =========================
    # Si EL HEALTH ya se registra en register_routes, comenta la línea de abajo
    # app.register_blueprint(health_bp)

    @app.get("/healthz")
    def healthz():
        return {"ok": True}, 200

    return app
