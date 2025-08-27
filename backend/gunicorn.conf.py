# backend/gunicorn.conf.py
import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8080')}"  # Railway inyecta PORT
workers = int(os.environ.get('WEB_CONCURRENCY', '2'))
timeout = 120
loglevel = "debug"
