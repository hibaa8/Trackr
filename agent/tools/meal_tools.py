from __future__ import annotations

import hashlib
import json
from datetime import date, datetime
from typing import List, Optional

from langchain_core.tools import tool

from agent.config.constants import CACHE_TTL_LONG, _draft_meal_logs_key
from agent.redis.cache import _redis_delete, _redis_get_json, _redis_set_json
from agent.state import SESSION_CACHE
from agent.db.connection import get_db_conn


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


def _estimate_meal_item_calories(item: str) -> int:
    lookup = {
        "egg": 78,
        "eggs": 78,
        "chicken breast": 165,
        "chicken": 180,
        "rice": 200,
        "pasta": 220,
        "salad": 120,
        "apple": 95,
        "banana": 105,
        "oatmeal": 150,
        "yogurt": 120,
        "greek yogurt": 130,
        "protein shake": 200,
        "sandwich": 350,
        "burger": 550,
        "pizza": 285,
        "steak": 400,
        "fish": 250,
        "tuna": 200,
        "tofu": 180,
        "beans": 220,
        "avocado": 240,
    }
    lowered = item.lower()
    for key, calories in lookup.items():
        if key in lowered:
            return calories
    return 150


def _estimate_meal_calories(items: List[str]) -> int:
    return sum(_estimate_meal_item_calories(item) for item in items if item.strip())


def _normalize_meal_time(consumed_at: Optional[str]) -> str:
    now = datetime.now()
    if not consumed_at:
        return now.isoformat(timespec="seconds")
    value = consumed_at.strip()
    if not value:
        return now.isoformat(timespec="seconds")
    # Preserve already-valid ISO datetimes.
    try:
        return datetime.fromisoformat(value).isoformat(timespec="seconds")
    except ValueError:
        pass
    lowered = value.lower()
    meal_aliases = {
        "breakfast": "08:00",
        "lunch": "13:00",
        "dinner": "19:00",
        "snack": "16:00",
    }
    if lowered in meal_aliases:
        parsed = datetime.strptime(meal_aliases[lowered], "%H:%M").time()
        return datetime.combine(now.date(), parsed).isoformat(timespec="seconds")
    if "today" in lowered:
        value = value.replace("today", "").strip()
        lowered = value.lower()
        if not value:
            return now.isoformat(timespec="seconds")
    for fmt in ("%I %p", "%I:%M %p", "%H:%M"):
        try:
            parsed = datetime.strptime(value, fmt).time()
            return datetime.combine(now.date(), parsed).isoformat(timespec="seconds")
        except ValueError:
            continue
    # Fallback to a valid timestamp so rows always persist and appear in daily totals.
    return now.isoformat(timespec="seconds")


def _estimate_macros_from_calories(total_calories: int) -> dict[str, int]:
    # MVP default split: 30% protein / 40% carbs / 30% fat.
    protein_cals = total_calories * 0.3
    carbs_cals = total_calories * 0.4
    fat_cals = total_calories * 0.3
    return {
        "protein_g": int(round(protein_cals / 4)),
        "carbs_g": int(round(carbs_cals / 4)),
        "fat_g": int(round(fat_cals / 9)),
    }


def _load_meal_logs_draft(user_id: int) -> dict:
    draft_key = _draft_meal_logs_key(user_id)
    cached = _redis_get_json(draft_key)
    if cached:
        return cached
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, user_id, logged_at, description, calories, protein_g, carbs_g, fat_g, confidence, confirmed
            FROM meal_logs
            WHERE user_id = ?
            ORDER BY logged_at DESC
            """,
            (user_id,),
        )
        meals = [
            {
                "id": row[0],
                "user_id": row[1],
                "logged_at": row[2],
                "description": row[3],
                "calories": row[4],
                "protein_g": row[5],
                "carbs_g": row[6],
                "fat_g": row[7],
                "confidence": row[8],
                "confirmed": row[9],
            }
            for row in cur.fetchall()
        ]
    draft = {"meals": meals}
    _redis_set_json(draft_key, draft, ttl_seconds=CACHE_TTL_LONG)
    return draft


def _sync_meal_logs_to_db(user_id: int, meals: List[dict]) -> None:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("DELETE FROM meal_logs WHERE user_id = ?", (user_id,))
        for meal in meals:
            logged_at = meal.get("logged_at")
            description = meal.get("description")
            if not logged_at or not description:
                continue
            logged_at = _normalize_meal_time(str(logged_at))
            cur.execute(
                """
                INSERT INTO meal_logs (
                    user_id, logged_at, photo_path, description, calories, protein_g, carbs_g, fat_g, confidence, confirmed
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_id,
                    logged_at,
                    None,
                    description,
                    meal.get("calories", 0),
                    meal.get("protein_g", 0),
                    meal.get("carbs_g", 0),
                    meal.get("fat_g", 0),
                    meal.get("confidence", 0.5),
                    meal.get("confirmed", 1),
                ),
            )
        conn.commit()


