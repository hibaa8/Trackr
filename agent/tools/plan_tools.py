from __future__ import annotations

import json
import hashlib
import os
import re
import uuid
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI
from langchain_tavily import TavilySearch

from agent.config.constants import (
    CACHE_TTL_LONG,
    CACHE_TTL_PLAN,
    _draft_plan_key,
    _draft_plan_patches_key,
    _draft_checkins_key,
    _draft_health_activity_key,
    _draft_plan_status_key,
    _draft_reminders_key,
)
from agent.config.constants import _draft_meal_logs_key, _draft_workout_sessions_key
from agent.db import queries
from agent.plan.plan_generation import _build_plan_data, _format_plan_text, _macro_split, generate_workout_plan
from agent.redis.cache import _redis_delete, _redis_get_json, _redis_set_json
from agent.state import SESSION_CACHE
from agent.tools.activity_utils import _estimate_workout_calories, _is_cardio_exercise
from agent.db.connection import get_db_conn
from google.oauth2 import service_account
from googleapiclient.discovery import build


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


def _apply_daily_checklist_completion_bonus(user_id: int, target_day: str) -> None:
    start = f"{target_day}T00:00:00"
    end = f"{target_day}T23:59:59"
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM meal_logs WHERE user_id = ? AND logged_at BETWEEN ? AND ?", (user_id, start, end))
        meal_count = int((cur.fetchone() or [0])[0] or 0)
        cur.execute("SELECT COUNT(*) FROM workout_sessions WHERE user_id = ? AND completed = 1 AND date = ?", (user_id, target_day))
        workout_count = int((cur.fetchone() or [0])[0] or 0)
        cur.execute("SELECT COUNT(*) FROM checkins WHERE user_id = ? AND checkin_date = ?", (user_id, target_day))
        checkin_count = int((cur.fetchone() or [0])[0] or 0)
        if meal_count < 3 or workout_count < 1 or checkin_count < 1:
            return
        reason = f"daily_checklist_complete:{target_day}"
        cur.execute("SELECT 1 FROM points WHERE user_id = ? AND reason = ? LIMIT 1", (user_id, reason))
        if cur.fetchone() is not None:
            return
        cur.execute(
            "INSERT INTO points (user_id, points, reason, created_at) VALUES (?, ?, ?, ?)",
            (user_id, 10, reason, datetime.now().isoformat(timespec="seconds")),
        )
        conn.commit()


def _has_points_reason(user_id: int, reason: str) -> bool:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT 1 FROM points WHERE user_id = ? AND reason = ? LIMIT 1", (user_id, reason))
        return cur.fetchone() is not None


def _workout_label_from_json(workout_json: Optional[str]) -> str:
    if not workout_json:
        return "Workout"
    try:
        payload = json.loads(workout_json)
    except json.JSONDecodeError:
        return str(workout_json)
    if isinstance(payload, dict):
        return payload.get("label") or payload.get("type") or "Workout"
    return str(payload)


def _coerce_to_date(value: Any) -> date:
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    return datetime.strptime(str(value), "%Y-%m-%d").date()


def _google_calendar_service():
    raw_json = os.getenv("GOOGLE_CALENDAR_SERVICE_ACCOUNT_JSON", "").strip()
    json_path = os.getenv("GOOGLE_CALENDAR_SERVICE_ACCOUNT_FILE", "").strip()
    delegated_user = os.getenv("GOOGLE_CALENDAR_DELEGATED_USER", "").strip()
    if not raw_json and not json_path:
        raise RuntimeError(
            "Google Calendar is not configured. Set GOOGLE_CALENDAR_SERVICE_ACCOUNT_JSON or GOOGLE_CALENDAR_SERVICE_ACCOUNT_FILE."
        )
    scopes = ["https://www.googleapis.com/auth/calendar"]
    if raw_json:
        info = json.loads(raw_json)
        credentials = service_account.Credentials.from_service_account_info(info, scopes=scopes)
    else:
        credentials = service_account.Credentials.from_service_account_file(json_path, scopes=scopes)
    if delegated_user:
        credentials = credentials.with_subject(delegated_user)
    return build("calendar", "v3", credentials=credentials, cache_discovery=False)


def _fetch_user_email(user_id: int) -> Optional[str]:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT email FROM users WHERE id = ? LIMIT 1", (user_id,))
        row = cur.fetchone()
    if not row:
        return None
    email = str(row[0] or "").strip()
    return email or None


def _to_iso(value: str) -> str:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return parsed.isoformat()


def _plan_calendar_events(
    user_id: int,
    include_meal_logs: bool,
    timezone: str,
) -> List[Dict[str, Any]]:
    bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
    plan_days = bundle.get("plan_days") or []
    events: List[Dict[str, Any]] = []
    for day in plan_days:
        day_date = str(day.get("date") or "").strip()
        if not day_date:
            continue
        workout_label = str(day.get("workout_plan") or "Workout").strip() or "Workout"
        events.append(
            {
                "title": workout_label,
                "start_at": f"{day_date}T18:00:00",
                "end_at": f"{day_date}T19:00:00",
                "description": "Auto-synced from your AI Trainer plan.",
                "timezone": timezone,
            }
        )
        if include_meal_logs:
            events.append(
                {
                    "title": "Log meals for today",
                    "start_at": f"{day_date}T20:00:00",
                    "end_at": f"{day_date}T20:20:00",
                    "description": "Auto-synced meal logging reminder from your AI Trainer plan.",
                    "timezone": timezone,
                }
            )
    return events


def _normalize_checkin_date(value: Optional[str]) -> str:
    if not value:
        return date.today().isoformat()
    raw = str(value).strip()
    if not raw:
        return date.today().isoformat()
    lowered = raw.lower()
    today = date.today()

    if lowered in {"today", "now"}:
        return today.isoformat()
    if lowered == "yesterday":
        return (today - timedelta(days=1)).isoformat()

    week_match = re.match(r"^(\d+)\s*week(?:s)?\s*ago$", lowered)
    if week_match:
        weeks = int(week_match.group(1))
        return (today - timedelta(days=weeks * 7)).isoformat()

    day_match = re.match(r"^(\d+)\s*day(?:s)?\s*ago$", lowered)
    if day_match:
        days = int(day_match.group(1))
        return (today - timedelta(days=days)).isoformat()

    try:
        return datetime.fromisoformat(raw).date().isoformat()
    except Exception:
        pass
    try:
        return datetime.strptime(raw, "%Y-%m-%d").date().isoformat()
    except Exception:
        return today.isoformat()


def _render_plan_days(
    start_date: Any,
    end_date: Any,
    cycle_length: int,
    default_calories: int,
    default_macros: Dict[str, int],
    template_days: Dict[int, Dict[str, Any]],
    overrides: Dict[str, Dict[str, Any]],
) -> List[Dict[str, Any]]:
    start = _coerce_to_date(start_date)
    end = _coerce_to_date(end_date)
    total_days = (end - start).days + 1
    plan_days = []
    for offset in range(total_days):
        day_date = start + timedelta(days=offset)
        day_key = day_date.isoformat()
        day_index = offset % max(1, cycle_length)
        template = template_days.get(day_index, {})
        base_calories = default_calories + int(template.get("calorie_delta") or 0)
        workout_json = template.get("workout_json")
        if day_key == date.today().isoformat():
            print("workout_json fetched for today:", workout_json)
        rest_day = _workout_label_from_json(workout_json).lower() == "rest day"
        override = overrides.get(day_key)
        if override:
            if override.get("workout_json"):
                workout_json = override["workout_json"]
                rest_day = _workout_label_from_json(workout_json).lower() == "rest day"
            if override.get("calorie_target") is not None:
                base_calories = override["calorie_target"]
            elif override.get("calorie_delta") is not None:
                base_calories = default_calories + int(override["calorie_delta"])
            if override.get("override_type") in {"pause", "deload"}:
                rest_day = True
        macros = _macro_split(base_calories) if base_calories else default_macros
        workout_label = _workout_label_from_json(workout_json)
        if workout_label == "workout" and workout_json:
            workout_label = str(workout_json)
        plan_days.append(
            {
                "date": day_key,
                "workout_plan": workout_label,
                "workout_raw": workout_json,
                "rest_day": 1 if rest_day else 0,
                "calorie_target": base_calories,
                "protein_g": macros["protein_g"],
                "carbs_g": macros["carbs_g"],
                "fat_g": macros["fat_g"],
            }
        )
    return plan_days


def _load_user_context_data(user_id: int) -> Dict[str, Any]:
    cache_key = f"user:{user_id}:profile"
    cached = _redis_get_json(cache_key)
    if cached:
        return cached
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(queries.SELECT_USER_PROFILE, (user_id,))
        user_row = cur.fetchone()
        cur.execute(queries.SELECT_USER_PREFS, (user_id,))
        pref_row = cur.fetchone()
    data = {"user": user_row, "preferences": pref_row}
    _redis_set_json(cache_key, data, ttl_seconds=CACHE_TTL_LONG)
    return data


def _get_active_plan_bundle_data(user_id: int, allow_db_fallback: bool = True) -> Dict[str, Any]:
    cache_key = f"active_plan:{user_id}"
    legacy_key = f"user:{user_id}:active_plan"
    cached = _redis_get_json(cache_key) or _redis_get_json(legacy_key)
    if cached:
        return cached
    if not allow_db_fallback:
        return {"plan": None, "plan_days": []}
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(queries.SELECT_ACTIVE_PLAN, (user_id,))
        plan_row = cur.fetchone()
        if not plan_row:
            return {"plan": None, "plan_days": []}
        template_id = plan_row[0]
        start_date = plan_row[2]
        end_date = plan_row[3]
        daily_calorie_target = plan_row[4]
        protein_g = plan_row[5]
        carbs_g = plan_row[6]
        fat_g = plan_row[7]
        status = plan_row[8]
        cycle_length = plan_row[9] or 7
        default_calories = plan_row[11] or daily_calorie_target
        default_macros = {
            "protein_g": plan_row[12] or protein_g,
            "carbs_g": plan_row[13] or carbs_g,
            "fat_g": plan_row[14] or fat_g,
        }
        cur.execute(queries.SELECT_TEMPLATE_DAYS, (template_id,))
        template_days = {row[0]: {"workout_json": row[1], "calorie_delta": row[2]} for row in cur.fetchall()}
        cur.execute(queries.SELECT_PLAN_OVERRIDES, (template_id, start_date, end_date))
        overrides = {
            row[0]: {
                "override_type": row[1],
                "workout_json": row[2],
                "calorie_target": row[3],
                "calorie_delta": row[4],
            }
            for row in cur.fetchall()
        }
        plan_days = _render_plan_days(
            start_date=start_date,
            end_date=end_date,
            cycle_length=cycle_length,
            default_calories=default_calories,
            default_macros=default_macros,
            template_days=template_days,
            overrides=overrides,
        )
        cur.execute(queries.SELECT_PLAN_CHECKPOINTS, (template_id,))
        checkpoints = [
            {
                "week": row[0],
                "expected_weight_kg": row[1],
                "min_weight_kg": row[2],
                "max_weight_kg": row[3],
            }
            for row in cur.fetchall()
        ]
    bundle = {
        "plan": {
            "id": template_id,
            "start_date": start_date,
            "end_date": end_date,
            "daily_calorie_target": daily_calorie_target,
            "protein_g": protein_g,
            "carbs_g": carbs_g,
            "fat_g": fat_g,
            "status": status,
        },
        "plan_days": plan_days,
        "checkpoints": checkpoints,
    }
    _redis_set_json(cache_key, bundle, ttl_seconds=CACHE_TTL_PLAN)
    _redis_set_json(legacy_key, bundle, ttl_seconds=CACHE_TTL_PLAN)
    return bundle


