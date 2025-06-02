# -----------------------------------------------------------------------------
# Hugging Face + FastAPI + Gunicorn + NGINX container
# -----------------------------------------------------------------------------

# 1. Base image
FROM python:3.11-slim

# 2. Install system packages (NGINX)
RUN apt-get update && \
    apt-get install -y nginx && \
    rm -rf /var/lib/apt/lists/*

# 3. Set work directory
WORKDIR /code

# 4. Python dependencies
COPY src/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 5. Copy application code & nginx config
COPY src/app /code/app
COPY src/nginx/nginx.conf /etc/nginx/nginx.conf

# 6. Environment variables
ENV HF_MODEL_ID="distilbert-base-uncased-finetuned-sst-2-english" \
    GUNICORN_CMD_ARGS="--workers=2 --worker-class=uvicorn.workers.UvicornWorker --bind=0.0.0.0:8000 --timeout 120"

# 7. Startup command
CMD service nginx start && gunicorn app.main:app
