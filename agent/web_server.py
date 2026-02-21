from __future__ import annotations

import argparse
import base64
import json
import os
import uuid
import threading
import time
from datetime import datetime, timedelta
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional
import re
import smtplib
import ssl
from email.message import EmailMessage
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen

from langchain_core.messages import HumanMessage, ToolMessage
from langchain_tavily import TavilySearch
import psycopg2
from dotenv import load_dotenv

from agent.config.constants import (
    CACHE_TTL_LONG,
    DEFAULT_USER_ID,
    _draft_checkins_key,
    _draft_meal_logs_key,
    _draft_workout_sessions_key,
)
from agent.db import queries
from agent.db.connection import get_db_conn
from agent.graph.graph import build_graph, _preload_session_cache
from agent.rag.rag import _build_rag_index
from agent.tools.plan_tools import (
    _estimate_cardio_minutes,
    _get_active_plan_bundle_data,
    _load_active_plan_draft,
    _set_active_plan_cache,
    compute_plan_status,
)
from agent.redis.cache import _redis_delete, _redis_get_json, _redis_set_json
from agent.state import SESSION_CACHE
from agent.plan.plan_generation import _build_plan_data
from agent.tools.activity_utils import _estimate_workout_calories, _is_cardio_exercise

BASE_DIR = Path(__file__).resolve().parents[1]
WEB_DIR = BASE_DIR / "web"
SUPABASE_BUCKET = "meal-photos"
ASSET_DIR = WEB_DIR / "assets"

_ROOT_ENV_PATH = BASE_DIR / ".env"
_ENV_PATH = Path(__file__).with_name(".env")
load_dotenv(dotenv_path=_ROOT_ENV_PATH)
load_dotenv(dotenv_path=_ENV_PATH)

from openai import OpenAI

class AgentService:
    def __init__(self) -> None:
        self.graph = build_graph()
        self.preload = _preload_session_cache(DEFAULT_USER_ID)
        _build_rag_index()
        self.openai = OpenAI()

    @staticmethod
    def _find_plan_payload(messages: list[Any]) -> tuple[str | None, Any | None]:
        plan_text = None
        plan_data = None
        for message in reversed(messages):
            if isinstance(message, ToolMessage):
                try:
                    payload = json.loads(message.content)
                except json.JSONDecodeError:
                    payload = None
                if isinstance(payload, dict):
                    plan_text = payload.get("plan_text") or payload.get("plan")
                    plan_data = payload.get("plan_data")
                if not plan_text:
                    plan_text = message.content
                break
        return plan_text, plan_data

    @staticmethod
    def _message_to_dict(message: Any) -> dict[str, Any]:
        msg_type = getattr(message, "type", None) or message.__class__.__name__
        payload = {
            "type": msg_type,
            "content": getattr(message, "content", None),
        }
        name = getattr(message, "name", None)
        if name:
            payload["name"] = name
        tool_call_id = getattr(message, "tool_call_id", None)
        if tool_call_id:
            payload["tool_call_id"] = tool_call_id
        return payload

    @staticmethod
    def _find_reply(messages: list[Any]) -> str | None:
        for message in reversed(messages):
            if not isinstance(message, ToolMessage):
                return getattr(message, "content", None)
        if messages:
            return getattr(messages[-1], "content", None)
        return None

    def invoke(
        self,
        message: str | None,
        thread_id: str,
        approve_plan: bool | None,
    ) -> dict[str, Any]:
        config = {"configurable": {"thread_id": thread_id}}
        if message:
            state = self.graph.invoke(
                {
                    "messages": [HumanMessage(content=message)],
                    "context": self.preload.get("context"),
                    "active_plan": self.preload.get("active_plan"),
                },
                config,
            )
        else:
            state = self.graph.invoke(None, config)

        graph_state = self.graph.get_state(config)
        needs_feedback = bool(graph_state.next and "human_feedback" in graph_state.next)
        plan_text, plan_data = (None, None)
        if needs_feedback:
            plan_text, plan_data = self._find_plan_payload(state["messages"])

        if approve_plan is not None and needs_feedback:
            self.graph.update_state(
                config,
                {"approve_plan": approve_plan, "proposed_plan": plan_data},
                as_node="human_feedback",
            )
            state = self.graph.invoke(None, config)
            graph_state = self.graph.get_state(config)
            needs_feedback = bool(graph_state.next and "human_feedback" in graph_state.next)
            if needs_feedback:
                plan_text, plan_data = self._find_plan_payload(state["messages"])
            else:
                plan_text, plan_data = (None, None)

        messages = state.get("messages", []) if isinstance(state, dict) else []
        response = {
            "thread_id": thread_id,
            "reply": self._find_reply(messages),
            "requires_approval": needs_feedback,
            "plan_text": plan_text,
            "plan_data": plan_data,
            "messages": [self._message_to_dict(msg) for msg in messages],
        }
        return response


def _read_json_body(handler: SimpleHTTPRequestHandler) -> dict[str, Any] | None:
    content_length = int(handler.headers.get("Content-Length", "0"))
    if content_length <= 0:
        return None
    body = handler.rfile.read(content_length)
    try:
        return json.loads(body.decode("utf-8"))
    except json.JSONDecodeError:
        return None


