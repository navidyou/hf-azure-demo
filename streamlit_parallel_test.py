import streamlit as st, requests, concurrent.futures, random

API_URL = st.text_input("API endpoint", value="https://sentiment-api.<hash>.westus2.azurecontainerapps.io/predict")
texts = [
    "I love Azure!",
    "This new feature is terrible.",
    "The movie was okay, nothing special.",
    "Streamlit makes demos easy.",
]

n_requests = st.slider("How many parallel requests?", 1, 100, 20)
start = st.button("Fire!")

def call_api(text):
    r = requests.post(API_URL, json={"text": text})
    return r.json()

if start:
    with concurrent.futures.ThreadPoolExecutor() as pool:
        futures = [pool.submit(call_api, random.choice(texts)) for _ in range(n_requests)]
        for f in concurrent.futures.as_completed(futures):
            st.write(f.result())
