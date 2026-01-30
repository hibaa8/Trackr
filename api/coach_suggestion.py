from api._shared import json_response, require_user_id, _get_latest_ai_suggestion, _derive_suggestion_from_status


def handler(request):
    user_id = require_user_id()
    suggestion = _get_latest_ai_suggestion(user_id) or _derive_suggestion_from_status(user_id)
    return json_response({"suggestion": suggestion})
