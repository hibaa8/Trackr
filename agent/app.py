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
import sys
import time
import uuid
from datetime import date, datetime
from typing import Any, Dict, List, Optional

_ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if _ROOT_DIR not in sys.path:
    sys.path.insert(0, _ROOT_DIR)
_ROOT_ENV_PATH = os.path.join(_ROOT_DIR, ".env")
_ENV_PATH = os.path.join(os.path.dirname(__file__), ".env")

import certifi
import json
import urllib.parse
import urllib.request

from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, Query, UploadFile
from openai import OpenAI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from googleapiclient.discovery import build
import google.generativeai as genai
from langchain_core.messages import HumanMessage, ToolMessage
from PIL import Image
from pydantic import BaseModel

from agent.state import SESSION_CACHE
from agent.redis.cache import _redis_set_json

from config.constants import DB_PATH
from agent.db.connection import get_db_conn
from agent.plan.plan_generation import _build_plan_data
from agent.tools.plan_tools import _set_active_plan_cache
load_dotenv(dotenv_path=_ROOT_ENV_PATH)
load_dotenv(dotenv_path=_ENV_PATH)
YOUTUBE_API_KEY = os.getenv("YOUTUBE_API_KEY", "")
PLACES_API_KEY = os.getenv("GOOGLE_PLACES_API_KEY", "")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
TAVILY_API_KEY = os.getenv("TAVILY_API_KEY", "")
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
openai_client = OpenAI()

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
        if "gemini-2.5-flash" in name:
            return name
    if models:
        return getattr(models[0], "name", "gemini-2.5-flash")
    return "gemini-2.5-flash"


def _get_gemini_model():
    global _GEMINI_MODEL
    if _GEMINI_MODEL is None:
        if not GEMINI_API_KEY:
            raise RuntimeError("Missing GEMINI_API_KEY env var")
        genai.configure(api_key=GEMINI_API_KEY)
        model_name = _resolve_gemini_model_name()
        print(f"🔄 Initializing Gemini model: {model_name}")  # Debug log
        _GEMINI_MODEL = genai.GenerativeModel(model_name)
    return _GEMINI_MODEL

def _reset_gemini_model():
    global _GEMINI_MODEL
    _GEMINI_MODEL = None


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


def _extract_ingredients_from_image(image_bytes: bytes) -> List[str]:
    prompt = (
        "Identify the ingredients in the photo and return JSON only with this schema: "
        "{\"ingredients\":[\"string\", ...]}. No markdown."
    )
    content = _gemini_generate_content(prompt, image_bytes=image_bytes, temperature=0.1)
    payload = _safe_parse_json(content)
    ingredients = payload.get("ingredients", []) if isinstance(payload, dict) else []
    return [item.strip() for item in ingredients if isinstance(item, str) and item.strip()]


def _categorize_food_name(food_name: str) -> str:
    name = (food_name or "").lower()
    if any(k in name for k in ["chicken", "beef", "fish", "egg", "pork"]):
        return "protein"
    if any(k in name for k in ["salad", "lettuce", "broccoli", "spinach"]):
        return "vegetable"
    if any(k in name for k in ["apple", "banana", "orange", "berry"]):
        return "fruit"
    if any(k in name for k in ["rice", "bread", "pasta", "noodle"]):
        return "grain"
    if any(k in name for k in ["milk", "yogurt", "cheese"]):
        return "dairy"
    if any(k in name for k in ["nut", "almond", "peanut"]):
        return "nuts"
    if any(k in name for k in ["cake", "cookie", "dessert"]):
        return "dessert"
    if any(k in name for k in ["coffee", "tea", "juice", "soda"]):
        return "beverage"
    if any(k in name for k in ["burger", "pizza", "fries"]):
        return "fast_food"
    if any(k in name for k in ["soup", "broth"]):
        return "soup"
    if any(k in name for k in ["bowl", "plate", "mix"]):
        return "mixed"
    return "other"