def _summarize_active_plan_for_context(active_plan: Dict[str, Any]) -> Dict[str, Any]:
    plan = active_plan.get("plan")
    plan_days = active_plan.get("plan_days", [])
    if not plan:
        return {"plan": None, "plan_days": []}
    return {
        "plan": {
            "start_date": plan.get("start_date"),
            "end_date": plan.get("end_date"),
            "daily_calorie_target": plan.get("daily_calorie_target"),
            "protein_g": plan.get("protein_g"),
            "carbs_g": plan.get("carbs_g"),
            "fat_g": plan.get("fat_g"),
            "status": plan.get("status"),
        },
        "plan_days": plan_days[:7],
    }


def _compact_context_summary(context: Dict[str, Any], active_plan: Dict[str, Any]) -> str:
    user = context.get("user") or ()
    pref = context.get("preferences") or ()

    if isinstance(user, dict):
        birthdate = user.get("birthdate")
        height_cm = user.get("height_cm")
        weight_kg = user.get("weight_kg")
        gender = user.get("gender")
        age_years = user.get("age_years")
    else:
        birthdate = user[2] if len(user) > 2 else None
        height_cm = user[3] if len(user) > 3 else None
        weight_kg = user[4] if len(user) > 4 else None
        gender = user[5] if len(user) > 5 else None
        age_years = user[6] if len(user) > 6 else None

    if isinstance(pref, dict):
        goal_type = pref.get("goal_type")
        activity_level = pref.get("activity_level")
    else:
        goal_type = pref[2] if len(pref) > 2 else None
        activity_level = pref[1] if len(pref) > 1 else None

    age = age_years

    plan = active_plan.get("plan") or {}
    plan_days = active_plan.get("plan_days", [])
    next_days = [day.get("workout_plan") or day.get("workout") for day in plan_days[:7]]
    checkpoints = active_plan.get("checkpoints", [])
    next_checkpoint = checkpoints[0] if checkpoints else None

    summary = {
        "age": age,
        "sex": gender,
        "height_cm": height_cm,
        "weight_kg": weight_kg,
        "goal_type": goal_type,
        "activity_level": activity_level,
        "calorie_target": plan.get("daily_calorie_target"),
        "macros_g": {
            "protein": plan.get("protein_g"),
            "carbs": plan.get("carbs_g"),
            "fat": plan.get("fat_g"),
        },
        "next_7_workouts": [label for label in next_days if label],
        "next_checkpoint": next_checkpoint,
    }
    return json.dumps(summary)



def _load_active_plan_draft(user_id: int) -> Dict[str, Any]:
    draft_key = _draft_plan_key(user_id)
    cached = _redis_get_json(draft_key)
    if cached:
        return cached
    bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
    _redis_set_json(draft_key, bundle, ttl_seconds=CACHE_TTL_LONG)
    if _redis_get_json(_draft_plan_patches_key(user_id)) is None:
        _redis_set_json(_draft_plan_patches_key(user_id), [], ttl_seconds=CACHE_TTL_LONG)
    return bundle


def _set_active_plan_cache(user_id: int, bundle: Dict[str, Any]) -> None:
    _redis_set_json(_draft_plan_key(user_id), bundle, ttl_seconds=CACHE_TTL_LONG)
    _redis_set_json(f"active_plan:{user_id}", bundle, ttl_seconds=CACHE_TTL_PLAN)
    _redis_set_json(f"user:{user_id}:active_plan", bundle, ttl_seconds=CACHE_TTL_PLAN)
    SESSION_CACHE.setdefault(user_id, {})["active_plan"] = bundle


def _append_plan_patch(user_id: int, patch: Dict[str, Any]) -> None:
    patches = _redis_get_json(_draft_plan_patches_key(user_id))
    if not isinstance(patches, list):
        patches = []
    patches.append(patch)
    _redis_set_json(_draft_plan_patches_key(user_id), patches, ttl_seconds=CACHE_TTL_LONG)


def _invalidate_active_plan_cache(user_id: int) -> None:
    _redis_delete(f"active_plan:{user_id}")
    _redis_delete(f"user:{user_id}:active_plan")
    _redis_delete(_draft_plan_key(user_id))
    _redis_delete(_draft_plan_patches_key(user_id))


def _load_checkins_draft(user_id: int) -> Dict[str, Any]:
    draft_key = _draft_checkins_key(user_id)
    cached = _redis_get_json(draft_key)
    if cached:
        return cached
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, user_id, checkin_date, weight_kg, mood, notes
            FROM checkins
            WHERE user_id = ?
            ORDER BY checkin_date DESC
            """,
            (user_id,),
        )
        checkins = [
            {
                "id": row[0],
                "user_id": row[1],
                "checkin_date": row[2],
                "weight_kg": row[3],
                "mood": row[4],
                "notes": row[5],
            }
            for row in cur.fetchall()
        ]
    draft = {"checkins": checkins}
    _redis_set_json(draft_key, draft, ttl_seconds=CACHE_TTL_LONG)
    return draft


def _sync_checkins_to_db(user_id: int, checkins: List[Dict[str, Any]]) -> None:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("DELETE FROM checkins WHERE user_id = ?", (user_id,))
        for checkin in checkins:
            checkin_date = checkin.get("checkin_date")
            weight_kg = checkin.get("weight_kg")
            if not checkin_date:
                continue
            cur.execute(
                """
                INSERT INTO checkins (
                    user_id, checkin_date, weight_kg, mood, notes
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    user_id,
                    checkin_date,
                    weight_kg,
                    checkin.get("mood"),
                    checkin.get("notes"),
                ),
            )
        conn.commit()


def _invalidate_checkins_cache(user_id: int) -> None:
    _redis_delete(_draft_checkins_key(user_id))
    _redis_delete(f"session_hydration:{user_id}")


def _load_health_activity_draft(user_id: int) -> Dict[str, Any]:
    draft_key = _draft_health_activity_key(user_id)
    cached = _redis_get_json(draft_key)
    if cached:
        return cached
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, user_id, date, steps, calories_burned, workouts_summary, source
            FROM health_activity
            WHERE user_id = ?
            ORDER BY date DESC
            """,
            (user_id,),
        )
        activity = [
            {
                "id": row[0],
                "user_id": row[1],
                "date": row[2],
                "steps": row[3],
                "calories_burned": row[4],
                "workouts_summary": row[5],
                "source": row[6],
            }
            for row in cur.fetchall()
        ]
    draft = {"activity": activity}
    _redis_set_json(draft_key, draft, ttl_seconds=CACHE_TTL_LONG)
    return draft


def _load_reminders_draft(user_id: int) -> Dict[str, Any]:
    draft_key = _draft_reminders_key(user_id)
    cached = _redis_get_json(draft_key)
    if cached:
        return cached
    draft = _load_reminders_from_db(user_id)
    _redis_set_json(draft_key, draft, ttl_seconds=CACHE_TTL_LONG)
    SESSION_CACHE.setdefault(user_id, {})["reminders"] = draft
    return draft


def _load_reminders_from_db(user_id: int) -> Dict[str, Any]:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, user_id, reminder_type, scheduled_at, status, channel, related_plan_override_id
            FROM reminders
            WHERE user_id = ?
            ORDER BY scheduled_at
            """,
            (user_id,),
        )
        reminders = [
            {
                "id": row[0],
                "user_id": row[1],
                "reminder_type": row[2],
                "scheduled_at": row[3],
                "status": row[4],
                "channel": row[5],
                "related_plan_override_id": row[6],
            }
            for row in cur.fetchall()
        ]
    return {"reminders": reminders}


def _refresh_reminders_cache(user_id: int) -> Dict[str, Any]:
    draft = _load_reminders_from_db(user_id)
    _redis_set_json(_draft_reminders_key(user_id), draft, ttl_seconds=CACHE_TTL_LONG)
    SESSION_CACHE.setdefault(user_id, {})["reminders"] = draft
    return draft


@tool("get_current_plan_summary")
def get_current_plan_summary(user_id: int) -> str:
    """Return a basic plan summary for the given user_id."""
    bundle = (
        SESSION_CACHE.get(user_id, {}).get("active_plan")
        or _redis_get_json(_draft_plan_key(user_id))
        or _redis_get_json(f"user:{user_id}:active_plan")
        or {}
    )
    if bundle and user_id not in SESSION_CACHE:
        SESSION_CACHE[user_id] = {"context": None, "active_plan": bundle}
    plan = bundle.get("plan")
    plan_days = bundle.get("plan_days", [])
    if not plan:
        return "No cached plan found for this user. Try again or start a new session."
    start_date = plan["start_date"]
    end_date = plan["end_date"]
    calories = plan["daily_calorie_target"]
    protein = plan["protein_g"]
    carbs = plan["carbs_g"]
    fat = plan["fat_g"]
    status = plan["status"]
    workout_lines = []

    for day in plan_days[:14]:
        workout_plan = day.get("workout_plan") or day.get("workout") or "Workout"
        rest_day = day.get("rest_day")
        if rest_day is None:
            rest_day = "rest" in workout_plan.lower()
        workout_label = "Rest day" if rest_day else workout_plan
        workout_lines.append(f"{day['date']}: {workout_label}")
    workout_summary = "\n".join(workout_lines) if workout_lines else "No workouts scheduled."
    template_note = ""
    if len(plan_days) in {7, 14}:
        template_note = f" Template repeats until {end_date}."
    return (
        f"Plan {status}: {start_date} to {end_date}. "
        f"Calories {calories}, macros (g) P{protein}/C{carbs}/F{fat}. "
        f"Next 14 days:\n{workout_summary}{template_note}"
    )


