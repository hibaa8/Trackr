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
call the tool `generate_plan` using user_id=1 and days between 14 and 60.
If they specify a weight loss amount, pass target_loss_lbs.
If they ask to gain muscle or stay fit, pass goal_override="gain" or "maintain".

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


def _redis_get_json(key: str) -> Optional[Dict[str, Any]]:
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


def _redis_set_json(key: str, value: Dict[str, Any], ttl_seconds: int) -> None:
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
    active_plan = _get_active_plan_bundle_data(user_id)
    SESSION_CACHE[user_id] = {"context": context, "active_plan": active_plan}
    return {"context": context, "active_plan": active_plan}


def _invalidate_active_plan_cache(user_id: int) -> None:
    _redis_delete(f"user:{user_id}:active_plan")


@tool("get_current_plan_summary")
def get_current_plan_summary(user_id: int) -> str:
    """Return a basic plan summary for the given user_id."""
    bundle = SESSION_CACHE.get(user_id, {}).get("active_plan") or _redis_get_json(f"user:{user_id}:active_plan") or {}
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
    keywords = ["run", "jog", "bike", "cycle", "row", "elliptical", "swim", "walk", "cardio", "hiit"]
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
) -> Dict[str, Any]:
    weight_kg = user_row[2]
    goal_type = goal_override or (pref_row[2] if pref_row else "lose")
    target_weight = target_weight_override or (pref_row[3] if pref_row else None)
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
    _redis_set_json(f"user:{user_id}:active_plan", cache_bundle, ttl_seconds=30 * 60)
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

    bundle = SESSION_CACHE.get(user_id, {}).get("active_plan") or _redis_get_json(f"user:{user_id}:active_plan") or {}
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

def assistant(state: AgentState):
    context = state.get("context")
    active_plan = state.get("active_plan")
    session = SESSION_CACHE.get(1, {})
    if session.get("context"):
        context = session["context"]
    if session.get("active_plan"):
        active_plan = session["active_plan"]
    if context is None or active_plan is None:
        preload = _preload_session_cache(1)
        context = preload["context"]
        active_plan = preload["active_plan"]
    SESSION_CACHE[1] = {"context": context, "active_plan": active_plan}
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


def main() -> None:
    
    parser = argparse.ArgumentParser(description="Run the basic AI Trainer agent.")
    _ = parser.parse_args()
    run_cli()


if __name__ == "__main__":
    main()