import os

from api._shared import json_response, query_params, get_agent_service
from vercel_runtime import Response


def handler(request):
    params = query_params(request)
    text = (params.get("text") or "").strip()
    instructions = (params.get("instructions") or "").strip()
    voice = (params.get("voice") or "alloy").strip()
    if not text:
        return json_response({"error": "Missing text"}, status=400)
    if not os.environ.get("OPENAI_API_KEY"):
        return json_response({"error": "OPENAI_API_KEY not configured."}, status=400)
    agent_service = get_agent_service()
    if not agent_service:
        return json_response({"error": "AI service is not available."}, status=500)
    try:
        args = {
            "model": "gpt-4o-mini-tts",
            "voice": voice,
            "input": text,
        }
        if instructions:
            args["instructions"] = instructions
        response = agent_service.openai.audio.speech.create(**args)
        data = response.content
    except Exception as exc:
        return json_response({"error": f"TTS failed: {exc}"}, status=500)
    return Response(data, status=200, headers={"Content-Type": "audio/mpeg"})
