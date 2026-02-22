from __future__ import annotations

"""
AI Trainer unified backend (videos, gyms, coach).
"""

import base64
import hashlib
import io
import os
import re
import hmac
import secrets
import ssl
import sys
import time
import uuid
import tempfile
from dotenv import load_dotenv

# Load environment variables from .env file
dotenv_path = os.path.join(os.path.dirname(__file__), ".env")
load_dotenv(dotenv_path=dotenv_path, override=True)
from datetime import date, datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Union

_ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if _ROOT_DIR not in sys.path:
    sys.path.insert(0, _ROOT_DIR)
_ROOT_ENV_PATH = os.path.join(_ROOT_DIR, ".env")
_ENV_PATH = os.path.join(os.path.dirname(__file__), ".env")

import certifi
import json
import urllib.parse
import urllib.request
import stripe

from fastapi import FastAPI, File, Form, HTTPException, Query, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response
from googleapiclient.discovery import build
import google.generativeai as genai
from langchain_core.messages import HumanMessage, ToolMessage
from PIL import Image
from pydantic import BaseModel
from openai import OpenAI

from agent.state import SESSION_CACHE
from agent.redis.cache import _redis_delete, _redis_get_json, _redis_set_json
from config.constants import DB_PATH, CACHE_TTL_LONG, _draft_health_activity_key, _draft_reminders_key
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
_OPENAI_CLIENT = None
COACH_CHANGE_COOLDOWN_DAYS = 2


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


def _get_openai_client() -> OpenAI:
    global _OPENAI_CLIENT
    if _OPENAI_CLIENT is None:
        if not OPENAI_API_KEY:
            raise RuntimeError("Missing OPENAI_API_KEY env var")
        _OPENAI_CLIENT = OpenAI()
    return _OPENAI_CLIENT


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


def _strip_data_url_prefix(encoded: str) -> str:
    if not encoded:
        return encoded
    if encoded.startswith("data:") and "base64," in encoded:
        return encoded.split("base64,", 1)[1]
    return encoded


def _summarize_image(image_bytes: bytes, user_message: str) -> str:
    prompt = (
        "You are a fitness coach. Analyze the image and describe what you see in concise "
        "plain text. If it is a meal, mention foods and estimated portions. If it is a workout "
        "image, identify the activity, equipment, form cues, and any visible risks. If unsure, "
        "say so. No markdown."
    )
    if user_message:
        prompt += f"\nUser note: {user_message}"
    return _gemini_generate_content(prompt, image_bytes=image_bytes, temperature=0.2).strip()


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
    _ensure_meal_log_schema()
    def _idempotency_key() -> str:
        if payload.idempotency_key and payload.idempotency_key.strip():
            return payload.idempotency_key.strip()
        item_payload = [
            {
                "name": item.name,
                "amount": item.amount,
                "calories": item.calories,
                "protein_g": item.protein_g,
                "carbs_g": item.carbs_g,
                "fat_g": item.fat_g,
                "fiber_g": item.fiber_g,
                "sugar_g": item.sugar_g,
                "sodium_mg": item.sodium_mg,
            }
            for item in payload.items
        ]
        normalized = {
            "food_name": payload.food_name,
            "total_calories": payload.total_calories,
            "protein_g": payload.protein_g,
            "carbs_g": payload.carbs_g,
            "fat_g": payload.fat_g,
            "fiber_g": payload.fiber_g,
            "sugar_g": payload.sugar_g,
            "sodium_mg": payload.sodium_mg,
            "items": item_payload,
            "logged_at": payload.logged_at or "",
        }
        digest = hashlib.sha256(json.dumps(normalized, sort_keys=True).encode("utf-8")).hexdigest()
        return f"auto:{digest}"

    logged_at = payload.logged_at or datetime.now().isoformat(timespec="seconds")
    description = payload.food_name
    day_key = logged_at[:10]
    idem_key = _idempotency_key()
    idem_cache_key = f"idem:api:meal:{payload.user_id}:{idem_key}"
    cached = _redis_get_json(idem_cache_key)
    if isinstance(cached, dict) and cached.get("ok"):
        return
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO meal_logs (
                user_id, logged_at, photo_path, description, calories,
                protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg, confidence, confirmed
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                float(payload.fiber_g or 0),
                float(payload.sugar_g or 0),
                float(payload.sodium_mg or 0),
                max((item.confidence for item in payload.items), default=0.6),
                1,
            ),
        )
        conn.commit()
    _invalidate_user_activity_cache(payload.user_id, day=day_key)
    _award_points(payload.user_id, 5, f"meal_log:{logged_at}")
    _maybe_award_daily_calorie_target_bonus(payload.user_id, logged_at[:10])
    _apply_daily_checklist_completion_bonus(payload.user_id, logged_at[:10])
    _ensure_daily_coach_checkin_reminder(payload.user_id)
    _redis_set_json(idem_cache_key, {"ok": True}, ttl_seconds=600)


def _ensure_auth_schema() -> None:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'users'
              AND column_name = 'password_hash'
            """
        )
        has_password_hash = cur.fetchone() is not None
        if not has_password_hash:
            cur.execute("ALTER TABLE users ADD COLUMN password_hash TEXT NULL")
            conn.commit()


def _ensure_profile_schema() -> None:
    with get_db_conn() as conn:
        cur = conn.cursor()
        # Check if profile_image_base64 column exists (PostgreSQL compatible)
        cur.execute(
            """
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'users'
              AND column_name = 'profile_image_base64'
            """
        )
        has_profile_image = cur.fetchone() is not None
        if not has_profile_image:
            cur.execute("ALTER TABLE users ADD COLUMN profile_image_base64 TEXT NULL")
        pref_columns = [
            ("allergies", "TEXT NULL"),
            ("preferred_workout_time", "TEXT NULL"),
            ("menstrual_cycle_notes", "TEXT NULL"),
        ]
        for col_name, col_type in pref_columns:
            cur.execute(
                """
                SELECT 1
                FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = 'user_preferences'
                  AND column_name = ?
                """,
                (col_name,),
            )
            has_col = cur.fetchone() is not None
            if not has_col:
                cur.execute(f"ALTER TABLE user_preferences ADD COLUMN {col_name} {col_type}")
        conn.commit()


def _ensure_meal_log_schema() -> None:
    with get_db_conn() as conn:
        cur = conn.cursor()
        meal_columns = [
            ("fiber_g", "DOUBLE PRECISION NULL"),
            ("sugar_g", "DOUBLE PRECISION NULL"),
            ("sodium_mg", "DOUBLE PRECISION NULL"),
        ]
        for col_name, col_type in meal_columns:
            cur.execute(
                """
                SELECT 1
                FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = 'meal_logs'
                  AND column_name = ?
                """,
                (col_name,),
            )
            has_col = cur.fetchone() is not None
            if not has_col:
                cur.execute(f"ALTER TABLE meal_logs ADD COLUMN {col_name} {col_type}")
        conn.commit()


def _supabase_url() -> Optional[str]:
    url = os.environ.get("SUPABASE_URL")
    return url.rstrip("/") if url else None


def _supabase_headers() -> dict[str, str]:
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or ""
    if not service_key:
        return {}
    return {"Authorization": f"Bearer {service_key}", "apikey": service_key}


def _extract_storage_path(url: str) -> Optional[str]:
    marker = "/storage/v1/object/"
    if marker not in url:
        return None
    return url.split(marker, 1)[1]


def _sign_storage_url(url: str, expires_in: int = 3600) -> Optional[str]:
    base = _supabase_url()
    if not base or not os.environ.get("SUPABASE_SERVICE_ROLE_KEY"):
        return None
    path = _extract_storage_path(url)
    if not path:
        return None
    endpoint = f"{base}/storage/v1/object/sign/{path}"
    payload = json.dumps({"expiresIn": expires_in}).encode("utf-8")
    headers = {"Content-Type": "application/json", **_supabase_headers()}
    request = urllib.request.Request(endpoint, data=payload, headers=headers, method="POST")
    ssl_context = ssl.create_default_context(cafile=certifi.where())
    with urllib.request.urlopen(request, timeout=20, context=ssl_context) as response:
        data = json.loads(response.read().decode("utf-8"))
    signed = data.get("signedURL")
    if not signed:
        return None
    return f"{base}{signed}"


def _ensure_coach_schema() -> None:
    with get_db_conn() as conn:
        cur = conn.cursor()
        # Check if agent_id column exists (PostgreSQL compatible)
        cur.execute(
            """
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'users'
              AND column_name = 'agent_id'
            """
        )
        has_agent_id = cur.fetchone() is not None
        if not has_agent_id:
            cur.execute("ALTER TABLE users ADD COLUMN agent_id BIGINT NULL")

        cur.execute(
            """
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'users'
              AND column_name = 'coach_voice'
            """
        )
        has_coach_voice = cur.fetchone() is not None
        if not has_coach_voice:
            cur.execute("ALTER TABLE users ADD COLUMN coach_voice TEXT NULL")

        cur.execute(
            """
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'users'
              AND column_name = 'last_agent_change_at'
            """
        )
        has_last_agent_change_at = cur.fetchone() is not None
        if not has_last_agent_change_at:
            cur.execute("ALTER TABLE users ADD COLUMN last_agent_change_at TEXT NULL")

        # Default to Marcus (id=1) when missing.
        cur.execute("UPDATE users SET agent_id = 1 WHERE agent_id IS NULL")
        cur.execute(
            """
            UPDATE users
            SET coach_voice = CASE
                WHEN agent_id = 1 THEN 'onyx'
                WHEN agent_id = 2 THEN 'shimmer'
                WHEN agent_id = 3 THEN 'sage'
                WHEN agent_id = 4 THEN 'nova'
                WHEN agent_id = 5 THEN 'echo'
                WHEN agent_id = 6 THEN 'alloy'
                WHEN agent_id = 7 THEN 'nova'
                WHEN agent_id = 8 THEN 'echo'
                WHEN agent_id = 9 THEN 'shimmer'
                WHEN agent_id = 10 THEN 'nova'
                WHEN agent_id = 11 THEN 'alloy'
                ELSE 'alloy'
            END
            WHERE coach_voice IS NULL OR coach_voice = ''
            """
        )
        conn.commit()


def _default_voice_for_agent(agent_id: Optional[int]) -> str:
    mapping = {
        1: "onyx",
        2: "shimmer",
        3: "sage",
        4: "nova",
        5: "echo",
        6: "alloy",
        7: "nova",
        8: "echo",
        9: "shimmer",
        10: "nova",
        11: "alloy",
    }
    if agent_id is None:
        return "alloy"
    return mapping.get(int(agent_id), "alloy")


def _agent_change_cooldown_state(last_changed_at: Any) -> Dict[str, Any]:
    last_changed = _coerce_to_datetime(last_changed_at)
    if not last_changed:
        return {
            "blocked": False,
            "next_change_available_at": None,
            "retry_after_days": 0,
        }
    next_allowed = last_changed + timedelta(days=COACH_CHANGE_COOLDOWN_DAYS)
    now_utc = datetime.now(timezone.utc)
    if now_utc >= next_allowed:
        return {
            "blocked": False,
            "next_change_available_at": next_allowed.isoformat(),
            "retry_after_days": 0,
        }
    seconds_left = max(0, int((next_allowed - now_utc).total_seconds()))
    retry_after_days = max(1, int((seconds_left + 86399) / 86400))
    return {
        "blocked": True,
        "next_change_available_at": next_allowed.isoformat(),
        "retry_after_days": retry_after_days,
    }


def _hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    iterations = 150000
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), bytes.fromhex(salt), iterations).hex()
    return f"pbkdf2_sha256${iterations}${salt}${digest}"


def _verify_password(password: str, stored: Optional[str]) -> bool:
    if not stored:
        return False
    if stored.startswith("seeded$"):
        expected = "seeded$" + hashlib.sha256(password.encode("utf-8")).hexdigest()
        return hmac.compare_digest(expected, stored)
    try:
        algo, iter_text, salt_hex, digest_hex = stored.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        iterations = int(iter_text)
        actual = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            bytes.fromhex(salt_hex),
            iterations,
        ).hex()
        return hmac.compare_digest(actual, digest_hex)
    except Exception:
        return False


def _user_has_active_plan(user_id: int) -> bool:
    try:
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT 1
                FROM plan_templates
                WHERE user_id = ? AND status = 'active'
                LIMIT 1
                """,
                (user_id,),
            )
            return cur.fetchone() is not None
    except Exception:
        return False