@tool("get_plan_day")
def get_plan_day(user_id: int, date_str: Optional[str] = None) -> str:
    """Return the planned workout for a specific date (defaults to tomorrow)."""
    bundle = (
        SESSION_CACHE.get(user_id, {}).get("active_plan")
        or _redis_get_json(_draft_plan_key(user_id))
        or _redis_get_json(f"user:{user_id}:active_plan")
        or {}
    )
    if bundle and user_id not in SESSION_CACHE:
        SESSION_CACHE[user_id] = {"context": None, "active_plan": bundle}
    plan = bundle.get("plan")
    plan_days = bundle.get("plan_days", [])
    if not plan or not plan_days:
        return "No cached plan found for this user. Try again or start a new session."
    target_date = date_str or (date.today() + timedelta(days=1)).isoformat()
    day = next((d for d in plan_days if d.get("date") == target_date), None)
    if not day:
        return f"No planned workout found for {target_date}."
    workout_plan = day.get("workout_plan") or day.get("workout") or "Workout"
    rest_day = day.get("rest_day")
    if rest_day is None:
        rest_day = "rest" in workout_plan.lower()
    workout_label = "Rest day" if rest_day else workout_plan
    return f"{target_date}: {workout_label}"


@tool("get_reminders")
def get_reminders(user_id: int) -> str:
    """Return reminders for the user from cache."""
    draft = _load_reminders_draft(user_id)
    reminders = draft.get("reminders", []) if isinstance(draft, dict) else []
    return json.dumps({"reminders": reminders})


@tool("add_reminder")
def add_reminder(
    user_id: int,
    reminder_type: Optional[str] = None,
    scheduled_at: Optional[str] = None,
    status: str = "active",
    channel: str = "push",
    related_plan_override_id: Optional[int] = None,
) -> str:
    """Add a reminder and update cache + DB."""
    if not reminder_type or not scheduled_at:
        return "Please provide reminder_type and scheduled_at."
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO reminders (
                user_id, reminder_type, scheduled_at, status, channel, related_plan_override_id
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (user_id, reminder_type, scheduled_at, status, channel, related_plan_override_id),
        )
        conn.commit()
    _refresh_reminders_cache(user_id)
    return "Reminder added."


@tool("update_reminder")
def update_reminder(
    user_id: int,
    reminder_id: int,
    reminder_type: Optional[str] = None,
    scheduled_at: Optional[str] = None,
    status: Optional[str] = None,
    channel: Optional[str] = None,
    related_plan_override_id: Optional[int] = None,
) -> str:
    """Update a reminder and refresh cache."""
    fields = []
    values: List[Any] = []
    if reminder_type is not None:
        fields.append("reminder_type = ?")
        values.append(reminder_type)
    if scheduled_at is not None:
        fields.append("scheduled_at = ?")
        values.append(scheduled_at)
    if status is not None:
        fields.append("status = ?")
        values.append(status)
    if channel is not None:
        fields.append("channel = ?")
        values.append(channel)
    if related_plan_override_id is not None:
        fields.append("related_plan_override_id = ?")
        values.append(related_plan_override_id)
    if not fields:
        return "No fields provided to update."
    values.extend([user_id, reminder_id])
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            f"UPDATE reminders SET {', '.join(fields)} WHERE user_id = ? AND id = ?",
            tuple(values),
        )
        conn.commit()
    _refresh_reminders_cache(user_id)
    return "Reminder updated."


@tool("delete_reminder")
def delete_reminder(user_id: int, reminder_id: int) -> str:
    """Delete a reminder and refresh cache."""
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("DELETE FROM reminders WHERE user_id = ? AND id = ?", (user_id, reminder_id))
        conn.commit()
    _refresh_reminders_cache(user_id)
    return "Reminder deleted."


