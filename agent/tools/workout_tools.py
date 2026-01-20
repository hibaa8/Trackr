from __future__ import annotations

import json
import sqlite3
from datetime import date, datetime
from typing import Any, Dict, List, Optional

from langchain_core.tools import tool

from agent.config.constants import CACHE_TTL_LONG, DB_PATH, _draft_workout_sessions_key, _draft_workout_sessions_ops_key
from agent.redis.cache import _redis_get_json, _redis_set_json
from agent.state import SESSION_CACHE
from agent.tools.plan_tools import _is_cardio_exercise, _load_user_context_data


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


def _append_workout_session_op(user_id: int, op: Dict[str, Any]) -> None:
    ops = _redis_get_json(_draft_workout_sessions_ops_key(user_id))
    if not isinstance(ops, list):
        ops = []
    ops.append(op)
    _redis_set_json(_draft_workout_sessions_ops_key(user_id), ops, ttl_seconds=CACHE_TTL_LONG)


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
    _redis_set_json(draft_key, draft, ttl_seconds=CACHE_TTL_LONG)
    if _redis_get_json(_draft_workout_sessions_ops_key(user_id)) is None:
        _redis_set_json(_draft_workout_sessions_ops_key(user_id), [], ttl_seconds=CACHE_TTL_LONG)
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


@tool("get_workout_sessions")
def get_workout_sessions(user_id: int) -> str:
    """Return logged workout sessions from the draft cache."""
    draft = SESSION_CACHE.get(user_id, {}).get("workout_sessions") or _redis_get_json(
        _draft_workout_sessions_key(user_id)
    )
    if draft is None:
        return "No cached workout logs found. Start a session to load them."
    sessions = draft.get("sessions", []) if isinstance(draft, dict) else []
    if not sessions:
        return "No workout sessions logged yet for the active plan."
    lines = []
    plan_bundle = SESSION_CACHE.get(user_id, {}).get("active_plan")
    plan = plan_bundle.get("plan") if isinstance(plan_bundle, dict) else None
    plan_start = plan.get("start_date") if isinstance(plan, dict) else None
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
        _redis_set_json(_draft_workout_sessions_key(user_id), draft, ttl_seconds=CACHE_TTL_LONG)
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
    _redis_set_json(_draft_workout_sessions_key(user_id), draft, ttl_seconds=CACHE_TTL_LONG)
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
        _redis_set_json(_draft_workout_sessions_key(user_id), draft, ttl_seconds=CACHE_TTL_LONG)
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
    target = workout_type.strip().lower()
    remove_all_cardio = target in {"cardio", "all cardio", "all cardio entries", "cardio entries"}
    draft = _load_workout_sessions_draft(user_id)
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
    _redis_set_json(_draft_workout_sessions_key(user_id), draft, ttl_seconds=CACHE_TTL_LONG)
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