def _onboarding_completed_from_row(row: tuple) -> bool:
    # row: id, email, name, password_hash, height_cm, weight_kg, age_years, agent_id
    # Treat onboarding as complete if core profile exists OR user already has an active plan.
    has_profile_basics = bool(row[4] is not None and row[5] is not None and row[6] is not None)
    if has_profile_basics:
        return True
    user_id = int(row[0]) if row and row[0] is not None else None
    if user_id is None:
        return False
    return _user_has_active_plan(user_id)


def _coerce_to_date(value: Any) -> Optional[date]:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    text = str(value)
    for fmt in ("%Y-%m-%d", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(text).date()
    except ValueError:
        return None


def _coerce_to_datetime(value: Any) -> Optional[datetime]:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, date):
        return datetime.combine(value, datetime.min.time(), tzinfo=timezone.utc)
    text = str(value).strip()
    if not text:
        return None
    normalized = text.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        pass
    for fmt in ("%Y-%m-%d %H:%M:%S",):
        try:
            parsed = datetime.strptime(text, fmt)
            return parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


def _award_points(user_id: int, points: int, reason: str) -> None:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO points (user_id, points, reason, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (user_id, points, reason, datetime.now().isoformat(timespec="seconds")),
        )
        conn.commit()


def _has_points_reason(user_id: int, reason: str) -> bool:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT 1 FROM points WHERE user_id = ? AND reason = ? LIMIT 1", (user_id, reason))
        return cur.fetchone() is not None


def _count_points_reason_like(user_id: int, reason_like: str) -> int:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM points WHERE user_id = ? AND reason LIKE ?", (user_id, reason_like))
        row = cur.fetchone()
        return int(row[0] or 0) if row else 0


def _total_points(user_id: int) -> int:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT COALESCE(SUM(points), 0) FROM points WHERE user_id = ?", (user_id,))
        row = cur.fetchone()
        return int(row[0] or 0) if row else 0


def _level_progress_from_points(points: int) -> Dict[str, int]:
    # Progressive thresholds: 60, 65, 70, 75, ...
    remaining = max(0, int(points))
    level = 1
    required = 60
    while remaining >= required:
        remaining -= required
        level += 1
        required += 5
    return {
        "level": level,
        "xp_in_level": remaining,
        "xp_for_next_level": required,
        "xp_to_next_level": required - remaining,
    }


def _invalidate_user_activity_cache(user_id: int, day: Optional[str] = None) -> None:
    _redis_delete(f"session_hydration:{user_id}")
    _redis_delete(f"user:{user_id}:meal_logs")
    if day:
        _redis_delete(f"daily_intake:{user_id}:{day}")


def _ensure_daily_coach_checkin_reminder(user_id: int) -> None:
    # Schedule today's check-in if upcoming; otherwise schedule for tomorrow.
    now = datetime.now()
    target = now.replace(hour=20, minute=0, second=0, microsecond=0)
    if target <= now:
        target = target + timedelta(days=1)
    scheduled_at = target.isoformat(timespec="seconds")
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO reminders (
                user_id, reminder_type, scheduled_at, status, channel, related_plan_override_id
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (user_id, reminder_type, scheduled_at) DO NOTHING
            """,
            (user_id, "daily_coach_checkin", scheduled_at, "pending", "ios", None),
        )
        conn.commit()
    _invalidate_reminders_cache(user_id)


def _invalidate_health_activity_cache(user_id: int) -> None:
    _redis_delete(_draft_health_activity_key(user_id))
    _redis_delete(f"session_hydration:{user_id}")


def _invalidate_reminders_cache(user_id: int) -> None:
    _redis_delete(_draft_reminders_key(user_id))
    _redis_delete(f"session_hydration:{user_id}")


def _ensure_app_open_schema() -> None:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS app_open_events (
                user_id INTEGER PRIMARY KEY,
                last_open_at TEXT NOT NULL
            )
            """
        )
        conn.commit()