def _send_json(handler: SimpleHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    data = json.dumps(payload, indent=2).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.end_headers()
    handler.wfile.write(data)


def _parse_json(value: Optional[str]) -> Optional[dict[str, Any]]:
    if not value:
        return None
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def _require_user_id(handler: SimpleHTTPRequestHandler) -> int:
    return DEFAULT_USER_ID


def _supabase_headers() -> dict[str, str]:
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or ""
    return {"Authorization": f"Bearer {service_key}", "apikey": service_key}


def _supabase_url() -> Optional[str]:
    url = os.environ.get("SUPABASE_URL")
    return url.rstrip("/") if url else None


def _build_public_photo_url(path: str) -> Optional[str]:
    base = _supabase_url()
    if not base:
        return None
    return f"{base}/storage/v1/object/public/{path}"


def _sign_photo_url(path: str, expires_in: int = 3600) -> Optional[str]:
    base = _supabase_url()
    if not base:
        return None
    endpoint = f"{base}/storage/v1/object/sign/{path}"
    payload = json.dumps({"expiresIn": expires_in}).encode("utf-8")
    headers = {"Content-Type": "application/json", **_supabase_headers()}
    request = Request(endpoint, data=payload, headers=headers, method="POST")
    with urlopen(request, timeout=20) as response:
        data = json.loads(response.read().decode("utf-8"))
    signed = data.get("signedURL")
    if not signed:
        return None
    return f"{base}{signed}"


def _store_photo_in_supabase(image_bytes: bytes, content_type: str, filename: str) -> str:
    base = _supabase_url()
    if not base:
        raise RuntimeError("SUPABASE_URL not configured.")
    if not os.environ.get("SUPABASE_SERVICE_ROLE_KEY"):
        raise RuntimeError("SUPABASE_SERVICE_ROLE_KEY not configured.")
    path = f"{SUPABASE_BUCKET}/{filename}"
    endpoint = f"{base}/storage/v1/object/{path}"
    headers = {"Content-Type": content_type, "x-upsert": "true", **_supabase_headers()}
    request = Request(endpoint, data=image_bytes, headers=headers, method="POST")
    try:
        with urlopen(request, timeout=20) as response:
            if response.status >= 400:
                raise RuntimeError("Failed to upload image to storage.")
    except HTTPError as exc:
        body = exc.read().decode("utf-8") if exc.fp else ""
        hint = ""
        if exc.code == 404:
            hint = f" Ensure Supabase bucket '{SUPABASE_BUCKET}' exists."
        raise RuntimeError(
            f"Supabase upload failed (HTTP {exc.code}).{hint} {body}".strip()
        ) from exc
    return path


def _extension_from_mime(mime_type: str) -> str:
    if mime_type == "image/png":
        return "png"
    if mime_type == "image/webp":
        return "webp"
    if mime_type in {"image/heic", "image/heif"}:
        return "heic"
    return "jpg"


def _call_gemini_for_nutrition(image_b64: str, mime_type: str) -> dict[str, Any]:
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY not configured.")
    endpoint = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        "gemini-2.5-flash:generateContent?key="
        f"{api_key}"
    )
    system_prompt = (
        "You are a nutrition assistant. Analyze the food photo and return ONLY valid JSON "
        "with this schema: {\"description\": string, \"calories\": int, \"protein_g\": int, "
        "\"carbs_g\": int, \"fat_g\": int, \"confidence\": float}. "
        "Use integers for macro grams and calories. Confidence must be 0 to 1."
    )
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": system_prompt},
                    {"inlineData": {"mimeType": mime_type, "data": image_b64}},
                ],
            }
        ],
        "generationConfig": {"response_mime_type": "application/json"},
    }
    body = json.dumps(payload).encode("utf-8")
    request = Request(endpoint, data=body, headers={"Content-Type": "application/json"}, method="POST")
    with urlopen(request, timeout=30) as response:
        data = json.loads(response.read().decode("utf-8"))
    candidates = data.get("candidates", [])
    if not candidates:
        raise RuntimeError("Gemini returned no candidates.")
    content = candidates[0].get("content", {})
    parts = content.get("parts", [])
    text = "".join(part.get("text", "") for part in parts if isinstance(part, dict)).strip()
    try:
        result = json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, re.DOTALL)
        if not match:
            raise RuntimeError("Gemini returned invalid JSON.")
        try:
            result = json.loads(match.group(0))
        except json.JSONDecodeError as exc:
            snippet = text[:200].replace("\n", " ")
            raise RuntimeError(f"Gemini returned invalid JSON: {snippet}") from exc
    def _coerce_int(value: Any) -> int:
        try:
            return int(float(value))
        except (TypeError, ValueError):
            return 0

    def _coerce_float(value: Any) -> float:
        try:
            return float(value)
        except (TypeError, ValueError):
            return 0.0

    def _lookup(source: dict[str, Any], *keys: str) -> Any:
        for key in keys:
            if key in source:
                return source.get(key)
        return None

    def _pull_nested(source: dict[str, Any], *names: str) -> dict[str, Any]:
        for name in names:
            nested = source.get(name)
            if isinstance(nested, dict):
                return nested
        return {}

    nested = _pull_nested(result, "macros", "nutrition", "nutrients")
    normalized = {
        "description": _lookup(result, "description", "summary", "food", "meal") or "Meal",
        "calories": _coerce_int(_lookup(result, "calories", "kcal", "energy_kcal", "energy")),
        "protein_g": _coerce_int(
            _lookup(result, "protein_g", "protein", "proteins")
            or _lookup(nested, "protein_g", "protein", "proteins")
        ),
        "carbs_g": _coerce_int(
            _lookup(result, "carbs_g", "carbs", "carbohydrates")
            or _lookup(nested, "carbs_g", "carbs", "carbohydrates")
        ),
        "fat_g": _coerce_int(
            _lookup(result, "fat_g", "fat", "fats")
            or _lookup(nested, "fat_g", "fat", "fats")
        ),
        "confidence": _coerce_float(_lookup(result, "confidence", "score", "probability") or 0.6),
    }
    return normalized


