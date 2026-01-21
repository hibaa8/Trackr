from __future__ import annotations

import time
from pathlib import Path

from langchain_openai import OpenAIEmbeddings
from langchain_community.vectorstores import FAISS

from agent.config.constants import RAG_SOURCES_DIR

RAG_INDEX = None
RAG_READY = False
RAG_QUERY_CACHE = {}


def _build_rag_index() -> None:
    global RAG_INDEX, RAG_READY
    if RAG_READY:
        return
    RAG_READY = True
    index_path = Path(__file__).resolve().parents[2] / "data" / "faiss_index"
    if not index_path.exists():
        return
    try:
        embeddings = OpenAIEmbeddings()
        RAG_INDEX = FAISS.load_local(str(index_path), embeddings, allow_dangerous_deserialization=True)
    except Exception:
        RAG_INDEX = None


def _retrieve_rag_context(query: str, k: int = 3) -> str:
    if not query:
        return ""
    if not RAG_INDEX:
        return ""
    cache_key = f"default:{hash(query)}"
    cached = RAG_QUERY_CACHE.get(cache_key)
    now = time.time()
    if cached and now - cached["ts"] < 10 * 60:
        return cached["value"]
    results = RAG_INDEX.similarity_search_with_score(query, k=k)
    if not results:
        return ""
    lines = []
    for doc, score in results:
        source = doc.metadata.get("source", "unknown")
        page = doc.metadata.get("page")
        page_note = f" p.{page + 1}" if isinstance(page, int) else ""
        content = doc.page_content.strip().replace("\n", " ")
        if content:
            lines.append(f"({Path(source).name}{page_note}) {content[:200]}")
    value = "\n".join(lines)[:800]
    RAG_QUERY_CACHE[cache_key] = {"ts": now, "value": value}
    return value


def _should_apply_rag(message: str) -> bool:
    if not message:
        return False
    lower = message.lower()
    keywords = [
        "plan",
        "workout",
        "schedule",
        "routine",
        "days off",
        "shift",
        "too intense",
        "don't like",
        "dislike",
        "replace",
        "modify",
        "update plan",
        "adjust plan",
        "generate plan",
        "new plan",
    ]
    return any(keyword in lower for keyword in keywords)