def _daily_intake_and_target(user_id: int, target_day: str) -> tuple[int, Optional[int]]:
    start = f"{target_day}T00:00:00"
    end = f"{target_day}T23:59:59"
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT COALESCE(SUM(calories), 0)
            FROM meal_logs
            WHERE user_id = ? AND logged_at BETWEEN ? AND ?
            """,
            (user_id, start, end),
        )
        row = cur.fetchone()
    total_calories = int(row[0] or 0) if row else 0
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
    return total_calories, int(daily_target) if daily_target is not None else None


def _maybe_award_daily_calorie_target_bonus(user_id: int, target_day: str) -> None:
    total, target = _daily_intake_and_target(user_id, target_day)
    if target is None or target <= 0 or total < target:
        return
    reason = f"daily_target_met:{target_day}"
    if not _has_points_reason(user_id, reason):
        _award_points(user_id, 20, reason)


def _update_login_streak(user_id: int) -> Dict[str, int]:
    today_str = date.today().isoformat()
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT id, current_count, best_count, last_date FROM streaks WHERE user_id = ? AND streak_type = ? LIMIT 1",
            (user_id, "login"),
        )
        row = cur.fetchone()
        if not row:
            cur.execute(
                """
                INSERT INTO streaks (user_id, streak_type, current_count, best_count, last_date)
                VALUES (?, ?, ?, ?, ?)
                """,
                (user_id, "login", 1, 1, today_str),
            )
            conn.commit()
            return {"current_count": 1, "best_count": 1, "last_date": today_str}

        streak_id, current_count, best_count, last_date = row
        last_dt = _coerce_to_date(last_date)
        today_dt = date.today()

        if last_dt == today_dt:
            return {"current_count": int(current_count), "best_count": int(best_count), "last_date": today_str}
        if last_dt == (today_dt - timedelta(days=1)):
            current_count = int(current_count) + 1
        elif last_dt is None:
            current_count = 1
        else:
            # Preserve streak until user decides freeze vs reset after inactivity.
            return {"current_count": int(current_count), "best_count": int(best_count), "last_date": str(last_date)}
        best_count = max(int(best_count), int(current_count))
        cur.execute(
            "UPDATE streaks SET current_count = ?, best_count = ?, last_date = ? WHERE id = ?",
            (int(current_count), int(best_count), today_str, streak_id),
        )
        conn.commit()
        return {"current_count": int(current_count), "best_count": int(best_count), "last_date": today_str}


def _set_streak_for_today(user_id: int, keep_count: bool) -> None:
    today_str = date.today().isoformat()
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT id, current_count, best_count FROM streaks WHERE user_id = ? AND streak_type = ? LIMIT 1",
            (user_id, "login"),
        )
        row = cur.fetchone()
        if not row:
            cur.execute(
                """
                INSERT INTO streaks (user_id, streak_type, current_count, best_count, last_date)
                VALUES (?, ?, ?, ?, ?)
                """,
                (user_id, "login", 1, 1, today_str),
            )
            conn.commit()
            return
        streak_id, current_count, best_count = row
        if keep_count:
            new_count = max(1, int(current_count or 1))
            new_best = max(int(best_count or 0), new_count)
        else:
            new_count = 1
            new_best = max(int(best_count or 0), 1)
        cur.execute(
            "UPDATE streaks SET current_count = ?, best_count = ?, last_date = ? WHERE id = ?",
            (new_count, new_best, today_str, int(streak_id)),
        )
        conn.commit()


def _apply_daily_checklist_completion_bonus(user_id: int, target_day: str) -> None:
    start = f"{target_day}T00:00:00"
    end = f"{target_day}T23:59:59"
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT COUNT(*) FROM meal_logs WHERE user_id = ? AND logged_at BETWEEN ? AND ?",
            (user_id, start, end),
        )
        meal_count = int((cur.fetchone() or [0])[0] or 0)
        cur.execute(
            "SELECT COUNT(*) FROM workout_sessions WHERE user_id = ? AND completed = 1 AND date = ?",
            (user_id, target_day),
        )
        workout_count = int((cur.fetchone() or [0])[0] or 0)
        cur.execute(
            "SELECT COUNT(*) FROM checkins WHERE user_id = ? AND checkin_date = ?",
            (user_id, target_day),
        )
        checkin_count = int((cur.fetchone() or [0])[0] or 0)
    if meal_count < 3 or workout_count < 1 or checkin_count < 1:
        return
    reason = f"daily_checklist_complete:{target_day}"
    if _has_points_reason(user_id, reason):
        return
    _award_points(user_id, 10, reason)


def _daily_checklist_status(user_id: int, target_day: str) -> Dict[str, Any]:
    start = f"{target_day}T00:00:00"
    end = f"{target_day}T23:59:59"
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM meal_logs WHERE user_id = ? AND logged_at BETWEEN ? AND ?", (user_id, start, end))
        meal_count = int((cur.fetchone() or [0])[0] or 0)
        cur.execute("SELECT COUNT(*) FROM workout_sessions WHERE user_id = ? AND completed = 1 AND date = ?", (user_id, target_day))
        workout_count = int((cur.fetchone() or [0])[0] or 0)
    checkin_done = _has_points_reason(user_id, f"checkin_log:{target_day}")
    checklist_reason = f"daily_checklist_complete:{target_day}"
    checklist_done = _has_points_reason(user_id, checklist_reason)
    return {
        "day": target_day,
        "meals_logged": meal_count,
        "workouts_logged": workout_count,
        "checkin_done": checkin_done,
        "meals_done": meal_count >= 3,
        "workout_done": workout_count >= 1,
        "checklist_done": checklist_done,
        "xp_awarded": 10 if checklist_done else 0,
    }


def _maybe_award_biweekly_target_bonus(user_id: int) -> None:
    try:
        from agent.tools.plan_tools import _get_active_plan_bundle_data

        bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
        checkpoints = bundle.get("checkpoints") or []
        if not checkpoints:
            return
        plan = bundle.get("plan")
        plan_start: Optional[date] = None
        if isinstance(plan, dict) and plan.get("start_date"):
            plan_start = _coerce_to_date(plan.get("start_date"))
        elif isinstance(plan, tuple) and len(plan) >= 2 and plan[1]:
            plan_start = _coerce_to_date(plan[1])
        if plan_start is None:
            return
        today_dt = date.today()
        eligible = []
        for cp in checkpoints:
            week = int(cp.get("week") or 0)
            if week <= 0 or week % 2 != 0:
                continue
            cp_date = plan_start + timedelta(days=week * 7)
            if cp_date <= today_dt:
                eligible.append((week, cp))
        if not eligible:
            return
        week, checkpoint = sorted(eligible, key=lambda item: item[0])[-1]
        checkins = _list_checkins(user_id)
        latest = next((c for c in checkins if c.get("weight_kg") is not None), None)
        if latest is None:
            return
        weight = float(latest.get("weight_kg"))
        min_w = float(checkpoint.get("min_weight_kg"))
        max_w = float(checkpoint.get("max_weight_kg"))
        if min_w <= weight <= max_w:
            reason = f"biweekly_target_met:week{week}"
            if not _has_points_reason(user_id, reason):
                _award_points(user_id, 40, reason)
    except Exception:
        return


def _gamification_summary(user_id: int) -> Dict[str, Any]:
    streak = _update_login_streak(user_id)
    _maybe_award_daily_calorie_target_bonus(user_id, date.today().isoformat())
    _maybe_award_biweekly_target_bonus(user_id)

    points = _total_points(user_id)
    progress = _level_progress_from_points(points)
    level = progress["level"]
    next_level_points = progress["xp_to_next_level"]
    unlocked_freezes = max(0, level - 1)
    used_freezes = _count_points_reason_like(user_id, "freeze_used:%")
    available_freezes = max(0, unlocked_freezes - used_freezes)
    streak_days = int(streak.get("current_count", 0))
    best_streak_days = int(streak.get("best_count", streak_days))
    share_text = f"I've got a {streak_days}-day streak on AI Trainer. Level {level} and climbing."
    return {
        "points": points,
        "level": level,
        "next_level_points": next_level_points,
        "streak_days": streak_days,
        "best_streak_days": best_streak_days,
        "freeze_streaks": available_freezes,
        "unlocked_freeze_streaks": unlocked_freezes,
        "used_freeze_streaks": used_freezes,
        "share_text": share_text,
    }


def _load_user_profile(user_id: int) -> Dict[str, Any]:
    _ensure_profile_schema()
    _ensure_coach_schema()
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
            "agent_id": row[7],
            "profile_image_base64": row[8],
            "coach_voice": row[9],
            "last_agent_change_at": row[10],
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
            "allergies": row[8] if len(row) > 8 else None,
            "preferred_workout_time": row[9] if len(row) > 9 else None,
            "menstrual_cycle_notes": row[10] if len(row) > 10 else None,
        }

    try:
        from db import queries

        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute(queries.SELECT_USER_PROFILE, (user_id,))
            user_row = cur.fetchone()
            cur.execute(queries.SELECT_USER_PREFS, (user_id,))
            pref_row = cur.fetchone()
        return {"user": _map_user(user_row), "preferences": _map_prefs(pref_row)}
    except Exception:
        return {"user": None, "preferences": None}


def _as_string_list(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return [str(item) for item in value if item is not None]
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return []
        try:
            parsed = json.loads(stripped)
            if isinstance(parsed, list):
                return [str(item) for item in parsed if item is not None]
        except Exception:
            pass
        return [part.strip() for part in stripped.split(",") if part.strip()]
    return []


def _resolve_coach_slug(agent_id: Optional[Union[int, str]]) -> Optional[str]:
    if agent_id is None:
        return None
    if isinstance(agent_id, str):
        normalized = agent_id.strip().lower()
        if not normalized:
            return None
        if normalized.isdigit():
            agent_id = int(normalized)
        else:
            return normalized
    if isinstance(agent_id, int):
        try:
            with get_db_conn() as conn:
                cur = conn.cursor()
                cur.execute("SELECT slug FROM coaches WHERE id = ? LIMIT 1", (agent_id,))
                row = cur.fetchone()
                if row and row[0]:
                    return str(row[0]).strip().lower()
        except Exception:
            return str(agent_id)
        return str(agent_id)
    return str(agent_id).strip().lower()


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


def _upsert_daily_weight_checkin(user_id: int, weight_kg: float, conn=None) -> None:
    """Persist the latest user weight to checkins for charting."""
    own_conn = False
    if conn is None:
        conn = get_db_conn()
        own_conn = True
    try:
        cur = conn.cursor()
        today = datetime.now().date().isoformat()
        cur.execute(
            """
            SELECT id
            FROM checkins
            WHERE user_id = ? AND checkin_date = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            (user_id, today),
        )
        existing = cur.fetchone()
        if existing and existing[0]:
            cur.execute(
                "UPDATE checkins SET weight_kg = ? WHERE id = ?",
                (weight_kg, int(existing[0])),
            )
        else:
            cur.execute(
                """
                INSERT INTO checkins (user_id, checkin_date, weight_kg, mood, notes)
                VALUES (?, ?, ?, NULL, NULL)
                """,
                (user_id, today, weight_kg),
            )
        if own_conn:
            conn.commit()
    finally:
        if own_conn:
            conn.close()


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
    _ensure_meal_log_schema()
    try:
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT id, logged_at, photo_path, description, calories, protein_g, carbs_g, fat_g,
                       fiber_g, sugar_g, sodium_mg, confidence, confirmed
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
                    "fiber_g": float(row[8] or 0),
                    "sugar_g": float(row[9] or 0),
                    "sodium_mg": float(row[10] or 0),
                    "confidence": row[11],
                    "confirmed": bool(row[12]),
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
    agent_id: Optional[Union[int, str]] = None
    image_base64: Optional[str] = None


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


class CoachItemResponse(BaseModel):
    id: int
    slug: str
    name: str
    nickname: Optional[str] = None
    title: str
    age: int
    ethnicity: str
    gender: str
    pronouns: str
    philosophy: str
    background_story: str
    personality: str
    speaking_style: str
    expertise: List[str]
    common_phrases: List[str]
    tags: List[str]
    primary_color: str
    secondary_color: str
    image_url: Optional[str] = None
    video_url: Optional[str] = None


class FoodScanItem(BaseModel):
    name: str
    amount: str
    calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float = 0.0
    sugar_g: float = 0.0
    sodium_mg: float = 0.0
    category: Optional[str] = None
    confidence: float


class FoodScanResponse(BaseModel):
    food_name: str
    total_calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float = 0.0
    sugar_g: float = 0.0
    sodium_mg: float = 0.0
    confidence: float
    items: List[FoodScanItem]


class FoodLogRequest(BaseModel):
    user_id: int
    food_name: str
    total_calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float = 0.0
    sugar_g: float = 0.0
    sodium_mg: float = 0.0
    items: List[FoodScanItem]
    logged_at: Optional[str] = None
    idempotency_key: Optional[str] = None


class DailyIntakeResponse(BaseModel):
    date: str
    total_calories: int
    total_protein_g: float
    total_carbs_g: float
    total_fat_g: float
    total_fiber_g: float
    total_sugar_g: float
    total_sodium_mg: float
    meals_count: int
    daily_calorie_target: Optional[int] = None


class MealLogItem(BaseModel):
    name: str
    calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float = 0.0
    sugar_g: float = 0.0
    sodium_mg: float = 0.0
    logged_at: str


class DailyMealLogsResponse(BaseModel):
    date: str
    meals: List[MealLogItem]


class ReminderItemResponse(BaseModel):
    id: int
    reminder_type: str
    scheduled_at: str
    status: str
    channel: str
    related_plan_override_id: Optional[int] = None


class ReminderCreateRequest(BaseModel):
    user_id: int
    reminder_type: str
    scheduled_at: str
    status: str = "pending"
    channel: str = "ios"


class ReminderUpdateRequest(BaseModel):
    user_id: int
    status: Optional[str] = None
    scheduled_at: Optional[str] = None


class HealthActivityLogRequest(BaseModel):
    user_id: int
    date: Optional[str] = None
    steps: int = 0
    calories_burned: int = 0
    active_minutes: int = 0
    workouts_summary: Optional[str] = None
    source: str = "apple_health"


class HealthActivityImpactItemResponse(BaseModel):
    date: str
    steps: int
    health_calories_burned: int
    active_minutes: int
    workouts_summary: str
    source: str
    meal_intake: int
    meal_target: Optional[int] = None
    workout_expected_burn: Optional[int] = None
    burn_delta: Optional[int] = None
    intake_delta: Optional[int] = None


class HealthActivityImpactResponse(BaseModel):
    start_day: str
    end_day: str
    items: List[HealthActivityImpactItemResponse]


class SessionHydrationResponse(BaseModel):
    user_id: int
    date: str
    profile: Dict[str, Any]
    progress: Dict[str, Any]
    today_plan: Optional[PlanDayResponse] = None
    daily_intake: DailyIntakeResponse
    gamification: GamificationResponse
    coach_suggestion: Optional[Dict[str, Any]] = None


class AuthSignInRequest(BaseModel):
    email: str
    password: str


class AuthSignUpRequest(BaseModel):
    email: str
    password: str
    name: Optional[str] = None


class AuthCallbackRequest(BaseModel):
    access_token: str
    email: Optional[str] = None
    name: Optional[str] = None


class AuthResponse(BaseModel):
    user_id: int
    email: str
    name: str
    onboarding_completed: bool


class CoachChangeRequest(BaseModel):
    user_id: int
    new_coach_id: int


class CoachChangeResponse(BaseModel):
    success: bool
    message: Optional[str] = None
    next_change_available_at: Optional[str] = None
    retry_after_days: Optional[int] = None


class LocalWorkoutVideoResponse(BaseModel):
    key: str
    base_filename: str
    base_url: str
    base_local_path: Optional[str] = None
    reps_filename: Optional[str] = None
    reps_url: Optional[str] = None
    reps_local_path: Optional[str] = None


