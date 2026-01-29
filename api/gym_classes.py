from api._shared import json_response, _search_gym_classes


def handler(request):
    return json_response({"classes": _search_gym_classes()})
