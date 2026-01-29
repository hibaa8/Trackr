from datetime import timedelta, datetime

from api._shared import json_response, read_json, require_user_id
from agent.web_server import _smtp_settings, _send_email, _build_ics_event, _next_scheduled_datetime


def handler(request):
    if request.method != "POST":
        return json_response({"error": "Method not allowed"}, status=405)
    user_id = require_user_id()
    payload = read_json(request) or {}
    email = payload.get("email")
    reminder_type = payload.get("reminder_type") or "workout"
    reminder_time = payload.get("reminder_time") or "09:00"
    if not email:
        return json_response({"error": "Email is required."}, status=400)
    settings = _smtp_settings()
    if not settings.get("host") or not settings.get("sender"):
        return json_response({"error": "SMTP settings not configured."}, status=400)
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
        return json_response({"error": str(exc)}, status=400)
    return json_response({"ok": True})
