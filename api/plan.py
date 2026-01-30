from api._shared import json_response, require_user_id, _get_active_plan_bundle_data, _load_user_profile, _estimate_plan_burn


def handler(request):
    user_id = require_user_id()
    plan_bundle = _get_active_plan_bundle_data(user_id, allow_db_fallback=True)
    profile = _load_user_profile(user_id)
    weight_kg = profile.get("user", {}).get("weight_kg") if profile else None
    plan_days = []
    for day in plan_bundle.get("plan_days", []):
        workout_label = day.get("workout_plan") or day.get("workout")
        rest_day = bool(day.get("rest_day"))
        plan_days.append(
            {
                **day,
                "calories_burned_est": _estimate_plan_burn(
                    weight_kg, workout_label, rest_day
                ),
            }
        )
    return json_response({"plan": plan_bundle.get("plan"), "plan_days": plan_days})