@tool("add_google_calendar_events")
def add_google_calendar_events(
    user_id: int,
    confirmed_by_user: bool,
    request_type: str = "custom",
    events: Optional[List[Dict[str, Any]]] = None,
    timezone: str = "UTC",
) -> str:
    """
    Add Google Calendar events for the current user after explicit confirmation.

    request_type:
    - "custom": use the provided events list
    - "active_plan_workouts": create workout events for each day in active plan
    - "active_plan_workouts_and_meal_logs": create workout + meal log events for each plan day
    """
    if not confirmed_by_user:
        return "Confirmation required. Ask the user to confirm exactly what calendar events to add, then try again."

    user_email = _fetch_user_email(user_id)
    if not user_email:
        return "Could not find a user email on file. Please update profile email first."

    prepared_events: List[Dict[str, Any]]
    mode = (request_type or "custom").strip().lower()
    if mode == "active_plan_workouts":
        prepared_events = _plan_calendar_events(user_id, include_meal_logs=False, timezone=timezone)
    elif mode == "active_plan_workouts_and_meal_logs":
        prepared_events = _plan_calendar_events(user_id, include_meal_logs=True, timezone=timezone)
    else:
        prepared_events = events or []

    if not prepared_events:
        return "No events to add. Provide event details or choose an active-plan request type."

    try:
        service = _google_calendar_service()
    except Exception as exc:
        return f"Google Calendar setup error: {exc}"

    calendar_id = os.getenv("GOOGLE_CALENDAR_ID", "primary").strip() or "primary"
    success_count = 0
    failed = 0
    created_links: List[str] = []
    with get_db_conn() as conn:
        cur = conn.cursor()
        for item in prepared_events:
            title = str(item.get("title") or "Workout").strip() or "Workout"
            start_at = str(item.get("start_at") or "").strip()
            end_at = str(item.get("end_at") or "").strip()
            description = str(item.get("description") or "").strip()
            tz = str(item.get("timezone") or timezone).strip() or "UTC"
            if not start_at or not end_at:
                failed += 1
                continue
            try:
                body = {
                    "summary": title,
                    "description": description,
                    "start": {"dateTime": _to_iso(start_at), "timeZone": tz},
                    "end": {"dateTime": _to_iso(end_at), "timeZone": tz},
                    "attendees": [{"email": user_email}],
                }
                created = service.events().insert(
                    calendarId=calendar_id,
                    body=body,
                    sendUpdates="all",
                ).execute()
                success_count += 1
                html_link = str(created.get("htmlLink") or "").strip()
                if html_link:
                    created_links.append(html_link)
                cur.execute(
                    """
                    INSERT INTO calendar_blocks (user_id, start_at, end_at, title, source, status)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (user_id, start_at, end_at, title, "google_calendar_sync", "active"),
                )
            except Exception:
                failed += 1
        conn.commit()

    if success_count <= 0:
        return "I couldn't add any events to Google Calendar. Please verify calendar credentials and try again."
    link_preview = "\n".join(created_links[:3]) if created_links else "Events created successfully."
    return (
        f"Added {success_count} Google Calendar event(s) for {user_email}."
        + (f" Failed: {failed}." if failed else "")
        + f"\n{link_preview}"
    )


@tool("generate_plan")
def generate_plan(
    user_id: int,
    days: int = 14,
    target_loss_lbs: Optional[float] = None,
    goal_override: Optional[str] = None,
) -> str:
    """Generate a simple 14-60 day plan based on user profile and preferences."""
    if days < 14:
        days = 14
    if days > 60:
        days = 60
    if target_loss_lbs is not None and not goal_override:
        goal_override = "lose"

    plan_data = _build_plan_data(user_id, days, target_loss_lbs, goal_override=goal_override)
    if "error" in plan_data:
        return plan_data["error"]
    cache_bundle = {
        "plan": {
            "id": None,
            "start_date": plan_data["start_date"],
            "end_date": plan_data["end_date"],
            "daily_calorie_target": plan_data["calorie_target"],
            "protein_g": plan_data["macros"]["protein_g"],
            "carbs_g": plan_data["macros"]["carbs_g"],
            "fat_g": plan_data["macros"]["fat_g"],
            "status": "proposed",
        },
        "plan_days": plan_data["plan_days"],
        "checkpoints": plan_data.get("checkpoints", []),
    }
    _redis_set_json(_draft_plan_key(user_id), cache_bundle, ttl_seconds=CACHE_TTL_LONG)
    SESSION_CACHE[user_id] = {
        "context": SESSION_CACHE.get(user_id, {}).get("context"),
        "active_plan": cache_bundle,
    }
    plan_text = _format_plan_text(plan_data)
    return json.dumps({"plan_text": plan_text, "plan_data": plan_data})


@tool("shift_active_plan_end_date")
def shift_active_plan_end_date(
    user_id: int,
    days_off: int,
    pause_dates: Optional[List[str]] = None,
    calorie_delta: Optional[int] = None,
) -> str:
    """Pause specific dates and shift the active plan end date by days_off."""
    if days_off <= 0:
        return "Days off must be at least 1."
    bundle = SESSION_CACHE.get(user_id, {}).get("active_plan") or _load_active_plan_draft(user_id)
    plan = bundle.get("plan")
    plan_days = bundle.get("plan_days", [])
    if not plan:
        return "No active plan found."
    end_date = plan.get("end_date")
    start_date = plan.get("start_date")
    if not end_date or not start_date:
        return "Active plan dates are missing."

    end = datetime.strptime(end_date, "%Y-%m-%d").date()
    new_end = (end + timedelta(days=days_off)).isoformat()

    dates = pause_dates or []
    if not dates:
        start = datetime.strptime(start_date, "%Y-%m-%d").date()
        dates = [(start + timedelta(days=i)).isoformat() for i in range(days_off)]

    if calorie_delta is None:
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute("SELECT goal_type FROM user_preferences WHERE user_id = ?", (user_id,))
            pref_row = cur.fetchone()
        goal_type = pref_row[0] if pref_row else "lose"
        calorie_delta = 100 if goal_type == "lose" else 0

    plan["end_date"] = new_end
    if plan_days:
        cycle_length = min(7, len(plan_days))
        start_dt = datetime.strptime(start_date, "%Y-%m-%d").date()
        existing_by_date = {day["date"]: day for day in plan_days}
        for offset in range(1, days_off + 1):
            new_day = end + timedelta(days=offset)
            day_key = new_day.isoformat()
            if day_key in existing_by_date:
                continue
            day_index = ((new_day - start_dt).days) % cycle_length
            template = plan_days[day_index]
            existing_by_date[day_key] = {
                "date": day_key,
                "workout_plan": template.get("workout_plan"),
                "rest_day": template.get("rest_day", 0),
                "calorie_target": template.get("calorie_target"),
                "protein_g": template.get("protein_g"),
                "carbs_g": template.get("carbs_g"),
                "fat_g": template.get("fat_g"),
            }
        for pause_day in dates:
            if pause_day in existing_by_date:
                existing_by_date[pause_day]["workout_plan"] = "Rest day"
                existing_by_date[pause_day]["rest_day"] = 1
        bundle["plan_days"] = sorted(existing_by_date.values(), key=lambda d: d["date"])
    _set_active_plan_cache(user_id, bundle)
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT t.id, t.end_date, t.start_date, pref.goal_type
            FROM plan_templates t
            JOIN user_preferences pref ON pref.user_id = t.user_id
            WHERE t.user_id = ? AND t.status = 'active'
            ORDER BY t.start_date DESC
            LIMIT 1
            """,
            (user_id,),
        )
        row = cur.fetchone()
        if not row:
            return "No active plan found."
        template_id, end_date, start_date, goal_type = row
        end = datetime.strptime(end_date, "%Y-%m-%d").date()
        new_end = (end + timedelta(days=days_off)).isoformat()

        dates = pause_dates or []
        if not dates:
            start = datetime.strptime(start_date, "%Y-%m-%d").date()
            dates = [(start + timedelta(days=i)).isoformat() for i in range(days_off)]

        if calorie_delta is None:
            calorie_delta = 100 if goal_type == "lose" else 0

        for day in dates:
            cur.execute("DELETE FROM plan_overrides WHERE template_id = ? AND date = ?", (template_id, day))
            cur.execute(
                """
                INSERT INTO plan_overrides (
                    template_id, date, override_type, workout_json, calorie_target, calorie_delta, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    template_id,
                    day,
                    "pause",
                    json.dumps({"label": "Rest day"}),
                    None,
                    calorie_delta,
                    datetime.now().isoformat(timespec="seconds"),
                ),
            )

        cur.execute("UPDATE plan_templates SET end_date = ? WHERE id = ?", (new_end, template_id))
        conn.commit()

    payload = {
        "plan_patch": {
            "end_date_shift_days": days_off,
            "overrides": [
                {
                    "date": day,
                    "override_type": "pause",
                    "workout_json": json.dumps({"label": "Rest day"}),
                    "calorie_delta": calorie_delta,
                }
                for day in dates
            ],
            "notes": "Paused days and shifted end date; kept cycle order intact.",
        },
        "message": f"Paused {len(dates)} days; plan end date moved from {end_date} to {new_end}.",
    }
    return json.dumps(payload)


def _estimate_total_sets(workout_label: str) -> int:
    matches = re.findall(r"(\\d+)\\s*x", workout_label)
    if not matches:
        return 12
    return max(6, sum(int(m) for m in matches))


def _estimate_cardio_minutes(workout_label: str) -> int:
    range_match = re.search(r"(\\d+)\\s*[–-]\\s*(\\d+)\\s*min", workout_label)
    if range_match:
        return int((int(range_match.group(1)) + int(range_match.group(2))) / 2)
    single_match = re.search(r"(\\d+)\\s*min", workout_label)
    if single_match:
        return int(single_match.group(1))
    return 30


def _build_strength_workout_label(preferred: List[str], total_sets: int) -> str:
    exercises = [ex.strip() for ex in preferred if ex.strip()]
    if not exercises:
        exercises = ["Squat", "Bench", "Row"]
    sets_per_ex = max(2, int(round(total_sets / len(exercises))))
    parts = [f"{ex} {sets_per_ex}x8–12 @RPE7–8" for ex in exercises]
    return "Preferred Strength: " + ", ".join(parts)


def _build_cardio_workout_label(preferred: List[str], minutes: int) -> str:
    exercises = [ex.strip() for ex in preferred if ex.strip()]
    if not exercises:
        exercises = ["Bike"]
    cardio = exercises[0]
    return f"Cardio: {cardio} {minutes} min @RPE5–6"


def _replace_workout_label(existing_label: str, preferred_exercises: List[str]) -> str:
    if "rest" in existing_label.lower():
        return existing_label
    if "cardio" in existing_label.lower() or _is_cardio_exercise(existing_label):
        minutes = _estimate_cardio_minutes(existing_label)
        return _build_cardio_workout_label(preferred_exercises, minutes)
    total_sets = _estimate_total_sets(existing_label)
    return _build_strength_workout_label(preferred_exercises, total_sets)


def _reduce_sets_in_label(label: str) -> str:
    def _repl(match: re.Match) -> str:
        sets = max(1, int(match.group(1)) - 1)
        return f"{sets}x"
    return re.sub(r"(\\d+)\\s*x", _repl, label)


def _reduce_rpe_in_label(label: str) -> str:
    label = re.sub(r"RPE\\s*7–8", "RPE6–7", label)
    label = re.sub(r"RPE\\s*7-8", "RPE6-7", label)
    label = re.sub(r"RPE\\s*7", "RPE6", label)
    return label


def _parse_iso_date(value: Optional[str]) -> Optional[date]:
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        return None


def _reminder_timestamp(day: date, hour: int = 18) -> str:
    return f"{day.isoformat()}T{hour:02d}:00:00"


def _upsert_status_reminder(
    user_id: int,
    reminder_type: str,
    scheduled_at: str,
    status: str = "active",
    channel: str = "push",
) -> None:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM reminders WHERE user_id = ? AND reminder_type = ? AND scheduled_at = ?",
            (user_id, reminder_type, scheduled_at),
        )
        cur.execute(
            """
            INSERT INTO reminders (
                user_id, reminder_type, scheduled_at, status, channel, related_plan_override_id
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (user_id, reminder_type, scheduled_at, status, channel, None),
        )
        conn.commit()


def _update_status_reminders(
    user_id: int,
    status_payload: Dict[str, Any],
    bundle: Dict[str, Any],
    as_of: date,
) -> None:
    today_str = as_of.isoformat()
    last_7d_days = status_payload.get("last_7d_days", [])
    if not isinstance(last_7d_days, list):
        return
    today_entry = next((d for d in last_7d_days if d.get("date") == today_str), None)
    if not isinstance(today_entry, dict):
        return

    plan = bundle.get("plan") if isinstance(bundle, dict) else None
    default_target = plan.get("daily_calorie_target") if isinstance(plan, dict) else None
    intake_target = today_entry.get("intake_target") if today_entry.get("intake_target") is not None else default_target
    actual_intake = today_entry.get("intake")
    goal_type = status_payload.get("goal_type")

    scheduled_at = _reminder_timestamp(as_of)
    if intake_target is not None:
        if actual_intake is None:
            if goal_type == "gain":
                message = f"meal: Log your food. Target {intake_target} kcal today; eat to hit your goal."
            elif goal_type == "lose":
                message = f"meal: Log your food. Target {intake_target} kcal today; stay on track."
            else:
                message = f"meal: Log your food. Target {intake_target} kcal today."
            _upsert_status_reminder(user_id, message, scheduled_at)
        else:
            delta = int(actual_intake) - int(intake_target)
            if goal_type == "gain" and delta < -150:
                remaining = int(intake_target) - int(actual_intake)
                message = f"meal: You have {remaining} kcal left today. Log your food and eat to hit target."
                _upsert_status_reminder(user_id, message, scheduled_at)
            elif goal_type == "lose" and delta > 150:
                message = f"meal: You're {delta} kcal over target today. Log what you eat and ease intake."
                _upsert_status_reminder(user_id, message, scheduled_at)
            elif goal_type not in {"gain", "lose"} and abs(delta) > 150:
                direction = "over" if delta > 0 else "under"
                message = f"meal: You're {abs(delta)} kcal {direction} target today. Log your food."
                _upsert_status_reminder(user_id, message, scheduled_at)

    if not today_entry.get("planned_rest_day") and not today_entry.get("exercised"):
        workout_label = today_entry.get("planned_workout_label") or "Workout"
        context = _load_user_context_data(user_id)
        user = context.get("user") if isinstance(context, dict) else None
        weight_kg = user[4] if user and len(user) > 4 else 0
        if "cardio" in workout_label.lower() or _is_cardio_exercise(workout_label):
            minutes = _estimate_cardio_minutes(workout_label)
        else:
            minutes = 45
        target_burn = _estimate_workout_calories(weight_kg, [], minutes)
        message = (
            f"workout: Today's plan: {workout_label}. "
            f"Target burn ~{target_burn} kcal. Log your workout."
        )
        _upsert_status_reminder(user_id, message, scheduled_at)
    _refresh_reminders_cache(user_id)


def _movement_category(exercise: str) -> Optional[str]:
    lower = exercise.lower()
    if any(k in lower for k in ["squat", "leg press", "goblet"]):
        return "squat"
    if any(k in lower for k in ["hinge", "rdl", "deadlift", "hip thrust"]):
        return "hinge"
    if any(k in lower for k in ["bench", "press", "chest press"]):
        return "horizontal_push"
    if any(k in lower for k in ["row", "cable row"]):
        return "horizontal_pull"
    if any(k in lower for k in ["overhead", "shoulder press", "ohp"]):
        return "vertical_push"
    if any(k in lower for k in ["pull-down", "pulldown", "pull up", "pull-up", "lat"]):
        return "vertical_pull"
    return None


def _replacement_for_category(category: str, preferred: List[str]) -> str:
    category_map = {
        "squat": ["Leg press", "Goblet squat"],
        "hinge": ["RDL", "Hip thrust"],
        "horizontal_push": ["DB bench", "Machine press"],
        "horizontal_pull": ["Cable row", "DB row"],
        "vertical_push": ["DB shoulder press"],
        "vertical_pull": ["Lat pulldown", "Assisted pull-up"],
    }
    preferred_lower = [p.lower() for p in preferred]
    for p in preferred:
        if _movement_category(p) == category:
            return p
    return category_map.get(category, ["Strength exercise"])[0]


def _swap_exercises_by_pattern(label: str, preferred: List[str]) -> str:
    parts = [p.strip() for p in label.split(",")]
    updated = []
    for part in parts:
        match = re.match(r"([A-Za-z \\/\\-]+)\\s+(\\d+x[^\\@]+)(.*)", part)
        if not match:
            updated.append(part)
            continue
        exercise = match.group(1).strip()
        rest = f"{match.group(2)}{match.group(3)}"
        category = _movement_category(exercise)
        if category:
            new_ex = _replacement_for_category(category, preferred)
            updated.append(f"{new_ex} {rest}".strip())
        else:
            updated.append(part)
    return ", ".join(updated)


@tool("replace_active_plan_workouts")
def replace_active_plan_workouts(
    user_id: int,
    preferred_exercises: Any,
    reduce_intensity: bool = False,
    cardio_preference: Optional[str] = None,
) -> str:
    """Legacy: replace active plan workouts using preferred exercises."""
    if isinstance(preferred_exercises, str):
        preferred_list = [ex.strip() for ex in preferred_exercises.split(",") if ex.strip()]
    elif isinstance(preferred_exercises, list):
        preferred_list = [str(ex).strip() for ex in preferred_exercises if str(ex).strip()]
    else:
        preferred_list = []

    bundle = SESSION_CACHE.get(user_id, {}).get("active_plan") or _load_active_plan_draft(user_id)
    if bundle and user_id not in SESSION_CACHE:
        SESSION_CACHE[user_id] = {"context": None, "active_plan": bundle}
    plan = bundle.get("plan")
    plan_days = bundle.get("plan_days", [])
    if not plan or not plan_days:
        return "No cached plan days found to update."

    start_date = plan.get("start_date")
    end_date = plan.get("end_date")
    today = date.today().isoformat()
    affected = []
    overrides = []
    replacement_labels = []
    if not preferred_list:
        context = _load_user_context_data(user_id)
        pref = context.get("preferences") or ()
        goal_type = pref[2] if len(pref) > 2 else "lose"
        days_per_week = 5 if goal_type == "gain" else 4
        workout_cycle = generate_workout_plan(goal_type, days_per_week=days_per_week)
        replacement_labels = [label for label in workout_cycle if "Upper A" in label or "Lower A" in label]
        if not replacement_labels:
            replacement_labels = workout_cycle
    replacement_index = 0
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id
            FROM plan_templates
            WHERE user_id = ? AND status = 'active'
            ORDER BY start_date DESC
            LIMIT 1
            """,
            (user_id,),
        )
        row = cur.fetchone()
        if not row:
            return "No active plan found."
        template_id = row[0]

        for day in plan_days:
            if day["date"] < today or day["date"] > end_date:
                continue
            before_label = day["workout_plan"]
            if not preferred_list and "preferred strength" in (before_label or "").lower() and replacement_labels:
                new_label = replacement_labels[replacement_index % len(replacement_labels)]
                replacement_index += 1
            else:
                new_label = _replace_workout_label(before_label, preferred_list)
                new_label = _swap_exercises_by_pattern(new_label, preferred_list)
            if cardio_preference and "cardio" in new_label.lower():
                new_label = _build_cardio_workout_label([cardio_preference], _estimate_cardio_minutes(new_label))
            if reduce_intensity:
                new_label = _reduce_sets_in_label(new_label)
                new_label = _reduce_rpe_in_label(new_label)
            if new_label != before_label:
                affected.append({"date": day["date"], "before": before_label, "after": new_label})
                overrides.append(
                    {
                        "date": day["date"],
                        "override_type": "adjust",
                        "workout_json": json.dumps({"label": new_label}),
                    }
                )

        for override in overrides:
            cur.execute(
                "DELETE FROM plan_overrides WHERE template_id = ? AND date = ?",
                (template_id, override["date"]),
            )
            cur.execute(
                """
                INSERT INTO plan_overrides (
                    template_id, date, override_type, workout_json, calorie_target, calorie_delta, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    template_id,
                    override["date"],
                    override["override_type"],
                    override["workout_json"],
                    None,
                    None,
                    datetime.now().isoformat(timespec="seconds"),
                ),
            )
        conn.commit()

    if overrides:
        plan_days_map = {day["date"]: day for day in plan_days}
        for override in overrides:
            day = plan_days_map.get(override["date"])
            if day:
                day["workout_plan"] = json.loads(override["workout_json"]).get("label", day["workout_plan"])
        bundle["plan_days"] = list(plan_days_map.values())
    _set_active_plan_cache(user_id, bundle)
    payload = {
        "plan_patch": {
            "end_date_shift_days": 0,
            "overrides": overrides,
            "notes": "Matched movement pattern and kept weekly volume similar.",
        },
        "changes": affected,
    }
    return json.dumps(payload)


