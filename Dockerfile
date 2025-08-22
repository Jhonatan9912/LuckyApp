FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PORT=8000 \
    FLASK_ENV=production \
    GUNICORN_CMD_ARGS="--log-level debug --timeout 120 --workers 2"

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc libpq-dev curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY backend/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copia TODO el backend (incluye backend/wsgi.py -> /app/wsgi.py)
COPY backend/ /app/

EXPOSE 8000
CMD gunicorn -b 0.0.0.0:$PORT wsgi:app
