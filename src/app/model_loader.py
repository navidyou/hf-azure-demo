import os
from functools import lru_cache
from transformers import pipeline

MODEL_ID = os.getenv("HF_MODEL_ID", "distilbert-base-uncased-finetuned-sst-2-english")

@lru_cache(maxsize=1)
def get_pipeline():
    return pipeline("sentiment-analysis", model=MODEL_ID)
