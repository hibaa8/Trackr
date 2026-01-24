from __future__ import annotations

"""
AI Trainer unified backend (videos, gyms, coach).
"""

import base64
import io
import os
import re
import sqlite3
import ssl
import time
from datetime import date, datetime
from typing import Any, Dict, List, Optional

import certifi
import json
import urllib.parse
import urllib.request

from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from googleapiclient.discovery import build
import google.generativeai as genai
from langchain_core.messages import HumanMessage, ToolMessage
from PIL import Image
from pydantic import BaseModel

from config.constants import DB_PATH

# Configuration
_ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
_ROOT_ENV_PATH = os.path.join(_ROOT_DIR, ".env")
_ENV_PATH = os.path.join(os.path.dirname(__file__), ".env")
load_dotenv(dotenv_path=_ROOT_ENV_PATH)
load_dotenv(dotenv_path=_ENV_PATH)
YOUTUBE_API_KEY = os.getenv("YOUTUBE_API_KEY", "")
PLACES_API_KEY = os.getenv("GOOGLE_PLACES_API_KEY", "")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY") or os.getenv("GEMINI_AISTUDIO_API_KEY", "")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "").strip()
if not YOUTUBE_API_KEY:
    raise RuntimeError("Missing YOUTUBE_API_KEY env var")

# Search queries for each category (embeddable videos only)
CATEGORY_QUERIES = {
    "all": "full body workout",
    "cardio": "cardio workout",
    "strength": "strength training workout",
    "yoga": "yoga flow",
    "hiit": "HIIT workout",
}

# Fallback video IDs if search fails
CATEGORY_VIDEOS = {
    "all": [
        "MLpne8lFxHs",  # 10 MIN MORNING YOGA FLOW - Yoga with Adriene
        "IODxDxX7oi4",  # 20 MIN FULL BODY WORKOUT - MadFit
        "v7AYKMP6rOE",  # Morning Yoga For Beginners - Yoga with Adriene
        "9jcKUb_-1eA",  # 12 MIN AB WORKOUT - Chloe Ting
        "6K8_N4XtTOQ",  # 15 MIN FULL BODY WORKOUT - FitnessBlender
    ],
    "cardio": [
        "MLpne8lFxHs",
        "6K8_N4XtTOQ",
        "9jcKUb_-1eA",
    ],
    "strength": [
        "IODxDxX7oi4",
        "6K8_N4XtTOQ",
    ],
    "yoga": [
        "MLpne8lFxHs",
        "v7AYKMP6rOE",
    ],
    "hiit": [
        "9jcKUb_-1eA",
        "IODxDxX7oi4",
    ],
}

app = FastAPI(title="AI Trainer Backend", version="1.0.0")

# Allow CORS for iOS app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

youtube = build("youtube", "v3", developerKey=YOUTUBE_API_KEY)

# Agent integration (lazy-loaded so env vars are available)
_AGENT_GRAPH = None
_AGENT_PRELOADED: set[str] = set()
_AGENT_PRELOAD_FN = None
_AGENT_RAG_INIT = None
_PENDING_PLANS: Dict[str, Dict[str, Any]] = {}
_GEMINI_MODEL = None


def _get_agent_graph():
    global _AGENT_GRAPH, _AGENT_PRELOAD_FN, _AGENT_RAG_INIT
    if _AGENT_GRAPH is None:
        from graph.graph import build_graph, _preload_session_cache
        from rag.rag import _build_rag_index

        _AGENT_GRAPH = build_graph()
        _AGENT_PRELOAD_FN = _preload_session_cache
        _AGENT_RAG_INIT = _build_rag_index
        _AGENT_RAG_INIT()
    return _AGENT_GRAPH, _AGENT_PRELOAD_FN


def _resolve_gemini_model_name() -> str:
    if GEMINI_MODEL:
        return GEMINI_MODEL
    try:
        models = [
            m for m in genai.list_models()
            if "generateContent" in getattr(m, "supported_generation_methods", [])
        ]
    except Exception:
        models = []
    for model in models:
        name = getattr(model, "name", "")
        if any(key in name for key in ("gemini-1.5-flash", "gemini-1.5-pro")):
            return name
    if models:
        return getattr(models[0], "name", "gemini-1.5-flash")
    return "gemini-1.5-flash"


