from api._shared import json_response, require_user_id, _list_workout_sessions


def handler(request):
    user_id = require_user_id()
    return json_response({"sessions": _list_workout_sessions(user_id)})
