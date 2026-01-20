#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sqlite3
import time
from pathlib import Path
from datetime import date, datetime, timedelta
from typing import List, Optional, Dict, Any, Annotated

try:
    import redis.asyncio as AsyncRedis
except ImportError:  # pragma: no cover - optional dependency for local dev
    AsyncRedis = None
try:
    from upstash_redis import Redis as UpstashRedis
except ImportError:  # pragma: no cover - optional dependency for local dev
    UpstashRedis = None
from typing_extensions import TypedDict
from langchain_openai import ChatOpenAI, OpenAIEmbeddings
from langchain_core.messages import HumanMessage, SystemMessage, BaseMessage, AIMessage, ToolMessage
from langchain_core.tools import tool
from langgraph.graph import StateGraph, START, END, add_messages
from langgraph.checkpoint.memory import MemorySaver
from dotenv import load_dotenv
from langgraph.prebuilt import ToolNode
from langgraph.prebuilt import tools_condition
from langchain_tavily import TavilySearch
from langchain_community.document_loaders import PyPDFLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.vectorstores import FAISS

load_dotenv()

DB_PATH = "/Users/admin/Documents/AI-trainer-agent/data/ai_trainer.db"

sys_msg = SystemMessage(content="""You are an AI Trainer assistant.

Assume user context and active plan are preloaded into memory and provided in a
context message. Only call tools if the user explicitly asks to see the current
plan summary or to generate a new plan.

Use any provided reference excerpts to ground exercise guidance and safety.

Policy (nutrition + training constraints):
- Gain: target +0.1–0.25% bodyweight/week (beginner/high body fat: 0–0.25%); if user asks to bulk fast, cap at 0.5%/week and warn about fat gain.
- Gain calories: estimate TDEE, then +150 to +300 kcal/day (default +200). Never > +500 unless user explicitly requests.
- Maintain calories: TDEE ± 100 (leaner but maintain only with explicit intent: −150 to −250).
- Protein: gain 1.6–2.2 g/kg (default 1.8), maintain 1.4–2.0 g/kg (default 1.6); never <1.2 g/kg; never >2.4 g/kg without warning.
- Fat: 0.6–1.0 g/kg (default 0.8) and ≥20% of calories unless medically directed.
- Carbs: fill remainder; round macros to nearest 5g; ensure macro calories within ±50 of total.
- Gain/maintain: no auto calorie decrement. Adjust by ±100–150 based on 2–4 week trends.
- Training: gain 3–6 strength days/week (hypertrophy focus, 10–20 hard sets/muscle, reps 6–12, accessories 12–20, RPE 6–9). Maintain: 2–4 strength days + 2–4 cardio sessions + mobility 2–3x/week, moderate volume.

If the user asks a nutrition or exercise question that requires external info,
call the tool `search_web` with a concise search query.

If the user asks to calculate a plan for weight loss or a workout schedule,
call the tool `generate_plan` using user_id=1 and their requested timeframe
(clamp to 14–60 days). If the requested timeframe is not feasible given a
specific target loss/gain, use the next best fit and explain the adjustment.
If they specify a weight loss amount, pass target_loss_lbs.
If they ask to gain muscle or stay fit, pass goal_override="gain" or "maintain".
If the user wants to log a workout session, call `log_workout_session` and include
the exercises list with name, sets, reps, weight, and RPE for strength work, and
duration_min for cardio.
If the user asks to show their logged workouts, call `get_workout_sessions`.
If the user asks to remove an exercise from a logged workout, call `remove_workout_exercise`
with the exercise name and date (default to today if not provided).
If the user asks to remove cardio entries, pass exercise_name="all cardio".
If the user asks to remove a workout log (not just an exercise), call `delete_workout_from_draft`.
If the user wants to log a meal, call `log_meal` with a list of items and the time consumed.
If the user asks to show meal logs, call `get_meal_logs`.
If the user asks to delete all meal logs, call `delete_all_meal_logs`.
If the user asks for today's date, call `get_current_date`.

If the user says they are taking days off, ask only if missing: how many days and which dates. Then call `shift_active_plan_end_date`.
If the user says the workouts are too intense or they dislike exercises, ask:
- Do you prefer machines, dumbbells, barbells, bodyweight, or bands?
- Any exercises you hate or any injuries?
- If cardio swap is needed: walking, cycling, rowing, or elliptical?
Then call `replace_active_plan_workouts`.
If the user asks what their weight should be this week, call `get_weight_checkpoint_for_current_week` (use cached checkpoints only).
If the user asks how to do an exercise, provide 4–6 form cues, 2 common mistakes, 1 regression, 1 progression, and a YouTube link (call `search_web` with a YouTube query like "{exercise} proper form tutorial Jeff Nippard").

Small changes should use patch, not full regeneration. For pause days or workout swaps, return a plan_patch JSON:
{"end_date_shift_days": N, "overrides":[{date, override_type, workout_json, calorie_target|calorie_delta}], "notes": "..."}.
The assistant must never claim a data change unless a mutation tool has succeeded.
If no draft state exists, the assistant must ask to load or confirm an editable session.
""")


class AgentState(TypedDict):
    messages: Annotated[List[BaseMessage], add_messages]
    approve_plan: Optional[bool]
    context: Optional[Dict[str, Any]]
    active_plan: Optional[Dict[str, Any]]
    proposed_plan: Optional[Dict[str, Any]]

def _redis_client() -> Optional[Any]:
    tcp_url = os.getenv("REDIS_URL")
    if tcp_url and AsyncRedis is not None:
        return AsyncRedis.from_url(tcp_url, decode_responses=True)
    if UpstashRedis is None:
        return None
    url = os.getenv("UPSTASH_REDIS_REST_URL")
    token = os.getenv("UPSTASH_REDIS_REST_TOKEN")
    if not url or not token:
        return None
    return UpstashRedis(url=url, token=token)


def _run_async(coro):
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        return asyncio.run(coro)
    return loop.run_until_complete(coro)


def _redis_get_json(key: str) -> Optional[Any]:
    if not REDIS:
        return None
    if AsyncRedis and isinstance(REDIS, AsyncRedis.Redis):
        raw = _run_async(REDIS.get(key))
    else:
        raw = REDIS.get(key)
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def _redis_set_json(key: str, value: Any, ttl_seconds: int) -> None:
    if not REDIS:
        return
    payload = json.dumps(value)
    if AsyncRedis and isinstance(REDIS, AsyncRedis.Redis):
        _run_async(REDIS.setex(key, ttl_seconds, payload))
    else:
        REDIS.setex(key, ttl_seconds, payload)


def _redis_delete(key: str) -> None:
    if not REDIS:
        return
    if AsyncRedis and isinstance(REDIS, AsyncRedis.Redis):
        _run_async(REDIS.delete(key))
    else:
        REDIS.delete(key)


def _draft_plan_key(user_id: int) -> str:
    return f"draft:{user_id}:plan"


def _draft_plan_patches_key(user_id: int) -> str:
    return f"draft:{user_id}:plan:patches"


def _draft_workout_sessions_key(user_id: int) -> str:
    return f"draft:{user_id}:workout_sessions"


def _draft_workout_sessions_ops_key(user_id: int) -> str:
    return f"draft:{user_id}:workout_sessions:ops"


def _draft_meal_logs_key(user_id: int) -> str:
    return f"draft:{user_id}:meal_logs"


REDIS = _redis_client()
SESSION_CACHE: Dict[int, Dict[str, Any]] = {}
RAG_QUERY_CACHE: Dict[str, Dict[str, Any]] = {}

RAG_SOURCES_DIR = Path("/Users/admin/Documents/AI-trainer-agent/sources")
RAG_INDEX = None
RAG_READY = False


def _build_rag_index():
    global RAG_INDEX, RAG_READY
    if RAG_READY:
        return
    RAG_READY = True
    index_path = Path("/Users/admin/Documents/AI-trainer-agent/data/faiss_index")
    if not index_path.exists():
        return
    try:
        embeddings = OpenAIEmbeddings()
        RAG_INDEX = FAISS.load_local(str(index_path), embeddings, allow_dangerous_deserialization=True)
    except Exception:
        RAG_INDEX = None


def _retrieve_rag_context(query: str, k: int = 3) -> str:
    if not query:
        return ""
    if not RAG_INDEX:
        return ""
    cache_key = f"default:{hash(query)}"
    cached = RAG_QUERY_CACHE.get(cache_key)
    now = time.time()
    if cached and now - cached["ts"] < 10 * 60:
        return cached["value"]
    results = RAG_INDEX.similarity_search_with_score(query, k=k)
    if not results:
        return ""
    lines = []
    for doc, score in results:
        source = doc.metadata.get("source", "unknown")
        page = doc.metadata.get("page")
        page_note = f" p.{page + 1}" if isinstance(page, int) else ""
        content = doc.page_content.strip().replace("\n", " ")
        if content:
            lines.append(f"({Path(source).name}{page_note}) {content[:200]}")
    value = "\n".join(lines)[:800]
    RAG_QUERY_CACHE[cache_key] = {"ts": now, "value": value}
    return value