def _invalidate_meal_cache(user_id: int, day: Optional[str]) -> None:
    _redis_delete(_draft_meal_logs_key(user_id))
    _redis_delete(f"user:{user_id}:meal_logs")
    if day:
        _redis_delete(f"daily_intake:{user_id}:{day}")


def _idempotency_key_for_meal(
    user_id: int,
    items: List[str],
    logged_at: str,
    total_calories: int,
    protein_g: int,
    carbs_g: int,
    fat_g: int,
    explicit_key: Optional[str],
) -> str:
    if explicit_key and explicit_key.strip():
        return explicit_key.strip()
    payload = {
        "items": items,
        "logged_at": logged_at,
        "total_calories": total_calories,
        "protein_g": protein_g,
        "carbs_g": carbs_g,
        "fat_g": fat_g,
    }
    digest = hashlib.sha256(json.dumps(payload, sort_keys=True).encode("utf-8")).hexdigest()
    return f"auto:{digest}"


@tool("log_meal")
def log_meal(
    user_id: int,
    items: Optional[List[str]] = None,
    consumed_at: Optional[str] = None,
    total_calories: Optional[int] = None,
    protein_g: Optional[int] = None,
    carbs_g: Optional[int] = None,
    fat_g: Optional[int] = None,
    notes: Optional[str] = None,
    idempotency_key: Optional[str] = None,
) -> str:
    """Log a meal entry into the cache and database."""
    if not items:
        return "What items were included in the meal?"
    meal_items = [item.strip() for item in items if str(item).strip()]
    if not meal_items:
        return "What items were included in the meal?"
    if total_calories is None:
        total_calories = _estimate_meal_calories(meal_items)
    macros = {
        "protein_g": protein_g,
        "carbs_g": carbs_g,
        "fat_g": fat_g,
    }
    if not all(isinstance(value, int) and value >= 0 for value in macros.values()):
        macros = _estimate_macros_from_calories(total_calories)
    logged_at = _normalize_meal_time(consumed_at)
    idem_key = _idempotency_key_for_meal(
        user_id=user_id,
        items=meal_items,
        logged_at=logged_at,
        total_calories=total_calories,
        protein_g=macros["protein_g"],
        carbs_g=macros["carbs_g"],
        fat_g=macros["fat_g"],
        explicit_key=idempotency_key,
    )
    idem_cache_key = f"idem:tool:meal:{user_id}:{idem_key}"
    cached = _redis_get_json(idem_cache_key)
    if isinstance(cached, dict) and cached.get("message"):
        return str(cached["message"])
    description = ", ".join(meal_items)
    if notes:
        description = f"{description}. Notes: {notes}"
    draft = _load_meal_logs_draft(user_id)
    new_entry = {
        "id": None,
        "user_id": user_id,
        "logged_at": logged_at,
        "description": description,
        "calories": total_calories,
        "protein_g": macros["protein_g"],
        "carbs_g": macros["carbs_g"],
        "fat_g": macros["fat_g"],
        "confidence": 0.5,
        "confirmed": 1,
    }
    draft.setdefault("meals", []).insert(0, new_entry)
    _redis_set_json(_draft_meal_logs_key(user_id), draft, ttl_seconds=CACHE_TTL_LONG)
    SESSION_CACHE.setdefault(user_id, {})["meal_logs"] = draft
    _sync_meal_logs_to_db(user_id, draft.get("meals", []))
    _invalidate_meal_cache(user_id, logged_at[:10])
    _award_points(user_id, 5, f"meal_log:{logged_at}")
    message = "Meal logged."
    _redis_set_json(idem_cache_key, {"message": message}, ttl_seconds=600)
    return message


@tool("get_meal_logs")
def get_meal_logs(user_id: int) -> str:
    """Return meal logs from the cache."""
    draft = SESSION_CACHE.get(user_id, {}).get("meal_logs") or _redis_get_json(_draft_meal_logs_key(user_id))
    if draft is None:
        return "No cached meal logs found. Start a session to load them."
    meals = draft.get("meals", []) if isinstance(draft, dict) else []
    if not meals:
        return "No meal logs found."
    lines = []
    for meal in meals[:20]:
        logged_at = meal.get("logged_at") or "unknown time"
        description = meal.get("description") or "Meal"
        calories = meal.get("calories")
        calorie_label = f"{calories} kcal" if calories is not None else "calories unknown"
        lines.append(f"{logged_at}: {description} ({calorie_label})")
    return "\n".join(lines)


@tool("delete_all_meal_logs")
def delete_all_meal_logs(user_id: int) -> str:
    """Delete all meal logs for the user from cache and database."""
    draft = {"meals": []}
    _redis_set_json(_draft_meal_logs_key(user_id), draft, ttl_seconds=CACHE_TTL_LONG)
    SESSION_CACHE.setdefault(user_id, {})["meal_logs"] = draft
    _sync_meal_logs_to_db(user_id, [])
    return "All meal logs deleted."