def _get_or_create_user(email: str, name: str) -> tuple[int, bool]:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT id FROM users WHERE email = ?", (email,))
        row = cur.fetchone()
        if row:
            return int(row[0]), False
        cur.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM users")
        next_id = int(cur.fetchone()[0])
        now = datetime.now().isoformat(timespec="seconds")
        cur.execute(
            """
            INSERT INTO users (id, email, name, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (next_id, email, name or "New User", now),
        )
        cur.execute("SELECT id FROM user_preferences WHERE user_id = ?", (next_id,))
        pref_row = cur.fetchone()
        if not pref_row:
            cur.execute(
                """
                INSERT INTO user_preferences (
                    user_id, goal_type, target_weight_kg, weekly_weight_change_kg,
                    activity_level, dietary_preferences, workout_preferences, timezone, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    next_id,
                    "maintain",
                    None,
                    None,
                    "moderate",
                    None,
                    None,
                    "America/New_York",
                    now,
                ),
            )
        conn.commit()
        return next_id, True


def _update_onboarding_preferences(user_id: int, payload: dict[str, Any]) -> None:
    goal_type = payload.get("goal_type") or "maintain"
    target_weight_kg = payload.get("target_weight_kg")
    weekly_weight_change_kg = payload.get("weekly_weight_change_kg")
    activity_level = payload.get("activity_level") or "moderate"
    storyline = payload.get("storyline")
    trainer = payload.get("trainer")
    full_name = payload.get("full_name")
    personality = payload.get("personality")
    voice = payload.get("voice")
    timeframe_weeks = payload.get("timeframe_weeks")
    current_weight_kg = payload.get("current_weight_kg")
    height_cm = payload.get("height_cm")
    age = payload.get("age")
    fitness_background = payload.get("fitness_background")
    onboarding_payload = {
        "trainer": trainer,
        "personality": personality,
        "voice": voice,
        "storyline": storyline,
        "timeframe_weeks": timeframe_weeks,
        "fitness_background": fitness_background,
        "age": age,
    }
    with get_db_conn() as conn:
        cur = conn.cursor()
        if current_weight_kg is not None or height_cm is not None or age is not None or trainer or full_name:
            fields = []
            values: list[Any] = []
            if current_weight_kg is not None:
                fields.append("weight_kg = ?")
                values.append(current_weight_kg)
            if height_cm is not None:
                fields.append("height_cm = ?")
                values.append(height_cm)
            if age is not None:
                fields.append("age_years = ?")
                values.append(age)
            if trainer:
                fields.append("agent_id = ?")
                values.append(trainer)
            if full_name:
                fields.append("name = ?")
                values.append(full_name)
            values.append(user_id)
            cur.execute(
                f"UPDATE users SET {', '.join(fields)} WHERE id = ?",
                tuple(values),
            )
        if current_weight_kg is not None:
            today = datetime.now().date().isoformat()
            cur.execute(
                """
                SELECT 1 FROM checkins WHERE user_id = ? AND checkin_date = ?
                """,
                (user_id, today),
            )
            if not cur.fetchone():
                cur.execute(
                    """
                    INSERT INTO checkins (user_id, checkin_date, weight_kg, mood, notes)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (user_id, today, current_weight_kg, "onboarding", "Initial check-in"),
                )
        # User preferences mapping intentionally omitted for now.
        conn.commit()


def _list_workout_sessions(user_id: int) -> list[dict[str, Any]]:
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
        details = _parse_json(notes) if isinstance(notes, str) else None
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
    if sessions:
        return sessions
    cached = _redis_get_json(_draft_workout_sessions_key(user_id))
    if isinstance(cached, dict) and cached.get("sessions"):
        cached_sessions = []
        for session in cached.get("sessions", []):
            raw_notes = session.get("notes")
            details = _parse_json(raw_notes) if isinstance(raw_notes, str) else None
            cached_sessions.append(
                {
                    "id": session.get("id"),
                    "date": session.get("date"),
                    "workout_type": session.get("workout_type"),
                    "duration_min": session.get("duration_min"),
                    "calories_burned": session.get("calories_burned"),
                    "completed": bool(session.get("completed", 1)),
                    "source": session.get("source"),
                    "details": details,
                }
            )
        return cached_sessions
    return sessions


def _list_meal_logs(user_id: int) -> list[dict[str, Any]]:
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
        path = row[2]
        photo_url = _build_public_photo_url(path) if path else None
        meals.append(
            {
                "id": row[0],
                "logged_at": row[1],
                "photo_path": path,
                "photo_url": photo_url,
                "description": row[3],
                "calories": row[4],
                "protein_g": row[5],
                "carbs_g": row[6],
                "fat_g": row[7],
                "confidence": row[8],
                "confirmed": bool(row[9]),
            }
        )
    if meals:
        return meals
    cached = _redis_get_json(_draft_meal_logs_key(user_id))
    if isinstance(cached, dict) and cached.get("meals"):
        cached_meals = []
        for meal in cached.get("meals", []):
            cached_meals.append(
                {
                    "id": meal.get("id"),
                    "logged_at": meal.get("logged_at"),
                    "photo_path": meal.get("photo_path"),
                    "photo_url": meal.get("photo_url"),
                    "description": meal.get("description"),
                    "calories": meal.get("calories"),
                    "protein_g": meal.get("protein_g"),
                    "carbs_g": meal.get("carbs_g"),
                    "fat_g": meal.get("fat_g"),
                    "confidence": meal.get("confidence"),
                    "confirmed": bool(meal.get("confirmed", 1)),
                }
            )
        return cached_meals
    return meals


def _list_checkins(user_id: int) -> list[dict[str, Any]]:
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


def _list_health_activity(user_id: int) -> list[dict[str, Any]]:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT date, steps, calories_burned, workouts_summary, source
            FROM health_activity
            WHERE user_id = ?
            ORDER BY date DESC
            """,
            (user_id,),
        )
        rows = cur.fetchall()
    return [
        {
            "date": row[0],
            "steps": row[1],
            "calories_burned": row[2],
            "workouts_summary": row[3],
            "source": row[4],
        }
        for row in rows
    ]


