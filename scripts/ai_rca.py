# Pre-requisites & Local Setup
# Before we start, ensure your local environment is ready:

# Python 3.x installed (for the AI scripts).

# AWS CLI configured with the same account used in your Jenkinsfile.

# Gemini API Key: Get one from Google AI Studio.


# it takes jenkins logs as input, sends them to Google Gemini API, and prints root cause + fix
import os     #Used to access environment variables
import requests    #Used to make HTTP API calls
import sys       #Used to handle input/output from terminal

def analyze_logs(log_text):      # create a function that takes log text as input
    api_key = os.getenv("GEMINI_API_KEY")    # Reads API key from environment variable
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={api_key}"  # build request URL for Gemini API
    
    prompt = f"Analyze these Jenkins logs for a Spring Boot banking app. Identify the root cause of failure and suggest a fix:\n\n{log_text[-2000:]}"    #This is what you send to AI
    
    payload = {"contents": [{"parts": [{"text": prompt}]}]}   #Format required by Gemini API
    response = requests.post(url, json=payload)               #Sends POST request to Gemini
    return response.json()['candidates'][0]['content']['parts'][0]['text']      #Converts response to JSON then extracts candidates[0] → first AI answer -> content → parts → text → actual message

if __name__ == "__main__":   #This block runs when you execute the script
    logs = sys.stdin.read()     #Reads input from terminal / pipeline
    print("--- AI ROOT CAUSE ANALYSIS ---")
    print(analyze_logs(logs))   # it call function and pass the logs