class ProfileUpdateRequest(BaseModel):
    user_id: int
    name: Optional[str] = None
    birthdate: Optional[str] = None
    height_cm: Optional[float] = None
    weight_kg: Optional[float] = None
    gender: Optional[str] = None
    age_years: Optional[int] = None
    agent_id: Optional[int] = None
    profile_image_base64: Optional[str] = None
    activity_level: Optional[str] = None
    goal_type: Optional[str] = None
    target_weight_kg: Optional[float] = None
    dietary_preferences: Optional[str] = None
    workout_preferences: Optional[str] = None
    allergies: Optional[str] = None
    preferred_workout_time: Optional[str] = None
    menstrual_cycle_notes: Optional[str] = None


class BillingCheckoutRequest(BaseModel):
    user_id: int
    plan_tier: str = "premium"


class BillingCheckoutResponse(BaseModel):
    checkout_url: str
    session_id: str


class PlanDayResponse(BaseModel):
    date: str
    workout_plan: str
    rest_day: bool
    calorie_target: int
    protein_g: int
    carbs_g: int
    fat_g: int


class RecipeSuggestRequest(BaseModel):
    user_id: int
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
    source_links: List[str] = []


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
    trainer_id: Optional[int] = None
    trainer: Optional[str] = None
    full_name: Optional[str] = None
    voice: Optional[str] = None
    allergies: Optional[str] = None
    preferred_workout_time: Optional[str] = None
    menstrual_cycle_notes: Optional[str] = None


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




class GamificationResponse(BaseModel):
    points: int
    level: int
    next_level_points: int
    streak_days: int
    best_streak_days: int
    freeze_streaks: int
    unlocked_freeze_streaks: int
    used_freeze_streaks: int
    share_text: str


class UseFreezeRequest(BaseModel):
    user_id: int


class StreakDecisionRequest(BaseModel):
    user_id: int
    use_freeze: bool


class AppOpenStreakResponse(BaseModel):
    freeze_prompt_required: bool
    inactivity_hours: float
    streak_reset: bool
    message: str
    gamification: GamificationResponse


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


def _local_workout_videos_dir() -> str:
    return os.path.join(os.path.dirname(__file__), "videos")


def _safe_local_video_path(file_name: str) -> str:
    videos_dir = os.path.abspath(_local_workout_videos_dir())
    candidate = os.path.abspath(os.path.join(videos_dir, file_name))
    if not candidate.startswith(videos_dir + os.sep):
        raise HTTPException(status_code=400, detail="Invalid video filename")
    return candidate


def _group_local_workout_videos() -> Dict[str, Dict[str, str]]:
    videos_dir = _local_workout_videos_dir()
    if not os.path.isdir(videos_dir):
        return {}
    grouped: Dict[str, Dict[str, str]] = {}
    allowed_ext = {".mp4", ".mov", ".m4v"}

    def _normalized_key(raw_stem: str) -> str:
        lowered = raw_stem.strip().lower()
        for suffix in ("_intro", "_reps", "-intro", "-reps", " intro", " reps"):
            if lowered.endswith(suffix):
                lowered = lowered[: -len(suffix)]
                break
        lowered = re.sub(r"[^a-z0-9]+", "_", lowered).strip("_")
        return lowered or "video"

    for entry in os.listdir(videos_dir):
        path = os.path.join(videos_dir, entry)
        if not os.path.isfile(path):
            continue
        stem, ext = os.path.splitext(entry)
        if ext.lower() not in allowed_ext:
            continue
        stem_lower = stem.lower().strip()
        is_intro = stem_lower.endswith("_intro") or stem_lower.endswith("-intro") or stem_lower.endswith(" intro")
        is_reps = stem_lower.endswith("_reps") or stem_lower.endswith("-reps") or stem_lower.endswith(" reps")
        key = _normalized_key(stem)
        slot = grouped.setdefault(key, {})
        if is_intro:
            slot["base"] = entry
        elif is_reps:
            slot["reps"] = entry
        else:
            # Fallback for files that don't carry explicit suffix.
            if "base" not in slot:
                slot["base"] = entry
            elif "reps" not in slot:
                slot["reps"] = entry
    return {k: v for k, v in grouped.items() if v.get("base")}


@app.get("/api/workout-local-videos", response_model=List[LocalWorkoutVideoResponse])
def get_local_workout_videos(request: Request):
    grouped = _group_local_workout_videos()
    base_url = str(request.base_url).rstrip("/")
    rows: List[LocalWorkoutVideoResponse] = []
    for key in sorted(grouped.keys()):
        files = grouped[key]
        base_name = files.get("base")
        reps_name = files.get("reps")
        if not base_name:
            continue
        rows.append(
            LocalWorkoutVideoResponse(
                key=key,
                base_filename=base_name,
                base_url=f"{base_url}/api/workout-local-videos/file/{urllib.parse.quote(base_name)}",
                base_local_path=os.path.abspath(os.path.join(_local_workout_videos_dir(), base_name)),
                reps_filename=reps_name,
                reps_url=(
                    f"{base_url}/api/workout-local-videos/file/{urllib.parse.quote(reps_name)}"
                    if reps_name
                    else None
                ),
                reps_local_path=(
                    os.path.abspath(os.path.join(_local_workout_videos_dir(), reps_name))
                    if reps_name
                    else None
                ),
            )
        )
    return rows


@app.get("/api/workout-local-videos/file/{file_name:path}")
def get_local_workout_video_file(file_name: str):
    full_path = _safe_local_video_path(file_name)
    if not os.path.exists(full_path):
        raise HTTPException(status_code=404, detail="Workout video file not found")
    return FileResponse(full_path, media_type="video/mp4", filename=os.path.basename(full_path))


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


