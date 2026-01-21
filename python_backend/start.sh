#!/bin/bash
set -e
# Start the AI Trainer YouTube API Backend

echo "🚀 Starting AI Trainer YouTube API Backend..."

# Install dependencies if not already installed
if [ ! -d "venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv venv
fi

echo "🔄 Activating virtual environment..."
source venv/bin/activate

echo "📥 Installing dependencies..."
pip install -r requirements.txt

echo "🌟 Starting FastAPI server..."
echo "🔗 Backend will be available at: http://localhost:8000"
echo "📖 API docs will be at: http://localhost:8000/docs"

uvicorn app:app --reload --host 0.0.0.0 --port 8000