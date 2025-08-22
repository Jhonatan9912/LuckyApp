# backend/wsgi.py
try:
    # Caso común: tienes una factory create_app() en app/__init__.py
    from app import create_app
    app = create_app()
except Exception:
    # Plan B: quizás ya tienes una instancia 'app' en algún módulo
    try:
        from app import app  # e.g., app = Flask(__name__)
    except Exception as e:
        # Último recurso: app mínima para que Gunicorn levante y podamos ver logs
        from flask import Flask, jsonify
        app = Flask(__name__)

        @app.route("/health")
        def _health():
            return jsonify(ok=True), 200

        @app.route("/")
        def _root():
            return "WSGI fallback running", 200
