from __future__ import annotations

import asyncio
import json
import os
from typing import Any, Optional

from dotenv import load_dotenv

try:
    import redis.asyncio as AsyncRedis
except ImportError:  # pragma: no cover - optional dependency for local dev
    AsyncRedis = None
try:
    from upstash_redis import Redis as UpstashRedis
except ImportError:  # pragma: no cover - optional dependency for local dev
    UpstashRedis = None

load_dotenv()


def _redis_client() -> Optional[Any]:
    tcp_url = os.getenv("REDIS_URL")
    if tcp_url and AsyncRedis is not None:
        return AsyncRedis.from_url(tcp_url, decode_responses=True)
    if UpstashRedis is None:
        return None
    url = os.getenv("UPSTASH_REDIS_REST_URL")
    token = os.getenv("UPSTASH_REDIS_REST_TOKEN")
    if not url or not token:
        return None
    return UpstashRedis(url=url, token=token)


def _run_async(coro):
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        return asyncio.run(coro)
    return loop.run_until_complete(coro)


def _redis_get_json(key: str) -> Optional[Any]:
    if not REDIS:
        return None
    if AsyncRedis and isinstance(REDIS, AsyncRedis.Redis):
        raw = _run_async(REDIS.get(key))
    else:
        raw = REDIS.get(key)
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def _redis_set_json(key: str, value: Any, ttl_seconds: int) -> None:
    if not REDIS:
        return
    payload = json.dumps(value)
    if AsyncRedis and isinstance(REDIS, AsyncRedis.Redis):
        _run_async(REDIS.setex(key, ttl_seconds, payload))
    else:
        REDIS.setex(key, ttl_seconds, payload)


def _redis_delete(key: str) -> None:
    if not REDIS:
        return
    if AsyncRedis and isinstance(REDIS, AsyncRedis.Redis):
        _run_async(REDIS.delete(key))
    else:
        REDIS.delete(key)


REDIS = _redis_client()

