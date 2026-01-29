from api._shared import json_response, read_json, require_user_id, _generate_plan_for_user


def handler(request):
    if request.method != "POST":
        return json_response({"error": "Method not allowed"}, status=405)
    try:
        payload = read_json(request) or {}
        user_id = require_user_id()
        goal_type = payload.get("goal_type")
        timeframe_weeks = payload.get("timeframe_weeks")
        weekly_change_kg = payload.get("weekly_weight_change_kg")
        bundle = _generate_plan_for_user(user_id, goal_type, timeframe_weeks, weekly_change_kg)
        if not bundle:
            return json_response({"error": "Unable to generate plan yet."}, status=400)
        return json_response({"ok": True})
    except Exception as exc:
        return json_response({"error": f"Plan generation failed: {exc}"}, status=500)
