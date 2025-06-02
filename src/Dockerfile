FROM python:3.11-slim

RUN apt-get update && apt-get install -y nginx && rm -rf /var/lib/apt/lists/*

WORKDIR /code
COPY src/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/app /code/app
COPY src/nginx/nginx.conf /etc/nginx/nginx.conf

ENV HF_MODEL_ID=distilbert-base-uncased-finetuned-sst-2-english 
    GUNICORN_CMD_ARGS="--workers=2 --worker-class=uvicorn.workers.UvicornWorker --bind=0.0.0.0:8000 --timeout 120"

CMD service nginx start && gunicorn app.main:app