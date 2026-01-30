from api._shared import json_response, require_user_id, _get_active_plan_bundle_data, _list_checkins, _list_meal_logs, _list_workout_sessions


def handler(request):
    user_id = require_user_id()
    checkins = _list_checkins(user_id)
    plan_bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
    checkpoints = plan_bundle.get("checkpoints", [])
    meals = _list_meal_logs(user_id)
    workouts = _list_workout_sessions(user_id)
    return json_response(
        {
            "checkins": checkins,
            "checkpoints": checkpoints,
            "plan": plan_bundle.get("plan"),
            "meals": meals,
            "workouts": workouts,
        }
    )
