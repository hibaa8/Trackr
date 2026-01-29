from api._shared import json_response, _search_workout_videos


def handler(request):
    return json_response({"videos": _search_workout_videos()})
