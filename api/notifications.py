from api._shared import json_response, read_json, require_user_id
from agent.web_server import _next_scheduled_datetime
from agent.db.connection import get_db_conn


def handler(request):
    if request.method == "GET":
        user_id = require_user_id()
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
        return json_response(
            {"email": user_row[0] if user_row else None, "reminders": reminders}
        )
    if request.method != "POST":
        return json_response({"error": "Method not allowed"}, status=405)
    user_id = require_user_id()
    payload = read_json(request)
    if payload is None:
        return json_response({"error": "Invalid JSON payload."}, status=400)
    email = payload.get("email")
    reminder_type = payload.get("reminder_type")
    reminder_time = payload.get("reminder_time")
    if not email:
        return json_response({"error": "Email is required."}, status=400)
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
    return json_response({"ok": True})