def _load_user_profile(user_id: int) -> dict[str, Any]:
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(queries.SELECT_USER_PROFILE, (user_id,))
        user_row = cur.fetchone()
        cur.execute(queries.SELECT_USER_PREFS, (user_id,))
        pref_row = cur.fetchone()
    user = None
    if user_row:
        user = {
            "id": user_row[0],
            "name": user_row[1],
            "birthdate": user_row[2],
            "height_cm": user_row[3],
            "weight_kg": user_row[4],
            "gender": user_row[5],
            "age_years": user_row[6],
            "agent_id": user_row[7],
        }
    prefs = None
    if pref_row:
        prefs = {
            "weekly_weight_change_kg": pref_row[0],
            "activity_level": pref_row[1],
            "goal_type": pref_row[2],
            "target_weight_kg": pref_row[3],
            "dietary_preferences": pref_row[4],
            "workout_preferences": pref_row[5],
            "timezone": pref_row[6],
            "created_at": pref_row[7],
        }
    return {"user": user, "preferences": prefs}


def _smtp_settings() -> dict[str, Any]:
    host = os.environ.get("SMTP_HOST")
    port = int(os.environ.get("SMTP_PORT", "587"))
    user = os.environ.get("SMTP_USER")
    password = os.environ.get("SMTP_PASSWORD")
    sender = os.environ.get("SMTP_FROM") or user
    return {"host": host, "port": port, "user": user, "password": password, "sender": sender}


def _build_ics_event(title: str, start_at: datetime, end_at: datetime, uid: str) -> str:
    dt_start = start_at.strftime("%Y%m%dT%H%M%S")
    dt_end = end_at.strftime("%Y%m%dT%H%M%S")
    dt_stamp = datetime.now().strftime("%Y%m%dT%H%M%S")
    return "\r\n".join(
        [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Vaylo Fitness//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:REQUEST",
            "BEGIN:VEVENT",
            f"UID:{uid}",
            f"DTSTAMP:{dt_stamp}",
            f"DTSTART:{dt_start}",
            f"DTEND:{dt_end}",
            f"SUMMARY:{title}",
            "DESCRIPTION:Vaylo Fitness reminder",
            "END:VEVENT",
            "END:VCALENDAR",
            "",
        ]
    )


def _send_email(to_email: str, subject: str, body: str, ics_event: Optional[str] = None) -> None:
    settings = _smtp_settings()
    if not settings["host"] or not settings["sender"]:
        raise RuntimeError("SMTP settings not configured.")
    message = EmailMessage()
    message["From"] = settings["sender"]
    message["To"] = to_email
    message["Subject"] = subject
    message.set_content(body)
    if ics_event:
        message.add_attachment(
            ics_event.encode("utf-8"),
            maintype="text",
            subtype="calendar",
            filename="vaylo-reminder.ics",
            params={"method": "REQUEST"},
        )
    context = ssl.create_default_context()
    with smtplib.SMTP(settings["host"], settings["port"], timeout=10) as server:
        server.starttls(context=context)
        if settings["user"] and settings["password"]:
            server.login(settings["user"], settings["password"])
        server.send_message(message)


def _next_scheduled_datetime(time_str: str) -> datetime:
    now = datetime.now()
    try:
        hour, minute = [int(part) for part in time_str.split(":", 1)]
    except ValueError as exc:
        raise ValueError("Time must be HH:MM.") from exc
    candidate = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if candidate <= now:
        candidate += timedelta(days=1)
    return candidate


def _run_reminder_worker(stop_event: threading.Event) -> None:
    while not stop_event.is_set():
        try:
            with get_db_conn() as conn:
                cur = conn.cursor()
                cur.execute(
                    """
                    SELECT id, user_id, reminder_type, scheduled_at
                    FROM reminders
                    WHERE status IN ('pending', 'active') AND channel = 'email' AND scheduled_at <= ?
                    ORDER BY scheduled_at ASC
                    LIMIT 10
                    """,
                    (datetime.now().isoformat(timespec="seconds"),),
                )
                rows = cur.fetchall()
                for reminder_id, user_id, reminder_type, scheduled_at in rows:
                    cur.execute("SELECT email FROM users WHERE id = ?", (user_id,))
                    row = cur.fetchone()
                    to_email = row[0] if row else None
                    if not to_email:
                        cur.execute(
                            "UPDATE reminders SET status = 'failed' WHERE id = ?",
                            (reminder_id,),
                        )
                        continue
                    subject = "Your Vaylo Fitness reminder"
                    body = f"Reminder: {reminder_type.replace('_', ' ').title()}."
                    start_at = datetime.fromisoformat(str(scheduled_at))
                    end_at = start_at + timedelta(minutes=30)
                    ics_event = _build_ics_event(
                        f"Vaylo Fitness: {reminder_type.replace('_', ' ').title()}",
                        start_at,
                        end_at,
                        f"{reminder_id}@vaylo",
                    )
                    _send_email(to_email, subject, body, ics_event=ics_event)
                    next_time = _next_scheduled_datetime(
                        datetime.fromisoformat(str(scheduled_at)).strftime("%H:%M")
                    )
                    cur.execute(
                        """
                        UPDATE reminders
                        SET status = 'active', scheduled_at = ?
                        WHERE id = ?
                        """,
                        (next_time.isoformat(timespec="seconds"), reminder_id),
                    )
                conn.commit()
        except Exception:
            pass
        stop_event.wait(30)


def _activate_plan_from_data(user_id: int, plan_data: dict[str, Any]) -> dict[str, Any]:
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
        "plan_days": plan_data["plan_days"],
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
    return cache_bundle


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
    if "error" in plan_data:
        return None
    return _activate_plan_from_data(user_id, plan_data)


