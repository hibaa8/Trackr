#!/bin/bash
set -e
# Start the AI Trainer backend (videos, gyms, coach)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Starting AI Trainer backend..."

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