from datetime import timedelta, datetime

from api._shared import json_response, require_user_id
from agent.web_server import _smtp_settings, _send_email, _build_ics_event
from agent.db.connection import get_db_conn


def handler(request):
    if request.method != "POST":
        return json_response({"error": "Method not allowed"}, status=405)
    user_id = require_user_id()
    settings = _smtp_settings()
    if not settings.get("host") or not settings.get("sender"):
        return json_response({"error": "SMTP settings not configured."}, status=400)
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT email FROM users WHERE id = ?", (user_id,))
        user_row = cur.fetchone()
        to_email = user_row[0] if user_row else None
        if not to_email:
            return json_response({"error": "Email not set for user."}, status=400)
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
            cur.execute("UPDATE reminders SET status = 'active' WHERE id = ?", (reminder_id,))
        conn.commit()
    return json_response({"ok": True, "sent": len(rows)})