def _maybe_generate_plan_for_user(user_id: int) -> Optional[dict[str, Any]]:
    profile = _load_user_profile(user_id)
    prefs = profile.get("preferences") or {}
    if not prefs:
        return None
    goal_type = (prefs.get("goal_type") or "maintain").lower()
    weekly_change_kg = prefs.get("weekly_weight_change_kg")
    timeframe_weeks = None
    workout_prefs = prefs.get("workout_preferences")
    if isinstance(workout_prefs, str):
        try:
            workout_prefs = json.loads(workout_prefs)
        except json.JSONDecodeError:
            workout_prefs = None
    if isinstance(workout_prefs, dict):
        timeframe_weeks = workout_prefs.get("timeframe_weeks")
    return _generate_plan_for_user(user_id, goal_type, timeframe_weeks, weekly_change_kg)


def _get_latest_ai_suggestion(user_id: int) -> Optional[dict[str, Any]]:
    try:
        with get_db_conn() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT suggestion_type, rationale, suggestion_text, status, created_at
                FROM ai_suggestions
                WHERE user_id = ?
                ORDER BY created_at DESC
                LIMIT 1
                """,
                (user_id,),
            )
            row = cur.fetchone()
    except psycopg2.errors.UndefinedTable:
        return None
    if not row:
        return None
    return {
        "suggestion_type": row[0],
        "rationale": row[1],
        "suggestion_text": row[2],
        "status": row[3],
        "created_at": row[4],
    }


def _derive_suggestion_from_status(user_id: int) -> Optional[dict[str, Any]]:
    raw = compute_plan_status.func(user_id)
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return None
    status = payload.get("status")
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


def _search_gym_classes() -> list[dict[str, Any]]:
    if not os.environ.get("TAVILY_API_KEY"):
        return []
    query = "New York City gym classes schedule yoga HIIT strength"
    tavily = TavilySearch(max_results=5)
    data = tavily.invoke({"query": query})
    results = data.get("results", data)
    classes = []
    for doc in results:
        url = doc.get("url")
        title = doc.get("title") or doc.get("url") or "Gym class"
        snippet = doc.get("content") or ""
        if url:
            classes.append({"title": title, "url": url, "snippet": snippet})
    return classes


def _search_workout_videos() -> list[dict[str, Any]]:
    if not os.environ.get("TAVILY_API_KEY"):
        return []
    query = "best workout how-to videos squat deadlift bench press form tutorial"
    tavily = TavilySearch(max_results=6)
    data = tavily.invoke({"query": query})
    results = data.get("results", data)
    videos = []
    for doc in results:
        url = doc.get("url")
        if not url:
            continue
        title = doc.get("title") or "Workout tutorial"
        snippet = doc.get("content") or ""
        
        videos.append({"title": title, "url": url, "snippet": snippet})
    return videos


def _estimate_plan_burn(weight_kg: float | None, workout_label: str | None, rest_day: bool) -> int:
    if rest_day or not workout_label:
        return 0
    if "rest" in workout_label.lower():
        return 0
    minutes = 45
    if "cardio" in workout_label.lower() or _is_cardio_exercise(workout_label):
        minutes = _estimate_cardio_minutes(workout_label)
    return _estimate_workout_calories(weight_kg or 0, [], minutes)


def create_handler(agent_service: AgentService):
    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *args: Any, **kwargs: Any) -> None:
            super().__init__(*args, directory=str(WEB_DIR), **kwargs)

        def do_GET(self) -> None:
            parsed = urlparse(self.path)
            if parsed.path.startswith("/assets/"):
                asset_path = (ASSET_DIR / parsed.path.replace("/assets/", "")).resolve()
                if not str(asset_path).startswith(str(ASSET_DIR.resolve())) or not asset_path.exists():
                    self.send_error(404, "Not Found")
                    return
                mime = "application/octet-stream"
                if asset_path.suffix.lower() in {".png"}:
                    mime = "image/png"
                elif asset_path.suffix.lower() in {".jpg", ".jpeg"}:
                    mime = "image/jpeg"
                elif asset_path.suffix.lower() in {".webp"}:
                    mime = "image/webp"
                elif asset_path.suffix.lower() in {".gif"}:
                    mime = "image/gif"
                with open(asset_path, "rb") as handle:
                    data = handle.read()
                self.send_response(200)
                self.send_header("Content-Type", mime)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            if parsed.path == "/favicon.ico":
                self.send_response(204)
                self.end_headers()
                return
            if parsed.path == "/api/voice":
                query = parse_qs(parsed.query or "")
                text = (query.get("text") or [""])[0].strip()
                instructions = (query.get("instructions") or [""])[0].strip()
                voice = (query.get("voice") or ["alloy"])[0].strip()
                if not text:
                    self.send_error(400, "Missing text")
                    return
                try:
                    args: dict[str, Any] = {
                        "model": "gpt-4o-mini-tts",
                        "voice": voice,
                        "input": text,
                    }
                    if instructions:
                        args["instructions"] = instructions
                    response = agent_service.openai.audio.speech.create(**args)
                    data = response.content
                    mime = "audio/mpeg"
                except Exception as exc:
                    self.send_error(500, f"TTS failed: {exc}")
                    return
                self.send_response(200)
                self.send_header("Content-Type", mime)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            if parsed.path == "/api/profile":
                user_id = _require_user_id(self)
                _send_json(self, 200, _load_user_profile(user_id))
                return
            if parsed.path == "/api/health":
                try:
                    with get_db_conn() as conn:
                        cur = conn.cursor()
                        cur.execute("SELECT 1")
                        cur.fetchone()
                    _send_json(self, 200, {"ok": True, "db": "postgres"})
                except Exception as exc:
                    _send_json(self, 500, {"ok": False, "error": str(exc)})
                return
            if parsed.path == "/api/dashboard":
                user_id = _require_user_id(self)
                plan_bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
                if not plan_bundle.get("plan"):
                    generated = _maybe_generate_plan_for_user(user_id)
                    if generated:
                        plan_bundle = generated
                meals = _list_meal_logs(user_id)[:5]
                activity = _list_health_activity(user_id)[:7]
                profile = _load_user_profile(user_id)
                with get_db_conn() as conn:
                    cur = conn.cursor()
                    cur.execute(
                        "SELECT streak_type, current_count, best_count FROM streaks WHERE user_id = ?",
                        (user_id,),
                    )
                    streaks = [
                        {"type": row[0], "current": row[1], "best": row[2]}
                        for row in cur.fetchall()
                    ]
                    cur.execute("SELECT points FROM points WHERE user_id = ?", (user_id,))
                    points_total = sum(row[0] for row in cur.fetchall())
                response = {
                    "plan": plan_bundle.get("plan"),
                    "plan_days": plan_bundle.get("plan_days", [])[:7],
                    "meals": meals,
                    "activity": activity,
                    "streaks": streaks,
                    "points": points_total,
                    "preferences": profile.get("preferences"),
                }
                _send_json(self, 200, response)
                return
            if parsed.path == "/api/workouts":
                user_id = _require_user_id(self)
                _send_json(self, 200, {"sessions": _list_workout_sessions(user_id)})
                return
            if parsed.path == "/api/meal-logs":
                user_id = _require_user_id(self)
                _send_json(self, 200, {"meals": _list_meal_logs(user_id)})
                return
            if parsed.path == "/api/plan":
                user_id = _require_user_id(self)
                plan_bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
                profile = _load_user_profile(user_id)
                weight_kg = profile.get("user", {}).get("weight_kg") if profile else None
                plan_days = []
                for day in plan_bundle.get("plan_days", []):
                    workout_label = day.get("workout_plan") or day.get("workout")
                    rest_day = bool(day.get("rest_day"))
                    plan_days.append(
                        {
                            **day,
                            "calories_burned_est": _estimate_plan_burn(
                                weight_kg, workout_label, rest_day
                            ),
                        }
                    )
                _send_json(
                    self,
                    200,
                    {
                        "plan": plan_bundle.get("plan"),
                        "plan_days": plan_days,
                    },
                )
                return
            if parsed.path == "/api/progress":
                user_id = _require_user_id(self)
                checkins = _list_checkins(user_id)
                plan_bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
                checkpoints = plan_bundle.get("checkpoints", [])
                meals = _list_meal_logs(user_id)
                workouts = _list_workout_sessions(user_id)
                _send_json(
                    self,
                    200,
                    {
                        "checkins": checkins,
                        "checkpoints": checkpoints,
                        "plan": plan_bundle.get("plan"),
                        "meals": meals,
                        "workouts": workouts,
                    },
                )
                return
            if parsed.path == "/api/coach-suggestion":
                user_id = _require_user_id(self)
                suggestion = _get_latest_ai_suggestion(user_id) or _derive_suggestion_from_status(user_id)
                _send_json(self, 200, {"suggestion": suggestion})
                return
            if parsed.path == "/api/workout-videos":
                _send_json(self, 200, {"videos": _search_workout_videos()})
                return
            if parsed.path == "/api/gym-classes":
                _send_json(self, 200, {"classes": _search_gym_classes()})
                return
            if parsed.path == "/api/status-summary":
                user_id = _require_user_id(self)
                status_raw = compute_plan_status.func(user_id)
                try:
                    status = json.loads(status_raw)
                except json.JSONDecodeError:
                    status = {"explanation": "No status available."}
                preferences = _load_user_profile(user_id).get("preferences") or {}
                suggestions = []
                explanation = status.get("explanation") or "Keep logging to get tailored feedback."
                if status.get("status") == "behind":
                    suggestions.append("Log meals and workouts consistently for better guidance.")
                if preferences.get("workout_preferences") and "run" in str(preferences.get("workout_preferences")).lower():
                    suggestions.append("Check today's weather before your run.")
                if status.get("status") == "on_track":
                    suggestions.append("Maintain your current routine and recovery.")
                _send_json(
                    self,
                    200,
                    {
                        "status": status,
                        "suggestions": suggestions,
                    },
                )
                return
            if parsed.path == "/api/notifications":
                user_id = _require_user_id(self)
                with get_db_conn() as conn:
                    cur = conn.cursor()
                    cur.execute("SELECT email FROM users WHERE id = ?", (user_id,))
                    user_row = cur.fetchone()
                    cur.execute(
                        """
                        SELECT id, reminder_type, scheduled_at, status, channel
                        FROM reminders
                        WHERE user_id = ?
                        ORDER BY scheduled_at ASC
                        """,
                        (user_id,),
                    )
                    reminders = [
                        {
                            "id": row[0],
                            "type": row[1],
                            "scheduled_at": row[2],
                            "status": row[3],
                            "channel": row[4],
                        }
                        for row in cur.fetchall()
                    ]
                _send_json(
                    self,
                    200,
                    {"email": user_row[0] if user_row else None, "reminders": reminders},
                )
                return
            return super().do_GET()

        def do_POST(self) -> None:
            if self.path == "/api/chat":
                payload = _read_json_body(self)
                if payload is None:
                    _send_json(self, 400, {"error": "Invalid JSON payload."})
                    return

                message = payload.get("message")
                approve_plan = payload.get("approve_plan")
                thread_id = payload.get("thread_id") or "web"
                agent_id = payload.get("agent_id")

                if not message and approve_plan is None:
                    _send_json(self, 400, {"error": "Provide message or approve_plan."})
                    return

                if agent_id:
                    SESSION_CACHE.setdefault(DEFAULT_USER_ID, {})["agent_id"] = agent_id
                try:
                    response = agent_service.invoke(message, thread_id, approve_plan)
                except Exception as exc:  # pragma: no cover - surface runtime errors
                    _send_json(self, 500, {"error": str(exc)})
                    return

                _send_json(self, 200, response)
                return

            if self.path == "/api/meal-photo":
                user_id = _require_user_id(self)
                payload = _read_json_body(self)
                if payload is None:
                    _send_json(self, 400, {"error": "Invalid JSON payload."})
                    return
                if payload.get("image_url"):
                    _send_json(self, 400, {"error": "Use image_base64; image_url is not supported."})
                    return
                image_b64 = payload.get("image_base64")
                mime_type = payload.get("mime_type", "image/jpeg")
                if not image_b64:
                    _send_json(self, 400, {"error": "Missing image_base64."})
                    return
                if isinstance(image_b64, str) and image_b64.startswith("http"):
                    _send_json(self, 400, {"error": "Use image_base64; URLs are not supported."})
                    return
                if "," in image_b64:
                    image_b64 = image_b64.split(",", 1)[1]
                try:
                    image_bytes = base64.b64decode(image_b64)
                except ValueError:
                    _send_json(self, 400, {"error": "Invalid base64 image."})
                    return

                try:
                    analysis = _call_gemini_for_nutrition(image_b64, mime_type)
                except Exception as exc:  # pragma: no cover
                    _send_json(self, 500, {"error": f"Gemini analysis failed: {exc}"})
                    return

                try:
                    ext = _extension_from_mime(mime_type)
                    filename = f"{uuid.uuid4().hex}.{ext}"
                    path = _store_photo_in_supabase(image_bytes, mime_type, filename)
                    photo_url = _build_public_photo_url(path) or _sign_photo_url(path)
                except Exception as exc:  # pragma: no cover
                    _send_json(self, 500, {"error": f"Image upload failed: {exc}"})
                    return

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
                        _redis_set_json(
                            _draft_meal_logs_key(user_id), cached, ttl_seconds=CACHE_TTL_LONG
                        )
                        SESSION_CACHE.setdefault(user_id, {})["meal_logs"] = cached
                    _send_json(
                        self,
                        200,
                        {
                            "logged_at": logged_at,
                            "photo_path": path,
                            "photo_url": photo_url,
                            "analysis": analysis,
                        },
                    )
                except Exception as exc:  # pragma: no cover
                    _send_json(self, 500, {"error": f"Database insert failed: {exc}"})
                return

            if self.path == "/api/checkins":
                user_id = _require_user_id(self)
                payload = _read_json_body(self)
                if payload is None:
                    _send_json(self, 400, {"error": "Invalid JSON payload."})
                    return
                weight_kg = payload.get("weight_kg")
                reset = bool(payload.get("reset"))
                checkin_date = payload.get("date") or datetime.now().date().isoformat()
                try:
                    weight_kg = float(weight_kg)
                except (TypeError, ValueError):
                    _send_json(self, 400, {"error": "Weight must be a number."})
                    return
                if weight_kg <= 0:
                    _send_json(self, 400, {"error": "Weight must be greater than 0."})
                    return
                try:
                    parsed_date = datetime.fromisoformat(str(checkin_date)).date()
                except ValueError:
                    _send_json(self, 400, {"error": "Date must be YYYY-MM-DD."})
                    return
                today = datetime.now().date()
                if parsed_date > today:
                    if reset and parsed_date == (today + timedelta(days=1)):
                        parsed_date = today
                    else:
                        _send_json(self, 400, {"error": "Date cannot be in the future."})
                        return
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
                                _send_json(
                                    self,
                                    400,
                                    {
                                        "error": (
                                            "That change looks too sudden. "
                                            "Please talk to your AI trainer before logging this."
                                        )
                                    },
                                )
                                return
                    cur.execute(
                        """
                        SELECT 1 FROM checkins WHERE user_id = ? AND checkin_date = ?
                        """,
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
                _send_json(self, 200, {"ok": True})
                return

            if self.path == "/api/onboarding/complete":
                payload = _read_json_body(self)
                if payload is None:
                    _send_json(self, 400, {"error": "Invalid JSON payload."})
                    return
                payload_user_id = payload.get("user_id")
                user_id = payload_user_id if isinstance(payload_user_id, int) else _require_user_id(self)
                _update_onboarding_preferences(user_id, payload)
                _send_json(self, 200, {"ok": True})
                return

            if self.path == "/api/plan/generate":
                user_id = _require_user_id(self)
                payload = _read_json_body(self) or {}
                goal_type = payload.get("goal_type")
                timeframe_weeks = payload.get("timeframe_weeks")
                weekly_change_kg = payload.get("weekly_weight_change_kg")
                bundle = _generate_plan_for_user(user_id, goal_type, timeframe_weeks, weekly_change_kg)
                if not bundle:
                    _send_json(self, 400, {"error": "Unable to generate plan yet."})
                    return
                _send_json(self, 200, {"ok": True})
                return
            if self.path == "/api/notifications":
                user_id = _require_user_id(self)
                payload = _read_json_body(self)
                if payload is None:
                    _send_json(self, 400, {"error": "Invalid JSON payload."})
                    return
                email = payload.get("email")
                reminder_type = payload.get("reminder_type")
                reminder_time = payload.get("reminder_time")
                if not email:
                    _send_json(self, 400, {"error": "Email is required."})
                    return
                with get_db_conn() as conn:
                    cur = conn.cursor()
                    cur.execute("UPDATE users SET email = ? WHERE id = ?", (email, user_id))
                    if reminder_type and reminder_time:
                        scheduled_at = _next_scheduled_datetime(reminder_time)
                        cur.execute(
                            """
                            SELECT id FROM reminders
                            WHERE user_id = ? AND reminder_type = ? AND channel = 'email'
                            ORDER BY scheduled_at DESC
                            LIMIT 1
                            """,
                            (user_id, reminder_type),
                        )
                        row = cur.fetchone()
                        if row:
                            cur.execute(
                                """
                                UPDATE reminders
                                SET scheduled_at = ?, status = 'pending'
                                WHERE id = ?
                                """,
                                (scheduled_at.isoformat(timespec="seconds"), row[0]),
                            )
                        else:
                            cur.execute(
                                """
                                INSERT INTO reminders (
                                    user_id, reminder_type, scheduled_at, status, channel
                                ) VALUES (?, ?, ?, ?, ?)
                                """,
                                (
                                    user_id,
                                    reminder_type,
                                    scheduled_at.isoformat(timespec="seconds"),
                                    "pending",
                                    "email",
                                ),
                            )
                    conn.commit()
                _send_json(self, 200, {"ok": True})
                return
            if self.path == "/api/notifications/test":
                user_id = _require_user_id(self)
                payload = _read_json_body(self) or {}
                email = payload.get("email")
                reminder_type = payload.get("reminder_type") or "workout"
                reminder_time = payload.get("reminder_time") or "09:00"
                if not email:
                    _send_json(self, 400, {"error": "Email is required."})
                    return
                settings = _smtp_settings()
                if not settings.get("host") or not settings.get("sender"):
                    _send_json(self, 400, {"error": "SMTP settings not configured."})
                    return
                start_at = _next_scheduled_datetime(reminder_time)
                end_at = start_at + timedelta(minutes=30)
                ics_event = _build_ics_event(
                    f"Vaylo Fitness: {reminder_type.replace('_', ' ').title()}",
                    start_at,
                    end_at,
                    f"test-{user_id}@vaylo",
                )
                try:
                    _send_email(
                        email,
                        "Vaylo Fitness test reminder",
                        "This is a test reminder from Vaylo Fitness.",
                        ics_event=ics_event,
                    )
                except Exception as exc:
                    _send_json(self, 400, {"error": str(exc)})
                    return
                _send_json(self, 200, {"ok": True})
                return
            if self.path == "/api/notifications/send-existing":
                user_id = _require_user_id(self)
                settings = _smtp_settings()
                if not settings.get("host") or not settings.get("sender"):
                    _send_json(self, 400, {"error": "SMTP settings not configured."})
                    return
                with get_db_conn() as conn:
                    cur = conn.cursor()
                    cur.execute("SELECT email FROM users WHERE id = ?", (user_id,))
                    user_row = cur.fetchone()
                    to_email = user_row[0] if user_row else None
                    if not to_email:
                        _send_json(self, 400, {"error": "Email not set for user."})
                        return
                    cur.execute(
                        """
                        SELECT id, reminder_type, scheduled_at
                        FROM reminders
                        WHERE user_id = ? AND channel = 'email' AND status = 'pending'
                        ORDER BY scheduled_at ASC
                        """,
                        (user_id,),
                    )
                    rows = cur.fetchall()
                    for reminder_id, reminder_type, scheduled_at in rows:
                        start_at = datetime.fromisoformat(str(scheduled_at))
                        end_at = start_at + timedelta(minutes=30)
                        ics_event = _build_ics_event(
                            f"Vaylo Fitness: {reminder_type.replace('_', ' ').title()}",
                            start_at,
                            end_at,
                            f"{reminder_id}@vaylo",
                        )
                        _send_email(
                            to_email,
                            "Vaylo Fitness reminder",
                            f"Reminder: {reminder_type.replace('_', ' ').title()}.",
                            ics_event=ics_event,
                        )
                        cur.execute(
                            "UPDATE reminders SET status = 'active' WHERE id = ?",
                            (reminder_id,),
                        )
                    conn.commit()
                _send_json(self, 200, {"ok": True, "sent": len(rows)})
                return

            if self.path == "/api/recipes":
                payload = _read_json_body(self)
                if payload is None:
                    _send_json(self, 400, {"error": "Invalid JSON payload."})
                    return
                ingredients = payload.get("ingredients") or ""
                cuisine = payload.get("cuisine") or ""
                prep_time = payload.get("prep_time") or ""
                dietary = payload.get("dietary") or ""
                if not os.environ.get("TAVILY_API_KEY"):
                    _send_json(self, 200, {"recipes": [], "deals": []})
                    return
                recipe_query = f"{cuisine} {dietary} recipes with {ingredients} prep time {prep_time} minutes"
                tavily = TavilySearch(max_results=6)
                recipe_data = tavily.invoke({"query": recipe_query})
                recipe_results = recipe_data.get("results", recipe_data)
                recipes = []
                for doc in recipe_results:
                    if not doc.get("url"):
                        continue
                    recipes.append(
                        {
                            "title": doc.get("title") or "Recipe idea",
                            "url": doc.get("url"),
                            "meta": doc.get("content") or "",
                        }
                    )
                deals_query = "healthy food chain deals salad bowl discount"
                deals_data = tavily.invoke({"query": deals_query})
                deals_results = deals_data.get("results", deals_data)
                deals = []
                for doc in deals_results:
                    if not doc.get("url"):
                        continue
                    deals.append(
                        {
                            "title": doc.get("title") or "Healthy food deal",
                            "url": doc.get("url"),
                            "meta": doc.get("content") or "",
                        }
                    )
                _send_json(self, 200, {"recipes": recipes, "deals": deals})
                return

            self.send_error(404, "Not Found")

    return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the Vaylo Fitness web chat server.")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind.")
    parser.add_argument("--port", default=8000, type=int, help="Port to bind.")
    args = parser.parse_args()

    WEB_DIR.mkdir(exist_ok=True)
    agent_service = AgentService()
    handler = create_handler(agent_service)
    server = ThreadingHTTPServer((args.host, args.port), handler)
    stop_event = threading.Event()
    worker = threading.Thread(target=_run_reminder_worker, args=(stop_event,), daemon=True)
    worker.start()

    print(f"Serving Vaylo Fitness web UI at http://{args.host}:{args.port}")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    finally:
        stop_event.set()


if __name__ == "__main__":
    main()
