from __future__ import annotations

import json
import re
import sqlite3
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional

from langchain_core.tools import tool
from langchain_tavily import TavilySearch

from agent.config.constants import (
    CACHE_TTL_LONG,
    CACHE_TTL_PLAN,
    DB_PATH,
    _draft_plan_key,
    _draft_plan_patches_key,
)
from agent.db import queries
from agent.plan.plan_generation import (
    _age_from_birthdate,
    _build_plan_data,
    _format_plan_text,
    _macro_split,
)
from agent.redis.cache import _redis_delete, _redis_get_json, _redis_set_json
from agent.state import SESSION_CACHE


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
        cur.execute(queries.SELECT_USER_PROFILE, (user_id,))
        user_row = cur.fetchone()
        cur.execute(queries.SELECT_USER_PREFS, (user_id,))
        pref_row = cur.fetchone()
    data = {"user": user_row, "preferences": pref_row}
    _redis_set_json(cache_key, data, ttl_seconds=CACHE_TTL_LONG)
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
        cur.execute(queries.SELECT_ACTIVE_PLAN, (user_id,))
        plan_row = cur.fetchone()
        if not plan_row:
            return {"plan": None, "plan_days": []}
        plan_id = plan_row[0]
        cur.execute(queries.SELECT_PLAN_TEMPLATE, (plan_id,))
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
        cur.execute(queries.SELECT_TEMPLATE_DAYS, (template_id,))
        template_days = {row[0]: {"workout_json": row[1], "calorie_delta": row[2]} for row in cur.fetchall()}
        cur.execute(queries.SELECT_PLAN_OVERRIDES, (plan_id, plan_row[1], plan_row[2]))
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
        cur.execute(queries.SELECT_PLAN_CHECKPOINTS, (plan_id,))
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
    _redis_set_json(cache_key, bundle, ttl_seconds=CACHE_TTL_PLAN)
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
    _redis_set_json(f"user:{user_id}:active_plan", bundle, ttl_seconds=CACHE_TTL_PLAN)
    SESSION_CACHE.setdefault(user_id, {})["active_plan"] = bundle


def _append_plan_patch(user_id: int, patch: Dict[str, Any]) -> None:
    patches = _redis_get_json(_draft_plan_patches_key(user_id))
    if not isinstance(patches, list):
        patches = []
    patches.append(patch)
    _redis_set_json(_draft_plan_patches_key(user_id), patches, ttl_seconds=CACHE_TTL_LONG)


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
        with sqlite3.connect(DB_PATH) as conn:
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
        match = re.match(r"([A-Za-z \\-/]+)\\s+(\\d+x[^\\@]+)(.*)", part)
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
