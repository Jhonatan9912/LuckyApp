# backend/run.py
import sys
import os

# Asegura que la carpeta 'backend' esté en sys.path
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from app import create_app

app = create_app()

if __name__ == '__main__':
    app.run(debug=True, port=8000)

