from api._shared import json_response, require_user_id, _load_user_profile


def handler(request):
    try:
        user_id = require_user_id()
        return json_response(_load_user_profile(user_id))
    except Exception as exc:
        return json_response({"error": f"Profile load failed: {exc}"}, status=500)