def _gemini_generate_content(
    prompt: str,
    image_bytes: Optional[bytes] = None,
    temperature: float = 0.2,
) -> str:
    """Call Gemini via REST to avoid gRPC DNS issues."""
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="Missing GEMINI_API_KEY")
    model_name = _resolve_gemini_model_name()
    if not model_name.startswith("models/"):
        model_name = f"models/{model_name}"
    url = f"https://generativelanguage.googleapis.com/v1beta/{model_name}:generateContent?key={GEMINI_API_KEY}"
    parts: List[Dict[str, Any]] = [{"text": prompt}]
    if image_bytes:
        encoded = base64.b64encode(image_bytes).decode("utf-8")
        parts.append(
            {
                "inline_data": {
                    "mime_type": "image/jpeg",
                    "data": encoded,
                }
            }
        )
    payload = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"temperature": temperature},
    }
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
    )
    try:
        ssl_context = ssl.create_default_context(cafile=certifi.where())
        with urllib.request.urlopen(request, timeout=30, context=ssl_context) as response:
            result = json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Gemini request failed: {exc}") from exc

    candidates = result.get("candidates", []) if isinstance(result, dict) else []
    if not candidates:
        return ""
    parts = candidates[0].get("content", {}).get("parts", [])
    texts = [p.get("text", "") for p in parts if isinstance(p, dict) and p.get("text")]
    return "\n".join(texts).strip()


def _tavily_search(query: str, max_results: int = 6) -> List[Dict[str, Any]]:
    """Consolidated Tavily search with images."""
    if not TAVILY_API_KEY:
        raise HTTPException(status_code=500, detail="Missing TAVILY_API_KEY")
    payload = {
        "api_key": TAVILY_API_KEY,
        "query": query,
        "search_depth": "basic",
        "max_results": max(1, min(max_results, 10)),
        "include_images": True,
    }
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        "https://api.tavily.com/search",
        data=data,
        headers={"Content-Type": "application/json", "User-Agent": "ai-trainer-backend"},
    )
    ssl_context = ssl.create_default_context(cafile=certifi.where())
    with urllib.request.urlopen(request, timeout=15, context=ssl_context) as response:
        result = json.loads(response.read().decode("utf-8"))
    return result.get("results", []) or []


def _extract_og_image(url: str) -> Optional[str]:
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "ai-trainer-backend"})
        ssl_context = ssl.create_default_context(cafile=certifi.where())
        with urllib.request.urlopen(request, timeout=6, context=ssl_context) as response:
            html = response.read(200_000).decode("utf-8", errors="ignore")
        match = re.search(
            r'property=["\']og:image["\']\s*content=["\']([^"\']+)["\']',
            html,
            flags=re.IGNORECASE,
        )
        if not match:
            match = re.search(
                r'name=["\']twitter:image["\']\s*content=["\']([^"\']+)["\']',
                html,
                flags=re.IGNORECASE,
            )
        return match.group(1) if match else None
    except Exception:
        return None


def _store_meal_log(payload: FoodLogRequest) -> None:
    logged_at = payload.logged_at or datetime.now().isoformat(timespec="seconds")
    description = payload.food_name
    with get_db_conn() as conn:
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


