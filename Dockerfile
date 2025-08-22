# ---- Imagen base ----
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Paquetes de sistema necesarios para psycopg2
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc libpq-dev curl && \
    rm -rf /var/lib/apt/lists/*

# Directorio de trabajo
WORKDIR /app

# Instalar dependencias primero (mejor caché)
COPY backend/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copiar el código del backend (carpeta backend/)
COPY backend/ /app/

# Variables por defecto (puedes sobreescribirlas en runtime)
ENV PORT=8000 \
    FLASK_ENV=production

EXPOSE 8000

# Arranque con Gunicorn (wsgi.py está en /app y expone 'app')
CMD gunicorn -w 3 -b 0.0.0.0:$PORT wsgi:app