@app.post("/auth/signup", response_model=AuthResponse)
def auth_signup(payload: AuthSignUpRequest):
    _ensure_auth_schema()
    email = (payload.email or "").strip().lower()
    password = payload.password or ""
    if not email or not password:
        raise HTTPException(status_code=400, detail="Email and password are required")
    if len(password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")

    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT id FROM users WHERE email = ? LIMIT 1", (email,))
        if cur.fetchone() is not None:
            raise HTTPException(status_code=409, detail="Email already exists")
        name = (payload.name or "New User").strip() or "New User"
        password_hash = _hash_password(password)
        created_at = datetime.now().isoformat(timespec="seconds")
        cur.execute(
            """
            INSERT INTO users (email, password_hash, name, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (email, password_hash, name, created_at),
        )
        cur.execute("SELECT id FROM users WHERE email = ? LIMIT 1", (email,))
        row = cur.fetchone()
        conn.commit()
    return AuthResponse(user_id=int(row[0]), email=email, name=name, onboarding_completed=False)


@app.post("/auth/signin", response_model=AuthResponse)
def auth_signin(payload: AuthSignInRequest):
    _ensure_auth_schema()
    email = (payload.email or "").strip().lower()
    password = payload.password or ""
    if not email or not password:
        raise HTTPException(status_code=400, detail="Email and password are required")

    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, email, name, password_hash, height_cm, weight_kg, age_years, agent_id, profile_image_base64
            FROM users
            WHERE email = ?
            LIMIT 1
            """,
            (email,),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=401, detail="Invalid email or password")
    if not _verify_password(password, row[3]):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    return AuthResponse(
        user_id=int(row[0]),
        email=str(row[1]),
        name=str(row[2] or "User"),
        onboarding_completed=_onboarding_completed_from_row(row),
    )


def _fetch_supabase_oauth_user(access_token: str) -> Dict[str, Any]:
    base = _supabase_url()
    if not base:
        raise HTTPException(status_code=500, detail="SUPABASE_URL is not configured")

    apikey = (
        os.environ.get("SUPABASE_ANON_KEY")
        or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        or ""
    ).strip()
    if not apikey:
        raise HTTPException(status_code=500, detail="Missing Supabase API key for auth callback")

    request = urllib.request.Request(
        f"{base}/auth/v1/user",
        headers={
            "Authorization": f"Bearer {access_token}",
            "apikey": apikey,
        },
        method="GET",
    )
    ssl_context = ssl.create_default_context(cafile=certifi.where())
    try:
        with urllib.request.urlopen(request, timeout=20, context=ssl_context) as response:
            body = response.read().decode("utf-8")
            return json.loads(body) if body else {}
    except Exception as exc:
        raise HTTPException(status_code=401, detail=f"Invalid OAuth callback token: {exc}") from exc


@app.post("/auth/callback", response_model=AuthResponse)
def auth_callback(payload: AuthCallbackRequest):
    access_token = (payload.access_token or "").strip()
    if not access_token:
        raise HTTPException(status_code=400, detail="access_token is required")

    oauth_user = _fetch_supabase_oauth_user(access_token)
    oauth_email = str(oauth_user.get("email") or "").strip().lower()
    if not oauth_email:
        oauth_email = str(payload.email or "").strip().lower()
    if not oauth_email:
        raise HTTPException(status_code=400, detail="OAuth user email is missing")

    metadata = oauth_user.get("user_metadata") or {}
    oauth_name = (
        str(metadata.get("full_name") or metadata.get("name") or "").strip()
        or str(payload.name or "").strip()
        or "Google User"
    )

    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO users (email, name, created_at)
            VALUES (?, ?, ?)
            ON CONFLICT (email) DO NOTHING
            """,
            (oauth_email, oauth_name, datetime.now().isoformat(timespec="seconds")),
        )
        cur.execute(
            """
            SELECT id, email, name, password_hash, height_cm, weight_kg, age_years, agent_id, profile_image_base64
            FROM users
            WHERE email = ?
            LIMIT 1
            """,
            (oauth_email,),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=500, detail="Unable to resolve user after OAuth callback")

    return AuthResponse(
        user_id=int(row[0]),
        email=str(row[1]),
        name=str(row[2] or oauth_name),
        onboarding_completed=_onboarding_completed_from_row(row),
    )


@app.post("/api/billing/checkout-session", response_model=BillingCheckoutResponse)
def create_checkout_session(payload: BillingCheckoutRequest):
    if payload.plan_tier.lower() != "premium":
        raise HTTPException(status_code=400, detail="Only premium checkout is supported.")

    # Re-load environment variables to ensure we have the latest values
    load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), ".env"), override=True)

    stripe_secret_key = os.getenv("STRIPE_SECRET_KEY", "").strip()
    stripe_price_id = os.getenv("STRIPE_PREMIUM_PRICE_ID", "").strip()
    if not stripe_secret_key:
        raise HTTPException(status_code=500, detail="Missing STRIPE_SECRET_KEY env var.")

    stripe.api_key = stripe_secret_key
    success_url = os.getenv("STRIPE_SUCCESS_URL", "https://example.com/billing/success")
    cancel_url = os.getenv("STRIPE_CANCEL_URL", "https://example.com/billing/cancel")

    user_email = None
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT email FROM users WHERE id = ? LIMIT 1", (payload.user_id,))
        row = cur.fetchone()
        if row and row[0]:
            user_email = str(row[0]).strip()

    line_items: List[Dict[str, Any]]
    if stripe_price_id:
        line_items = [{"price": stripe_price_id, "quantity": 1}]
    else:
        # Fallback inline subscription pricing for local testing.
        line_items = [
            {
                "price_data": {
                    "currency": "usd",
                    "product_data": {"name": "Vaylo Fitness Premium Plan"},
                    "unit_amount": 1499,
                    "recurring": {"interval": "month"},
                },
                "quantity": 1,
            }
        ]

    base_params: Dict[str, Any] = {
        "mode": "subscription",
        "line_items": line_items,
        "billing_address_collection": "required",
        "success_url": success_url,
        "cancel_url": cancel_url,
        "customer_email": user_email or None,
        "metadata": {
            "user_id": str(payload.user_id),
            "plan_tier": "premium",
        },
    }

    try:
        session = stripe.checkout.Session.create(**base_params)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to create checkout session: {exc}") from exc

    checkout_url = getattr(session, "url", None)
    session_id = getattr(session, "id", "")
    if not checkout_url or not session_id:
        raise HTTPException(status_code=500, detail="Stripe checkout session missing url or id.")
    return BillingCheckoutResponse(checkout_url=checkout_url, session_id=session_id)


@app.post("/coach/chat", response_model=CoachChatResponse)
def coach_chat(payload: CoachChatRequest):
    """Chat with the AI coach using the agent graph."""
    if payload.image_base64:
        try:
            image_bytes = base64.b64decode(payload.image_base64)
            analyzed = _analyze_food_image(image_bytes)
            idem = f"img:{hashlib.sha256(image_bytes).hexdigest()}"
            _store_meal_log(
                FoodLogRequest(
                    user_id=payload.user_id,
                    food_name=analyzed.food_name,
                    total_calories=analyzed.total_calories,
                    protein_g=analyzed.protein_g,
                    carbs_g=analyzed.carbs_g,
                    fat_g=analyzed.fat_g,
                    items=analyzed.items,
                    logged_at=datetime.now().isoformat(timespec="seconds"),
                    idempotency_key=idem,
                )
            )
            item_lines = []
            for item in analyzed.items[:6]:
                qty = item.amount or "estimated portion"
                item_lines.append(f"- {item.name}: {qty} (~{item.calories} kcal)")
            details = "\n".join(item_lines) if item_lines else "- Meal items detected."
            reply = (
                "I analyzed your photo and logged your meal.\n"
                f"Detected: {analyzed.food_name}\n"
                f"Totals: {analyzed.total_calories} kcal, P {int(analyzed.protein_g)}g, "
                f"C {int(analyzed.carbs_g)}g, F {int(analyzed.fat_g)}g\n"
                f"{details}"
            )
            return CoachChatResponse(reply=reply, thread_id=payload.thread_id or f"user:{payload.user_id}")
        except Exception as exc:
            raise HTTPException(status_code=400, detail=f"Image meal analysis failed: {exc}") from exc

    graph, preload_fn = _get_agent_graph()
    thread_id = payload.thread_id or f"user:{payload.user_id}"
    config = {"configurable": {"thread_id": thread_id}}

    resolved_agent = _resolve_coach_slug(payload.agent_id)
    if resolved_agent:
        SESSION_CACHE.setdefault(payload.user_id, {})["agent_id"] = resolved_agent

    if thread_id not in _AGENT_PRELOADED:
        preload_fn(payload.user_id)
        _AGENT_PRELOADED.add(thread_id)

    try:
        message = payload.message
        if payload.image_base64:
            try:
                encoded = _strip_data_url_prefix(payload.image_base64)
                image_bytes = base64.b64decode(encoded)
                analysis = _summarize_image(image_bytes, payload.message)
                if analysis:
                    if message:
                        message = f"{message}\n\nImage analysis: {analysis}"
                    else:
                        message = f"Image analysis: {analysis}"
            except Exception as exc:
                raise HTTPException(status_code=400, detail=f"Invalid image data: {exc}") from exc

        state = graph.invoke(
            {
                "messages": [HumanMessage(content=message)],
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


def _analyze_food_image(image: bytes) -> FoodScanResponse:
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
        raise RuntimeError("Failed to parse AI response")
    items = payload.get("items", []) or []
    if isinstance(items, list):
        for item in items:
            if isinstance(item, dict) and not item.get("category"):
                item["category"] = _categorize_food_name(item.get("name", ""))
    if not payload.get("total_calories"):
        payload["total_calories"] = sum(int(item.get("calories", 0)) for item in items if isinstance(item, dict))
    return FoodScanResponse(**payload)


@app.post("/food/scan", response_model=FoodScanResponse)
async def scan_food(file: UploadFile = File(...)):
    """Analyze a meal photo and return detected foods and macros."""
    if file is None:
        raise HTTPException(status_code=400, detail="Missing image file")
    image = await file.read()
    try:
        return _analyze_food_image(image)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Failed to analyze image: {exc}") from exc


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
        "You are a nutrition coach and recipe creator. Generate exactly 1 healthy recipe. "
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
        "\"tags\":[string],"
        "\"source_links\":[string]"
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
    fallback_recipe = {
        "id": str(uuid.uuid4()),
        "name": "Trainer Suggestion",
        "summary": "Balanced, high-protein bowl tailored to your current plan and ingredients.",
        "calories": int(per_meal_target),
        "protein_g": max(25, int(per_meal_target * 0.25 / 4)),
        "carbs_g": max(30, int(per_meal_target * 0.45 / 4)),
        "fat_g": max(10, int(per_meal_target * 0.30 / 9)),
        "ingredients": combined[:8] if combined else ["lean protein", "rice", "mixed vegetables", "olive oil", "seasoning"],
        "steps": [
            "Prep ingredients and season protein.",
            "Cook protein until done and set aside.",
            "Cook carbs base and warm vegetables.",
            "Assemble bowl and finish with healthy fats.",
        ],
        "tags": ["balanced", "high-protein", payload.cuisine or "any-cuisine"],
        "source_links": [
            "https://www.eatright.org/fitness/sports-and-performance/fueling-your-workout",
            "https://www.health.harvard.edu/staying-healthy/healthy-eating-plate",
        ],
    }

    try:
        content = _gemini_generate_content(prompt, temperature=0.3)
        payload_json = _safe_parse_json(content)
        recipes_raw = payload_json.get("recipes", []) if isinstance(payload_json, dict) else []
        recipes = []
        for item in recipes_raw[:1]:
            if not isinstance(item, dict):
                continue
            item["id"] = item.get("id") or str(uuid.uuid4())
            item["name"] = "Trainer Suggestion"
            source_links = item.get("source_links")
            if not isinstance(source_links, list) or not source_links:
                item["source_links"] = fallback_recipe["source_links"]
            recipes.append(item)
        if not recipes:
            recipes = [fallback_recipe]
        detected = payload_json.get("detected_ingredients", []) if isinstance(payload_json, dict) else []
        return RecipeSuggestResponse(
            recipes=[RecipeSuggestion(**item) for item in recipes],
            detected_ingredients=detected or detected_ingredients,
        )
    except Exception:
        return RecipeSuggestResponse(
            recipes=[RecipeSuggestion(**fallback_recipe)],
            detected_ingredients=detected_ingredients,
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
def get_daily_intake(user_id: int, day: Optional[str] = None):
    """Return daily calorie intake totals for a user."""
    _ensure_meal_log_schema()
    target_day = day or date.today().isoformat()
    cache_key = f"daily_intake:{user_id}:{target_day}"
    cached = _redis_get_json(cache_key)
    if isinstance(cached, dict):
        try:
            return DailyIntakeResponse(**cached)
        except Exception:
            pass
    start = f"{target_day}T00:00:00"
    end = f"{target_day}T23:59:59"
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg
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
    total_fiber = sum(float(row[4] or 0) for row in rows)
    total_sugar = sum(float(row[5] or 0) for row in rows)
    total_sodium = sum(float(row[6] or 0) for row in rows)
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
    response = DailyIntakeResponse(
        date=target_day,
        total_calories=total_calories,
        total_protein_g=total_protein,
        total_carbs_g=total_carbs,
        total_fat_g=total_fat,
        total_fiber_g=total_fiber,
        total_sugar_g=total_sugar,
        total_sodium_mg=total_sodium,
        meals_count=len(rows),
        daily_calorie_target=daily_target,
    )
    _redis_set_json(cache_key, response.model_dump(), ttl_seconds=180)
    return response


@app.get("/food/logs", response_model=DailyMealLogsResponse)
def get_food_logs(user_id: int, day: Optional[str] = None):
    """Return logged meals for a specific day."""
    _ensure_meal_log_schema()
    target_day = day or date.today().isoformat()
    bucket_key = f"user:{user_id}:meal_logs"
    cached_bucket = _redis_get_json(bucket_key)
    if isinstance(cached_bucket, dict):
        cached_day = cached_bucket.get(target_day)
        if isinstance(cached_day, dict):
            try:
                return DailyMealLogsResponse(**cached_day)
            except Exception:
                pass
    start = f"{target_day}T00:00:00"
    end = f"{target_day}T23:59:59"
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT description, calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg, logged_at
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
            fiber_g=float(row[5] or 0),
            sugar_g=float(row[6] or 0),
            sodium_mg=float(row[7] or 0),
            logged_at=row[8],
        )
        for row in rows
    ]
    response = DailyMealLogsResponse(date=target_day, meals=meals)
    bucket = cached_bucket if isinstance(cached_bucket, dict) else {}
    bucket[target_day] = response.model_dump()
    if len(bucket) > 14:
        for key in sorted(bucket.keys())[:-14]:
            bucket.pop(key, None)
    _redis_set_json(bucket_key, bucket, ttl_seconds=600)
    return response


@app.get("/plans/today", response_model=PlanDayResponse)
def get_today_plan(user_id: int, day: Optional[str] = None):
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
def get_profile(user_id: int):
    """Return user profile and preferences."""
    _ensure_profile_schema()
    return _load_user_profile(user_id)


@app.get("/api/coaches", response_model=List[CoachItemResponse])
def get_coaches():
    _ensure_coach_schema()
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, slug, name, nickname, title, age, ethnicity, gender, pronouns,
                   philosophy, background_story, personality, speaking_style,
                   expertise, common_phrases, tags,
                   primary_color, secondary_color, image_url, video_url
            FROM coaches
            ORDER BY id ASC
            """
        )
        rows = cur.fetchall()

    coaches: List[CoachItemResponse] = []
    for row in rows:
        coaches.append(
            CoachItemResponse(
                id=int(row[0]),
                slug=str(row[1] or ""),
                name=str(row[2] or ""),
                nickname=str(row[3]) if row[3] is not None else None,
                title=str(row[4] or "Coach"),
                age=int(row[5]) if row[5] is not None else 30,
                ethnicity=str(row[6] or "Unknown"),
                gender=str(row[7] or "Unknown"),
                pronouns=str(row[8] or ""),
                philosophy=str(row[9] or ""),
                background_story=str(row[10] or ""),
                personality=str(row[11] or ""),
                speaking_style=str(row[12] or ""),
                expertise=_as_string_list(row[13]),
                common_phrases=_as_string_list(row[14]),
                tags=_as_string_list(row[15]),
                primary_color=str(row[16] or "blue"),
                secondary_color=str(row[17] or "navy"),
                image_url=str(row[18]) if row[18] is not None else None,
                video_url=str(row[19]) if row[19] is not None else None,
            )
        )
    return coaches


