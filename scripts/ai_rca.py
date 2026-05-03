import os
import requests
import sys
import json

def analyze_logs(log_text):
    api_key = os.getenv("GEMINI_API_KEY")

    if not api_key or api_key == "None":
        return "ERROR: GEMINI_API_KEY not set or empty"

    url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=" + api_key

    prompt = (
        "You are a DevOps expert. Analyze these Jenkins CI/CD pipeline logs for a Spring Boot banking app.\n"
        "Provide:\n"
        "1. ROOT CAUSE: What exactly failed and why\n"
        "2. FAILED STAGE: Which pipeline stage failed\n"
        "3. FIX: Exact steps to resolve it\n\n"
        f"LOGS:\n{log_text[-3000:]}"
    )

    payload = {"contents": [{"parts": [{"text": prompt}]}]}

    try:
        response = requests.post(url, json=payload, timeout=30)
        data = response.json()

        if "candidates" not in data:
            error_msg = data.get("error", {}).get("message", str(data))
            return f"Gemini API error: {error_msg}"

        return data["candidates"][0]["content"]["parts"][0]["text"]

    except Exception as e:
        return f"Script exception: {str(e)}"

if __name__ == "__main__":
    logs = sys.stdin.read()
    if not logs.strip():
        print("No logs received on stdin")
        sys.exit(1)
    print("--- AI ROOT CAUSE ANALYSIS ---")
    print(analyze_logs(logs))
