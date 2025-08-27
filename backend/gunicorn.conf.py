# backend/gunicorn.conf.py
import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8080')}"  # Railway inyecta PORT
workers = int(os.environ.get('WEB_CONCURRENCY', '2'))
timeout = 120
loglevel = "debug"      # nivel máximo de detalle
capture_output = True   # 👈 fuerza que stdout/stderr vayan a logs
accesslog = "-"         # 👈 imprime access log en consola
errorlog = "-"          # 👈 imprime errores en consola