def _load_user_profile(user_id: int) -> Dict[str, Any]:
    def _map_user(row: Optional[tuple]) -> Optional[Dict[str, Any]]:
        if not row:
            return None
        return {
            "id": row[0],
            "name": row[1],
            "birthdate": row[2],
            "height_cm": row[3],
            "weight_kg": row[4],
            "gender": row[5],
            "age_years": row[6],
            "agent_name": row[7],
        }

    def _map_prefs(row: Optional[tuple]) -> Optional[Dict[str, Any]]:
        if not row:
            return None
        return {
            "weekly_weight_change_kg": row[0],
            "activity_level": row[1],
            "goal_type": row[2],
            "target_weight_kg": row[3],
            "dietary_preferences": row[4],
            "workout_preferences": row[5],
            "timezone": row[6],
            "created_at": row[7],
        }

    try:
        from db.connection import get_db_conn
        from db import queries

        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute(queries.SELECT_USER_PROFILE, (user_id,))
            user_row = cur.fetchone()
            cur.execute(queries.SELECT_USER_PREFS, (user_id,))
            pref_row = cur.fetchone()
        if user_row or pref_row:
            return {"user": _map_user(user_row), "preferences": _map_prefs(pref_row)}
    except Exception:
        pass

    try:
        with sqlite3.connect(DB_PATH) as conn:
            cur = conn.cursor()
            cur.execute(
                "SELECT id, name, birthdate, height_cm, weight_kg, gender FROM users WHERE id = ?",
                (user_id,),
            )
            user_row = cur.fetchone()
            cur.execute(
                """
                SELECT weekly_weight_change_kg, activity_level, goal_type, target_weight_kg,
                       dietary_preferences, workout_preferences, timezone, created_at
                FROM user_preferences
                WHERE user_id = ?
                """,
                (user_id,),
            )
            pref_row = cur.fetchone()
        return {"user": _map_user(user_row), "preferences": _map_prefs(pref_row)}
    except sqlite3.Error:
        return {"user": None, "preferences": None}


def _list_checkins(user_id: int) -> List[Dict[str, Any]]:
    try:
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT checkin_date, weight_kg, mood, notes
                FROM checkins
                WHERE user_id = ?
                ORDER BY checkin_date DESC
                """,
                (user_id,),
            )
            rows = cur.fetchall()
        return [
            {"date": row[0], "weight_kg": row[1], "mood": row[2], "notes": row[3]}
            for row in rows
        ]
    except Exception:
        return []


def _list_workout_sessions(user_id: int) -> List[Dict[str, Any]]:
    try:
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT id, date, workout_type, duration_min, calories_burned, notes, completed, source
                FROM workout_sessions
                WHERE user_id = ?
                ORDER BY date DESC
                """,
                (user_id,),
            )
            rows = cur.fetchall()
        sessions = []
        for row in rows:
            notes = row[5]
            details = _safe_parse_json(notes) if isinstance(notes, str) else None
            sessions.append(
                {
                    "id": row[0],
                    "date": row[1],
                    "workout_type": row[2],
                    "duration_min": row[3],
                    "calories_burned": row[4],
                    "completed": bool(row[6]),
                    "source": row[7],
                    "details": details,
                }
            )
        return sessions
    except Exception:
        return []


