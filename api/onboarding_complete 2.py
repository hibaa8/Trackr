from api._shared import json_response, read_json, require_user_id, _update_onboarding_preferences, _generate_plan_for_user


def handler(request):
    if request.method != "POST":
        return json_response({"error": "Method not allowed"}, status=405)
    try:
        user_id = require_user_id()
        payload = read_json(request)
        if payload is None:
            return json_response({"error": "Invalid JSON payload."}, status=400)
        _update_onboarding_preferences(user_id, payload)
        goal_type = payload.get("goal_type")
        timeframe_weeks = payload.get("timeframe_weeks")
        weekly_change_kg = payload.get("weekly_weight_change_kg")
        _generate_plan_for_user(user_id, goal_type, timeframe_weeks, weekly_change_kg)
        return json_response({"ok": True})
    except Exception as exc:
        return json_response({"error": f"Onboarding failed: {exc}"}, status=500)
