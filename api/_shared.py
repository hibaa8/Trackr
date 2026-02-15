import json
import os
import sys
from pathlib import Path
from typing import Any

from vercel_runtime import Response

ROOT = Path(__file__).resolve().parents[1]
VAYLO_FITNESS_DIR = ROOT
if str(VAYLO_FITNESS_DIR) not in sys.path:
    sys.path.insert(0, str(VAYLO_FITNESS_DIR))

from agent.tools.plan_tools import _estimate_cardio_minutes  # noqa: E402
from agent.tools.activity_utils import _estimate_workout_calories  # noqa: E402
from agent.config.constants import DEFAULT_USER_ID  # noqa: E402

_WEB_HELPERS = None
_WEB_HELPERS_ERROR = None
AGENT_SERVICE = None
AGENT_SERVICE_ERROR = None


def _get_web_helpers():
    global _WEB_HELPERS, _WEB_HELPERS_ERROR
    if _WEB_HELPERS is not None:
        return _WEB_HELPERS
    if _WEB_HELPERS_ERROR is not None:
        raise RuntimeError(_WEB_HELPERS_ERROR)
    try:
        from agent import web_server as ws  # noqa: E402

        _WEB_HELPERS = ws
        return _WEB_HELPERS
    except Exception as exc:  # pragma: no cover - runtime env issues
        _WEB_HELPERS_ERROR = exc
        raise RuntimeError(exc)


def get_agent_service():
    global AGENT_SERVICE, AGENT_SERVICE_ERROR
    if AGENT_SERVICE is not None:
        return AGENT_SERVICE
    if AGENT_SERVICE_ERROR is not None:
        return None
    try:
        ws = _get_web_helpers()
        AGENT_SERVICE = ws.AgentService()
    except Exception as exc:  # pragma: no cover - runtime env issues
        AGENT_SERVICE_ERROR = exc
        return None
    return AGENT_SERVICE


def _call_gemini_for_nutrition(image_b64: str, mime_type: str):
    return _get_web_helpers()._call_gemini_for_nutrition(image_b64, mime_type)


def _estimate_plan_burn(plan: dict, weight_kg: float | None = None):
    return _get_web_helpers()._estimate_plan_burn(plan, weight_kg)


def _get_active_plan_bundle_data(user_id: int, allow_db_fallback: bool = False):
    return _get_web_helpers()._get_active_plan_bundle_data(user_id, allow_db_fallback=allow_db_fallback)


def _get_latest_ai_suggestion(user_id: int):
    return _get_web_helpers()._get_latest_ai_suggestion(user_id)


def _list_checkins(user_id: int):
    return _get_web_helpers()._list_checkins(user_id)


def _list_health_activity(user_id: int):
    return _get_web_helpers()._list_health_activity(user_id)


def _list_meal_logs(user_id: int):
    return _get_web_helpers()._list_meal_logs(user_id)


def _list_workout_sessions(user_id: int):
    return _get_web_helpers()._list_workout_sessions(user_id)


def _load_user_profile(user_id: int):
    return _get_web_helpers()._load_user_profile(user_id)


def _search_gym_classes(query: str):
    return _get_web_helpers()._search_gym_classes(query)


def _search_workout_videos(query: str):
    return _get_web_helpers()._search_workout_videos(query)


def _sign_photo_url(path: str):
    return _get_web_helpers()._sign_photo_url(path)


def _store_photo_in_supabase(image_bytes: bytes, mime_type: str, filename: str):
    return _get_web_helpers()._store_photo_in_supabase(image_bytes, mime_type, filename)


def _build_public_photo_url(path: str):
    return _get_web_helpers()._build_public_photo_url(path)


def _extension_from_mime(mime_type: str):
    return _get_web_helpers()._extension_from_mime(mime_type)


def _generate_plan_for_user(user_id: int, goal_type=None, timeframe_weeks=None, weekly_change_kg=None):
    return _get_web_helpers()._generate_plan_for_user(
        user_id, goal_type=goal_type, timeframe_weeks=timeframe_weeks, weekly_change_kg=weekly_change_kg
    )


def _update_onboarding_preferences(user_id: int, payload: dict):
    return _get_web_helpers()._update_onboarding_preferences(user_id, payload)


def _derive_suggestion_from_status(user_id: int):
    return _get_web_helpers()._derive_suggestion_from_status(user_id)


def json_response(payload: dict[str, Any], status: int = 200) -> Response:
    return Response(
        json.dumps(payload),
        status=status,
        headers={"Content-Type": "application/json; charset=utf-8"},
    )


def _get_body(request) -> bytes:
    body = getattr(request, "body", b"") or b""
    if isinstance(body, str):
        body = body.encode("utf-8")
    return body


def read_json(request) -> dict[str, Any] | None:
    body = _get_body(request)
    if not body:
        return None
    try:
        return json.loads(body.decode("utf-8"))
    except json.JSONDecodeError:
        return None


def query_params(request) -> dict[str, Any]:
    params = getattr(request, "query", None)
    if isinstance(params, dict):
        return params
    params = getattr(request, "args", None)
    if isinstance(params, dict):
        return params
    return {}


def require_user_id() -> int:
    return DEFAULT_USER_ID

