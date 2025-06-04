import streamlit as st, requests, concurrent.futures, random

API_URL = st.text_input(
    "API endpoint", 
    value="https://sentiment-api-stage.ashybush-155fc5f4.westus2.azurecontainerapps.io/predict"
)
texts = [
    "I love Azure!",
    "This new feature is terrible.",
    "The movie was okay, nothing special.",
    "Streamlit makes demos easy.",
]

n_requests = st.slider("How many parallel requests?", 1, 1000, 20)
start = st.button("Fire!")

def call_api(text):
    try:
        r = requests.post(API_URL, json={"text": text}, timeout=10)
        if r.status_code == 200:
            return r.json()
        else:
            return {"error": f"Status code {r.status_code}", "text": text}
    except Exception as e:
        return {"error": str(e), "text": text}

if start:
    with st.spinner(f"Firing {n_requests} requests..."):
        with concurrent.futures.ThreadPoolExecutor() as pool:
            futures = [pool.submit(call_api, random.choice(texts)) for _ in range(n_requests)]
            for i, f in enumerate(concurrent.futures.as_completed(futures)):
                st.write(f"{i+1}: {f.result()}")