@app.put("/api/profile")
def update_profile(payload: ProfileUpdateRequest):
    _ensure_profile_schema()
    _ensure_coach_schema()
    user_fields: Dict[str, Any] = {}
    weight_updated = False
    if payload.name is not None:
        user_fields["name"] = payload.name
    if payload.birthdate is not None:
        user_fields["birthdate"] = payload.birthdate
    if payload.height_cm is not None:
        user_fields["height_cm"] = payload.height_cm
    if payload.weight_kg is not None:
        user_fields["weight_kg"] = payload.weight_kg
        weight_updated = True
    if payload.gender is not None:
        user_fields["gender"] = payload.gender
    if payload.age_years is not None:
        user_fields["age_years"] = payload.age_years
    if payload.profile_image_base64 is not None:
        user_fields["profile_image_base64"] = payload.profile_image_base64

    pref_fields: Dict[str, Any] = {}
    if payload.activity_level is not None:
        pref_fields["activity_level"] = payload.activity_level
    if payload.goal_type is not None:
        pref_fields["goal_type"] = payload.goal_type
    if payload.target_weight_kg is not None:
        pref_fields["target_weight_kg"] = payload.target_weight_kg
    if payload.dietary_preferences is not None:
        pref_fields["dietary_preferences"] = payload.dietary_preferences
    if payload.workout_preferences is not None:
        pref_fields["workout_preferences"] = payload.workout_preferences
    if payload.allergies is not None:
        pref_fields["allergies"] = payload.allergies
    if payload.preferred_workout_time is not None:
        pref_fields["preferred_workout_time"] = payload.preferred_workout_time
    if payload.menstrual_cycle_notes is not None:
        pref_fields["menstrual_cycle_notes"] = payload.menstrual_cycle_notes

    with get_db_conn() as conn:
        cur = conn.cursor()
        if payload.agent_id is not None:
            cur.execute("SELECT agent_id, last_agent_change_at FROM users WHERE id = ? LIMIT 1", (payload.user_id,))
            current_row = cur.fetchone()
            if not current_row:
                raise HTTPException(status_code=404, detail="User not found")
            current_agent_id = int(current_row[0]) if current_row[0] is not None else None
            if payload.agent_id != current_agent_id:
                cooldown_state = _agent_change_cooldown_state(current_row[1])
                if cooldown_state["blocked"]:
                    raise HTTPException(
                        status_code=429,
                        detail=(
                            f"You can change coaches once every {COACH_CHANGE_COOLDOWN_DAYS} days. "
                            f"Try again in about {cooldown_state['retry_after_days']} day(s)."
                        ),
                    )
                user_fields["last_agent_change_at"] = datetime.now(timezone.utc).isoformat()
            user_fields["agent_id"] = payload.agent_id
            user_fields["coach_voice"] = _default_voice_for_agent(payload.agent_id)
        if user_fields:
            set_clause = ", ".join(f"{key} = ?" for key in user_fields.keys())
            params = list(user_fields.values()) + [payload.user_id]
            cur.execute(f"UPDATE users SET {set_clause} WHERE id = ?", params)
            if weight_updated and payload.weight_kg is not None:
                _upsert_daily_weight_checkin(payload.user_id, float(payload.weight_kg), conn=conn)
                reason = f"checkin_log:{date.today().isoformat()}"
                if not _has_points_reason(payload.user_id, reason):
                    _award_points(payload.user_id, 5, reason)
                _apply_daily_checklist_completion_bonus(payload.user_id, date.today().isoformat())

        if pref_fields:
            cur.execute("SELECT 1 FROM user_preferences WHERE user_id = ? LIMIT 1", (payload.user_id,))
            has_row = cur.fetchone() is not None
            if not has_row:
                created_at = datetime.now().isoformat(timespec="seconds")
                cur.execute(
                    """
                    INSERT INTO user_preferences (
                        user_id, weekly_weight_change_kg, activity_level, goal_type,
                        target_weight_kg, dietary_preferences, workout_preferences, timezone, created_at,
                        allergies, preferred_workout_time, menstrual_cycle_notes
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        payload.user_id,
                        None,
                        pref_fields.get("activity_level"),
                        pref_fields.get("goal_type"),
                        pref_fields.get("target_weight_kg"),
                        pref_fields.get("dietary_preferences"),
                        pref_fields.get("workout_preferences"),
                        None,
                        created_at,
                        pref_fields.get("allergies"),
                        pref_fields.get("preferred_workout_time"),
                        pref_fields.get("menstrual_cycle_notes"),
                    ),
                )
            else:
                set_clause = ", ".join(f"{key} = ?" for key in pref_fields.keys())
                params = list(pref_fields.values()) + [payload.user_id]
                cur.execute(f"UPDATE user_preferences SET {set_clause} WHERE user_id = ?", params)
        conn.commit()

    if weight_updated:
        _invalidate_user_activity_cache(payload.user_id, day=date.today().isoformat())
    _refresh_profile_cache(payload.user_id)
    return _load_user_profile(payload.user_id)


@app.post("/api/test-coach")
def test_coach_endpoint():
    return {"status": "coach endpoint works"}

@app.post("/api/change-coach", response_model=CoachChangeResponse)
def change_user_coach(payload: CoachChangeRequest) -> CoachChangeResponse:
    """
    Change the user's assigned coach
    """
    _ensure_profile_schema()
    _ensure_coach_schema()

    with get_db_conn() as conn:
        cur = conn.cursor()

        # Check if user exists
        cur.execute("SELECT id, agent_id, last_agent_change_at FROM users WHERE id = ?", (payload.user_id,))
        user_row = cur.fetchone()
        if not user_row:
            raise HTTPException(status_code=404, detail="User not found")
        current_agent_id = int(user_row[1]) if user_row[1] is not None else None
        cooldown_state = _agent_change_cooldown_state(user_row[2])
        if current_agent_id == payload.new_coach_id:
            return CoachChangeResponse(success=True, message="Coach already selected")
        if cooldown_state["blocked"]:
            raise HTTPException(
                status_code=429,
                detail=(
                    f"You can change coaches once every {COACH_CHANGE_COOLDOWN_DAYS} days. "
                    f"Try again in about {cooldown_state['retry_after_days']} day(s)."
                ),
            )

        # Validate coach exists
        cur.execute("SELECT id FROM coaches WHERE id = ? LIMIT 1", (payload.new_coach_id,))
        if not cur.fetchone():
            raise HTTPException(status_code=400, detail=f"Invalid coach ID: {payload.new_coach_id}")

        # Update the user's coach assignment
        changed_at = datetime.now(timezone.utc).isoformat()
        cur.execute(
            "UPDATE users SET agent_id = ?, coach_voice = ?, last_agent_change_at = ? WHERE id = ?",
            (
                payload.new_coach_id,
                _default_voice_for_agent(payload.new_coach_id),
                changed_at,
                payload.user_id,
            )
        )

        # user_preferences does not store coach_id; agent_name lives on users

        conn.commit()

    # Refresh caches
    _refresh_profile_cache(payload.user_id)
    _redis_delete(f"session_hydration:{payload.user_id}")

    return CoachChangeResponse(
        success=True,
        message=f"Coach successfully changed to {payload.new_coach_id}",
        next_change_available_at=(datetime.now(timezone.utc) + timedelta(days=COACH_CHANGE_COOLDOWN_DAYS)).isoformat(),
        retry_after_days=COACH_CHANGE_COOLDOWN_DAYS,
    )


@app.get("/api/voice")
def generate_voice(
    text: str = Query(..., min_length=1),
    voice: str = Query("alloy"),
    instructions: Optional[str] = Query(None),
):
    """Generate TTS audio from text."""
    try:
        client = _get_openai_client()
        args: Dict[str, Any] = {
            "model": "gpt-4o-mini-tts",
            "voice": voice,
            "input": text,
        }
        if instructions:
            args["instructions"] = instructions
        response = client.audio.speech.create(**args)
        return Response(content=response.content, media_type="audio/mpeg")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"TTS failed: {exc}") from exc


@app.post("/api/voice-to-text")
async def voice_to_text(
    audio: UploadFile = File(...),
    trainer_id: str = Form(...),
):
    """Transcribe voice audio to text using Whisper."""
    try:
        client = _get_openai_client()
        audio_bytes = await audio.read()
        suffix = os.path.splitext(audio.filename or "")[1] or ".m4a"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as handle:
            handle.write(audio_bytes)
            temp_path = handle.name
        with open(temp_path, "rb") as audio_file:
            transcript = client.audio.transcriptions.create(
                model="whisper-1",
                file=audio_file,
            )
        os.remove(temp_path)
        return {"transcribed_text": transcript.text, "trainer_id": trainer_id}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Voice-to-text failed: {exc}") from exc


@app.post("/api/upload-image")
async def upload_image(
    image: UploadFile = File(...),
    trainer_id: str = Form(...),
    message: Optional[str] = Form(None),
):
    """Accept an image upload and return base64 for downstream use."""
    try:
        image_bytes = await image.read()
        image_base64 = base64.b64encode(image_bytes).decode("utf-8")
        return {
            "image_base64": image_base64,
            "trainer_id": trainer_id,
            "message": message,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Image upload failed: {exc}") from exc
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
def get_progress(user_id: int):
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
        "daily_checklist": _daily_checklist_status(user_id, date.today().isoformat()),
    }


@app.post("/api/health-activity/log")
def log_health_activity(payload: HealthActivityLogRequest):
    target_day_date = _coerce_to_date(payload.date) or date.today()
    target_day = target_day_date.isoformat()
    source = (payload.source or "apple_health").strip() or "apple_health"
    workouts_summary = (payload.workouts_summary or "").strip()
    if payload.active_minutes > 0:
        suffix = f"active_minutes={int(payload.active_minutes)}"
        workouts_summary = f"{workouts_summary}; {suffix}" if workouts_summary else suffix

    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            DELETE FROM health_activity
            WHERE user_id = ? AND date = ? AND source = ?
            """,
            (payload.user_id, target_day, source),
        )
        cur.execute(
            """
            INSERT INTO health_activity (user_id, date, steps, calories_burned, workouts_summary, source)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                payload.user_id,
                target_day,
                max(0, int(payload.steps)),
                max(0, int(payload.calories_burned)),
                workouts_summary or None,
                source,
            ),
        )
        conn.commit()

    _invalidate_health_activity_cache(payload.user_id)
    return {"ok": True, "date": target_day}


@app.get("/api/health-activity/impact", response_model=HealthActivityImpactResponse)
def get_health_activity_impact(
    user_id: int,
    start_day: Optional[str] = None,
    end_day: Optional[str] = None,
    days: int = 7,
):
    from agent.tools.activity_utils import _estimate_workout_calories

    range_end = _coerce_to_date(end_day) or date.today()
    default_start = range_end - timedelta(days=max(1, min(31, int(days))) - 1)
    range_start = _coerce_to_date(start_day) or default_start
    if range_start > range_end:
        range_start, range_end = range_end, range_start

    day_cursor = range_start
    day_keys: List[str] = []
    while day_cursor <= range_end:
        day_keys.append(day_cursor.isoformat())
        day_cursor += timedelta(days=1)

    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT date, steps, calories_burned, workouts_summary, source
            FROM health_activity
            WHERE user_id = ? AND date >= ? AND date <= ?
            ORDER BY date ASC
            """,
            (user_id, range_start.isoformat(), range_end.isoformat()),
        )
        activity_rows = cur.fetchall()

    activity_by_day: Dict[str, Dict[str, Any]] = {}
    for row in activity_rows:
        day = str(row[0])
        activity_by_day[day] = {
            "steps": int(row[1] or 0),
            "calories_burned": int(row[2] or 0),
            "workouts_summary": str(row[3] or ""),
            "source": str(row[4] or "unknown"),
        }

    meals_by_day: Dict[str, int] = {}
    for meal in _list_meal_logs(user_id):
        logged_at = str(meal.get("logged_at") or "")
        day_value = _coerce_to_date(logged_at)
        if not day_value:
            continue
        day_key = day_value.isoformat()
        if day_key not in day_keys:
            continue
        meals_by_day[day_key] = meals_by_day.get(day_key, 0) + int(meal.get("calories") or 0)

    plan_days_by_date: Dict[str, Dict[str, Any]] = {}
    weight_kg = 70.0
    try:
        profile = _load_user_profile(user_id)
        weight_kg = float(profile.get("user", {}).get("weight_kg") or 70.0)
    except Exception:
        pass
    try:
        from agent.tools.plan_tools import _get_active_plan_bundle_data

        bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
        for plan_day in bundle.get("plan_days", []):
            day_key = str(plan_day.get("date") or "")
            if day_key:
                plan_days_by_date[day_key] = plan_day
    except Exception:
        plan_days_by_date = {}

    def _extract_minutes(label: str) -> int:
        lowered = label.lower()
        match = re.search(r"(\d{1,3})\s*min", lowered)
        if match:
            try:
                return max(10, int(match.group(1)))
            except Exception:
                return 30
        return 30

    items: List[HealthActivityImpactItemResponse] = []
    for day_key in day_keys:
        activity = activity_by_day.get(day_key, {})
        meal_intake = int(meals_by_day.get(day_key, 0))
        plan_day = plan_days_by_date.get(day_key, {})
        meal_target = plan_day.get("calorie_target")
        workout_label = str(plan_day.get("workout_plan") or "").strip()
        expected_burn: Optional[int] = None
        if workout_label and workout_label.lower() != "rest day":
            estimated = _estimate_workout_calories(
                max(35.0, weight_kg),
                [{"name": workout_label, "duration_min": _extract_minutes(workout_label)}],
                _extract_minutes(workout_label),
            )
            expected_burn = int(max(0, estimated))

        health_burn = int(activity.get("calories_burned", 0))
        burn_delta = (health_burn - expected_burn) if expected_burn is not None else None
        intake_delta = (meal_intake - int(meal_target)) if meal_target is not None else None

        active_minutes = 0
        summary_text = str(activity.get("workouts_summary") or "")
        active_match = re.search(r"active_minutes=(\d+)", summary_text)
        if active_match:
            try:
                active_minutes = int(active_match.group(1))
            except Exception:
                active_minutes = 0
        clean_summary = re.sub(r";?\s*active_minutes=\d+", "", summary_text).strip(" ;")

        items.append(
            HealthActivityImpactItemResponse(
                date=day_key,
                steps=int(activity.get("steps", 0)),
                health_calories_burned=health_burn,
                active_minutes=active_minutes,
                workouts_summary=clean_summary,
                source=str(activity.get("source") or "unknown"),
                meal_intake=meal_intake,
                meal_target=int(meal_target) if meal_target is not None else None,
                workout_expected_burn=expected_burn,
                burn_delta=burn_delta,
                intake_delta=intake_delta,
            )
        )

    return HealthActivityImpactResponse(
        start_day=range_start.isoformat(),
        end_day=range_end.isoformat(),
        items=items,
    )