def _should_apply_rag(message: str) -> bool:
    if not message:
        return False
    lower = message.lower()
    keywords = [
        "plan",
        "workout",
        "schedule",
        "routine",
        "days off",
        "shift",
        "too intense",
        "don't like",
        "dislike",
        "replace",
        "modify",
        "update plan",
        "adjust plan",
        "generate plan",
        "new plan",
    ]
    return any(keyword in lower for keyword in keywords)


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


def _render_plan_days(
    start_date: str,
    end_date: str,
    cycle_length: int,
    default_calories: int,
    default_macros: Dict[str, int],
    template_days: Dict[int, Dict[str, Any]],
    overrides: Dict[str, Dict[str, Any]],
) -> List[Dict[str, Any]]:
    start = datetime.strptime(start_date, "%Y-%m-%d").date()
    end = datetime.strptime(end_date, "%Y-%m-%d").date()
    total_days = (end - start).days + 1
    plan_days = []
    for offset in range(total_days):
        day_date = start + timedelta(days=offset)
        day_key = day_date.isoformat()
        day_index = offset % max(1, cycle_length)
        template = template_days.get(day_index, {})
        base_calories = default_calories + int(template.get("calorie_delta") or 0)
        workout_json = template.get("workout_json")
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
        plan_days.append(
            {
                "date": day_key,
                "workout_plan": _workout_label_from_json(workout_json),
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
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT id, name, birthdate, height_cm, weight_kg, gender FROM users WHERE id = ?",
            (user_id,),
        )
        user_row = cur.fetchone()
        cur.execute(
            "SELECT weekly_weight_change_kg, activity_level, goal_type, target_weight_kg FROM user_preferences WHERE user_id = ?",
            (user_id,),
        )
        pref_row = cur.fetchone()
    data = {"user": user_row, "preferences": pref_row}
    _redis_set_json(cache_key, data, ttl_seconds=6 * 60 * 60)
    return data


def _get_active_plan_bundle_data(user_id: int, allow_db_fallback: bool = True) -> Dict[str, Any]:
    cache_key = f"user:{user_id}:active_plan"
    cached = _redis_get_json(cache_key)
    if cached:
        return cached
    if not allow_db_fallback:
        return {"plan": None, "plan_days": []}
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, start_date, end_date, daily_calorie_target, protein_g, carbs_g, fat_g, status
            FROM plans
            WHERE user_id = ? AND status = 'active'
            ORDER BY start_date DESC
            LIMIT 1
            """,
            (user_id,),
        )
        plan_row = cur.fetchone()
        if not plan_row:
            return {"plan": None, "plan_days": []}
        plan_id = plan_row[0]
        cur.execute(
            """
            SELECT id, cycle_length_days, timezone, default_calories,
                   default_protein_g, default_carbs_g, default_fat_g
            FROM plan_templates
            WHERE plan_id = ?
            LIMIT 1
            """,
            (plan_id,),
        )
        template_row = cur.fetchone()
        if not template_row:
            return {"plan": plan_row, "plan_days": []}
        template_id = template_row[0]
        cycle_length = template_row[1]
        default_calories = template_row[3]
        default_macros = {
            "protein_g": template_row[4],
            "carbs_g": template_row[5],
            "fat_g": template_row[6],
        }
        cur.execute(
            """
            SELECT day_index, workout_json, calorie_delta
            FROM plan_template_days
            WHERE template_id = ?
            ORDER BY day_index
            """,
            (template_id,),
        )
        template_days = {row[0]: {"workout_json": row[1], "calorie_delta": row[2]} for row in cur.fetchall()}
        cur.execute(
            """
            SELECT date, override_type, workout_json, calorie_target, calorie_delta
            FROM plan_overrides
            WHERE plan_id = ? AND date BETWEEN ? AND ?
            ORDER BY date
            """,
            (plan_id, plan_row[1], plan_row[2]),
        )
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
            start_date=plan_row[1],
            end_date=plan_row[2],
            cycle_length=cycle_length,
            default_calories=default_calories,
            default_macros=default_macros,
            template_days=template_days,
            overrides=overrides,
        )
        cur.execute(
            """
            SELECT checkpoint_week, expected_weight_kg, min_weight_kg, max_weight_kg
            FROM plan_checkpoints
            WHERE plan_id = ?
            ORDER BY checkpoint_week
            """,
            (plan_id,),
        )
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
            "id": plan_row[0],
            "start_date": plan_row[1],
            "end_date": plan_row[2],
            "daily_calorie_target": plan_row[3],
            "protein_g": plan_row[4],
            "carbs_g": plan_row[5],
            "fat_g": plan_row[6],
            "status": plan_row[7],
        },
        "plan_days": plan_days,
        "checkpoints": checkpoints,
    }
    _redis_set_json(cache_key, bundle, ttl_seconds=30 * 60)
    return bundle


def _load_active_plan_draft(user_id: int) -> Dict[str, Any]:
    draft_key = _draft_plan_key(user_id)
    cached = _redis_get_json(draft_key)
    if cached:
        return cached
    bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
    _redis_set_json(draft_key, bundle, ttl_seconds=6 * 60 * 60)
    if _redis_get_json(_draft_plan_patches_key(user_id)) is None:
        _redis_set_json(_draft_plan_patches_key(user_id), [], ttl_seconds=6 * 60 * 60)
    return bundle


def _append_plan_patch(user_id: int, patch: Dict[str, Any]) -> None:
    patches = _redis_get_json(_draft_plan_patches_key(user_id))
    if not isinstance(patches, list):
        patches = []
    patches.append(patch)
    _redis_set_json(_draft_plan_patches_key(user_id), patches, ttl_seconds=6 * 60 * 60)


def _append_workout_session_op(user_id: int, op: Dict[str, Any]) -> None:
    ops = _redis_get_json(_draft_workout_sessions_ops_key(user_id))
    if not isinstance(ops, list):
        ops = []
    ops.append(op)
    _redis_set_json(_draft_workout_sessions_ops_key(user_id), ops, ttl_seconds=6 * 60 * 60)


def _load_workout_sessions_draft(user_id: int) -> Dict[str, Any]:
    draft_key = _draft_workout_sessions_key(user_id)
    cached = _redis_get_json(draft_key)
    if cached:
        return cached
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, user_id, date, workout_type, duration_min, calories_burned, notes, completed, source
            FROM workout_sessions
            WHERE user_id = ?
            ORDER BY date DESC
            """,
            (user_id,),
        )
        sessions = [
            {
                "id": row[0],
                "user_id": row[1],
                "date": row[2],
                "workout_type": row[3],
                "duration_min": row[4],
                "calories_burned": row[5],
                "notes": row[6],
                "completed": row[7],
                "source": row[8],
            }
            for row in cur.fetchall()
        ]
    draft = {"sessions": sessions, "new_sessions": []}
    _redis_set_json(draft_key, draft, ttl_seconds=6 * 60 * 60)
    if _redis_get_json(_draft_workout_sessions_ops_key(user_id)) is None:
        _redis_set_json(_draft_workout_sessions_ops_key(user_id), [], ttl_seconds=6 * 60 * 60)
    return draft


