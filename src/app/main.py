import os
import time
from fastapi import FastAPI
from pydantic import BaseModel
from app.model_loader import get_pipeline

# --- OpenTelemetry Metrics (optional) ---
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader

# Set up OpenTelemetry MeterProvider
#reader = PeriodicExportingMetricReader(OTLPMetricExporter())
#provider = MeterProvider(metric_readers=[reader])
#metrics.set_meter_provider(provider)

#meter = metrics.get_meter(__name__)
#req_counter = meter.create_counter("inference_requests")

# --- FastAPI setup ---
app = FastAPI(title="HF Sentiment API")
FastAPIInstrumentor.instrument_app(app)

class InferenceRequest(BaseModel):
    text: str

@app.post("/predict")
async def predict(req: InferenceRequest):
    start = time.perf_counter()
    pipe = get_pipeline()
    result = pipe(req.text)[0]
    latency_ms = (time.perf_counter() - start) * 1000
    #req_counter.add(1, {"model": os.getenv("HF_MODEL_ID")})
    return {
        "label": result["label"],
        "score": result["score"],
        "latency_ms": latency_ms
    }
