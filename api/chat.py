from api._shared import json_response, read_json, get_agent_service


def handler(request):
    if request.method != "POST":
        return json_response({"error": "Method not allowed"}, status=405)
    payload = read_json(request)
    if payload is None:
        return json_response({"error": "Invalid JSON payload."}, status=400)
    message = payload.get("message")
    approve_plan = payload.get("approve_plan")
    thread_id = payload.get("thread_id") or "web"
    if not message and approve_plan is None:
        return json_response({"error": "Provide message or approve_plan."}, status=400)
    agent_service = get_agent_service()
    if not agent_service:
        return json_response({"error": "AI service is not available."}, status=500)
    try:
        response = agent_service.invoke(message, thread_id, approve_plan)
    except Exception as exc:
        return json_response({"error": str(exc)}, status=500)
    return json_response(response)
