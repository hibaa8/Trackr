import base64
import uuid
from datetime import datetime

from api._shared import (
    json_response,
    read_json,
    require_user_id,
    _call_gemini_for_nutrition,
    _store_photo_in_supabase,
    _build_public_photo_url,
    _sign_photo_url,
    _extension_from_mime,
)
from agent.config.constants import CACHE_TTL_LONG, _draft_meal_logs_key
from agent.redis.cache import _redis_get_json, _redis_set_json
from agent.state import SESSION_CACHE
from agent.db.connection import get_db_conn


def handler(request):
    if request.method != "POST":
        return json_response({"error": "Method not allowed"}, status=405)
    user_id = require_user_id()
    payload = read_json(request)
    if payload is None:
        return json_response({"error": "Invalid JSON payload."}, status=400)
    if payload.get("image_url"):
        return json_response({"error": "Use image_base64; image_url is not supported."}, status=400)
    image_b64 = payload.get("image_base64")
    mime_type = payload.get("mime_type", "image/jpeg")
    if not image_b64:
        return json_response({"error": "Missing image_base64."}, status=400)
    if isinstance(image_b64, str) and image_b64.startswith("http"):
        return json_response({"error": "Use image_base64; URLs are not supported."}, status=400)
    if "," in image_b64:
        image_b64 = image_b64.split(",", 1)[1]
    try:
        image_bytes = base64.b64decode(image_b64)
    except ValueError:
        return json_response({"error": "Invalid base64 image."}, status=400)
    try:
        analysis = _call_gemini_for_nutrition(image_b64, mime_type)
    except Exception as exc:
        return json_response({"error": f"Gemini analysis failed: {exc}"}, status=500)
    try:
        ext = _extension_from_mime(mime_type)
        filename = f"{uuid.uuid4().hex}.{ext}"
        path = _store_photo_in_supabase(image_bytes, mime_type, filename)
        photo_url = _build_public_photo_url(path) or _sign_photo_url(path)
    except Exception as exc:
        return json_response({"error": f"Image upload failed: {exc}"}, status=500)
    try:
        logged_at = datetime.now().isoformat(timespec="seconds")
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
                    user_id,
                    logged_at,
                    path,
                    analysis.get("description") or "Meal",
                    int(analysis.get("calories") or 0),
                    int(analysis.get("protein_g") or 0),
                    int(analysis.get("carbs_g") or 0),
                    int(analysis.get("fat_g") or 0),
                    float(analysis.get("confidence") or 0.6),
                    1,
                ),
            )
            conn.commit()
        meal_entry = {
            "id": None,
            "user_id": user_id,
            "logged_at": logged_at,
            "photo_path": path,
            "photo_url": photo_url,
            "description": analysis.get("description") or "Meal",
            "calories": int(analysis.get("calories") or 0),
            "protein_g": int(analysis.get("protein_g") or 0),
            "carbs_g": int(analysis.get("carbs_g") or 0),
            "fat_g": int(analysis.get("fat_g") or 0),
            "confidence": float(analysis.get("confidence") or 0.6),
            "confirmed": 1,
        }
        cached = _redis_get_json(_draft_meal_logs_key(user_id)) or {"meals": []}
        if isinstance(cached, dict):
            cached.setdefault("meals", []).insert(0, meal_entry)
            _redis_set_json(_draft_meal_logs_key(user_id), cached, ttl_seconds=CACHE_TTL_LONG)
            SESSION_CACHE.setdefault(user_id, {})["meal_logs"] = cached
        return json_response(
            {
                "logged_at": logged_at,
                "photo_path": path,
                "photo_url": photo_url,
                "analysis": analysis,
            }
        )
    except Exception as exc:
        return json_response({"error": f"Database insert failed: {exc}"}, status=500)
