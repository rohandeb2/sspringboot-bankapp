# Pre-requisites & Local Setup
# Before we start, ensure your local environment is ready:

# Python 3.x installed (for the AI scripts).

# AWS CLI configured with the same account used in your Jenkinsfile.

# Gemini API Key: Get one from Google AI Studio.
import os
import requests
import sys

def analyze_logs(log_text):
    api_key = os.getenv("GEMINI_API_KEY")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={api_key}"
    
    prompt = f"Analyze these Jenkins logs for a Spring Boot banking app. Identify the root cause of failure and suggest a fix:\n\n{log_text[-2000:]}"
    
    payload = {"contents": [{"parts": [{"text": prompt}]}]}
    response = requests.post(url, json=payload)
    return response.json()['candidates'][0]['content']['parts'][0]['text']

if __name__ == "__main__":
    logs = sys.stdin.read()
    print("--- AI ROOT CAUSE ANALYSIS ---")
    print(analyze_logs(logs))