from datetime import datetime, timedelta

from api._shared import json_response, read_json, require_user_id
from agent.db.connection import get_db_conn
from agent.config.constants import CACHE_TTL_LONG, _draft_checkins_key
from agent.redis.cache import _redis_delete, _redis_set_json
from agent.state import SESSION_CACHE


def handler(request):
    if request.method != "POST":
        return json_response({"error": "Method not allowed"}, status=405)
    user_id = require_user_id()
    payload = read_json(request)
    if payload is None:
        return json_response({"error": "Invalid JSON payload."}, status=400)
    weight_kg = payload.get("weight_kg")
    reset = bool(payload.get("reset"))
    checkin_date = payload.get("date") or datetime.now().date().isoformat()
    try:
        weight_kg = float(weight_kg)
    except (TypeError, ValueError):
        return json_response({"error": "Weight must be a number."}, status=400)
    if weight_kg <= 0:
        return json_response({"error": "Weight must be greater than 0."}, status=400)
    try:
        parsed_date = datetime.fromisoformat(str(checkin_date)).date()
    except ValueError:
        return json_response({"error": "Date must be YYYY-MM-DD."}, status=400)
    today = datetime.now().date()
    if parsed_date > today:
        if reset and parsed_date == (today + timedelta(days=1)):
            parsed_date = today
        else:
            return json_response({"error": "Date cannot be in the future."}, status=400)
    with get_db_conn() as conn:
        cur = conn.cursor()
        if reset:
            cur.execute("DELETE FROM checkins WHERE user_id = ?", (user_id,))
            _redis_delete(_draft_checkins_key(user_id))
            SESSION_CACHE.setdefault(user_id, {})["checkins"] = {"checkins": []}
        else:
            cur.execute(
                """
                SELECT checkin_date, weight_kg
                FROM checkins
                WHERE user_id = ?
                ORDER BY checkin_date DESC
                LIMIT 1
                """,
                (user_id,),
            )
            last_row = cur.fetchone()
            if last_row:
                last_date = datetime.fromisoformat(str(last_row[0])).date()
                last_weight = float(last_row[1] or 0)
                delta_days = abs((parsed_date - last_date).days) or 1
                delta_weight = abs(weight_kg - last_weight)
                if (delta_days <= 7 and delta_weight > 5) or (
                    delta_days <= 30 and delta_weight > 10
                ):
                    return json_response(
                        {
                            "error": (
                                "That change looks too sudden. "
                                "Please talk to your AI trainer before logging this."
                            )
                        },
                        status=400,
                    )
        cur.execute(
            "SELECT 1 FROM checkins WHERE user_id = ? AND checkin_date = ?",
            (user_id, parsed_date.isoformat()),
        )
        if cur.fetchone():
            cur.execute(
                """
                UPDATE checkins
                SET weight_kg = ?, mood = ?, notes = ?
                WHERE user_id = ? AND checkin_date = ?
                """,
                (weight_kg, "manual", "Manual log", user_id, parsed_date.isoformat()),
            )
        else:
            cur.execute(
                """
                INSERT INTO checkins (user_id, checkin_date, weight_kg, mood, notes)
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    user_id,
                    parsed_date.isoformat(),
                    weight_kg,
                    "manual",
                    "Manual log",
                ),
            )
        cur.execute("UPDATE users SET weight_kg = ? WHERE id = ?", (weight_kg, user_id))
        conn.commit()
    draft = {
        "checkins": [
            {
                "checkin_date": parsed_date.isoformat(),
                "weight_kg": weight_kg,
                "mood": "manual",
                "notes": "Manual log",
            }
        ]
    }
    _redis_set_json(_draft_checkins_key(user_id), draft, ttl_seconds=CACHE_TTL_LONG)
    SESSION_CACHE.setdefault(user_id, {})["checkins"] = draft
    return json_response({"ok": True})