@app.get("/api/gamification", response_model=GamificationResponse)
def get_gamification(user_id: int):
    return _gamification_summary(user_id)


@app.post("/api/gamification/app-open", response_model=AppOpenStreakResponse)
def gamification_app_open(user_id: int):
    _ensure_app_open_schema()
    now = datetime.now()
    inactivity_hours = 0.0
    freeze_prompt_required = False
    streak_reset = False
    message = "Welcome back."

    has_existing_open_row = False
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT last_open_at FROM app_open_events WHERE user_id = ? LIMIT 1", (user_id,))
        row = cur.fetchone()
        has_existing_open_row = row is not None
        if row and row[0]:
            try:
                parsed_open = datetime.fromisoformat(str(row[0]))
                inactivity_hours = max(0.0, (now - parsed_open).total_seconds() / 3600.0)
            except Exception:
                inactivity_hours = 0.0

    summary = _gamification_summary(user_id)
    if inactivity_hours >= 24.0:
        if int(summary.get("freeze_streaks", 0)) > 0:
            freeze_prompt_required = True
            message = "You were away for over 24h. Use a freeze to keep your streak?"
        else:
            _set_streak_for_today(user_id, keep_count=False)
            streak_reset = True
            summary = _gamification_summary(user_id)
            message = "Your streak reset after 24h inactivity. Start a new streak today."

    if not freeze_prompt_required:
        with get_db_conn() as conn:
            cur = conn.cursor()
            if has_existing_open_row:
                cur.execute(
                    "UPDATE app_open_events SET last_open_at = ? WHERE user_id = ?",
                    (now.isoformat(timespec="seconds"), user_id),
                )
            else:
                cur.execute(
                    "INSERT INTO app_open_events (user_id, last_open_at) VALUES (?, ?)",
                    (user_id, now.isoformat(timespec="seconds")),
                )
            conn.commit()

    return AppOpenStreakResponse(
        freeze_prompt_required=freeze_prompt_required,
        inactivity_hours=round(inactivity_hours, 1),
        streak_reset=streak_reset,
        message=message,
        gamification=GamificationResponse(**summary),
    )


@app.post("/api/gamification/streak-decision", response_model=AppOpenStreakResponse)
def gamification_streak_decision(payload: StreakDecisionRequest):
    summary = _gamification_summary(payload.user_id)
    if payload.use_freeze:
        if int(summary.get("freeze_streaks", 0)) <= 0:
            raise HTTPException(status_code=400, detail="No freeze streaks available")
        reason = f"freeze_used:{date.today().isoformat()}"
        if not _has_points_reason(payload.user_id, reason):
            _award_points(payload.user_id, 0, reason)
        _set_streak_for_today(payload.user_id, keep_count=True)
        message = "Freeze used. Your streak is preserved."
    else:
        _set_streak_for_today(payload.user_id, keep_count=False)
        message = "Streak reset. You can build it back starting today."

    refreshed = _gamification_summary(payload.user_id)
    _ensure_app_open_schema()
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO app_open_events (user_id, last_open_at)
            VALUES (?, ?)
            ON CONFLICT(user_id) DO UPDATE SET last_open_at = excluded.last_open_at
            """,
            (payload.user_id, datetime.now().isoformat(timespec="seconds")),
        )
        conn.commit()
    return AppOpenStreakResponse(
        freeze_prompt_required=False,
        inactivity_hours=0.0,
        streak_reset=not payload.use_freeze,
        message=message,
        gamification=GamificationResponse(**refreshed),
    )


@app.post("/api/gamification/use-freeze", response_model=GamificationResponse)
def use_freeze_streak(payload: UseFreezeRequest):
    summary = _gamification_summary(payload.user_id)
    if int(summary.get("freeze_streaks", 0)) <= 0:
        raise HTTPException(status_code=400, detail="No freeze streaks available")
    reason = f"freeze_used:{date.today().isoformat()}"
    if _has_points_reason(payload.user_id, reason):
        raise HTTPException(status_code=400, detail="Freeze already used today")
    _award_points(payload.user_id, 0, reason)
    _set_streak_for_today(payload.user_id, keep_count=True)
    return _gamification_summary(payload.user_id)


@app.get("/api/coach-suggestion")
def get_coach_suggestion(user_id: int):
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


@app.get("/api/status-summary")
def get_status_summary(user_id: int):
    """Return end-of-day style status summary + actionable suggestions."""
    try:
        from agent.tools.plan_tools import compute_plan_status

        status_raw = compute_plan_status.func(user_id)
        status = _safe_parse_json(status_raw)
    except Exception:
        status = {"explanation": "No status available.", "status": "limited"}

    suggestions: List[str] = []
    last_7d = status.get("last_7d") if isinstance(status, dict) else None
    if isinstance(last_7d, dict):
        workouts_done = int(last_7d.get("workouts_done") or 0)
        workouts_planned = int(last_7d.get("workouts_planned") or 0)
        meal_log_days = int(last_7d.get("meal_log_days") or 0)
        if workouts_planned > workouts_done:
            suggestions.append("You missed some workouts. Want me to add reminders or rebalance this week?")
        if meal_log_days < 4:
            suggestions.append("Meal logging is sparse this week. Set reminders for key meal windows?")
        avg_target = last_7d.get("avg_target_kcal")
        avg_intake = last_7d.get("avg_intake_kcal")
        if avg_target is not None and avg_intake is not None:
            delta = int(avg_intake) - int(avg_target)
            if abs(delta) >= 150:
                direction = "over" if delta > 0 else "under"
                suggestions.append(
                    f"Your intake trend is {abs(delta)} kcal/day {direction} target. Want a calorie adjustment?"
                )

    if not suggestions:
        suggestions.append("You are in a solid spot. Want to keep the plan as-is or tweak anything?")
    health_summary: Dict[str, Any] = {"days_with_health_data": 0, "avg_steps": 0, "avg_burn_kcal": 0}
    try:
        end_day = date.today()
        start_day = end_day - timedelta(days=6)
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT date, steps, calories_burned, source
                FROM health_activity
                WHERE user_id = ? AND date >= ? AND date <= ? AND source = ?
                ORDER BY date ASC
                """,
                (user_id, start_day.isoformat(), end_day.isoformat(), "apple_health"),
            )
            rows = cur.fetchall()
        if rows:
            steps_total = sum(int(row[1] or 0) for row in rows)
            burn_total = sum(int(row[2] or 0) for row in rows)
            day_count = len(rows)
            health_summary = {
                "days_with_health_data": day_count,
                "avg_steps": int(steps_total / day_count),
                "avg_burn_kcal": int(burn_total / day_count),
            }
            if health_summary["avg_steps"] < 5000:
                suggestions.append("Apple Health shows lower daily movement. Want a step goal reminder added?")
    except Exception:
        pass

    return {"status": status, "health_activity_summary": health_summary, "suggestions": suggestions}


