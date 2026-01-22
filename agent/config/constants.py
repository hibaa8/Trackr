from __future__ import annotations

from pathlib import Path

DB_PATH = "/Users/admin/Documents/AI-trainer-agent/data/ai_trainer.db"
DEFAULT_USER_ID = 1
CACHE_TTL_LONG = 6 * 60 * 60
CACHE_TTL_PLAN = 30 * 60

RAG_SOURCES_DIR = Path("/Users/admin/Documents/AI-trainer-agent/sources")


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


def _draft_checkins_key(user_id: int) -> str:
    return f"draft:{user_id}:checkins"


def _draft_health_activity_key(user_id: int) -> str:
    return f"draft:{user_id}:health_activity"


def _draft_plan_status_key(user_id: int) -> str:
    return f"draft:{user_id}:plan_status"


def _draft_reminders_key(user_id: int) -> str:
    return f"draft:{user_id}:reminders"
