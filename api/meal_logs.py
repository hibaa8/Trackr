from api._shared import json_response, require_user_id, _list_meal_logs


def handler(request):
    user_id = require_user_id()
    return json_response({"meals": _list_meal_logs(user_id)})
