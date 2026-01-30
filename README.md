# AI Trainer

Unified iOS app + Python backend for workout videos, local gyms, and an AI coach.

## Repository Layout
- `AITrainer/`: iOS app (SwiftUI)
- `agent/`: unified FastAPI backend (videos + gyms + coach) and agent logic
- `data/`: SQLite data used by the agent
- `sources/`: RAG source documents

## Requirements
- Python 3.12+
- Xcode (for iOS app)

## Environment Variables
Create a `.env` in the repo root (or `agent/.env`). See `env.example`.

Required:
- `OPENAI_API_KEY` (AI coach)
- `GEMINI_API_KEY` (meal photo scan)
- `GEMINI_MODEL` (optional override; auto-detected if empty)
- `YOUTUBE_API_KEY`
- `GOOGLE_PLACES_API_KEY`
- `TAVILY_API_KEY` (online recipe search)

Optional:
- `REDIS_URL` or `UPSTASH_REDIS_REST_URL` + `UPSTASH_REDIS_REST_TOKEN`

## Run the Backend
From the repo root:
```bash
cd agent
./start.sh
```

Backend will be available at:
- `http://localhost:8000/health`
- `http://localhost:8000/docs`

## Run the Agent CLI
From the repo root:
```bash
python -m agent.cli
```

## iOS App
Open `AITrainer.xcodeproj` in Xcode and run on a simulator.

The app calls the backend here:
- `AITrainer/Models/Services/YouTubeService.swift`
- `AITrainer/Models/Services/GymFinderService.swift`
- `AITrainer/Models/Services/AICoachService.swift`
- `AITrainer/Models/Services/FoodScanService.swift` (meal photo analysis)
- `AITrainer/Models/Services/RecipeImageService.swift` (AI recipe images)

If you change the backend host, update the `baseURL` in those files.

## Notes
- The AI coach endpoints are served by the agent logic via FastAPI:
  - `POST /coach/chat`
  - `POST /coach/feedback`
- RAG index is loaded from `data/faiss_index` when present.