def _list_meal_logs(user_id: int) -> List[Dict[str, Any]]:
    try:
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT id, logged_at, photo_path, description, calories, protein_g, carbs_g, fat_g, confidence, confirmed
                FROM meal_logs
                WHERE user_id = ?
                ORDER BY logged_at DESC
                """,
                (user_id,),
            )
            rows = cur.fetchall()
        meals = []
        for row in rows:
            meals.append(
                {
                    "id": row[0],
                    "logged_at": row[1],
                    "photo_path": row[2],
                    "photo_url": None,
                    "description": row[3],
                    "calories": row[4],
                    "protein_g": row[5],
                    "carbs_g": row[6],
                    "fat_g": row[7],
                    "confidence": row[8],
                    "confirmed": bool(row[9]),
                }
            )
        return meals
    except Exception:
        return []


def _derive_suggestion_from_status(payload: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    status = payload.get("status") if isinstance(payload, dict) else None
    if status in {"on_track", "insufficient_data"}:
        return None
    goal_type = payload.get("goal_type")
    suggestion_text = payload.get("explanation") or "Review your recent progress and adjust."
    rationale = f"Status: {status}. Goal: {goal_type}."
    return {
        "suggestion_type": "plan_adjustment",
        "rationale": rationale,
        "suggestion_text": suggestion_text,
        "status": "generated",
        "created_at": datetime.now().isoformat(timespec="seconds"),
    }


class CoachChatRequest(BaseModel):
    message: str
    user_id: int
    thread_id: Optional[str] = None
    agent_id: Optional[str] = None


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
    category: Optional[str] = None
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
    daily_calorie_target: Optional[int] = None


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


class PlanDayResponse(BaseModel):
    date: str
    workout_plan: str
    rest_day: bool
    calorie_target: int
    protein_g: int
    carbs_g: int
    fat_g: int


class RecipeSuggestRequest(BaseModel):
    user_id: int = 1
    ingredients: str = ""
    cuisine: Optional[str] = None
    flavor: Optional[str] = None
    dietary: List[str] = []
    image_base64: Optional[str] = None


class RecipeSuggestion(BaseModel):
    id: str
    name: str
    summary: str
    calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    ingredients: List[str]
    steps: List[str]
    tags: List[str] = []


class RecipeSuggestResponse(BaseModel):
    recipes: List[RecipeSuggestion]
    detected_ingredients: List[str] = []


class OnboardingCompletePayload(BaseModel):
    user_id: Optional[int] = None
    current_weight_kg: Optional[float] = None
    height_cm: Optional[float] = None
    age: Optional[int] = None
    goal_type: Optional[str] = None
    timeframe_weeks: Optional[float] = None
    weekly_weight_change_kg: Optional[float] = None
    trainer: Optional[str] = None
    full_name: Optional[str] = None


class RecipeSearchRequest(BaseModel):
    query: str
    ingredients: Optional[str] = None
    cuisine: Optional[str] = None
    flavor: Optional[str] = None
    dietary: List[str] = []
    max_results: int = 6


class RecipeSearchResult(BaseModel):
    id: str
    title: str
    url: str
    summary: str
    image_url: Optional[str] = None
    source: Optional[str] = None


class RecipeSearchResponse(BaseModel):
    results: List[RecipeSearchResult]
    detected_ingredients: List[str] = []




class RecipeImageRequest(BaseModel):
    prompt: str
    width: int = 1024
    height: int = 768


class RecipeImageResponse(BaseModel):
    image_url: str

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

    if payload.agent_id:
        SESSION_CACHE.setdefault(payload.user_id, {})["agent_id"] = payload.agent_id

    if thread_id not in _AGENT_PRELOADED:
        preload_fn(payload.user_id)
        _AGENT_PRELOADED.add(thread_id)

    try:
        state = graph.invoke(
            {
                "messages": [HumanMessage(content=payload.message)],
                "user_id": payload.user_id,
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
    content = _gemini_generate_content(prompt, image_bytes=image, temperature=0.2)
    payload = _safe_parse_json(content)
    if not payload:
        raise HTTPException(status_code=502, detail="Failed to parse AI response")
    items = payload.get("items", []) or []
    if isinstance(items, list):
        for item in items:
            if isinstance(item, dict) and not item.get("category"):
                item["category"] = _categorize_food_name(item.get("name", ""))
    if not payload.get("total_calories"):
        payload["total_calories"] = sum(int(item.get("calories", 0)) for item in items)
    return FoodScanResponse(**payload)


@app.post("/recipes/suggest", response_model=RecipeSuggestResponse)
def suggest_recipes(payload: RecipeSuggestRequest):
    ingredients_text = (payload.ingredients or "").strip()
    if not ingredients_text and not payload.image_base64:
        raise HTTPException(status_code=400, detail="Provide ingredients text or an image.")

    detected_ingredients: List[str] = []
    if payload.image_base64:
        try:
            image_bytes = base64.b64decode(payload.image_base64)
            detected_ingredients = _extract_ingredients_from_image(image_bytes)
        except Exception as exc:
            raise HTTPException(status_code=400, detail=f"Invalid image data: {exc}") from exc

    typed_ingredients = [
        item.strip()
        for item in re.split(r"[,\n;]", ingredients_text)
        if item.strip()
    ]
    combined = list(dict.fromkeys(typed_ingredients + detected_ingredients))

    plan_context: Dict[str, Any] = {}
    try:
        from agent.tools.plan_tools import _get_active_plan_bundle_data

        bundle = _get_active_plan_bundle_data(payload.user_id, allow_db_fallback=True)
        plan_row = bundle.get("plan")
        if isinstance(plan_row, tuple) and len(plan_row) >= 8:
            plan_context["daily_calorie_target"] = plan_row[3]
            plan_context["protein_g"] = plan_row[4]
            plan_context["carbs_g"] = plan_row[5]
            plan_context["fat_g"] = plan_row[6]
        today_key = date.today().isoformat()
        plan_day = next((d for d in bundle.get("plan_days", []) if d.get("date") == today_key), None)
        if plan_day:
            plan_context["workout_plan"] = plan_day.get("workout_plan")
            plan_context["rest_day"] = plan_day.get("rest_day")
            plan_context["calorie_target"] = plan_day.get("calorie_target")
    except Exception:
        plan_context = {}

    calorie_target = plan_context.get("calorie_target") or plan_context.get("daily_calorie_target") or 2000
    per_meal_target = int(max(350, min(900, calorie_target * 0.3)))
    workout_label = plan_context.get("workout_plan") or "Unknown"

    prompt = (
        "You are a nutrition coach and recipe creator. Generate 3 healthy recipes. "
        "Return strictly valid JSON with this schema:\n"
        "{"
        "\"recipes\":[{"
        "\"id\":string,"
        "\"name\":string,"
        "\"summary\":string,"
        "\"calories\":number,"
        "\"protein_g\":number,"
        "\"carbs_g\":number,"
        "\"fat_g\":number,"
        "\"ingredients\":[string],"
        "\"steps\":[string],"
        "\"tags\":[string]"
        "}],"
        "\"detected_ingredients\":[string]"
        "}\n"
        "Use the provided ingredients if possible and allow pantry staples. "
        "Keep each recipe around "
        f"{per_meal_target} calories. "
        f"Workout plan today: {workout_label}. "
        f"Cuisine preference: {payload.cuisine or 'Any'}. "
        f"Flavor preference: {payload.flavor or 'Any'}. "
        f"Dietary preferences: {', '.join(payload.dietary) if payload.dietary else 'None'}. "
        f"Available ingredients: {', '.join(combined) if combined else 'None provided'}."
    )

    content = _gemini_generate_content(prompt, temperature=0.3)
    payload_json = _safe_parse_json(content)
    recipes_raw = payload_json.get("recipes", []) if isinstance(payload_json, dict) else []
    recipes = []
    for item in recipes_raw:
        if not isinstance(item, dict):
            continue
        item["id"] = item.get("id") or str(uuid.uuid4())
        recipes.append(item)

    return RecipeSuggestResponse(
        recipes=[RecipeSuggestion(**item) for item in recipes],
        detected_ingredients=payload_json.get("detected_ingredients", []) or detected_ingredients,
    )


@app.post("/recipes/search", response_model=RecipeSearchResponse)
def search_recipes(payload: RecipeSearchRequest):
    trimmed = payload.query.strip()
    if not trimmed:
        raise HTTPException(status_code=400, detail="Query must not be empty")

    filters = []
    if payload.ingredients:
        filters.append(f"ingredients: {payload.ingredients}")
    if payload.cuisine:
        filters.append(f"cuisine: {payload.cuisine}")
    if payload.flavor:
        filters.append(f"flavor: {payload.flavor}")
    if payload.dietary:
        filters.append(f"dietary: {', '.join(payload.dietary)}")

    full_query = trimmed
    if filters:
        full_query = f"{trimmed} ({'; '.join(filters)})"
    full_query = f"healthy recipe {full_query}"

    try:
        results = _tavily_search(full_query, payload.max_results)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Tavily search failed: {exc}") from exc

    parsed = []
    for item in results:
        if not isinstance(item, dict):
            continue
        url = item.get("url") or ""
        title = item.get("title") or "Recipe"
        summary = item.get("content") or item.get("snippet") or ""
        image_url = item.get("image")
        if not image_url:
            images = item.get("images") or []
            if isinstance(images, list) and images:
                image_url = images[0]
        source = None
        if url:
            try:
                source = urllib.parse.urlparse(url).netloc.replace("www.", "")
            except Exception:
                source = None
        parsed.append(
            RecipeSearchResult(
                id=str(uuid.uuid4()),
                title=title,
                url=url,
                summary=summary.strip(),
                image_url=image_url,
                source=source,
            )
        )

    return RecipeSearchResponse(results=parsed, detected_ingredients=[])


@app.post("/recipes/image", response_model=RecipeImageResponse)
def generate_recipe_image(payload: RecipeImageRequest):
    """
    Generate a recipe image using Unsplash as a fallback.
    Gemini's Imagen API requires separate setup, so we use a reliable image source.
    """
    try:
        # Use Unsplash as a reliable source for food photography
        query = payload.prompt.replace(" food photography", "").strip()
        encoded = urllib.parse.quote(query)
        image_url = f"https://source.unsplash.com/800x600/?{encoded},food"
        return RecipeImageResponse(image_url=image_url)
    except Exception as exc:
        # Fallback to a generic food image
        return RecipeImageResponse(image_url="https://source.unsplash.com/800x600/?healthy,food")


@app.post("/food/logs")
def log_food(payload: FoodLogRequest):
    """Persist a scanned meal log."""
    _store_meal_log(payload)
    return {"status": "ok"}


@app.post("/api/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    if not file:
        raise HTTPException(status_code=400, detail="Missing audio file")
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty audio file")
    try:
        response = openai_client.audio.transcriptions.create(
            model="gpt-4o-mini-transcribe",
            file=(file.filename or "audio.m4a", data, file.content_type or "audio/m4a"),
        )
        return {"text": response.text}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Transcription failed: {exc}") from exc


@app.get("/food/intake", response_model=DailyIntakeResponse)
def get_daily_intake(user_id: int = 1, day: Optional[str] = None):
    """Return daily calorie intake totals for a user."""
    target_day = day or date.today().isoformat()
    start = f"{target_day}T00:00:00"
    end = f"{target_day}T23:59:59"
    with get_db_conn() as conn:
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
    daily_target = None
    try:
        from agent.tools.plan_tools import _get_active_plan_bundle_data

        bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
        plan_row = bundle.get("plan")
        if isinstance(plan_row, tuple) and len(plan_row) >= 4:
            daily_target = plan_row[3]
        elif isinstance(plan_row, dict):
            daily_target = plan_row.get("daily_calorie_target")
        plan_day = next((d for d in bundle.get("plan_days", []) if d.get("date") == target_day), None)
        if plan_day and plan_day.get("calorie_target") is not None:
            daily_target = plan_day.get("calorie_target")
    except Exception:
        daily_target = None
    return DailyIntakeResponse(
        date=target_day,
        total_calories=total_calories,
        total_protein_g=total_protein,
        total_carbs_g=total_carbs,
        total_fat_g=total_fat,
        meals_count=len(rows),
        daily_calorie_target=daily_target,
    )


@app.get("/food/logs", response_model=DailyMealLogsResponse)
def get_food_logs(user_id: int = 1, day: Optional[str] = None):
    """Return logged meals for a specific day."""
    target_day = day or date.today().isoformat()
    start = f"{target_day}T00:00:00"
    end = f"{target_day}T23:59:59"
    with get_db_conn() as conn:
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


@app.get("/plans/today", response_model=PlanDayResponse)
def get_today_plan(user_id: int = 1, day: Optional[str] = None):
    """Return the active plan day for a specific date (defaults to today)."""
    from agent.tools.plan_tools import _get_active_plan_bundle_data

    target_day = day or date.today().isoformat()
    bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
    plan_days = bundle.get("plan_days", []) if isinstance(bundle, dict) else []
    day_data = next((d for d in plan_days if d.get("date") == target_day), None)
    if not day_data:
        raise HTTPException(status_code=404, detail="No plan found for requested day")

    workout_plan = day_data.get("workout_plan") or day_data.get("workout") or "Workout"
    if workout_plan == "Workout":
        raw = day_data.get("workout_raw")
        if raw:
            workout_plan = str(raw)
    return PlanDayResponse(
        date=day_data.get("date", target_day),
        workout_plan=workout_plan,
        rest_day=bool(day_data.get("rest_day")),
        calorie_target=int(day_data.get("calorie_target") or 0),
        protein_g=int(day_data.get("protein_g") or 0),
        carbs_g=int(day_data.get("carbs_g") or 0),
        fat_g=int(day_data.get("fat_g") or 0),
    )


@app.get("/api/profile")
def get_profile(user_id: int = 1):
    """Return user profile and preferences."""
    return _load_user_profile(user_id)


def _refresh_profile_cache(user_id: int) -> None:
    try:
        profile = _load_user_profile(user_id)
        _redis_set_json(f"user:{user_id}:profile", profile, ttl_seconds=CACHE_TTL_LONG)
        SESSION_CACHE.setdefault(user_id, {})["context"] = profile
    except Exception:
        pass


@app.get("/api/user-id")
def get_user_id(email: str):
    """Lookup user id by email."""
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT id FROM users WHERE email = ?", (email,))
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="User not found")
    return {"user_id": row[0]}


@app.get("/api/progress")
def get_progress(user_id: int = 1):
    """Return progress data (checkins, plan, meals, workouts)."""
    try:
        from agent.tools.plan_tools import _get_active_plan_bundle_data

        plan_bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
        plan = plan_bundle.get("plan")
        checkpoints = plan_bundle.get("checkpoints", [])
    except Exception:
        plan = None
        checkpoints = []
    return {
        "checkins": _list_checkins(user_id),
        "checkpoints": checkpoints,
        "plan": plan,
        "meals": _list_meal_logs(user_id),
        "workouts": _list_workout_sessions(user_id),
    }


@app.get("/api/coach-suggestion")
def get_coach_suggestion(user_id: int = 1):
    """Return a coach suggestion derived from plan status."""
    suggestion = None
    try:
        from agent.tools.plan_tools import compute_plan_status

        status_raw = compute_plan_status.func(user_id)
        payload = _safe_parse_json(status_raw)
        if payload:
            suggestion = _derive_suggestion_from_status(payload)
    except Exception:
        suggestion = None
    return {"suggestion": suggestion}


@app.get("/api/health")
def health_check():
    try:
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT 1")
            cur.fetchone()
            using_sqlite = conn._adapt_query is False
        return {"ok": True, "db": "sqlite" if using_sqlite else "postgres"}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


def _activate_plan_from_data(user_id: int, plan_data: dict[str, Any]) -> None:
    cache_days = []
    for day in plan_data["plan_days"]:
        cache_day = dict(day)
        if "workout_plan" not in cache_day and cache_day.get("workout"):
            cache_day["workout_plan"] = cache_day["workout"]
        cache_days.append(cache_day)
    cache_bundle = {
        "plan": {
            "id": None,
            "start_date": plan_data["start_date"],
            "end_date": plan_data["end_date"],
            "daily_calorie_target": plan_data["calorie_target"],
            "protein_g": plan_data["macros"]["protein_g"],
            "carbs_g": plan_data["macros"]["carbs_g"],
            "fat_g": plan_data["macros"]["fat_g"],
            "status": "active",
        },
        "plan_days": cache_days,
        "checkpoints": plan_data.get("checkpoints", []),
    }
    _set_active_plan_cache(user_id, cache_bundle)
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("UPDATE plan_templates SET status = 'inactive' WHERE user_id = ?", (user_id,))
        cur.execute("SELECT timezone FROM user_preferences WHERE user_id = ?", (user_id,))
        pref_row = cur.fetchone()
        timezone = pref_row[0] if pref_row else None
        cycle_length = min(7, len(plan_data["plan_days"]))
        cur.execute(
            """
            INSERT INTO plan_templates (
                user_id, start_date, end_date, daily_calorie_target, protein_g, carbs_g, fat_g,
                status, cycle_length_days, timezone, default_calories, default_protein_g,
                default_carbs_g, default_fat_g, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            RETURNING id
            """,
            (
                user_id,
                plan_data["start_date"],
                plan_data["end_date"],
                plan_data["calorie_target"],
                plan_data["macros"]["protein_g"],
                plan_data["macros"]["carbs_g"],
                plan_data["macros"]["fat_g"],
                "active",
                cycle_length,
                timezone,
                plan_data["calorie_target"],
                plan_data["macros"]["protein_g"],
                plan_data["macros"]["carbs_g"],
                plan_data["macros"]["fat_g"],
                datetime.now().isoformat(timespec="seconds"),
            ),
        )
        template_id = cur.fetchone()[0]
        for day_index in range(cycle_length):
            day = plan_data["plan_days"][day_index]
            workout_json = json.dumps({"label": day["workout"]})
            calorie_delta = day["calorie_target"] - plan_data["calorie_target"]
            cur.execute(
                """
                INSERT INTO plan_template_days (
                    template_id, day_index, workout_json, calorie_delta, notes
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    template_id,
                    day_index,
                    workout_json,
                    calorie_delta,
                    None,
                ),
            )
        for checkpoint in plan_data.get("checkpoints", []):
            cur.execute(
                """
                INSERT INTO plan_checkpoints (
                    template_id, checkpoint_week, expected_weight_kg, min_weight_kg, max_weight_kg
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    template_id,
                    checkpoint["week"],
                    checkpoint["expected_weight_kg"],
                    checkpoint["min_weight_kg"],
                    checkpoint["max_weight_kg"],
                ),
            )
        conn.commit()


def _generate_plan_for_user(
    user_id: int,
    goal_type: Optional[str] = None,
    timeframe_weeks: Optional[float] = None,
    weekly_change_kg: Optional[float] = None,
) -> Optional[dict[str, Any]]:
    days = 28
    if timeframe_weeks:
        try:
            days = int(float(timeframe_weeks) * 7)
        except (TypeError, ValueError):
            days = 28
    target_loss_lbs = None
    if goal_type == "lose" and timeframe_weeks and weekly_change_kg:
        try:
            total_kg = abs(float(weekly_change_kg) * float(timeframe_weeks))
            target_loss_lbs = round(total_kg * 2.20462, 1)
        except (TypeError, ValueError):
            target_loss_lbs = None
    plan_data = _build_plan_data(
        user_id,
        days,
        target_loss_lbs,
        goal_override=goal_type,
    )
    if not plan_data or plan_data.get("error"):
        print("Plan generation failed:", plan_data)
        return None
    print("Plan generation payload:", json.dumps(plan_data, indent=2, default=str))
    _activate_plan_from_data(user_id, plan_data)
    return plan_data


@app.post("/api/onboarding/complete")
def complete_onboarding(payload: OnboardingCompletePayload):
    user_id = payload.user_id or 1
    fields = []
    values: list[Any] = []
    if payload.current_weight_kg is not None:
        fields.append("weight_kg = ?")
        values.append(payload.current_weight_kg)
    if payload.height_cm is not None:
        fields.append("height_cm = ?")
        values.append(payload.height_cm)
    if payload.age is not None:
        fields.append("age_years = ?")
        values.append(payload.age)
    if payload.trainer:
        fields.append("agent_name = ?")
        values.append(payload.trainer)
    if payload.full_name:
        fields.append("name = ?")
        values.append(payload.full_name)
        if fields:
            values.append(user_id)
            with get_db_conn() as conn:
                cur = conn.cursor()
                cur.execute(f"UPDATE users SET {', '.join(fields)} WHERE id = ?", tuple(values))
                conn.commit()
        _refresh_profile_cache(user_id)
    _generate_plan_for_user(
        user_id,
        goal_type=payload.goal_type,
        timeframe_weeks=payload.timeframe_weeks,
        weekly_change_kg=payload.weekly_weight_change_kg,
    )
    return {"ok": True}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)