def _sync_workout_sessions_to_db(user_id: int, sessions: List[Dict[str, Any]]) -> None:
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("DELETE FROM workout_sessions WHERE user_id = ?", (user_id,))
        for session in sessions:
            session_date = session.get("date")
            workout_type = session.get("workout_type") or "Workout"
            if not session_date:
                continue
            cur.execute(
                """
                INSERT INTO workout_sessions (
                    user_id, date, workout_type, duration_min, calories_burned, notes, completed, source
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_id,
                    session_date,
                    workout_type,
                    session.get("duration_min"),
                    session.get("calories_burned"),
                    session.get("notes"),
                    session.get("completed", 1),
                    session.get("source", "manual"),
                ),
            )
        conn.commit()


def _load_meal_logs_draft(user_id: int) -> Dict[str, Any]:
    draft_key = _draft_meal_logs_key(user_id)
    cached = _redis_get_json(draft_key)
    if cached:
        return cached
    with sqlite3.connect(DB_PATH) as conn:
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
    _redis_set_json(draft_key, draft, ttl_seconds=6 * 60 * 60)
    return draft


def _sync_meal_logs_to_db(user_id: int, meals: List[Dict[str, Any]]) -> None:
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("DELETE FROM meal_logs WHERE user_id = ?", (user_id,))
        for meal in meals:
            logged_at = meal.get("logged_at")
            description = meal.get("description")
            if not logged_at or not description:
                continue
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
    birthdate = user[2] if len(user) > 2 else None
    height_cm = user[3] if len(user) > 3 else None
    weight_kg = user[4] if len(user) > 4 else None
    gender = user[5] if len(user) > 5 else None
    goal_type = pref[2] if len(pref) > 2 else None
    activity_level = pref[1] if len(pref) > 1 else None
    age = _age_from_birthdate(birthdate) if birthdate else None

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


def _preload_session_cache(user_id: int) -> Dict[str, Any]:
    context = _load_user_context_data(user_id)
    active_plan = _load_active_plan_draft(user_id)
    workout_sessions = _load_workout_sessions_draft(user_id)
    meal_logs = _load_meal_logs_draft(user_id)
    SESSION_CACHE[user_id] = {
        "context": context,
        "active_plan": active_plan,
        "workout_sessions": workout_sessions,
        "meal_logs": meal_logs,
    }
    return {
        "context": context,
        "active_plan": active_plan,
        "workout_sessions": workout_sessions,
        "meal_logs": meal_logs,
    }


def _invalidate_active_plan_cache(user_id: int) -> None:
    _redis_delete(f"user:{user_id}:active_plan")
    _redis_delete(_draft_plan_key(user_id))
    _redis_delete(_draft_plan_patches_key(user_id))


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
    return (
        f"Plan {status}: {start_date} to {end_date}. "
        f"Calories {calories}, macros (g) P{protein}/C{carbs}/F{fat}. "

        f"Next 14 days:\n{workout_summary}"
    )


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

def _age_from_birthdate(birthdate: str) -> int:
    born = datetime.strptime(birthdate, "%Y-%m-%d").date()
    today = date.today()
    return today.year - born.year - ((today.month, today.day) < (born.month, born.day))


def _bmr_mifflin(weight_kg: float, height_cm: float, age: int, gender: str) -> float:
    base = 10 * weight_kg + 6.25 * height_cm - 5 * age
    if gender.lower().startswith("f"):
        return base - 161
    return base + 5


def _activity_multiplier(activity_level: str) -> float:
    levels = {
        "sedentary": 1.2,
        "light": 1.375,
        "moderate": 1.55,
        "active": 1.725,
        "very_active": 1.9,
    }
    return levels.get(activity_level, 1.4)

def _macro_split(calories: int) -> Dict[str, int]:
    protein_cals = int(calories * 0.3)
    carbs_cals = int(calories * 0.4)
    fat_cals = calories - protein_cals - carbs_cals
    return {
        "protein_g": protein_cals // 4,
        "carbs_g": carbs_cals // 4,
        "fat_g": fat_cals // 9,
    }


def _round_to_nearest_5(value: float) -> int:
    return int(5 * round(value / 5))


def _bmi(weight_kg: float, height_cm: float) -> float:
    height_m = height_cm / 100.0
    if height_m <= 0:
        return 0.0
    return weight_kg / (height_m ** 2)


def _calorie_minimum(goal_type: str, weight_kg: float) -> Optional[int]:
    if goal_type == "maintain":
        return 1500 if weight_kg < 60 else 1800
    return None


def _macro_targets(calories: int, weight_kg: float, goal_type: str) -> Dict[str, int]:
    if goal_type == "gain":
        protein_per_kg = 1.8
        protein_min = 1.6
        protein_max = 2.2
    elif goal_type == "maintain":
        protein_per_kg = 1.6
        protein_min = 1.4
        protein_max = 2.0
    else:
        protein_per_kg = 1.6
        protein_min = 1.4
        protein_max = 2.2

    protein_g = weight_kg * protein_per_kg
    protein_g = max(weight_kg * 1.2, protein_g)
    protein_g = min(weight_kg * 2.4, protein_g)
    protein_g = min(max(protein_g, weight_kg * protein_min), weight_kg * protein_max)

    fat_g = weight_kg * 0.8
    fat_g = min(max(fat_g, weight_kg * 0.6), weight_kg * 1.0)

    min_fat_for_20pct = (0.2 * calories) / 9.0
    fat_g = max(fat_g, min_fat_for_20pct)

    protein_cals = protein_g * 4
    fat_cals = fat_g * 9
    remaining = calories - (protein_cals + fat_cals)
    if remaining < 0:
        fat_g = max(weight_kg * 0.6, (0.2 * calories) / 9.0)
        fat_cals = fat_g * 9
        remaining = calories - (protein_cals + fat_cals)
        if remaining < 0:
            protein_g = max(weight_kg * 1.2, (calories - fat_cals) / 4)
            protein_cals = protein_g * 4
            remaining = calories - (protein_cals + fat_cals)

    carbs_g = max(0.0, remaining / 4)

    protein_g = _round_to_nearest_5(protein_g)
    fat_g = _round_to_nearest_5(fat_g)
    carbs_g = _round_to_nearest_5(carbs_g)

    total_cals = protein_g * 4 + carbs_g * 4 + fat_g * 9
    delta = calories - total_cals
    if abs(delta) > 50:
        carbs_adjust = _round_to_nearest_5(delta / 4)
        carbs_g = max(0, carbs_g + carbs_adjust)

    return {
        "protein_g": int(protein_g),
        "carbs_g": int(carbs_g),
        "fat_g": int(fat_g),
    }


def validate_macros(calories: int, protein_g: int, carbs_g: int, fat_g: int) -> bool:
    if min(protein_g, carbs_g, fat_g) < 0:
        return False
    total_cals = protein_g * 4 + carbs_g * 4 + fat_g * 9
    return abs(total_cals - calories) <= 50


def validate_protein(weight_kg: float, protein_g: int, goal_type: str) -> bool:
    per_kg = protein_g / max(weight_kg, 1)
    if per_kg < 1.2 or per_kg > 2.4:
        return False
    if goal_type == "gain":
        return 1.6 <= per_kg <= 2.2
    if goal_type == "maintain":
        return 1.4 <= per_kg <= 2.0
    return True


def validate_workout_volume(goal_type: str, sessions: int, sets_per_week: Optional[int] = None) -> bool:
    if goal_type == "gain":
        return 4 <= sessions <= 6
    if goal_type == "maintain":
        return 3 <= sessions <= 4
    return True


def _is_cardio_exercise(name: str) -> bool:
    lower = name.lower()
    keywords = [
        "run",
        "jog",
        "bike",
        "cycle",
        "rowing",
        "rower",
        "elliptical",
        "swim",
        "walk",
        "cardio",
        "hiit",
        "treadmill",
    ]
    return any(keyword in lower for keyword in keywords)


def _estimate_total_sets(workout_label: str) -> int:
    matches = re.findall(r"(\d+)\s*x", workout_label)
    if not matches:
        return 12
    return max(6, sum(int(m) for m in matches))


def _estimate_cardio_minutes(workout_label: str) -> int:
    range_match = re.search(r"(\d+)\s*[–-]\s*(\d+)\s*min", workout_label)
    if range_match:
        return int((int(range_match.group(1)) + int(range_match.group(2))) / 2)
    single_match = re.search(r"(\d+)\s*min", workout_label)
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
    return re.sub(r"(\d+)\s*x", _repl, label)


def _reduce_rpe_in_label(label: str) -> str:
    label = re.sub(r"RPE\s*7–8", "RPE6–7", label)
    label = re.sub(r"RPE\s*7-8", "RPE6-7", label)
    label = re.sub(r"RPE\s*7", "RPE6", label)
    return label


def _estimate_met_for_exercise(name: str) -> float:
    lower = name.lower()
    if any(k in lower for k in ["run", "jog", "treadmill"]):
        return 9.0
    if any(k in lower for k in ["bike", "cycle"]):
        return 7.0
    if "row" in lower:
        return 7.0
    if any(k in lower for k in ["elliptical", "swim"]):
        return 6.5
    if "walk" in lower:
        return 4.0
    if "hiit" in lower:
        return 10.0
    return 6.0


def _estimate_workout_calories(
    weight_kg: float,
    exercises: List[Dict[str, Any]],
    duration_min: int,
) -> int:
    if weight_kg <= 0:
        return 0
    if not exercises:
        met = 6.0
        return int((met * 3.5 * weight_kg / 200) * max(1, duration_min))
    total = 0.0
    fallback_per_ex = max(1, int(duration_min / max(1, len(exercises))))
    for exercise in exercises:
        if not isinstance(exercise, dict):
            continue
        name = str(exercise.get("name") or exercise.get("exercise") or "").strip()
        minutes = exercise.get("duration_min")
        if minutes is None:
            minutes = fallback_per_ex
        if _is_cardio_exercise(name):
            met = _estimate_met_for_exercise(name)
        else:
            met = 6.0
        total += (met * 3.5 * weight_kg / 200) * max(1, int(minutes))
    return int(total)


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
    lowered = value.lower()
    if "today" in lowered:
        value = value.replace("today", "").strip()
        lowered = value.lower()
    for fmt in ("%I %p", "%I:%M %p", "%H:%M"):
        try:
            parsed = datetime.strptime(value, fmt).time()
            return datetime.combine(now.date(), parsed).isoformat(timespec="seconds")
        except ValueError:
            continue
    return value


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
        match = re.match(r"([A-Za-z \-/]+)\s+(\d+x[^\@]+)(.*)", part)
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


def _repair_macros(calories: int, weight_kg: float, goal_type: str) -> Dict[str, int]:
    macros = _macro_targets(calories, weight_kg, goal_type)
    if not validate_macros(calories, macros["protein_g"], macros["carbs_g"], macros["fat_g"]):
        macros = _macro_targets(calories, weight_kg, goal_type)
    if not validate_protein(weight_kg, macros["protein_g"], goal_type):
        macros = _macro_targets(calories, weight_kg, goal_type)
    return macros


def _format_plan_text(plan_data: Dict[str, Any]) -> str:
    lines = [
        f"Plan length: {plan_data['days']} days",
        f"Daily calories (start): {plan_data['calorie_target']} ({plan_data.get('calorie_formula', 'formula unavailable')})",
        (
            "Macros (g): "
            f"P{plan_data['macros']['protein_g']} "
            f"C{plan_data['macros']['carbs_g']} "
            f"F{plan_data['macros']['fat_g']} "
            "(protein+carbs*4 + fat*9 ≈ calories)"
        ),
        f"Progression rule: {plan_data.get('progression_rule', 'double progression')}",
        f"Check-in rule: {plan_data.get('check_in_rule', 'Check-in every 2 weeks and adjust based on trend.')}",
        (
            "No auto calorie decrement for gain/maintain; adjust ±100–150 based on 2–3 week trends."
            if plan_data.get("decrement", 0) == 0
            else f"Adjust calories every 14 days by -{plan_data['decrement']} (if applicable)."
        ),
        "Workout schedule:",
    ]
    requested_days = plan_data.get("requested_days")
    if requested_days and requested_days != plan_data["days"]:
        lines.insert(
            1,
            f"Requested timeframe: {requested_days} days; adjusted to {plan_data['days']} days for a safer pace.",
        )
    if plan_data["checkpoints"]:
        first_checkpoint = plan_data["checkpoints"][0]
        lines.append(
            f"Current weight: {plan_data['current_weight_kg']:.1f} kg. "
            f"Expected by week {first_checkpoint['week']}: {first_checkpoint['expected_weight_kg']:.1f} kg "
            f"(range {first_checkpoint['min_weight_kg']:.1f}–{first_checkpoint['max_weight_kg']:.1f})."
        )
    for day in plan_data["plan_days"]:
        lines.append(f"{day['date']}: {day['workout']} | {day['calorie_target']} kcal")
    if plan_data["target_weight_kg"] is not None:
        lines.append(f"Target weight: {plan_data['target_weight_kg']:.1f} kg.")
    if plan_data["checkpoints"]:
        lines.append("Expected weight checkpoints (every 2 weeks):")
        for checkpoint in plan_data["checkpoints"]:
            lines.append(
                f"Week {checkpoint['week']}: {checkpoint['expected_weight_kg']:.1f} kg "
                f"(range {checkpoint['min_weight_kg']:.1f}–{checkpoint['max_weight_kg']:.1f})"
            )
    lines.append(
        "If you are unsure how to perform any exercise, ask and I can explain it and share a video."
    )
    return "\n".join(lines)

def calc_targets(
    user_row: tuple,
    pref_row: Optional[tuple],
    goal_override: Optional[str] = None,
) -> Dict[str, Any]:
    birthdate, height_cm, weight_kg, gender = user_row
    weekly_delta = pref_row[0] if pref_row else -0.5
    activity_level = pref_row[1] if pref_row else "moderate"
    goal_type = goal_override or (pref_row[2] if pref_row else "lose")

    age = _age_from_birthdate(birthdate)
    bmr = _bmr_mifflin(weight_kg, height_cm, age, gender)
    tdee = bmr * _activity_multiplier(activity_level)
    calorie_target = int(tdee)
    calorie_formula = f"TDEE {int(tdee)} kcal"

    if goal_type == "gain":
        is_underweight = _bmi(weight_kg, height_cm) < 18.5
        very_active = activity_level in {"active", "very_active"}
        surplus = 200
        if is_underweight or very_active:
            surplus = 350
        surplus = min(surplus, 500)
        calorie_target = int(tdee + surplus)
        calorie_formula = f"TDEE {int(tdee)} + surplus {surplus}"
    elif goal_type == "maintain":
        calorie_target = int(tdee)
        calorie_formula = f"TDEE {int(tdee)} (maintenance)"
    else:
        daily_delta = (weekly_delta * 7700) / 7.0
        calorie_target = int(max(1200, tdee + daily_delta))
        calorie_formula = f"TDEE {int(tdee)} + daily_delta {int(daily_delta)}"

    min_cals = _calorie_minimum(goal_type, weight_kg)
    if min_cals:
        calorie_target = max(calorie_target, min_cals)
    if goal_type == "gain":
        calorie_target = max(calorie_target, int(tdee))

    macros = _repair_macros(calorie_target, weight_kg, goal_type)

    step_goal = 10000 if goal_type == "lose" else 8000
    return {
        "goal_type": goal_type,
        "calorie_target": calorie_target,
        "macros": macros,
        "step_goal": step_goal,
        "tdee": int(tdee),
        "calorie_formula": calorie_formula,
    }


def compute_weight_checkpoints(
    user_row: tuple,
    pref_row: Optional[tuple],
    requested_days: int,
    target_weight_override: Optional[float],
    goal_override: Optional[str] = None,
    use_pref_target_weight: bool = True,
) -> Dict[str, Any]:
    weight_kg = user_row[2]
    goal_type = goal_override or (pref_row[2] if pref_row else "lose")
    target_weight = target_weight_override
    if use_pref_target_weight and target_weight is None:
        target_weight = pref_row[3] if pref_row else None
    if target_weight is None:
        if goal_type in {"gain", "maintain"}:
            planned_days = requested_days
            total_weeks = max(1, int((planned_days + 6) / 7))
            num_checkpoints = max(1, int((total_weeks + 1) / 2))
            rate_per_week = 0.002 if goal_type == "gain" else 0.0
            band = 0.01 * weight_kg
            checkpoints = []
            for i in range(1, num_checkpoints + 1):
                week = i * 2
                expected = weight_kg * (1 + rate_per_week * week)
                checkpoints.append(
                    {
                        "week": week,
                        "expected_weight_kg": expected,
                        "min_weight_kg": expected - band,
                        "max_weight_kg": expected + band,
                    }
                )
            return {"checkpoints": checkpoints, "recommended_weeks": None, "planned_days": planned_days}
        return {"checkpoints": [], "recommended_weeks": None, "planned_days": requested_days}

    delta = abs(weight_kg - target_weight)
    if delta == 0:
        return {"checkpoints": [], "recommended_weeks": None, "planned_days": requested_days}

    min_loss = 0.005 * weight_kg
    max_loss = 0.01 * weight_kg
    requested_weeks = max(1, int((requested_days + 6) / 7))
    req_loss = delta / requested_weeks

    if req_loss > max_loss:
        recommended_weeks = int((delta / max_loss) + 0.999)
    elif req_loss < min_loss:
        recommended_weeks = int((delta / min_loss) + 0.999)
    else:
        recommended_weeks = requested_weeks

    if requested_days >= 60 and recommended_weeks < 12:
        recommended_weeks = 12

    planned_days = max(requested_days, recommended_weeks * 7)
    k = int((recommended_weeks + 1) / 2 + 0.999)
    loss_per_2w = delta / k
    band = 0.01 * weight_kg
    checkpoints = []
    for i in range(1, k + 1):
        expected = weight_kg - (loss_per_2w * i) if goal_type == "lose" else weight_kg + (loss_per_2w * i)
        checkpoints.append(
            {
                "week": i * 2,
                "expected_weight_kg": expected,
                "min_weight_kg": expected - band,
                "max_weight_kg": expected + band,
            }
        )
    return {
        "checkpoints": checkpoints,
        "recommended_weeks": recommended_weeks,
        "planned_days": planned_days,
    }


def generate_workout_plan(
    goal: str,
    days_per_week: int = 5,
) -> List[str]:
    warmup = "Warm-up 5–10 min + ramp-up sets."
    progression = (
        "Progression: double progression (add reps to top of range, then add load)."
    )
    strength_template = (
        "Full Body Strength: Squat 3x6–10 @RPE7, Bench 3x6–10 @RPE7, "
        "Row 3x8–12 @RPE7, RDL 2x8–12 @RPE7, Plank 3x30–45s. "
    )
    cardio_zone2 = "Zone 2 Cardio: 25–40 min @RPE5."
    core = "Core: Dead bug 3x10/side, Pallof press 3x10/side."

    if goal == "gain":
        week_template = [
            f"Upper A: Bench 4x6–10 @RPE7–8, Row 4x6–10 @RPE7–8, "
            f"OHP 3x8–12 @RPE7, Pull-down 3x8–12 @RPE7. {warmup} {progression}",
            f"Lower A: Squat 4x6–10 @RPE7–8, RDL 3x8–12 @RPE7, "
            f"Lunge 3x10/side @RPE7, Calf raise 3x12–15 @RPE7. {warmup} {progression}",
            "Rest / Mobility 10 min.",
            f"Upper B: Incline bench 4x6–10 @RPE7–8, Row 4x6–10 @RPE7–8, "
            f"DB press 3x8–12 @RPE7, Curl 3x10–12 @RPE7. {warmup} {progression}",
            f"Lower B: Deadlift 3x5–8 @RPE7–8, Leg press 3x10–12 @RPE7, "
            f"Ham curl 3x10–12 @RPE7, Calf raise 3x12–15 @RPE7. {warmup} {progression}",
            "Rest / Mobility 10 min.",
            "Rest / Mobility 10 min.",
        ]
    elif goal == "maintain":
        week_template = [
            f"{strength_template} {warmup} {progression}",
            f"{cardio_zone2} Mobility 10 min.",
            f"{strength_template} {warmup} {progression}",
            f"{cardio_zone2} {core} Mobility 10 min.",
            "Rest / active recovery.",
            "Rest / active recovery.",
            "Rest / active recovery.",
        ]
    else:
        week_template = [
            f"{strength_template} {warmup} {progression}",
            f"{cardio_zone2} Mobility 10 min.",
            f"{strength_template} {warmup} {progression}",
            f"{cardio_zone2} {core} Mobility 10 min.",
            f"{strength_template} {warmup} {progression}",
            "Rest / active recovery.",
            "Rest / active recovery.",
        ]

    return week_template[:days_per_week] + week_template[days_per_week:]


def _build_plan_data(
    user_id: int,
    days: int,
    target_loss_lbs: Optional[float],
    goal_override: Optional[str] = None,
) -> Dict[str, Any]:
    requested_days = days
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT birthdate, height_cm, weight_kg, gender FROM users WHERE id = ?",
            (user_id,),
        )
        user_row = cur.fetchone()
        if not user_row:
            return {"error": "User not found."}
        cur.execute(
            "SELECT weekly_weight_change_kg, activity_level, goal_type, target_weight_kg FROM user_preferences WHERE user_id = ?",
            (user_id,),
        )
        pref_row = cur.fetchone()

    targets = calc_targets(user_row, pref_row, goal_override=goal_override)
    target_weight_override = None
    if target_loss_lbs:
        target_weight_override = user_row[2] - (target_loss_lbs * 0.453592)
    weight_info = compute_weight_checkpoints(
        user_row,
        pref_row,
        days,
        target_weight_override,
        goal_override=goal_override,
        use_pref_target_weight=target_loss_lbs is not None,
    )
    days = weight_info["planned_days"]
    if targets["goal_type"] == "gain":
        days_per_week = 5
    elif targets["goal_type"] == "maintain":
        days_per_week = 4
    else:
        days_per_week = 4
    if not validate_workout_volume(targets["goal_type"], days_per_week):
        days_per_week = 5 if targets["goal_type"] == "gain" else 4
    workout_cycle = generate_workout_plan(targets["goal_type"], days_per_week=days_per_week)

    start = date.today()
    plan_days = []
    decrement = 0
    if days > 14 and targets["goal_type"] == "lose":
        decrement = 300
    for i in range(days):
        day = start + timedelta(days=i)
        workout = workout_cycle[i % len(workout_cycle)]
        block_index = i // 14
        calorie_target = max(1200, targets["calorie_target"] - (block_index * decrement))
        plan_days.append(
            {
                "date": day.isoformat(),
                "workout": workout,
                "calorie_target": calorie_target,
            }
        )

    if targets["goal_type"] == "gain":
        check_in_rule = (
            "Check-in every 2 weeks: if gain <0.1%/week → +100–150 kcal; "
            "if gain >0.5%/week → −100–150 kcal; if strength up and weight flat, hold."
        )
    elif targets["goal_type"] == "maintain":
        check_in_rule = (
            "Check-in every 2–4 weeks: if weight drifts >1% → adjust ±100 kcal; "
            "if low energy, reduce volume 10–20% before calories."
        )
    else:
        check_in_rule = "Check-in every 2 weeks and adjust calories based on trend."

    plan_data = {
        "user_id": user_id,
        "current_weight_kg": user_row[2],
        "target_weight_kg": target_weight_override,
        "start_date": start.isoformat(),
        "end_date": (start + timedelta(days=days - 1)).isoformat(),
        "days": days,
        "requested_days": requested_days,
        "calorie_target": targets["calorie_target"],
        "macros": targets["macros"],
        "step_goal": targets["step_goal"],
        "decrement": decrement,
        "checkpoints": weight_info["checkpoints"],
        "recommended_weeks": weight_info["recommended_weeks"],
        "plan_days": plan_days,
        "tdee": targets.get("tdee"),
        "calorie_formula": targets.get("calorie_formula"),
        "progression_rule": "double progression",
        "check_in_rule": check_in_rule,
    }
    if not validate_macros(
        plan_data["calorie_target"],
        plan_data["macros"]["protein_g"],
        plan_data["macros"]["carbs_g"],
        plan_data["macros"]["fat_g"],
    ):
        plan_data["macros"] = _repair_macros(plan_data["calorie_target"], user_row[2], targets["goal_type"])
    if not validate_protein(user_row[2], plan_data["macros"]["protein_g"], targets["goal_type"]):
        plan_data["macros"] = _repair_macros(plan_data["calorie_target"], user_row[2], targets["goal_type"])
    return plan_data

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
    _redis_set_json(_draft_plan_key(user_id), cache_bundle, ttl_seconds=6 * 60 * 60)
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
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT p.id, p.end_date, p.start_date, pref.goal_type
            FROM plans p
            JOIN user_preferences pref ON pref.user_id = p.user_id
            WHERE p.user_id = ? AND p.status = 'active'
            ORDER BY p.start_date DESC
            LIMIT 1
            """,
            (user_id,),
        )
        row = cur.fetchone()
        if not row:
            return "No active plan found."
        plan_id, end_date, start_date, goal_type = row
        end = datetime.strptime(end_date, "%Y-%m-%d").date()
        new_end = (end + timedelta(days=days_off)).isoformat()

        dates = pause_dates or []
        if not dates:
            start = datetime.strptime(start_date, "%Y-%m-%d").date()
            dates = [(start + timedelta(days=i)).isoformat() for i in range(days_off)]

        if calorie_delta is None:
            calorie_delta = 100 if goal_type == "lose" else 0

        for day in dates:
            cur.execute("DELETE FROM plan_overrides WHERE plan_id = ? AND date = ?", (plan_id, day))
            cur.execute(
                """
                INSERT INTO plan_overrides (
                    plan_id, date, override_type, workout_json, calorie_target, calorie_delta, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    plan_id,
                    day,
                    "pause",
                    json.dumps({"label": "Rest day"}),
                    None,
                    calorie_delta,
                    datetime.now().isoformat(timespec="seconds"),
                ),
            )

        cur.execute("UPDATE plans SET end_date = ? WHERE id = ?", (new_end, plan_id))
        conn.commit()

    _invalidate_active_plan_cache(user_id)
    SESSION_CACHE[user_id] = {
        "context": SESSION_CACHE.get(user_id, {}).get("context"),
        "active_plan": _get_active_plan_bundle_data(user_id),
    }
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


@tool("replace_active_plan_workouts")
def replace_active_plan_workouts(
    user_id: int,
    preferred_exercises: Any,
    reduce_intensity: bool = False,
    cardio_preference: Optional[str] = None,
) -> str:
    """Replace active plan workouts using preferred exercises while matching volume."""
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
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id
            FROM plans
            WHERE user_id = ? AND status = 'active'
            ORDER BY start_date DESC
            LIMIT 1
            """,
            (user_id,),
        )
        row = cur.fetchone()
        if not row:
            return "No active plan found."
        plan_id = row[0]

        for day in plan_days:
            if day["date"] < today or day["date"] > end_date:
                continue
            before_label = day["workout_plan"]
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
            cur.execute("DELETE FROM plan_overrides WHERE plan_id = ? AND date = ?", (plan_id, override["date"]))
            cur.execute(
                """
                INSERT INTO plan_overrides (
                    plan_id, date, override_type, workout_json, calorie_target, calorie_delta, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    plan_id,
                    override["date"],
                    override["override_type"],
                    override["workout_json"],
                    None,
                    None,
                    datetime.now().isoformat(timespec="seconds"),
                ),
            )
        conn.commit()

    _invalidate_active_plan_cache(user_id)
    SESSION_CACHE[user_id] = {
        "context": SESSION_CACHE.get(user_id, {}).get("context"),
        "active_plan": _get_active_plan_bundle_data(user_id),
    }
    payload = {
        "plan_patch": {
            "end_date_shift_days": 0,
            "overrides": overrides,
            "notes": "Matched movement pattern and kept weekly volume similar.",
        },
        "changes": affected,
    }
    return json.dumps(payload)


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


@tool("log_meal")
def log_meal(
    user_id: int,
    items: Optional[List[str]] = None,
    consumed_at: Optional[str] = None,
    total_calories: Optional[int] = None,
    notes: Optional[str] = None,
) -> str:
    """Log a meal entry into the cache and database."""
    if not items:
        return "What items were included in the meal?"
    meal_items = [item.strip() for item in items if str(item).strip()]
    if not meal_items:
        return "What items were included in the meal?"
    if total_calories is None:
        total_calories = _estimate_meal_calories(meal_items)
    logged_at = _normalize_meal_time(consumed_at)
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
        "protein_g": 0,
        "carbs_g": 0,
        "fat_g": 0,
        "confidence": 0.5,
        "confirmed": 1,
    }
    draft.setdefault("meals", []).insert(0, new_entry)
    _redis_set_json(_draft_meal_logs_key(user_id), draft, ttl_seconds=6 * 60 * 60)
    SESSION_CACHE.setdefault(user_id, {})["meal_logs"] = draft
    _sync_meal_logs_to_db(user_id, draft.get("meals", []))
    return "Meal logged."


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


@tool("get_current_date")
def get_current_date() -> str:
    """Return today's date in ISO format."""
    return date.today().isoformat()


@tool("delete_all_meal_logs")
def delete_all_meal_logs(user_id: int) -> str:
    """Delete all meal logs for the user from cache and database."""
    draft = {"meals": []}
    _redis_set_json(_draft_meal_logs_key(user_id), draft, ttl_seconds=6 * 60 * 60)
    SESSION_CACHE.setdefault(user_id, {})["meal_logs"] = draft
    _sync_meal_logs_to_db(user_id, [])
    return "All meal logs deleted."


@tool("log_workout_session")
def log_workout_session(
    user_id: int,
    date: Optional[str] = None,
    workout_type: Optional[str] = None,
    duration_min: Optional[int] = None,
    calories_burned: Optional[int] = None,
    notes: Optional[str] = None,
    completed: bool = True,
    exercises: Optional[List[Dict[str, Any]]] = None,
) -> str:
    """Log a workout session (with detailed exercises) into the draft."""
    session_date = date or datetime.now().date().isoformat()
    draft = _load_workout_sessions_draft(user_id)
    exercise_list = exercises or []
    if not exercise_list and workout_type and _is_cardio_exercise(workout_type):
        exercise_list = [{"name": workout_type, "duration_min": duration_min}]
    missing = []
    normalized = []
    for index, exercise in enumerate(exercise_list, start=1):
        if not isinstance(exercise, dict):
            missing.append(f"exercise #{index} name")
            continue
        name = exercise.get("name") or exercise.get("exercise")
        if not name:
            missing.append(f"exercise #{index} name")
            continue
        name = str(name).strip()
        normalized.append({**exercise, "name": name})
        if _is_cardio_exercise(name):
            if exercise.get("duration_min") is None:
                missing.append(f"{name} duration (minutes)")
        else:
            if exercise.get("sets") is None:
                missing.append(f"{name} sets")
            if exercise.get("reps") is None:
                missing.append(f"{name} reps")
            if exercise.get("rpe") is None and exercise.get("RPE") is None:
                missing.append(f"{name} RPE")
            if (
                exercise.get("weight") is None
                and exercise.get("weight_kg") is None
                and exercise.get("weight_lbs") is None
            ):
                missing.append(f"{name} weight")
    if missing:
        missing_list = ", ".join(missing)
        return f"I can log that. Please provide: {missing_list}."
    exercise_list = normalized
    if not workout_type:
        if exercise_list:
            names = [str(ex.get("name") or "").strip() for ex in exercise_list if ex.get("name")]
            workout_type = ", ".join(names[:3]) or "Workout"
        else:
            workout_type = "Workout"
    if duration_min is None:
        durations = [
            int(ex.get("duration_min"))
            for ex in exercise_list
            if ex.get("duration_min") is not None
        ]
        duration_min = max(1, sum(durations)) if durations else 30
    if calories_burned is None:
        context = _load_user_context_data(user_id)
        user = context.get("user") if isinstance(context, dict) else None
        weight_kg = user[4] if user and len(user) > 4 else 0
        calories_burned = _estimate_workout_calories(weight_kg, exercise_list, duration_min)
    detail_payload = {"exercises": exercise_list}
    if notes:
        detail_payload["notes"] = notes
    existing = None
    for entry in draft.get("sessions", []):
        if entry.get("date") == session_date:
            existing = entry
            break
    if existing:
        existing_details = None
        raw_notes = existing.get("notes")
        if isinstance(raw_notes, str):
            try:
                existing_details = json.loads(raw_notes)
            except json.JSONDecodeError:
                existing_details = None
        existing_exercises = []
        if isinstance(existing_details, dict):
            existing_exercises = existing_details.get("exercises", []) or []
        merged_exercises = existing_exercises + exercise_list
        if not merged_exercises and workout_type and _is_cardio_exercise(workout_type):
            merged_exercises = [{"name": workout_type, "duration_min": duration_min}]
        merged_payload = {"exercises": merged_exercises}
        if notes:
            merged_payload["notes"] = notes
        merged_duration = existing.get("duration_min") or 0
        if duration_min:
            merged_duration = max(merged_duration, duration_min)
        context = _load_user_context_data(user_id)
        user = context.get("user") if isinstance(context, dict) else None
        weight_kg = user[4] if user and len(user) > 4 else 0
        merged_calories = _estimate_workout_calories(weight_kg, merged_exercises, merged_duration)
        existing["workout_type"] = existing.get("workout_type") or workout_type
        existing["duration_min"] = merged_duration
        existing["calories_burned"] = merged_calories
        existing["notes"] = json.dumps(merged_payload)
        _redis_set_json(_draft_workout_sessions_key(user_id), draft, ttl_seconds=6 * 60 * 60)
        SESSION_CACHE.setdefault(user_id, {})["workout_sessions"] = draft
        _append_workout_session_op(
            user_id,
            {
                "op": "update_workout",
                "date": session_date,
                "workout_type": workout_type,
                "timestamp": datetime.now().isoformat(timespec="seconds"),
            },
        )
        _sync_workout_sessions_to_db(user_id, draft.get("sessions", []))
        return "Workout session updated for this session."
    new_entry = {
        "id": None,
        "user_id": user_id,
        "date": session_date,
        "workout_type": workout_type,
        "duration_min": duration_min,
        "calories_burned": calories_burned,
        "notes": json.dumps(detail_payload),
        "completed": 1 if completed else 0,
        "source": "manual",
    }
    draft.setdefault("new_sessions", []).append(new_entry)
    draft.setdefault("sessions", []).insert(0, new_entry)
    _redis_set_json(_draft_workout_sessions_key(user_id), draft, ttl_seconds=6 * 60 * 60)
    SESSION_CACHE.setdefault(user_id, {})["workout_sessions"] = draft
    _append_workout_session_op(
        user_id,
        {
            "op": "add_workout",
            "date": session_date,
            "workout_type": workout_type,
            "timestamp": datetime.now().isoformat(timespec="seconds"),
        },
    )
    _sync_workout_sessions_to_db(user_id, draft.get("sessions", []))
    return "Workout session logged for this session."


@tool("remove_workout_exercise")
def remove_workout_exercise(
    user_id: int,
    date: Optional[str] = None,
    exercise_name: Optional[str] = None,
) -> str:
    """Remove a specific exercise from a workout session by date."""
    session_date = date or datetime.now().date().isoformat()
    if not exercise_name:
        return "Which exercise should I remove?"
    draft = _load_workout_sessions_draft(user_id)
    target = exercise_name.strip().lower()
    remove_all_cardio = target in {
        "cardio",
        "all cardio",
        "all cardio entries",
        "cardio entries",
        "both",
        "remove both",
    }
    updated = False

    def _update_entry(entry: Dict[str, Any]) -> bool:
        raw_notes = entry.get("notes")
        details = None
        if isinstance(raw_notes, str):
            try:
                details = json.loads(raw_notes)
            except json.JSONDecodeError:
                details = None
        if not isinstance(details, dict):
            if remove_all_cardio and _is_cardio_exercise(entry.get("workout_type") or ""):
                entry["notes"] = json.dumps({"exercises": []})
                entry["duration_min"] = 0
                entry["calories_burned"] = 0
                return True
            return False
        exercises = details.get("exercises", [])
        if not isinstance(exercises, list):
            return False
        kept = []
        for ex in exercises:
            if not isinstance(ex, dict):
                kept.append(ex)
                continue
            name = str(ex.get("name") or ex.get("exercise") or "").strip().lower()
            if remove_all_cardio:
                if _is_cardio_exercise(name):
                    continue
            else:
                if name == target:
                    continue
            kept.append(ex)
        if len(kept) == len(exercises):
            return False
        details["exercises"] = kept
        entry["notes"] = json.dumps(details)
        minutes = 0
        if kept:
            for ex in kept:
                if isinstance(ex, dict) and ex.get("duration_min") is not None:
                    minutes += int(ex.get("duration_min") or 0)
        if minutes:
            entry["duration_min"] = minutes
        context = _load_user_context_data(user_id)
        user = context.get("user") if isinstance(context, dict) else None
        weight_kg = user[4] if user and len(user) > 4 else 0
        entry["calories_burned"] = _estimate_workout_calories(weight_kg, kept, entry.get("duration_min") or 0)
        return True

    updated_sessions = []
    for entry in draft.get("sessions", []):
        if entry.get("date") == session_date:
            if remove_all_cardio and _is_cardio_exercise(entry.get("workout_type") or ""):
                raw_notes = entry.get("notes")
                details = None
                if isinstance(raw_notes, str):
                    try:
                        details = json.loads(raw_notes)
                    except json.JSONDecodeError:
                        details = None
                exercises = details.get("exercises", []) if isinstance(details, dict) else []
                if not exercises:
                    updated = True
                    continue
            if _update_entry(entry):
                updated = True
        updated_sessions.append(entry)
    draft["sessions"] = updated_sessions
    if updated:
        for entry in draft.get("new_sessions", []):
            if entry.get("date") == session_date:
                _update_entry(entry)
                break
        _redis_set_json(_draft_workout_sessions_key(user_id), draft, ttl_seconds=6 * 60 * 60)
        SESSION_CACHE.setdefault(user_id, {})["workout_sessions"] = draft
        label = "all cardio entries" if remove_all_cardio else exercise_name
        _append_workout_session_op(
            user_id,
            {
                "op": "remove_exercise",
                "date": session_date,
                "exercise_name": label,
                "timestamp": datetime.now().isoformat(timespec="seconds"),
            },
        )
        _sync_workout_sessions_to_db(user_id, draft.get("sessions", []))
        return f"Removed {label} from {session_date}."
    return "No matching exercise found for that date."


@tool("delete_workout_from_draft")
def delete_workout_from_draft(
    user_id: int,
    date: str,
    workout_type: str,
) -> str:
    """Remove workout entries from the Redis draft."""
    if not date or not workout_type:
        return "Please provide the date and workout type to remove."
    draft = _load_workout_sessions_draft(user_id)
    target = workout_type.strip().lower()
    remove_all_cardio = target in {"cardio", "all cardio", "all cardio entries", "cardio entries"}
    sessions = draft.get("sessions", [])
    updated = False
    kept_sessions = []

    for session in sessions:
        if session.get("date") != date:
            kept_sessions.append(session)
            continue
        workout_label = (session.get("workout_type") or "").strip().lower()
        raw_notes = session.get("notes")
        details = None
        if isinstance(raw_notes, str):
            try:
                details = json.loads(raw_notes)
            except json.JSONDecodeError:
                details = None
        exercises = details.get("exercises", []) if isinstance(details, dict) else []
        if remove_all_cardio:
            if _is_cardio_exercise(workout_label):
                updated = True
                continue
            if exercises:
                kept = [ex for ex in exercises if not _is_cardio_exercise(str(ex.get("name") or "").lower())]
                if len(kept) != len(exercises):
                    details["exercises"] = kept
                    session["notes"] = json.dumps(details)
                    updated = True
            kept_sessions.append(session)
            continue
        if workout_label == target:
            updated = True
            continue
        kept_sessions.append(session)

    if not updated:
        return "No matching workout entries found for that date."
    draft["sessions"] = kept_sessions
    _redis_set_json(_draft_workout_sessions_key(user_id), draft, ttl_seconds=6 * 60 * 60)
    SESSION_CACHE.setdefault(user_id, {})["workout_sessions"] = draft
    _append_workout_session_op(
        user_id,
        {
            "op": "delete_workout",
            "date": date,
            "workout_type": workout_type,
            "timestamp": datetime.now().isoformat(timespec="seconds"),
        },
    )
    _sync_workout_sessions_to_db(user_id, draft.get("sessions", []))
    return f"Removed {workout_type} on {date}."


@tool("get_workout_sessions")
def get_workout_sessions(user_id: int) -> str:
    """Return logged workout sessions from the draft cache."""
    draft = SESSION_CACHE.get(user_id, {}).get("workout_sessions") or _redis_get_json(
        _draft_workout_sessions_key(user_id)
    )
    if draft is None:
        return "No cached workout logs found. Start a session to load them."
    sessions = draft.get("sessions", []) if isinstance(draft, dict) else []
    plan_bundle = SESSION_CACHE.get(user_id, {}).get("active_plan") or _load_active_plan_draft(user_id)
    plan = plan_bundle.get("plan") if isinstance(plan_bundle, dict) else None
    plan_start = plan.get("start_date") if isinstance(plan, dict) else None
    if not sessions:
        return "No workout sessions logged yet."
    lines = []
    for session in sessions:
        date_str = session.get("date") or "unknown date"
        if plan_start and date_str != "unknown date" and date_str < plan_start:
            continue
        workout_type = session.get("workout_type") or "Workout"
        lines.append(f"{date_str}: {workout_type}")
        details = None
        raw_notes = session.get("notes")
        if isinstance(raw_notes, str):
            try:
                details = json.loads(raw_notes)
            except json.JSONDecodeError:
                details = None
        exercises = details.get("exercises", []) if isinstance(details, dict) else []
        if exercises:
            for exercise in exercises:
                if not isinstance(exercise, dict):
                    continue
                name = exercise.get("name") or exercise.get("exercise") or "Exercise"
                name = str(name).strip() or "Exercise"
                if _is_cardio_exercise(name):
                    duration = exercise.get("duration_min") or session.get("duration_min")
                    duration_label = f"{duration} min" if duration is not None else "duration unknown"
                    lines.append(f"- {name}: {duration_label}")
                else:
                    sets = exercise.get("sets")
                    reps = exercise.get("reps")
                    rpe = exercise.get("rpe") or exercise.get("RPE")
                    weight = exercise.get("weight")
                    weight_kg = exercise.get("weight_kg")
                    weight_lbs = exercise.get("weight_lbs")
                    if weight is None:
                        if weight_kg is not None:
                            weight = f"{weight_kg} kg"
                        elif weight_lbs is not None:
                            weight = f"{weight_lbs} lb"
                    sets_label = sets if sets is not None else "N/A"
                    reps_label = reps if reps is not None else "N/A"
                    rpe_label = rpe if rpe is not None else "N/A"
                    weight_label = weight if weight is not None else "N/A"
                    lines.append(
                        f"- {name}: {sets_label}x{reps_label}, RPE {rpe_label}, weight {weight_label}"
                    )
        else:
            if _is_cardio_exercise(workout_type):
                duration = session.get("duration_min")
                duration_label = f"{duration} min" if duration is not None else "duration unknown"
                lines.append(f"- {workout_type}: {duration_label}")
            else:
                lines.append("- Exercise details not recorded.")
    return "\n".join(lines) if lines else "No workout sessions logged yet for the active plan."

def assistant(state: AgentState):
    context = state.get("context")
    active_plan = state.get("active_plan")
    session = SESSION_CACHE.get(1, {})
    if session.get("context"):
        context = session["context"]
    if session.get("active_plan"):
        active_plan = session["active_plan"]
    if session.get("workout_sessions"):
        state["workout_sessions"] = session["workout_sessions"]
    if context is None or active_plan is None:
        preload = _preload_session_cache(1)
        context = preload["context"]
        active_plan = preload["active_plan"]
    if 1 not in SESSION_CACHE:
        SESSION_CACHE[1] = {}
    if "workout_sessions" not in SESSION_CACHE[1]:
        SESSION_CACHE[1]["workout_sessions"] = _load_workout_sessions_draft(1)
    SESSION_CACHE[1]["context"] = context
    SESSION_CACHE[1]["active_plan"] = active_plan
    last_user_message = ""
    for message in reversed(state.get("messages", [])):
        if isinstance(message, HumanMessage):
            last_user_message = message.content
            break
    rag_context = _retrieve_rag_context(last_user_message) if _should_apply_rag(last_user_message) else ""
    context_msg = SystemMessage(
        content=(
            f"User context (compact): {_compact_context_summary(context, active_plan)}"
            + (f"\nReference excerpts (RAG):\n{rag_context}" if rag_context else "")
        )
    )
    return {
        "context": context,
        "active_plan": active_plan,
        "messages": [llm_with_tools.invoke([sys_msg, context_msg] + state["messages"])],
    }


tools = [
    get_current_plan_summary,
    search_web,
    generate_plan,
    shift_active_plan_end_date,
    replace_active_plan_workouts,
    get_weight_checkpoint_for_current_week,
    log_meal,
    get_meal_logs,
    get_current_date,
    delete_all_meal_logs,
    log_workout_session,
    get_workout_sessions,
    remove_workout_exercise,
    delete_workout_from_draft,
]
llm = ChatOpenAI(model="gpt-4o", temperature=0)
llm_with_tools = llm.bind_tools(tools, parallel_tool_calls=False)

def _last_tool_name(state: AgentState) -> Optional[str]:
    messages = state.get("messages", [])
    if len(messages) < 2:
        return None
    if isinstance(messages[-1], ToolMessage) and isinstance(messages[-2], AIMessage):
        tool_calls = messages[-2].tool_calls or []
        if tool_calls:
            return tool_calls[0].get("name")
    return None


def route_after_tools(state: AgentState) -> str:
    if _last_tool_name(state) == "generate_plan":
        return "human_feedback"
    return "assistant"

# added because human_feedback can only pause before a node not in the middle. Added so we can ask for input.
def human_feedback(state: AgentState) -> Dict[str, Any]:
    return {}


def apply_plan(state: AgentState) -> AgentState:
    if not state.get("approve_plan"):
        return {"messages": [AIMessage(content="Plan not changed.")]}

    plan_data = state.get("proposed_plan")
    if not plan_data:
        return {"messages": [AIMessage(content="No plan data to apply.")]}
    user_id = plan_data.get("user_id", 1)

    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("UPDATE plans SET status = 'inactive' WHERE user_id = ?", (user_id,))
        cur.execute("SELECT timezone FROM user_preferences WHERE user_id = ?", (user_id,))
        pref_row = cur.fetchone()
        timezone = pref_row[0] if pref_row else None
        cur.execute(
            """
            INSERT INTO plans (
                user_id, start_date, end_date, daily_calorie_target,
                protein_g, carbs_g, fat_g, status, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                datetime.now().isoformat(timespec="seconds"),
            ),
        )
        plan_id = cur.lastrowid
        cycle_length = min(7, len(plan_data["plan_days"]))
        cur.execute(
            """
            INSERT INTO plan_templates (
                plan_id, cycle_length_days, timezone, default_calories,
                default_protein_g, default_carbs_g, default_fat_g, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                plan_id,
                cycle_length,
                timezone,
                plan_data["calorie_target"],
                plan_data["macros"]["protein_g"],
                plan_data["macros"]["carbs_g"],
                plan_data["macros"]["fat_g"],
                datetime.now().isoformat(timespec="seconds"),
            ),
        )
        template_id = cur.lastrowid
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
        for checkpoint in plan_data["checkpoints"]:
            cur.execute(
                """
                INSERT INTO plan_checkpoints (
                    plan_id, checkpoint_week, expected_weight_kg, min_weight_kg, max_weight_kg
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    plan_id,
                    checkpoint["week"],
                    checkpoint["expected_weight_kg"],
                    checkpoint["min_weight_kg"],
                    checkpoint["max_weight_kg"],
                ),
            )
        conn.commit()

    _invalidate_active_plan_cache(user_id)
    SESSION_CACHE[user_id] = {
        "context": SESSION_CACHE.get(user_id, {}).get("context"),
        "active_plan": _get_active_plan_bundle_data(user_id),
    }
    return {"messages": [AIMessage(content="Plan updated and saved.")]}


def _commit_session_drafts(user_id: int) -> None:
    plan_patches = _redis_get_json(_draft_plan_patches_key(user_id))
    workout_draft = _redis_get_json(_draft_workout_sessions_key(user_id))
    new_sessions = []
    if isinstance(workout_draft, dict):
        new_sessions = workout_draft.get("new_sessions", [])
        workout_sessions = workout_draft.get("sessions", [])
    else:
        workout_sessions = []

    has_plan_patches = isinstance(plan_patches, list) and plan_patches
    if not has_plan_patches and not workout_sessions and not new_sessions:
        return

    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        plan_id_current = None
        draft_bundle = _redis_get_json(_draft_plan_key(user_id)) or {}
        plan_in_draft = draft_bundle.get("plan") if isinstance(draft_bundle, dict) else None
        if isinstance(plan_in_draft, dict):
            plan_id_current = plan_in_draft.get("id")

        for patch in plan_patches or []:
            patch_type = patch.get("type")
            if patch_type == "replace_plan":
                plan_data = patch.get("plan_data")
                if not plan_data:
                    continue
                cur.execute("UPDATE plans SET status = 'inactive' WHERE user_id = ?", (user_id,))
                cur.execute("SELECT timezone FROM user_preferences WHERE user_id = ?", (user_id,))
                pref_row = cur.fetchone()
                timezone = pref_row[0] if pref_row else None
                cur.execute(
                    """
                    INSERT INTO plans (
                        user_id, start_date, end_date, daily_calorie_target,
                        protein_g, carbs_g, fat_g, status, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                        datetime.now().isoformat(timespec="seconds"),
                    ),
                )
                plan_id_current = cur.lastrowid
                cycle_length = min(7, len(plan_data["plan_days"]))
                cur.execute(
                    """
                    INSERT INTO plan_templates (
                        plan_id, cycle_length_days, timezone, default_calories,
                        default_protein_g, default_carbs_g, default_fat_g, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        plan_id_current,
                        cycle_length,
                        timezone,
                        plan_data["calorie_target"],
                        plan_data["macros"]["protein_g"],
                        plan_data["macros"]["carbs_g"],
                        plan_data["macros"]["fat_g"],
                        datetime.now().isoformat(timespec="seconds"),
                    ),
                )
                template_id = cur.lastrowid
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
                for checkpoint in plan_data["checkpoints"]:
                    cur.execute(
                        """
                        INSERT INTO plan_checkpoints (
                            plan_id, checkpoint_week, expected_weight_kg, min_weight_kg, max_weight_kg
                        ) VALUES (?, ?, ?, ?, ?)
                        """,
                        (
                            plan_id_current,
                            checkpoint["week"],
                            checkpoint["expected_weight_kg"],
                            checkpoint["min_weight_kg"],
                            checkpoint["max_weight_kg"],
                        ),
                    )
            elif patch_type == "shift_end_date":
                target_plan_id = patch.get("plan_id") or plan_id_current
                if not target_plan_id:
                    continue
                new_end_date = patch.get("new_end_date")
                if new_end_date:
                    cur.execute("UPDATE plans SET end_date = ? WHERE id = ?", (new_end_date, target_plan_id))
                for day in patch.get("pause_dates", []):
                    cur.execute("DELETE FROM plan_overrides WHERE plan_id = ? AND date = ?", (target_plan_id, day))
                    cur.execute(
                        """
                        INSERT INTO plan_overrides (
                            plan_id, date, override_type, workout_json, calorie_target, calorie_delta, created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            target_plan_id,
                            day,
                            "pause",
                            json.dumps({"label": "Rest day"}),
                            None,
                            patch.get("calorie_delta"),
                            datetime.now().isoformat(timespec="seconds"),
                        ),
                    )
            elif patch_type == "replace_workouts":
                target_plan_id = patch.get("plan_id") or plan_id_current
                if not target_plan_id:
                    continue
                for override in patch.get("overrides", []):
                    cur.execute("DELETE FROM plan_overrides WHERE plan_id = ? AND date = ?", (target_plan_id, override["date"]))
                    cur.execute(
                        """
                        INSERT INTO plan_overrides (
                            plan_id, date, override_type, workout_json, calorie_target, calorie_delta, created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            target_plan_id,
                            override["date"],
                            override["override_type"],
                            override["workout_json"],
                            None,
                            None,
                            datetime.now().isoformat(timespec="seconds"),
                        ),
                    )

        if workout_sessions:
            cur.execute("DELETE FROM workout_sessions WHERE user_id = ?", (user_id,))
            for entry in workout_sessions:
                cur.execute(
                    """
                    INSERT INTO workout_sessions (
                        user_id, date, workout_type, duration_min, calories_burned, notes, completed, source
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        entry.get("user_id") or user_id,
                        entry.get("date"),
                        entry.get("workout_type"),
                        entry.get("duration_min"),
                        entry.get("calories_burned"),
                        entry.get("notes"),
                        entry.get("completed", 1),
                        entry.get("source", "manual"),
                    ),
                )
        conn.commit()

    _invalidate_active_plan_cache(user_id)
    _redis_delete(_draft_workout_sessions_key(user_id))
    _redis_delete(_draft_workout_sessions_ops_key(user_id))


def build_graph() -> StateGraph:
    builder = StateGraph(AgentState)
   
    builder.add_node("assistant", assistant)
    builder.add_node("tools", ToolNode(tools))
    builder.add_node("human_feedback", human_feedback)
    builder.add_node("apply_plan", apply_plan)

    
    builder.add_edge(START, "assistant")
    builder.add_conditional_edges(
        "assistant",
        # If the latest message (result) from assistant is a tool call -> tools_condition routes to tools
        # If the latest message (result) from assistant is a not a tool call -> tools_condition routes to assistant
        tools_condition,
    )
    builder.add_conditional_edges("tools", route_after_tools, ["assistant", "human_feedback"])
    builder.add_edge("human_feedback", "apply_plan")
    builder.add_edge("apply_plan", "assistant")
    memory = MemorySaver()
    return builder.compile(checkpointer=memory, interrupt_before=["human_feedback"])


def run_cli() -> None:
    graph = build_graph()
    print("Basic AI Trainer agent. Type 'exit' to quit.\n")

    config = {"configurable": {"thread_id": "cli"}}
    preload = _preload_session_cache(1)
    _build_rag_index()

    while True:
        user_input = input("You: ").strip()
        if user_input.lower() in {"exit", "quit"}:
            break
    
        state = graph.invoke(
            {
                "messages": [HumanMessage(content=user_input)],
                "context": preload.get("context"),
                "active_plan": preload.get("active_plan"),
            },
            config,
        )
        graph_state = graph.get_state(config)
        if graph_state.next and "human_feedback" in graph_state.next:
            plan_text = None
            proposed_plan = None
            for message in reversed(state["messages"]):
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
            if plan_text:
                print("\nAssistant (proposed plan):", plan_text, "\n")
            approval = input("Do you like this plan more than your current one? (yes/no): ").strip().lower()
            approve_plan = approval.startswith("y")
            graph.update_state(
                config,
                {"approve_plan": approve_plan, "proposed_plan": proposed_plan},
                as_node="human_feedback",
            )
            state = graph.invoke(None, config)
        print("\nAssistant:", state["messages"][-1].content, "\n")
    _commit_session_drafts(1)


def main() -> None:
    
    parser = argparse.ArgumentParser(description="Run the basic AI Trainer agent.")
    _ = parser.parse_args()
    run_cli()


if __name__ == "__main__":
    main()