def _get_gemini_model():
    global _GEMINI_MODEL
    if _GEMINI_MODEL is None:
        if not GEMINI_API_KEY:
            raise RuntimeError("Missing GEMINI_API_KEY env var")
        genai.configure(api_key=GEMINI_API_KEY)
        model_name = _resolve_gemini_model_name()
        _GEMINI_MODEL = genai.GenerativeModel(model_name)
    return _GEMINI_MODEL


def _extract_plan_from_messages(messages: List[Any]) -> Dict[str, Any]:
    plan_text = None
    proposed_plan = None
    for message in reversed(messages):
        if isinstance(message, ToolMessage):
            try:
                payload = json.loads(message.content)
            except json.JSONDecodeError:
                payload = None
            if isinstance(payload, dict):
                plan_text = payload.get("plan_text")
                proposed_plan = payload.get("plan_data")
            else:
                plan_text = message.content
            break
    return {"plan_text": plan_text, "proposed_plan": proposed_plan}


def _safe_parse_json(text: str) -> Dict[str, Any]:
    if not text:
        return {}
    match = re.search(r"\{.*\}", text, flags=re.DOTALL)
    payload = match.group(0) if match else text
    try:
        return json.loads(payload)
    except json.JSONDecodeError:
        return {}


def _store_meal_log(payload: FoodLogRequest) -> None:
    logged_at = payload.logged_at or datetime.now().isoformat(timespec="seconds")
    description = payload.food_name
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO meal_logs (
                user_id, logged_at, photo_path, description, calories,
                protein_g, carbs_g, fat_g, confidence, confirmed
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                payload.user_id,
                logged_at,
                None,
                description,
                payload.total_calories,
                int(payload.protein_g),
                int(payload.carbs_g),
                int(payload.fat_g),
                max((item.confidence for item in payload.items), default=0.6),
                1,
            ),
        )
        conn.commit()


class CoachChatRequest(BaseModel):
    message: str
    user_id: int = 1
    thread_id: Optional[str] = None


class CoachChatResponse(BaseModel):
    reply: str
    thread_id: str
    requires_feedback: bool = False
    plan_text: Optional[str] = None


class CoachFeedbackRequest(BaseModel):
    thread_id: str
    approve_plan: bool


class CoachFeedbackResponse(BaseModel):
    reply: str
    thread_id: str


class FoodScanItem(BaseModel):
    name: str
    amount: str
    calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    confidence: float


class FoodScanResponse(BaseModel):
    food_name: str
    total_calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    confidence: float
    items: List[FoodScanItem]


class FoodLogRequest(BaseModel):
    user_id: int = 1
    food_name: str
    total_calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    items: List[FoodScanItem]
    logged_at: Optional[str] = None


class DailyIntakeResponse(BaseModel):
    date: str
    total_calories: int
    total_protein_g: float
    total_carbs_g: float
    total_fat_g: float
    meals_count: int


class MealLogItem(BaseModel):
    name: str
    calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    logged_at: str


class DailyMealLogsResponse(BaseModel):
    date: str
    meals: List[MealLogItem]

# Simple in-memory cache
_CACHE: Dict[str, Dict] = {}
CACHE_TTL_SECONDS = 300  # 5 minutes


def _cache_get(key: str) -> Optional[Dict]:
    item = _CACHE.get(key)
    if not item:
        return None
    if time.time() - item["ts"] > CACHE_TTL_SECONDS:
        _CACHE.pop(key, None)
        return None
    return item["value"]


def _cache_set(key: str, value: Dict) -> None:
    _CACHE[key] = {"ts": time.time(), "value": value}


