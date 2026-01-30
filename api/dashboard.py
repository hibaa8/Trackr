from api._shared import json_response, require_user_id, _get_active_plan_bundle_data, _list_meal_logs, _list_health_activity, _load_user_profile, _generate_plan_for_user
from agent.db.connection import get_db_conn


def handler(request):
    user_id = require_user_id()
    plan_bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
    if not plan_bundle.get("plan"):
        generated = _generate_plan_for_user(user_id)
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
    return json_response(response)
