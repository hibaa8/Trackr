#!/usr/bin/env python3
"""
Test script to check if Gemini API is truly exhausted or if there's a backend logic issue
"""

import os
import google.generativeai as genai
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

def test_gemini_api():
    print("🧪 Testing Gemini API directly...")

    # Get API key
    api_key = os.getenv('GEMINI_API_KEY')
    if not api_key:
        print("❌ No GEMINI_API_KEY found in environment")
        return False

    print(f"✅ Found API key: {api_key[:10]}...")

    # Configure Gemini
    genai.configure(api_key=api_key)

    # Try to get model info first
    try:
        models = genai.list_models()
        print("✅ Successfully connected to Gemini API")

        # Try a simple generation
        model = genai.GenerativeModel('gemini-2.5-flash')
        response = model.generate_content("Say 'hello' in one word")
        print(f"✅ Simple test successful: {response.text}")
        return True

    except Exception as e:
        print(f"❌ Gemini API Error: {e}")
        if "ResourceExhausted" in str(e) or "429" in str(e):
            print("🔍 Confirmed: This is a real quota exhaustion, not a logic error")
        else:
            print("🔍 This might be a different issue (config, network, etc)")
        return False

if __name__ == "__main__":
    test_gemini_api()