def _parse_iso8601_duration(duration: str) -> int:
    """Convert YouTube ISO 8601 duration (PT15M30S) to seconds"""
    if not duration or not duration.startswith("PT"):
        return 0

    dur = duration[2:]
    num = ""
    hours = minutes = seconds = 0

    for ch in dur:
        if ch.isdigit():
            num += ch
            continue
        if ch == "H":
            hours = int(num or "0")
        elif ch == "M":
            minutes = int(num or "0")
        elif ch == "S":
            seconds = int(num or "0")
        num = ""

    return hours * 3600 + minutes * 60 + seconds


def _format_duration(total_seconds: int) -> str:
    """Format seconds as human readable duration"""
    if total_seconds >= 3600:
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        return f"{hours}h {minutes}m"
    elif total_seconds >= 60:
        minutes = total_seconds // 60
        return f"{minutes} min"
    else:
        return f"{total_seconds}s"


def _determine_difficulty(title: str, duration_seconds: int) -> str:
    """Determine workout difficulty based on title and duration"""
    title_lower = title.lower()

    if any(word in title_lower for word in ["beginner", "easy", "gentle", "starter"]):
        return "beginner"
    elif any(word in title_lower for word in ["advanced", "intense", "extreme", "hardcore"]):
        return "advanced"
    elif duration_seconds > 2400:  # > 40 minutes
        return "advanced"
    elif duration_seconds < 600:   # < 10 minutes
        return "beginner"
    else:
        return "intermediate"


def fetch_videos_by_ids(video_ids: List[str]) -> List[Dict]:
    """Fetch videos by their YouTube IDs"""
    try:
        if not video_ids:
            return []

        # Get video details
        videos_request = youtube.videos().list(
            part="snippet,contentDetails,statistics,status",
            id=",".join(video_ids)
        )
        videos_response = videos_request.execute()

        videos = []
        for item in videos_response.get("items", []):
            status = item.get("status", {})
            if not status.get("embeddable", False):
                continue
            if status.get("privacyStatus") != "public":
                continue

            snippet = item["snippet"]
            content_details = item["contentDetails"]
            statistics = item.get("statistics", {})

            duration_seconds = _parse_iso8601_duration(content_details.get("duration", ""))

            video_data = {
                "id": item["id"],
                "title": snippet["title"],
                "instructor": snippet["channelTitle"],
                "duration": duration_seconds // 60,  # Convert to minutes
                "formattedDuration": _format_duration(duration_seconds),
                "difficulty": _determine_difficulty(snippet["title"], duration_seconds),
                "thumbnailURL": snippet["thumbnails"]["high"]["url"],
                "viewCount": int(statistics.get("viewCount", 0)),
                "description": snippet.get("description", ""),
                "embedURL": f"https://www.youtube-nocookie.com/embed/{item['id']}",
                "youtubeURL": f"https://www.youtube.com/watch?v={item['id']}"
            }
            videos.append(video_data)

        return videos

    except Exception as e:
        print(f"Error fetching videos {video_ids}: {e}")
        return []


def _search_video_ids(query: str, limit: int, duration: Optional[str]) -> List[str]:
    """Search YouTube for embeddable video IDs"""
    try:
        params = {
            "part": "id",
            "q": query,
            "type": "video",
            "maxResults": limit,
            "videoEmbeddable": "true",
            "safeSearch": "moderate",
        }
        if duration:
            params["videoDuration"] = duration

        search_request = youtube.search().list(**params)
        search_response = search_request.execute()

        return [
            item["id"]["videoId"]
            for item in search_response.get("items", [])
            if item.get("id", {}).get("videoId")
        ]
    except Exception as e:
        print(f"Error searching videos for '{query}': {e}")
        return []


def fetch_videos_by_search(query: str, limit: int) -> List[Dict]:
    """Search YouTube for embeddable videos and return detailed results"""
    video_ids: List[str] = []
    for duration in ("medium", "long"):
        if len(video_ids) >= limit:
            break
        for video_id in _search_video_ids(query, limit - len(video_ids), duration):
            if video_id not in video_ids:
                video_ids.append(video_id)

    videos = fetch_videos_by_ids(video_ids)
    # Filter out very short clips (often Shorts) which are prone to embed errors
    return [video for video in videos if video.get("duration", 0) >= 1]


