FROM python:3.11-slim

# Install system dependencies (if needed)
RUN apt-get update && apt-get install -y build-essential && rm -rf /var/lib/apt/lists/*

# Set work directory
WORKDIR /code

# Install Python dependencies
COPY src/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/app /code/app

# Expose the port Azure will map (optional but clear)
EXPOSE 8000

# Environment variable for the model (optional)
ENV HF_MODEL_ID="distilbert-base-uncased-finetuned-sst-2-english"

# Start FastAPI app directly with Uvicorn
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