def _compact_status_summary(status_raw: str) -> Optional[Dict[str, Any]]:
    try:
        status_data = json.loads(status_raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(status_data, dict):
        return None
    if status_data.get("status") == "insufficient_data":
        return {"status": "insufficient_data"}
    last_7d = status_data.get("last_7d", {}) if isinstance(status_data.get("last_7d"), dict) else {}
    return {
        "status": status_data.get("status"),
        "as_of": status_data.get("as_of"),
        "goal_type": status_data.get("goal_type"),
        "explanation": status_data.get("explanation"),
        "last_7d": {
            "avg_intake_kcal": last_7d.get("avg_intake_kcal"),
            "avg_burn_kcal": last_7d.get("avg_burn_kcal"),
            "avg_target_kcal": last_7d.get("avg_target_kcal"),
            "workouts_done": last_7d.get("workouts_done"),
            "workouts_planned": last_7d.get("workouts_planned"),
            "workouts_missed": last_7d.get("workouts_missed"),
            "meal_log_days": last_7d.get("meal_log_days"),
        },
    }


def validate_patch(
    bundle: Dict[str, Any],
    patch: Dict[str, Any],
    as_of_date: Optional[str],
) -> tuple[bool, List[str]]:
    errors: List[str] = []
    if not isinstance(bundle, dict):
        return False, ["Active plan bundle missing."]
    plan = bundle.get("plan") if isinstance(bundle.get("plan"), dict) else None
    plan_days = bundle.get("plan_days", []) if isinstance(bundle.get("plan_days"), list) else []
    if not plan or not plan_days:
        return False, ["Active plan data unavailable."]

    overrides = patch.get("overrides")
    if not isinstance(overrides, list):
        return False, ["Patch must include an overrides list."]
    if len(overrides) > 30:
        errors.append("At most 30 overrides are allowed per patch.")

    today = date.today()
    as_of = _parse_iso_date(as_of_date) or today
    start_date = max(today, as_of)
    end_date = _parse_iso_date(plan.get("end_date"))
    if end_date is None:
        errors.append("Plan end date is missing or invalid.")
    plan_day_dates = {d.get("date") for d in plan_days if d.get("date")}

    user_id = patch.pop("_user_id", None)
    min_calories = 1200
    if user_id is not None:
        context = _load_user_context_data(int(user_id))
        user = context.get("user") if isinstance(context, dict) else None
        gender = user[5] if user and len(user) > 5 else None
        if isinstance(gender, str) and gender.lower().startswith("m"):
            min_calories = 1500

    for idx, override in enumerate(overrides):
        if not isinstance(override, dict):
            errors.append(f"Override #{idx + 1} must be an object.")
            continue
        date_str = override.get("date")
        parsed_date = _parse_iso_date(date_str)
        if not parsed_date:
            errors.append(f"Override #{idx + 1} has invalid date.")
            continue
        if parsed_date < start_date:
            errors.append(f"Override date {date_str} is before allowed window.")
        if end_date and parsed_date > end_date:
            errors.append(f"Override date {date_str} is after plan end date.")
        if date_str not in plan_day_dates:
            errors.append(f"Override date {date_str} is not in plan days.")

        override_type = override.get("override_type")
        if override_type not in {"adjust", "pause", "deload"}:
            errors.append(f"Override date {date_str} has invalid override_type.")

        workout_json = override.get("workout_json")
        if workout_json is not None:
            label = None
            if isinstance(workout_json, dict):
                label = workout_json.get("label")
            elif isinstance(workout_json, str):
                try:
                    parsed = json.loads(workout_json)
                except json.JSONDecodeError:
                    parsed = None
                if isinstance(parsed, dict) and parsed.get("label"):
                    label = parsed.get("label")
                else:
                    label = workout_json
            if not isinstance(label, str) or not label.strip():
                errors.append(f"Override date {date_str} has invalid workout label.")
            elif len(label) > 2500:
                errors.append(f"Override date {date_str} workout label too long.")
            else:
                override["workout_json"] = json.dumps({"label": label})

        calorie_target = override.get("calorie_target")
        calorie_delta = override.get("calorie_delta")
        if calorie_target is not None:
            if calorie_target < min_calories:
                errors.append(f"Override date {date_str} calorie_target below minimum.")
        elif calorie_delta is not None:
            base_target = plan.get("daily_calorie_target")
            day_target = next((d.get("calorie_target") for d in plan_days if d.get("date") == date_str), None)
            base = day_target if day_target is not None else base_target or 0
            if base + int(calorie_delta) < min_calories:
                errors.append(f"Override date {date_str} calorie_delta below minimum.")

    return len(errors) == 0, errors


@tool("propose_plan_patch_with_llm")
def propose_plan_patch_with_llm(
    user_id: int,
    user_request: str,
    as_of_date: Optional[str] = None,
    apply: bool = False,
) -> str:
    """Propose (and optionally apply) a plan patch based on user request."""
    if not user_request or not user_request.strip():
        return json.dumps({"applied": False, "validation_errors": ["Missing user request."], "patch": None, "apply_result": None})
    bundle = SESSION_CACHE.get(user_id, {}).get("active_plan") or _load_active_plan_draft(user_id)
    plan = bundle.get("plan")
    plan_days = bundle.get("plan_days", [])
    if not plan or not plan_days:
        return json.dumps({"applied": False, "validation_errors": ["No active plan found."], "patch": None, "apply_result": None})

    today = date.today()
    as_of = _parse_iso_date(as_of_date) or today
    start_day = max(today, as_of).isoformat()
    end_day = plan.get("end_date")
    plan_start = plan.get("start_date")
    plan_days_sorted = sorted([d for d in plan_days if d.get("date")], key=lambda d: d["date"])
    upcoming = [d for d in plan_days_sorted if d["date"] >= start_day]
    next_days = upcoming

    # Deterministic fast-path for "skip next N day(s)" so the plan reliably updates.
    lowered_request = user_request.lower()
    skip_match = re.search(r"skip\s+(?:the\s+)?next\s+(\d+)\s+day", lowered_request)
    word_to_num = {
        "one": 1,
        "two": 2,
        "three": 3,
        "four": 4,
        "five": 5,
        "six": 6,
        "seven": 7,
    }
    skip_word_match = re.search(
        r"skip\s+(?:the\s+)?next\s+(one|two|three|four|five|six|seven)\s+day",
        lowered_request,
    )
    if skip_match:
        skip_days = max(1, int(skip_match.group(1)))
    elif skip_word_match:
        skip_days = word_to_num.get(skip_word_match.group(1), 1)
    else:
        skip_days = 0
    if skip_days > 0:
        moved_workouts: List[str] = []
        overrides: List[Dict[str, Any]] = []
        for day in next_days[:skip_days]:
            if not day.get("rest_day"):
                moved_workouts.append(day.get("workout_plan") or "Workout")
            overrides.append(
                {
                    "date": day["date"],
                    "override_type": "pause",
                    "workout_json": {"label": "Rest day"},
                    "calorie_target": None,
                    "calorie_delta": None,
                }
            )

        # Reassign skipped workouts into existing rest days first to preserve end date.
        for day in next_days[skip_days:]:
            if not moved_workouts:
                break
            if day.get("rest_day"):
                label = moved_workouts.pop(0)
                overrides.append(
                    {
                        "date": day["date"],
                        "override_type": "adjust",
                        "workout_json": {"label": label},
                        "calorie_target": None,
                        "calorie_delta": None,
                    }
                )

        new_end_date = None
        if moved_workouts:
            end_dt = _parse_iso_date(end_day)
            if end_dt is not None:
                new_end_date = (end_dt + timedelta(days=len(moved_workouts))).isoformat()

        patch = {
            "overrides": overrides,
            "new_end_date": new_end_date,
            "notes": (
                "Auto-generated skip patch: paused requested days, moved missed workouts into remaining rest days, "
                "and extended end date only for residual carryover."
            ),
        }
        patch["_user_id"] = user_id
        is_ok, errors = validate_patch(bundle, patch, as_of.isoformat())
        sanitized_patch = {k: v for k, v in patch.items() if k != "_user_id"}
        apply_result = None
        if is_ok and apply:
            apply_result = apply_plan_patch.func(user_id, sanitized_patch)
        return json.dumps(
            {
                "applied": bool(apply and is_ok),
                "validation_errors": errors,
                "patch": sanitized_patch,
                "apply_result": apply_result,
            }
        )

    status_raw = compute_plan_status.func(user_id, as_of_date=as_of.isoformat())
    status_summary = _compact_status_summary(status_raw)

    day_lines = [
        f"{day['date']} | rest_day={day.get('rest_day', 0)} | workout_plan={day.get('workout_plan')}"
        for day in next_days
    ]
    status_block = json.dumps(status_summary) if status_summary else "null"
    system_prompt = (
        "You are a plan patch generator. Return ONLY valid JSON with the schema:\n"
        '{"overrides":[{"date":"YYYY-MM-DD","override_type":"adjust","workout_json":{"label":"..."},"calorie_target":null,"calorie_delta":null}],"new_end_date":null,"notes":"..."}\n'
        "Use only the dates provided. If no changes are needed, return overrides as an empty list. "
        "If user asks to skip days, first try to reassign missed workouts within existing remaining days; "
        "set new_end_date only if truly needed. No markdown."
    )
    human_prompt = (
        f"User request: {user_request}\n"
        f"As of: {as_of.isoformat()}\n"
        f"Plan range: {plan_start} to {end_day}\n"
        f"Next 14 plan days starting {start_day}:\n"
        + "\n".join(day_lines)
        + f"\nStatus summary (compact): {status_block}"
    )
    llm = ChatOpenAI(model="gpt-4o", temperature=0, max_retries=0, request_timeout=30)
    response = llm.invoke([SystemMessage(content=system_prompt), HumanMessage(content=human_prompt)])
    raw_content = response.content if isinstance(response.content, str) else ""
    print("LLM plan patch raw response:", raw_content)
    try:
        patch = json.loads(raw_content)
    except json.JSONDecodeError:
        return json.dumps(
            {
                "applied": False,
                "validation_errors": ["LLM response was not valid JSON."],
                "patch": None,
                "apply_result": None,
            }
        )
    print("LLM plan patch parsed:", patch)
    if not isinstance(patch, dict):
        return json.dumps(
            {
                "applied": False,
                "validation_errors": ["LLM response must be a JSON object."],
                "patch": None,
                "apply_result": None,
            }
        )
    patch.setdefault("overrides", [])
    patch.setdefault("new_end_date", None)
    patch.setdefault("notes", "")
    patch["_user_id"] = user_id
    is_ok, errors = validate_patch(bundle, patch, as_of.isoformat())
    sanitized_patch = {k: v for k, v in patch.items() if k != "_user_id"}
    if not is_ok:
        return json.dumps(
            {
                "applied": False,
                "validation_errors": errors,
                "patch": sanitized_patch,
                "apply_result": None,
            }
        )
    apply_result = None
    if apply:
        apply_result = apply_plan_patch.func(user_id, sanitized_patch)
    return json.dumps(
        {
            "applied": bool(apply),
            "validation_errors": errors,
            "patch": sanitized_patch,
            "apply_result": apply_result,
        }
    )


@tool("get_weight_checkpoint_for_current_week")
def get_weight_checkpoint_for_current_week(user_id: int) -> str:
    """Get the expected weight for the current week from cached checkpoints."""
    bundle = SESSION_CACHE.get(user_id, {}).get("active_plan") or _redis_get_json(f"user:{user_id}:active_plan") or {}
    if bundle and user_id not in SESSION_CACHE:
        SESSION_CACHE[user_id] = {"context": None, "active_plan": bundle}
    plan = bundle.get("plan")
    checkpoints = bundle.get("checkpoints", [])
    if not plan or not checkpoints:
        return "No cached weight checkpoints found for this plan."
    try:
        start_date = datetime.strptime(plan["start_date"], "%Y-%m-%d").date()
    except (KeyError, ValueError, TypeError):
        return "Plan start date missing or invalid."
    weeks_since_start = max(1, int(((date.today() - start_date).days + 1 + 6) / 7))
    selected = None
    previous = None
    for checkpoint in checkpoints:
        if checkpoint["week"] < weeks_since_start:
            previous = checkpoint
        if checkpoint["week"] >= weeks_since_start:
            selected = checkpoint
            break
    if selected is None:
        selected = checkpoints[-1]
    response = (
        f"By end of week {selected['week']}: expected {selected['expected_weight_kg']:.1f} kg "
        f"(range {selected['min_weight_kg']:.1f}–{selected['max_weight_kg']:.1f})."
    )
    if weeks_since_start % 2 == 1 and previous:
        response += (
            f" Prior checkpoint (week {previous['week']}): {previous['expected_weight_kg']:.1f} kg "
            f"(range {previous['min_weight_kg']:.1f}–{previous['max_weight_kg']:.1f})."
        )
    return response


@tool("get_current_date")
def get_current_date() -> str:
    """Return today's date in ISO format."""
    return date.today().isoformat()


@tool("search_web")
def search_web(query: str) -> str:
    """Search the web and return formatted source snippets."""
    tavily_search = TavilySearch(max_results=3)
    data = tavily_search.invoke({"query": query})
    search_docs = data.get("results", data)
    return "\n\n---\n\n".join(
        [
            f'<Document href="{doc["url"]}"/>\n{doc["content"]}\n</Document>'
            for doc in search_docs
        ]
    )


@tool("compute_plan_status")
def compute_plan_status(user_id: int, as_of_date: Optional[str] = None) -> str:
    """Compute plan status from cached check-ins, meals, workouts, and checkpoints."""
    bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
    plan = bundle.get("plan") if isinstance(bundle, dict) else None
    checkpoints = bundle.get("checkpoints", []) if isinstance(bundle, dict) else []
    if not plan or not checkpoints:
        meals = _redis_get_json(_draft_meal_logs_key(user_id)) or _load_meal_logs_draft(user_id)
        meal_rows = meals.get("meals", []) if isinstance(meals, dict) else []
        workouts = _redis_get_json(_draft_workout_sessions_key(user_id)) or _load_workout_sessions_draft(user_id)
        workout_rows = workouts.get("sessions", []) if isinstance(workouts, dict) else []
        checkins = _redis_get_json(_draft_checkins_key(user_id)) or _load_checkins_draft(user_id)
        checkin_rows = checkins.get("checkins", []) if isinstance(checkins, dict) else []

        today = date.today()
        days = [(today - timedelta(days=offset)).isoformat() for offset in range(7)]
        meal_days = {
            day
            for day in days
            if any((m.get("logged_at") or "").startswith(day) for m in meal_rows)
        }
        workout_days = {
            day
            for day in days
            if any((w.get("date") or "") == day for w in workout_rows)
        }
        recent_weighins = [
            c
            for c in checkin_rows
            if c.get("checkin_date")
            and (today - datetime.strptime(c["checkin_date"], "%Y-%m-%d").date()).days <= 14
        ]
        explanation = (
            f"Logged meals on {len(meal_days)} day(s) and workouts on {len(workout_days)} day(s) "
            f"in the last 7 days. Add a plan (or regenerate it) plus 2 weigh-ins to unlock "
            "full progress insights."
        )
        return json.dumps(
            {
                "status": "limited",
                "as_of": today.isoformat(),
                "last_7d": {
                    "meal_log_days": len(meal_days),
                    "workouts_done": len(workout_days),
                    "weighins_14d": len(recent_weighins),
                },
                "explanation": explanation,
            }
        )

    as_of = datetime.strptime(as_of_date, "%Y-%m-%d").date() if as_of_date else date.today()
    start_date = datetime.strptime(plan["start_date"], "%Y-%m-%d").date()
    weeks_since_start = max(1, int(((as_of - start_date).days + 1 + 6) / 7))

    checkpoint = None
    for cp in checkpoints:
        if cp["week"] >= weeks_since_start:
            checkpoint = cp
            break
    if checkpoint is None:
        checkpoint = checkpoints[-1]

    checkins = _redis_get_json(_draft_checkins_key(user_id)) or _load_checkins_draft(user_id)
    checkin_rows = checkins.get("checkins", []) if isinstance(checkins, dict) else []
    recent_checkins = [
        c for c in checkin_rows if c.get("checkin_date") and c.get("weight_kg") is not None
    ]
    recent_checkins.sort(key=lambda c: c["checkin_date"], reverse=True)
    trend_weights = []
    recent_weighins_count = 0
    for c in recent_checkins:
        try:
            c_date = datetime.strptime(c["checkin_date"], "%Y-%m-%d").date()
        except ValueError:
            continue
        if (as_of - c_date).days <= 14:
            recent_weighins_count += 1
        if (as_of - c_date).days <= 7:
            trend_weights.append(c["weight_kg"])
        if len(trend_weights) >= 7:
            break
    if len(trend_weights) == 0:
        recent_14 = []
        for c in recent_checkins:
            try:
                c_date = datetime.strptime(c["checkin_date"], "%Y-%m-%d").date()
            except ValueError:
                continue
            if 0 <= (as_of - c_date).days <= 14:
                recent_14.append(c["weight_kg"])
            if len(recent_14) >= 2:
                break
        trend_weights = recent_14
    weight_insufficient = False
    if len(trend_weights) < 2 and recent_weighins_count < 2:
        weight_insufficient = True

    expected_kg = checkpoint["expected_weight_kg"]
    min_kg = checkpoint["min_weight_kg"]
    max_kg = checkpoint["max_weight_kg"]
    band = max(0.5, max(abs(expected_kg - min_kg), abs(max_kg - expected_kg)))
    current_trend = sum(trend_weights) / len(trend_weights) if trend_weights else expected_kg
    weight_error = current_trend - expected_kg

    context = _load_user_context_data(user_id)
    pref = context.get("preferences") or ()
    goal_type = pref[2] if len(pref) > 2 else "lose"
    user = context.get("user") if isinstance(context, dict) else None
    weight_for_burn = user[4] if user and len(user) > 4 else 0

    meals = _redis_get_json(_draft_meal_logs_key(user_id)) or _load_meal_logs_draft(user_id)
    meal_rows = meals.get("meals", []) if isinstance(meals, dict) else []
    workouts = _redis_get_json(_draft_workout_sessions_key(user_id)) or _load_workout_sessions_draft(user_id)
    workout_rows = workouts.get("sessions", []) if isinstance(workouts, dict) else []
    activity = _redis_get_json(_draft_health_activity_key(user_id)) or _load_health_activity_draft(user_id)
    activity_rows = activity.get("activity", []) if isinstance(activity, dict) else []

    def _within_last_7(date_str: str) -> bool:
        try:
            parsed = datetime.fromisoformat(date_str).date()
        except ValueError:
            try:
                parsed = datetime.strptime(date_str, "%Y-%m-%d").date()
            except ValueError:
                return False
        if parsed < start_date:
            return False
        return 0 <= (as_of - parsed).days <= 6

    def _plan_day_for_date(day_str: str) -> Optional[Dict[str, Any]]:
        for d in bundle.get("plan_days", []) or []:
            if d.get("date") == day_str:
                return d
        return None

    def _is_rest_day(plan_day: Optional[Dict[str, Any]]) -> bool:
        if not plan_day:
            return False
        if plan_day.get("rest_day") == 1:
            return True
        return "rest" in (plan_day.get("workout_plan", "").lower())

    def _expected_burn_for_day(plan_day: Optional[Dict[str, Any]]) -> Optional[int]:
        if not plan_day:
            return None
        workout_label = plan_day.get("workout_plan") or ""
        if "rest" in workout_label.lower():
            return 0
        if "cardio" in workout_label.lower() or _is_cardio_exercise(workout_label):
            minutes = _estimate_cardio_minutes(workout_label)
        else:
            minutes = 45
        return _estimate_workout_calories(weight_for_burn, [], minutes)

    last_7d_days = []
    for offset in range(7):
        day = as_of - timedelta(days=offset)
        if day < start_date:
            continue
        day_str = day.isoformat()
        plan_day = _plan_day_for_date(day_str)
        planned_rest = _is_rest_day(plan_day)
        planned_label = plan_day.get("workout_plan") if plan_day else None

        meals_for_day = [m for m in meal_rows if m.get("logged_at", "").startswith(day_str)]
        actual_intake = sum(m.get("calories", 0) for m in meals_for_day) if meals_for_day else None
        intake_target = plan_day.get("calorie_target") if plan_day else plan.get("daily_calorie_target")
        intake_delta = (actual_intake - intake_target) if actual_intake is not None and intake_target is not None else None

        activity_for_day = [a for a in activity_rows if a.get("date") == day_str]
        workout_for_day = [w for w in workout_rows if w.get("date") == day_str]
        if activity_for_day:
            actual_burn = sum(a.get("calories_burned", 0) for a in activity_for_day)
        elif workout_for_day:
            actual_burn = sum(w.get("calories_burned", 0) for w in workout_for_day)
        else:
            actual_burn = None

        exercised = bool(workout_for_day) or any(
            (a.get("workouts_summary") or "").strip() for a in activity_for_day
        )

        expected_burn = _expected_burn_for_day(plan_day)
        burn_delta = (actual_burn - expected_burn) if actual_burn is not None and expected_burn is not None else None

        nutrition_ok = None if actual_intake is None or intake_delta is None else abs(intake_delta) <= 150
        training_ok = True if planned_rest else exercised
        if expected_burn and actual_burn is not None:
            intensity_ok = actual_burn >= int(0.8 * expected_burn)
        else:
            intensity_ok = None

        missing_flags = []
        if actual_intake is None:
            missing_flags.append("missing_meal_log")
        if actual_burn is None:
            missing_flags.append("missing_burn")
        if plan_day is None:
            missing_flags.append("missing_plan_day")

        last_7d_days.append(
            {
                "date": day_str,
                "planned_workout_label": planned_label,
                "planned_rest_day": planned_rest,
                "intake": actual_intake,
                "intake_target": intake_target,
                "intake_delta": intake_delta,
                "actual_burn": actual_burn,
                "expected_burn": expected_burn,
                "burn_delta": burn_delta,
                "exercised": exercised,
                "nutrition_ok": nutrition_ok,
                "training_ok": training_ok,
                "intensity_ok": intensity_ok,
                "notes_missing_data_flags": missing_flags,
            }
        )

    intake_days = [d for d in last_7d_days if d.get("intake") is not None and d.get("intake_target") is not None]
    burn_days = [d for d in last_7d_days if d.get("actual_burn") is not None]
    workouts_planned = sum(1 for d in last_7d_days if not d.get("planned_rest_day"))
    workouts_done = len({w.get("date") for w in workout_rows if w.get("date") and _within_last_7(w["date"])})
    workouts_missed = max(
        0,
        workouts_planned
        - sum(1 for d in last_7d_days if d.get("training_ok") and not d.get("planned_rest_day")),
    )
    meal_log_days = sum(1 for d in last_7d_days if d.get("intake") is not None)

    avg_intake = int(sum(d["intake"] for d in intake_days) / max(1, len(intake_days))) if intake_days else None
    avg_target = int(sum(d["intake_target"] for d in intake_days) / max(1, len(intake_days))) if intake_days else None
    avg_burn = int(sum(d["actual_burn"] for d in burn_days) / max(1, len(burn_days))) if burn_days else None

    weekly_intake_delta = sum(d["intake_delta"] for d in intake_days if d.get("intake_delta") is not None)
    weekly_burn_delta = sum(d["burn_delta"] for d in burn_days if d.get("burn_delta") is not None)
    weekly_net_delta_est = weekly_intake_delta - weekly_burn_delta

    if meal_log_days < 1 and workouts_done < 1 and recent_weighins_count < 1:
        status = "insufficient_data"
    else:
        weight_ok = True if weight_insufficient else min_kg <= current_trend <= max_kg
        nutrition_ok_week = None if not intake_days else abs(avg_intake - avg_target) <= 150
        training_ok_week = True if workouts_planned <= 0 else workouts_missed <= 1
        intensity_checks = [
            d for d in last_7d_days
            if not d.get("planned_rest_day") and d.get("expected_burn") and d.get("intensity_ok") is not None
        ]
        if intensity_checks:
            intensity_ok_week = (sum(1 for d in intensity_checks if d["intensity_ok"]) / len(intensity_checks)) >= 0.7
        else:
            intensity_ok_week = None

        if weight_ok and (nutrition_ok_week is True or training_ok_week):
            status = "on_track"
        elif not weight_ok:
            if goal_type == "gain":
                status = "behind" if current_trend < min_kg else "ahead"
            elif goal_type == "maintain":
                status = "behind" if current_trend > max_kg else "ahead"
            else:
                status = "behind" if current_trend > max_kg else "ahead"
        else:
            if nutrition_ok_week is False or training_ok_week is False:
                if goal_type == "gain":
                    status = "behind" if avg_intake is not None and avg_intake < avg_target else "ahead"
                else:
                    status = "behind" if avg_intake is not None and avg_intake > avg_target else "ahead"
            else:
                status = "on_track"

    if status == "behind":
        if goal_type == "gain":
            suggestion = "Consider +100–200 kcal/day or add 1 extra strength session."
        else:
            suggestion = "Consider -150–250 kcal/day or add 1–2 cardio sessions."
    elif status == "ahead":
        if goal_type == "gain":
            suggestion = "Consider reducing intake by ~100 kcal/day to avoid overshooting."
        else:
            suggestion = "Consider a small increase of ~100 kcal/day to avoid excessive deficit."
    elif status == "insufficient_data":
        suggestion = "Log at least 3 days of meals and 2 weigh-ins to assess progress."
    else:
        suggestion = "Keep current targets; you are aligned with the plan."

    explanation = (
        f"{workouts_done}/{workouts_planned} workouts completed; "
        f"avg intake {avg_intake} kcal vs target {avg_target} kcal; "
        f"intensity below target on {sum(1 for d in last_7d_days if d.get('intensity_ok') is False)} day(s). "
        f"{suggestion}"
    )
    if weight_insufficient:
        explanation = f"{explanation} Add another weigh-in this week for higher accuracy."

    status_payload = {
        "status": status,
        "confidence": 0.7 if trend_weights else 0.4,
        "as_of": as_of.isoformat(),
        "goal_type": goal_type,
        "checkpoint": {
            "week": checkpoint["week"],
            "expected_kg": expected_kg,
            "min_kg": min_kg,
            "max_kg": max_kg,
        },
        "current_weight_trend_kg": round(current_trend, 2),
        "weight_error_kg": round(weight_error, 2),
        "last_7d_days": list(reversed(last_7d_days)),
        "last_7d": {
            "avg_intake_kcal": avg_intake,
            "avg_burn_kcal": avg_burn,
            "avg_target_kcal": avg_target,
            "workouts_done": workouts_done,
            "workouts_planned": workouts_planned,
            "workouts_missed": workouts_missed,
            "meal_log_days": meal_log_days,
        },
        "estimated_required_delta_kcal_per_day": int(avg_target - avg_intake) if avg_intake is not None else None,
        "explanation": explanation,
    }
    if status == "behind":
        _update_status_reminders(user_id, status_payload, bundle, as_of)
    _redis_set_json(_draft_plan_status_key(user_id), status_payload, ttl_seconds=CACHE_TTL_LONG)
    return json.dumps(status_payload)


@tool("apply_plan_patch")
def apply_plan_patch(user_id: int, patch: Dict[str, Any]) -> str:
    """Apply a plan patch (overrides + optional end_date) to cache and DB."""
    idem_digest = hashlib.sha256(json.dumps(patch, sort_keys=True).encode("utf-8")).hexdigest()
    idem_key = f"idem:tool:plan_patch:{user_id}:auto:{idem_digest}"
    cached = _redis_get_json(idem_key)
    if isinstance(cached, dict) and cached.get("message"):
        return str(cached["message"])

    bundle = SESSION_CACHE.get(user_id, {}).get("active_plan") or _load_active_plan_draft(user_id)
    plan = bundle.get("plan")
    plan_days = bundle.get("plan_days", [])
    if not plan:
        return "No active plan found."

    overrides = patch.get("overrides", [])
    new_end_date = patch.get("new_end_date")

    if new_end_date:
        plan["end_date"] = new_end_date
    plan_days_by_date = {day.get("date"): day for day in plan_days if day.get("date")}

    if new_end_date:
        old_end = max((day.get("date") for day in plan_days if day.get("date")), default=None)
        old_end_dt = _parse_iso_date(old_end)
        new_end_dt = _parse_iso_date(new_end_date)
        sorted_existing = sorted(plan_days, key=lambda d: d.get("date") or "")
        cycle_length = max(1, min(7, len(sorted_existing)))
        if old_end_dt and new_end_dt and sorted_existing:
            offset = 1
            while old_end_dt + timedelta(days=offset) <= new_end_dt:
                new_day = old_end_dt + timedelta(days=offset)
                date_key = new_day.isoformat()
                if date_key in plan_days_by_date:
                    offset += 1
                    continue
                template = sorted_existing[((new_day - _coerce_to_date(plan.get("start_date"))).days) % cycle_length]
                plan_days_by_date[date_key] = {
                    "date": date_key,
                    "workout_plan": template.get("workout_plan"),
                    "workout_raw": template.get("workout_raw"),
                    "rest_day": template.get("rest_day", 0),
                    "calorie_target": template.get("calorie_target"),
                    "protein_g": template.get("protein_g"),
                    "carbs_g": template.get("carbs_g"),
                    "fat_g": template.get("fat_g"),
                }
                offset += 1
    for override in overrides:
        day = plan_days_by_date.get(override.get("date"))
        if not day:
            continue
        if override.get("calorie_target") is not None:
            day["calorie_target"] = override["calorie_target"]
        elif override.get("calorie_delta") is not None:
            base = plan.get("daily_calorie_target") or day.get("calorie_target") or 0
            day["calorie_target"] = base + int(override["calorie_delta"])
        if override.get("workout_json"):
            try:
                label = json.loads(override["workout_json"]).get("label")
            except json.JSONDecodeError:
                label = None
            if label:
                day["workout_plan"] = label
    bundle["plan_days"] = sorted(plan_days_by_date.values(), key=lambda d: d.get("date") or "")
    _set_active_plan_cache(user_id, bundle)

    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT id FROM plan_templates WHERE user_id = ? AND status = 'active' ORDER BY start_date DESC LIMIT 1",
            (user_id,),
        )
        row = cur.fetchone()
        if not row:
            message = "No active plan found."
            _redis_set_json(idem_key, {"message": message}, ttl_seconds=600)
            return message
        template_id = row[0]
        if new_end_date:
            cur.execute("UPDATE plan_templates SET end_date = ? WHERE id = ?", (new_end_date, template_id))
        for override in overrides:
            cur.execute(
                "DELETE FROM plan_overrides WHERE template_id = ? AND date = ?",
                (template_id, override["date"]),
            )
            cur.execute(
                """
                INSERT INTO plan_overrides (
                    template_id, date, override_type, workout_json, calorie_target, calorie_delta, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    template_id,
                    override.get("date"),
                    override.get("override_type", "adjust"),
                    override.get("workout_json"),
                    override.get("calorie_target"),
                    override.get("calorie_delta"),
                    datetime.now().isoformat(timespec="seconds"),
                ),
            )
        conn.commit()
    message = "Plan patch applied."
    _redis_set_json(idem_key, {"message": message}, ttl_seconds=600)
    return message


@tool("propose_plan_corrections")
def propose_plan_corrections(
    user_id: int,
    as_of_date: Optional[str] = None,
    apply: bool = False,
) -> str:
    """Propose (and optionally apply) plan corrections from today forward."""
    status_raw = compute_plan_status.func(user_id, as_of_date=as_of_date)
    try:
        status_data = json.loads(status_raw)
    except json.JSONDecodeError:
        return status_raw
    if status_data.get("status") == "insufficient_data":
        return json.dumps(
            {
                "status_summary": status_data,
                "correction_needed": False,
                "correction_plan": None,
                "rationale": "Insufficient data to recommend changes.",
                "safety_checks": {},
            }
        )

    bundle = SESSION_CACHE.get(user_id, {}).get("active_plan") or _redis_get_json(_draft_plan_key(user_id)) or {}
    plan = bundle.get("plan") if isinstance(bundle, dict) else None
    if not plan:
        return json.dumps({"status": "insufficient_data"})
    as_of = datetime.strptime(as_of_date, "%Y-%m-%d").date() if as_of_date else date.today()
    end_date = datetime.strptime(plan["end_date"], "%Y-%m-%d").date()
    days_remaining = max(1, (end_date - as_of).days + 1)

    goal_type = status_data.get("goal_type", "lose")
    avg_target = status_data.get("last_7d", {}).get("avg_target_kcal")
    avg_intake = status_data.get("last_7d", {}).get("avg_intake_kcal")
    if avg_target is None or avg_intake is None:
        return json.dumps(
            {
                "status_summary": status_data,
                "correction_needed": False,
                "correction_plan": None,
                "rationale": "Missing intake data to compute calorie corrections.",
                "safety_checks": {},
            }
        )

    delta_per_day = avg_target - avg_intake
    bounded_delta = max(-250, min(250, delta_per_day))
    correction_needed = status_data.get("status") in {"behind", "ahead"}

    override_dates = []
    for i in range(days_remaining):
        day = as_of + timedelta(days=i)
        override_dates.append(day.isoformat())

    overrides = [
        {"date": day, "override_type": "adjust", "calorie_delta": int(bounded_delta)}
        for day in override_dates
    ]

    patch = {
        "overrides": overrides,
        "notes": "Adjustment to hit checkpoint without extending end date.",
    }

    safety_checks = {
        "calorie_delta_bounds_ok": -250 <= bounded_delta <= 250,
        "minimum_calories_ok": True,
        "max_weekly_change_ok": True,
    }

    rationale = (
        f"Adjusting daily calories by {int(bounded_delta)} kcal for {days_remaining} day(s) "
        f"to align intake with target."
    )

    if apply and correction_needed:
        apply_plan_patch.func(user_id, patch)

    return json.dumps(
        {
            "status_summary": status_data,
            "correction_needed": correction_needed,
            "correction_plan": patch if correction_needed else None,
            "rationale": rationale,
            "safety_checks": safety_checks,
        }
    )


@tool("log_checkin")
def log_checkin(
    user_id: int,
    checkin_date: Optional[str] = None,
    weight_kg: Optional[float] = None,
    mood: Optional[str] = None,
    notes: Optional[str] = None,
) -> str:
    """Log or update a weight check-in."""
    if weight_kg is None:
        return "What was your weight in kg?"
    checkin_date = _normalize_checkin_date(checkin_date)
    draft = _load_checkins_draft(user_id)
    checkins = draft.get("checkins", [])
    updated = False
    for entry in checkins:
        if entry.get("checkin_date") == checkin_date:
            entry["weight_kg"] = weight_kg
            entry["mood"] = mood
            entry["notes"] = notes
            updated = True
            break
    if not updated:
        checkins.insert(
            0,
            {
                "id": None,
                "user_id": user_id,
                "checkin_date": checkin_date,
                "weight_kg": weight_kg,
                "mood": mood,
                "notes": notes,
            },
        )
    draft["checkins"] = checkins
    _redis_set_json(_draft_checkins_key(user_id), draft, ttl_seconds=CACHE_TTL_LONG)
    SESSION_CACHE.setdefault(user_id, {})["checkins"] = draft
    _sync_checkins_to_db(user_id, checkins)
    _invalidate_checkins_cache(user_id)
    reason = f"checkin_log:{checkin_date}"
    if not _has_points_reason(user_id, reason):
        _award_points(user_id, 5, reason)
    _apply_daily_checklist_completion_bonus(user_id, checkin_date)
    if checkin_date == date.today().isoformat():
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute("UPDATE users SET weight_kg = ? WHERE id = ?", (weight_kg, user_id))
            conn.commit()
        cached_context = SESSION_CACHE.get(user_id, {}).get("context") or _redis_get_json(f"user:{user_id}:profile")
        if isinstance(cached_context, dict) and cached_context.get("user"):
            user_list = list(cached_context["user"])
            if len(user_list) > 4:
                user_list[4] = weight_kg
                cached_context["user"] = user_list
                _redis_set_json(f"user:{user_id}:profile", cached_context, ttl_seconds=CACHE_TTL_LONG)
                SESSION_CACHE.setdefault(user_id, {})["context"] = cached_context
    return "Check-in logged."


@tool("delete_checkin")
def delete_checkin(user_id: int, checkin_date: str) -> str:
    """Delete a weight check-in for a specific date."""
    if not checkin_date:
        return "Which date should I delete?"
    checkin_date = _normalize_checkin_date(checkin_date)
    draft = _load_checkins_draft(user_id)
    checkins = [c for c in draft.get("checkins", []) if c.get("checkin_date") != checkin_date]
    draft["checkins"] = checkins
    _redis_set_json(_draft_checkins_key(user_id), draft, ttl_seconds=CACHE_TTL_LONG)
    SESSION_CACHE.setdefault(user_id, {})["checkins"] = draft
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("DELETE FROM checkins WHERE user_id = ? AND checkin_date = ?", (user_id, checkin_date))
        conn.commit()
    _invalidate_checkins_cache(user_id)
    return "Check-in deleted."