def _places_request(path: str, params: Dict[str, str]) -> Dict:
    if not PLACES_API_KEY:
        return {"status": "REQUEST_DENIED", "error_message": "Missing GOOGLE_PLACES_API_KEY"}

    params_with_key = {**params, "key": PLACES_API_KEY}
    query = urllib.parse.urlencode(params_with_key)
    url = f"https://maps.googleapis.com/maps/api/place/{path}/json?{query}"
    request = urllib.request.Request(url, headers={"User-Agent": "ai-trainer-backend"})
    try:
        ssl_context = ssl.create_default_context(cafile=certifi.where())
        with urllib.request.urlopen(request, timeout=10, context=ssl_context) as response:
            data = response.read()
        return json.loads(data.decode("utf-8"))
    except Exception as e:
        return {"status": "UNKNOWN_ERROR", "error_message": str(e)}


@app.get("/health")
def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "ai-trainer-youtube-api"}


@app.get("/categories")
def get_categories():
    """Get available workout categories"""
    return {
        "categories": [
            {"key": "all", "name": "All Workouts", "emoji": "🏃‍♂️"},
            {"key": "cardio", "name": "Cardio", "emoji": "❤️"},
            {"key": "strength", "name": "Strength", "emoji": "💪"},
            {"key": "yoga", "name": "Yoga", "emoji": "🧘‍♀️"},
            {"key": "hiit", "name": "HIIT", "emoji": "⚡"},
        ]
    }


@app.get("/videos")
def get_videos(
    category: str = Query("all", description="Workout category"),
    limit: int = Query(20, ge=1, le=50, description="Max videos to return")
):
    """Get workout videos for a category"""

    # Normalize category
    category = category.lower()
    if category not in CATEGORY_VIDEOS:
        raise HTTPException(status_code=400, detail=f"Invalid category: {category}")

    cache_key = f"videos:{category}:{limit}"
    cached = _cache_get(cache_key)
    if cached:
        return cached

    videos = []
    query = CATEGORY_QUERIES.get(category)
    if query:
        videos = fetch_videos_by_search(query, limit)

    if not videos:
        video_ids = CATEGORY_VIDEOS[category][:limit]  # Limit the video IDs
        videos = fetch_videos_by_ids(video_ids)

    result = {
        "category": category,
        "total": len(videos),
        "videos": videos
    }

    _cache_set(cache_key, result)
    return result