@app.get("/api/reminders", response_model=List[ReminderItemResponse])
def get_reminders_api(user_id: int):
    _ensure_daily_coach_checkin_reminder(user_id)
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, reminder_type, scheduled_at, status, channel, related_plan_override_id
            FROM reminders
            WHERE user_id = ?
            ORDER BY scheduled_at ASC
            """,
            (user_id,),
        )
        rows = cur.fetchall()
    return [
        ReminderItemResponse(
            id=int(row[0]),
            reminder_type=str(row[1]),
            scheduled_at=str(row[2]),
            status=str(row[3]),
            channel=str(row[4]),
            related_plan_override_id=int(row[5]) if row[5] is not None else None,
        )
        for row in rows
    ]


@app.post("/api/reminders", response_model=ReminderItemResponse)
def create_reminder_api(payload: ReminderCreateRequest):
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO reminders (user_id, reminder_type, scheduled_at, status, channel, related_plan_override_id)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                payload.user_id,
                payload.reminder_type,
                payload.scheduled_at,
                payload.status,
                payload.channel,
                None,
            ),
        )
        reminder_id = int(cur.lastrowid or 0)
        conn.commit()
        cur.execute(
            """
            SELECT id, reminder_type, scheduled_at, status, channel, related_plan_override_id
            FROM reminders
            WHERE id = ? AND user_id = ?
            LIMIT 1
            """,
            (reminder_id, payload.user_id),
        )
        row = cur.fetchone()
    _invalidate_reminders_cache(payload.user_id)
    if not row:
        raise HTTPException(status_code=500, detail="Failed to create reminder")
    return ReminderItemResponse(
        id=int(row[0]),
        reminder_type=str(row[1]),
        scheduled_at=str(row[2]),
        status=str(row[3]),
        channel=str(row[4]),
        related_plan_override_id=int(row[5]) if row[5] is not None else None,
    )


@app.put("/api/reminders/{reminder_id}", response_model=ReminderItemResponse)
def update_reminder_api(reminder_id: int, payload: ReminderUpdateRequest):
    fields: List[str] = []
    values: List[Any] = []
    if payload.status is not None:
        fields.append("status = ?")
        values.append(payload.status)
    if payload.scheduled_at is not None:
        fields.append("scheduled_at = ?")
        values.append(payload.scheduled_at)
    if not fields:
        raise HTTPException(status_code=400, detail="No reminder fields to update")

    with get_db_conn() as conn:
        cur = conn.cursor()
        values.extend([payload.user_id, reminder_id])
        cur.execute(
            f"UPDATE reminders SET {', '.join(fields)} WHERE user_id = ? AND id = ?",
            values,
        )
        conn.commit()
        cur.execute(
            """
            SELECT id, reminder_type, scheduled_at, status, channel, related_plan_override_id
            FROM reminders
            WHERE id = ? AND user_id = ?
            LIMIT 1
            """,
            (reminder_id, payload.user_id),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Reminder not found")
    _invalidate_reminders_cache(payload.user_id)
    return ReminderItemResponse(
        id=int(row[0]),
        reminder_type=str(row[1]),
        scheduled_at=str(row[2]),
        status=str(row[3]),
        channel=str(row[4]),
        related_plan_override_id=int(row[5]) if row[5] is not None else None,
    )


@app.delete("/api/reminders/{reminder_id}")
def delete_reminder_api(reminder_id: int, user_id: int):
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("DELETE FROM reminders WHERE id = ? AND user_id = ?", (reminder_id, user_id))
        deleted = int(cur.rowcount or 0)
        conn.commit()
    if deleted <= 0:
        raise HTTPException(status_code=404, detail="Reminder not found")
    _invalidate_reminders_cache(user_id)
    return {"ok": True}


@app.get("/api/session/hydrate", response_model=SessionHydrationResponse)
def hydrate_session(user_id: int, day: Optional[str] = None):
    target_day = day or date.today().isoformat()
    _ensure_daily_coach_checkin_reminder(user_id)
    profile = _load_user_profile(user_id)
    progress = get_progress(user_id)
    daily_intake = get_daily_intake(user_id, target_day)
    gamification = _gamification_summary(user_id)
    coach_suggestion = get_coach_suggestion(user_id)
    today_plan: Optional[PlanDayResponse] = None
    try:
        today_plan = get_today_plan(user_id, target_day)
    except HTTPException:
        today_plan = None
    return SessionHydrationResponse(
        user_id=user_id,
        date=target_day,
        profile=profile,
        progress=progress,
        today_plan=today_plan,
        daily_intake=daily_intake,
        gamification=GamificationResponse(**gamification),
        coach_suggestion=coach_suggestion.get("suggestion") if isinstance(coach_suggestion, dict) else None,
    )


@app.get("/api/health")
def health_check():
    try:
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT 1")
            cur.fetchone()
        return {"ok": True, "db": "postgres"}
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
    _ensure_coach_schema()
    _ensure_profile_schema()
    user_id = payload.user_id or 1
    fields = []
    values: list[Any] = []
    selected_trainer_id: Optional[int] = None
    if payload.current_weight_kg is not None:
        fields.append("weight_kg = ?")
        values.append(payload.current_weight_kg)
    if payload.height_cm is not None:
        fields.append("height_cm = ?")
        values.append(payload.height_cm)
    if payload.age is not None:
        fields.append("age_years = ?")
        values.append(payload.age)
    if payload.trainer_id is not None:
        fields.append("agent_id = ?")
        values.append(payload.trainer_id)
        selected_trainer_id = int(payload.trainer_id)
    elif payload.trainer:
        # Fallback for legacy payloads using trainer slug
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT id FROM coaches WHERE slug = ? LIMIT 1", (payload.trainer,))
            row = cur.fetchone()
        if row and row[0]:
            fields.append("agent_id = ?")
            selected_trainer_id = int(row[0])
            values.append(selected_trainer_id)
    if payload.voice:
        fields.append("coach_voice = ?")
        values.append(payload.voice)
    elif selected_trainer_id is not None:
        fields.append("coach_voice = ?")
        values.append(_default_voice_for_agent(selected_trainer_id))
    if payload.full_name:
        fields.append("name = ?")
        values.append(payload.full_name)

    if fields:
        values.append(user_id)
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute(f"UPDATE users SET {', '.join(fields)} WHERE id = ?", tuple(values))
            if payload.current_weight_kg is not None:
                _upsert_daily_weight_checkin(user_id, float(payload.current_weight_kg), conn=conn)
                reason = f"checkin_log:{date.today().isoformat()}"
                if not _has_points_reason(user_id, reason):
                    _award_points(user_id, 5, reason)
                _apply_daily_checklist_completion_bonus(user_id, date.today().isoformat())
            conn.commit()

    pref_updates: Dict[str, Any] = {}
    if payload.activity_level is not None:
        pref_updates["activity_level"] = payload.activity_level
    if payload.goal_type is not None:
        pref_updates["goal_type"] = payload.goal_type
    if payload.target_weight_kg is not None:
        pref_updates["target_weight_kg"] = payload.target_weight_kg
    if payload.allergies is not None:
        pref_updates["allergies"] = payload.allergies
    if payload.preferred_workout_time is not None:
        pref_updates["preferred_workout_time"] = payload.preferred_workout_time
    if payload.menstrual_cycle_notes is not None:
        pref_updates["menstrual_cycle_notes"] = payload.menstrual_cycle_notes
    if pref_updates:
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT 1 FROM user_preferences WHERE user_id = ? LIMIT 1", (user_id,))
            has_pref = cur.fetchone() is not None
            if not has_pref:
                created_at = datetime.now().isoformat(timespec="seconds")
                cur.execute(
                    """
                    INSERT INTO user_preferences (
                        user_id, weekly_weight_change_kg, activity_level, goal_type, target_weight_kg,
                        dietary_preferences, workout_preferences, timezone, created_at,
                        allergies, preferred_workout_time, menstrual_cycle_notes
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        user_id,
                        payload.weekly_weight_change_kg,
                        pref_updates.get("activity_level"),
                        pref_updates.get("goal_type"),
                        pref_updates.get("target_weight_kg"),
                        None,
                        None,
                        None,
                        created_at,
                        pref_updates.get("allergies"),
                        pref_updates.get("preferred_workout_time"),
                        pref_updates.get("menstrual_cycle_notes"),
                    ),
                )
            else:
                set_clause = ", ".join(f"{k} = ?" for k in pref_updates.keys())
                cur.execute(
                    f"UPDATE user_preferences SET {set_clause} WHERE user_id = ?",
                    tuple(pref_updates.values()) + (user_id,),
                )
            conn.commit()
    if payload.current_weight_kg is not None:
        _invalidate_user_activity_cache(user_id, day=date.today().isoformat())
    _refresh_profile_cache(user_id)
    _generate_plan_for_user(
        user_id,
        goal_type=payload.goal_type,
        timeframe_weeks=payload.timeframe_weeks,
        weekly_change_kg=payload.weekly_weight_change_kg,
    )
    return {"ok": True}


@app.get("/api/coach-media/{media_type}/{filename}")
def get_coach_media(media_type: str, filename: str):
    """Serve coach media files securely from Supabase with signed URLs."""
    # Validate media type
    if media_type not in ["images", "videos"]:
        raise HTTPException(status_code=404, detail="Invalid media type")

    # Validate filename format (basic security check)
    import re
    if not re.match(r'^[a-zA-Z0-9_-]+\.(png|jpg|jpeg|mp4|mov)$', filename):
        raise HTTPException(status_code=404, detail="Invalid filename")

    base = _supabase_url()
    if not base or not os.environ.get("SUPABASE_SERVICE_ROLE_KEY"):
        raise HTTPException(status_code=500, detail="Supabase not configured")

    # Generate signed URL for the coach media
    path = f"coach-media/{media_type}/{filename}"
    url = f"{base}/storage/v1/object/sign/coach-media/{media_type}/{filename}"

    headers = {
        "Content-Type": "application/json",
        **_supabase_headers()
    }

    try:
        import requests
        # Request a signed URL that expires in 1 hour
        response = requests.post(url, json={"expiresIn": 3600}, headers=headers)
        response.raise_for_status()
        signed_data = response.json()

        if "signedURL" in signed_data:
            # Return the signed URL for the client to fetch directly
            from fastapi.responses import RedirectResponse
            return RedirectResponse(url=signed_data["signedURL"])
        else:
            raise HTTPException(status_code=500, detail="Failed to generate signed URL")

    except requests.exceptions.RequestException as e:
        raise HTTPException(status_code=500, detail=f"Failed to access media: {str(e)}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)