@app.get("/video/{video_id}")
def get_video_details(video_id: str):
    """Get detailed information for a specific video"""
    try:
        videos_request = youtube.videos().list(
            part="snippet,contentDetails,statistics",
            id=video_id
        )
        response = videos_request.execute()

        if not response.get("items"):
            raise HTTPException(status_code=404, detail="Video not found")

        item = response["items"][0]
        snippet = item["snippet"]
        content_details = item["contentDetails"]
        statistics = item.get("statistics", {})

        duration_seconds = _parse_iso8601_duration(content_details.get("duration", ""))

        return {
            "id": video_id,
            "title": snippet["title"],
            "instructor": snippet["channelTitle"],
            "duration": duration_seconds // 60,
            "formattedDuration": _format_duration(duration_seconds),
            "difficulty": _determine_difficulty(snippet["title"], duration_seconds),
            "thumbnailURL": snippet["thumbnails"]["high"]["url"],
            "viewCount": int(statistics.get("viewCount", 0)),
            "likeCount": int(statistics.get("likeCount", 0)),
            "description": snippet.get("description", ""),
            "embedURL": f"https://www.youtube-nocookie.com/embed/{video_id}",
            "youtubeURL": f"https://www.youtube.com/watch?v={video_id}",
            "publishedAt": snippet.get("publishedAt")
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching video: {e}")


@app.get("/gyms/nearby")
def get_nearby_gyms(
    lat: float = Query(..., description="Latitude"),
    lng: float = Query(..., description="Longitude"),
    radius: int = Query(5000, ge=100, le=50000, description="Search radius in meters"),
    keyword: Optional[str] = Query(None, description="Optional keyword filter"),
):
    """Proxy to Google Places Nearby Search for gyms."""
    params: Dict[str, str] = {
        "location": f"{lat},{lng}",
        "radius": str(radius),
        "type": "gym",
    }
    if keyword:
        params["keyword"] = keyword
    return _places_request("nearbysearch", params)


@app.get("/gyms/search")
def search_gyms(
    query: str = Query(..., description="Search text"),
    lat: Optional[float] = Query(None, description="Optional latitude"),
    lng: Optional[float] = Query(None, description="Optional longitude"),
):
    """Proxy to Google Places Text Search for gyms."""
    trimmed = query.strip()
    if not trimmed:
        raise HTTPException(status_code=400, detail="Query must not be empty")

    params: Dict[str, str] = {"query": f"gym near {trimmed}"}
    if lat is not None and lng is not None:
        params["location"] = f"{lat},{lng}"
        params["radius"] = "10000"
    return _places_request("textsearch", params)


@app.get("/gyms/photo")
def get_gym_photo(
    ref: str = Query(..., description="Google Places photo reference"),
    maxwidth: int = Query(400, ge=100, le=1600, description="Photo max width"),
):
    """Proxy Google Places photo to avoid exposing API key to clients."""
    if not PLACES_API_KEY:
        raise HTTPException(status_code=500, detail="Missing GOOGLE_PLACES_API_KEY")

    params = urllib.parse.urlencode(
        {"maxwidth": str(maxwidth), "photoreference": ref, "key": PLACES_API_KEY}
    )
    url = f"https://maps.googleapis.com/maps/api/place/photo?{params}"
    request = urllib.request.Request(url, headers={"User-Agent": "ai-trainer-backend"})

    try:
        ssl_context = ssl.create_default_context(cafile=certifi.where())
        with urllib.request.urlopen(request, timeout=10, context=ssl_context) as response:
            data = response.read()
            content_type = response.headers.get("Content-Type", "image/jpeg")
        return Response(content=data, media_type=content_type)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Photo fetch failed: {e}")


@app.get("/coach/health")
def coach_health_check():
    """Health check for the AI coach backend."""
    return {"status": "healthy", "service": "ai-coach"}


@app.post("/coach/chat", response_model=CoachChatResponse)
def coach_chat(payload: CoachChatRequest):
    """Chat with the AI coach using the agent graph."""
    graph, preload_fn = _get_agent_graph()
    thread_id = payload.thread_id or f"user:{payload.user_id}"
    config = {"configurable": {"thread_id": thread_id}}

    if thread_id not in _AGENT_PRELOADED:
        preload_fn(payload.user_id)
        _AGENT_PRELOADED.add(thread_id)

    try:
        state = graph.invoke(
            {
                "messages": [HumanMessage(content=payload.message)],
            },
            config,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Coach error: {exc}") from exc

    graph_state = graph.get_state(config)
    reply = state["messages"][-1].content if state.get("messages") else ""
    if graph_state.next and "human_feedback" in graph_state.next:
        plan_data = _extract_plan_from_messages(state.get("messages", []))
        if plan_data.get("proposed_plan"):
            _PENDING_PLANS[thread_id] = plan_data["proposed_plan"]
        return CoachChatResponse(
            reply=reply or (plan_data.get("plan_text") or ""),
            thread_id=thread_id,
            requires_feedback=True,
            plan_text=plan_data.get("plan_text"),
        )
    return CoachChatResponse(reply=reply, thread_id=thread_id)


@app.post("/coach/feedback", response_model=CoachFeedbackResponse)
def coach_feedback(payload: CoachFeedbackRequest):
    """Submit human feedback for a proposed plan."""
    graph, _ = _get_agent_graph()
    config = {"configurable": {"thread_id": payload.thread_id}}
    try:
        proposed_plan = _PENDING_PLANS.get(payload.thread_id)
        graph.update_state(
            config,
            {"approve_plan": payload.approve_plan, "proposed_plan": proposed_plan},
            as_node="human_feedback",
        )
        if payload.thread_id in _PENDING_PLANS:
            _PENDING_PLANS.pop(payload.thread_id, None)
        state = graph.invoke(None, config)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Coach feedback error: {exc}") from exc
    reply = state["messages"][-1].content if state.get("messages") else ""
    return CoachFeedbackResponse(reply=reply, thread_id=payload.thread_id)


@app.post("/food/scan", response_model=FoodScanResponse)
async def scan_food(file: UploadFile = File(...)):
    """Analyze a meal photo and return detected foods and macros."""
    if file is None:
        raise HTTPException(status_code=400, detail="Missing image file")
    image = await file.read()
    model = _get_gemini_model()
    encoded = base64.b64encode(image).decode("utf-8")
    prompt = (
        "You are a nutrition assistant. Analyze the meal photo and return JSON only. "
        "Include a short food_name, overall totals, and line items with amounts. "
        "Use this schema:\n"
        "{"
        "\"food_name\": string,"
        "\"total_calories\": number,"
        "\"protein_g\": number,"
        "\"carbs_g\": number,"
        "\"fat_g\": number,"
        "\"confidence\": number,"
        "\"items\": ["
        "{"
        "\"name\": string,"
        "\"amount\": string,"
        "\"calories\": number,"
        "\"protein_g\": number,"
        "\"carbs_g\": number,"
        "\"fat_g\": number,"
        "\"confidence\": number"
        "}"
        "]"
        "}"
    )
    prompt = "Return strictly valid JSON. No markdown. " + prompt
    image_obj = Image.open(io.BytesIO(image))
    response = model.generate_content(
        [prompt, image_obj],
        generation_config={"temperature": 0.2},
    )
    content = getattr(response, "text", "") or ""
    payload = _safe_parse_json(content)
    if not payload:
        raise HTTPException(status_code=502, detail="Failed to parse AI response")
    items = payload.get("items", []) or []
    if not payload.get("total_calories"):
        payload["total_calories"] = sum(int(item.get("calories", 0)) for item in items)
    return FoodScanResponse(**payload)


@app.post("/food/logs")
def log_food(payload: FoodLogRequest):
    """Persist a scanned meal log."""
    _store_meal_log(payload)
    return {"status": "ok"}


@app.get("/food/intake", response_model=DailyIntakeResponse)
def get_daily_intake(user_id: int = 1, day: Optional[str] = None):
    """Return daily calorie intake totals for a user."""
    target_day = day or date.today().isoformat()
    start = f"{target_day}T00:00:00"
    end = f"{target_day}T23:59:59"
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT calories, protein_g, carbs_g, fat_g
            FROM meal_logs
            WHERE user_id = ? AND logged_at BETWEEN ? AND ?
            """,
            (user_id, start, end),
        )
        rows = cur.fetchall()
    total_calories = sum(row[0] for row in rows)
    total_protein = sum(row[1] for row in rows)
    total_carbs = sum(row[2] for row in rows)
    total_fat = sum(row[3] for row in rows)
    return DailyIntakeResponse(
        date=target_day,
        total_calories=total_calories,
        total_protein_g=total_protein,
        total_carbs_g=total_carbs,
        total_fat_g=total_fat,
        meals_count=len(rows),
    )


@app.get("/food/logs", response_model=DailyMealLogsResponse)
def get_food_logs(user_id: int = 1, day: Optional[str] = None):
    """Return logged meals for a specific day."""
    target_day = day or date.today().isoformat()
    start = f"{target_day}T00:00:00"
    end = f"{target_day}T23:59:59"
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT description, calories, protein_g, carbs_g, fat_g, logged_at
            FROM meal_logs
            WHERE user_id = ? AND logged_at BETWEEN ? AND ?
            ORDER BY logged_at DESC
            """,
            (user_id, start, end),
        )
        rows = cur.fetchall()
    meals = [
        MealLogItem(
            name=row[0] or "Meal",
            calories=row[1],
            protein_g=row[2],
            carbs_g=row[3],
            fat_g=row[4],
            logged_at=row[5],
        )
        for row in rows
    ]
    return DailyMealLogsResponse(date=target_day, meals=meals)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)