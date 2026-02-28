from __future__ import annotations

import json
from datetime import datetime
from typing import Any, Dict, List, Optional, Annotated

from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage, BaseMessage, ToolMessage, AIMessage
from langgraph.graph import StateGraph, START, add_messages
from langgraph.checkpoint.memory import MemorySaver
from langgraph.prebuilt import ToolNode, tools_condition
from typing_extensions import TypedDict

from agent.config.constants import CACHE_TTL_LONG, CACHE_TTL_PLAN, DEFAULT_USER_ID, _draft_plan_key
from agent.prompts.system_prompt import DEFAULT_AGENT_ID, get_system_prompt
from agent.rag.rag import _build_rag_index, _retrieve_rag_context, _should_apply_rag
from agent.state import SESSION_CACHE
from agent.tools.meal_tools import delete_all_meal_logs, get_meal_logs, log_meal
from agent.redis.cache import _redis_get_json, _redis_set_json
from agent.db.connection import get_db_conn
from agent.tools.plan_tools import (
    _compact_context_summary,
    _get_active_plan_bundle_data,
    _invalidate_active_plan_cache,
    _load_checkins_draft,
    _load_health_activity_draft,
    _load_active_plan_draft,
    _load_reminders_draft,
    _load_user_context_data,
    apply_plan_patch,
    compute_plan_status,
    generate_plan,
    get_current_date,
    get_current_plan_summary,
    get_plan_day,
    get_reminders,
    get_weight_checkpoint_for_current_week,
    log_checkin,
    delete_checkin,
    propose_plan_corrections,
    propose_plan_patch_with_llm,
    replace_active_plan_workouts,
    add_reminder,
    update_reminder,
    delete_reminder,
    search_web,
    shift_active_plan_end_date,
)
from agent.tools.workout_tools import (
    delete_workout_from_draft,
    get_workout_sessions,
    log_workout_session,
    remove_workout_exercise,
)
from agent.tools.meal_tools import _load_meal_logs_draft
from agent.tools.workout_tools import _load_workout_sessions_draft


def _system_message(agent_id: str | int | None) -> SystemMessage:
    return SystemMessage(content=get_system_prompt(agent_id))



class AgentState(TypedDict):
    messages: Annotated[List[BaseMessage], add_messages]
    approve_plan: Optional[bool]
    context: Optional[Dict[str, Any]]
    active_plan: Optional[Dict[str, Any]]
    proposed_plan: Optional[Dict[str, Any]]
    user_id: Optional[int]


def _sanitize_messages_for_llm(messages: List[BaseMessage]) -> List[BaseMessage]:
    """
    Remove malformed tool-call segments before sending chat history to OpenAI.

    If an assistant message contains tool_calls but the required tool_call_id
    responses are missing, OpenAI rejects the request with a 400. This can
    happen after interrupted tool execution/retries. We drop dangling segments
    so a thread can recover on the next turn.
    """
    cleaned: List[BaseMessage] = []
    idx = 0

    while idx < len(messages):
        message = messages[idx]

        if isinstance(message, ToolMessage):
            # Orphan tool message with no preceding assistant tool call in cleaned history.
            if not cleaned or not isinstance(cleaned[-1], AIMessage):
                idx += 1
                continue

        if isinstance(message, AIMessage):
            tool_calls = message.tool_calls or []
            if tool_calls:
                required_ids = {
                    call.get("id")
                    for call in tool_calls
                    if isinstance(call, dict) and call.get("id")
                }
                lookahead = idx + 1
                seen_ids = set()
                while lookahead < len(messages) and isinstance(messages[lookahead], ToolMessage):
                    tool_call_id = getattr(messages[lookahead], "tool_call_id", None)
                    if tool_call_id:
                        seen_ids.add(tool_call_id)
                    lookahead += 1

                if required_ids and not required_ids.issubset(seen_ids):
                    # Drop this malformed assistant tool-call segment entirely.
                    idx = lookahead
                    continue

        cleaned.append(message)
        idx += 1

    return cleaned


def _preload_session_cache(user_id: int) -> Dict[str, Any]:
    existing = SESSION_CACHE.get(user_id, {})
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.fetchone()
    context = _load_user_context_data(user_id)
    active_plan = _load_active_plan_draft(user_id)
    workout_sessions = _load_workout_sessions_draft(user_id)
    meal_logs = _load_meal_logs_draft(user_id)
    checkins = _load_checkins_draft(user_id)
    health_activity = _load_health_activity_draft(user_id)
    reminders = _load_reminders_draft(user_id)
    SESSION_CACHE[user_id] = {
        "context": context,
        "active_plan": active_plan,
        "workout_sessions": workout_sessions,
        "meal_logs": meal_logs,
        "checkins": checkins,
        "health_activity": health_activity,
        "reminders": reminders,
        "agent_id": existing.get("agent_id"),
    }
    return {
        "context": context,
        "active_plan": active_plan,
        "workout_sessions": workout_sessions,
        "meal_logs": meal_logs,
        "checkins": checkins,
        "health_activity": health_activity,
        "reminders": reminders,
    }


def assistant(state: AgentState):
    context = state.get("context")
    active_plan = state.get("active_plan")
    user_id = state.get("user_id") or DEFAULT_USER_ID
    session = SESSION_CACHE.get(user_id, {})
    agent_id = session.get("agent_id", DEFAULT_AGENT_ID)
    if session.get("context"):
        context = session["context"]
    if session.get("active_plan"):
        active_plan = session["active_plan"]
    if session.get("workout_sessions"):
        state["workout_sessions"] = session["workout_sessions"]
    if context is None or active_plan is None:
        preload = _preload_session_cache(user_id)
        context = preload["context"]
        active_plan = preload["active_plan"]
    if user_id not in SESSION_CACHE:
        SESSION_CACHE[user_id] = {}
    if "workout_sessions" not in SESSION_CACHE[user_id]:
        SESSION_CACHE[user_id]["workout_sessions"] = _load_workout_sessions_draft(user_id)
    if "meal_logs" not in SESSION_CACHE[user_id]:
        SESSION_CACHE[user_id]["meal_logs"] = _load_meal_logs_draft(user_id)
    SESSION_CACHE[user_id]["context"] = context
    SESSION_CACHE[user_id]["active_plan"] = active_plan
    last_user_message = ""
    for message in reversed(state.get("messages", [])):
        if isinstance(message, HumanMessage):
            last_user_message = message.content
            break
    rag_context = _retrieve_rag_context(last_user_message) if _should_apply_rag(last_user_message) else ""
    context_msg = SystemMessage(
        content=(
            f"User context (compact): {_compact_context_summary(context, active_plan)}"
            + (f"\nReference excerpts (RAG):\n{rag_context}" if rag_context else "")
        )
    )
    try:
        safe_messages = _sanitize_messages_for_llm(state.get("messages", []))
        response = llm_with_tools.invoke([_system_message(agent_id), context_msg] + safe_messages)
    except Exception as exc:
        return {
            "context": context,
            "active_plan": active_plan,
            "messages": [AIMessage(content=f"OpenAI request failed. Try again. Details: {exc}")],
        }
    return {
        "context": context,
        "active_plan": active_plan,
        "messages": [response],
    }


tools = [
    get_current_plan_summary,
    get_plan_day,
    search_web,
    generate_plan,
    shift_active_plan_end_date,
    replace_active_plan_workouts,
    get_weight_checkpoint_for_current_week,
    compute_plan_status,
    apply_plan_patch,
    propose_plan_corrections,
    propose_plan_patch_with_llm,
    get_reminders,
    add_reminder,
    update_reminder,
    delete_reminder,
    log_checkin,
    delete_checkin,
    log_meal,
    get_meal_logs,
    get_current_date,
    delete_all_meal_logs,
    log_workout_session,
    get_workout_sessions,
    remove_workout_exercise,
    delete_workout_from_draft,
]
llm = ChatOpenAI(model="gpt-4o", temperature=0, max_retries=0, request_timeout=30)
llm_with_tools = llm.bind_tools(tools, parallel_tool_calls=False)
_tool_node = ToolNode(tools)
_USER_SCOPED_TOOL_NAMES = {
    "get_current_plan_summary",
    "get_plan_day",
    "generate_plan",
    "shift_active_plan_end_date",
    "replace_active_plan_workouts",
    "get_weight_checkpoint_for_current_week",
    "compute_plan_status",
    "apply_plan_patch",
    "propose_plan_corrections",
    "propose_plan_patch_with_llm",
    "get_reminders",
    "add_reminder",
    "update_reminder",
    "delete_reminder",
    "log_checkin",
    "delete_checkin",
    "log_meal",
    "get_meal_logs",
    "delete_all_meal_logs",
    "log_workout_session",
    "get_workout_sessions",
    "remove_workout_exercise",
    "delete_workout_from_draft",
}


def execute_tools(state: AgentState) -> Dict[str, Any]:
    """Enforce active session user_id on all user-scoped tool calls."""
    user_id = state.get("user_id")
    if not user_id:
        return {"messages": [AIMessage(content="Missing user_id for tool execution.")]}

    messages = list(state.get("messages", []))
    if not messages or not isinstance(messages[-1], AIMessage):
        return _tool_node.invoke(state)

    last_ai = messages[-1]
    tool_calls = last_ai.tool_calls or []
    if not tool_calls:
        return _tool_node.invoke(state)

    rewritten = False
    patched_calls = []
    for call in tool_calls:
        if not isinstance(call, dict):
            patched_calls.append(call)
            continue
        name = call.get("name")
        args = call.get("args")
        if name in _USER_SCOPED_TOOL_NAMES:
            if not isinstance(args, dict):
                args = {}
            if args.get("user_id") != user_id:
                args = {**args, "user_id": user_id}
                rewritten = True
            call = {**call, "args": args}
        patched_calls.append(call)

    if rewritten:
        try:
            patched_ai = last_ai.model_copy(update={"tool_calls": patched_calls})
        except Exception:
            patched_ai = AIMessage(content=last_ai.content, tool_calls=patched_calls)
        messages[-1] = patched_ai
        patched_state = dict(state)
        patched_state["messages"] = messages
        return _tool_node.invoke(patched_state)

    return _tool_node.invoke(state)


def _last_tool_name(state: AgentState) -> Optional[str]:
    messages = state.get("messages", [])
    if len(messages) < 2:
        return None
    if isinstance(messages[-1], ToolMessage) and isinstance(messages[-2], AIMessage):
        tool_calls = messages[-2].tool_calls or []
        if tool_calls:
            return tool_calls[0].get("name")
    return None


def route_after_tools(state: AgentState) -> str:
    if _last_tool_name(state) == "generate_plan":
        return "human_feedback"
    return "assistant"


def human_feedback(state: AgentState) -> Dict[str, Any]:
    return {}


def apply_plan(state: AgentState) -> AgentState:
    if not state.get("approve_plan"):
        return {"messages": [AIMessage(content="Plan not changed.")]}

    plan_data = state.get("proposed_plan")
    if not plan_data:
        return {"messages": [AIMessage(content="No plan data to apply.")]}
    user_id = plan_data.get("user_id", DEFAULT_USER_ID)

    cache_bundle = {
        "plan": {
            "id": None,
            "start_date": plan_data["start_date"],
            "end_date": plan_data["end_date"],
            "daily_calorie_target": plan_data["calorie_target"],
            "protein_g": plan_data["macros"]["protein_g"],
            "carbs_g": plan_data["macros"]["carbs_g"],
            "fat_g": plan_data["macros"]["fat_g"],
            "status": "active",
        },
        "plan_days": plan_data["plan_days"],
        "checkpoints": plan_data.get("checkpoints", []),
    }
    _redis_set_json(_draft_plan_key(user_id), cache_bundle, ttl_seconds=CACHE_TTL_LONG)
    _redis_set_json(f"user:{user_id}:active_plan", cache_bundle, ttl_seconds=CACHE_TTL_PLAN)
    SESSION_CACHE[user_id] = {
        "context": SESSION_CACHE.get(user_id, {}).get("context"),
        "active_plan": cache_bundle,
    }

    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute("UPDATE plan_templates SET status = 'inactive' WHERE user_id = ?", (user_id,))
        if plan_data.get("goal_type"):
            cur.execute(
                "UPDATE user_preferences SET goal_type = ? WHERE user_id = ?",
                (plan_data["goal_type"], user_id),
            )
        cur.execute("SELECT timezone FROM user_preferences WHERE user_id = ?", (user_id,))
        pref_row = cur.fetchone()
        timezone = pref_row[0] if pref_row else None
        cycle_length = min(7, len(plan_data["plan_days"]))
        cur.execute(
            """
            INSERT INTO plan_templates (
                user_id, start_date, end_date, daily_calorie_target, protein_g, carbs_g, fat_g,
                status, cycle_length_days, timezone, default_calories, default_protein_g,
                default_carbs_g, default_fat_g, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            RETURNING id
            """,
            (
                user_id,
                plan_data["start_date"],
                plan_data["end_date"],
                plan_data["calorie_target"],
                plan_data["macros"]["protein_g"],
                plan_data["macros"]["carbs_g"],
                plan_data["macros"]["fat_g"],
                "active",
                cycle_length,
                timezone,
                plan_data["calorie_target"],
                plan_data["macros"]["protein_g"],
                plan_data["macros"]["carbs_g"],
                plan_data["macros"]["fat_g"],
                datetime.now().isoformat(timespec="seconds"),
            ),
        )
        template_id = cur.fetchone()[0]
        for day_index in range(cycle_length):
            day = plan_data["plan_days"][day_index]
            workout_json = json.dumps({"label": day["workout"]})
            calorie_delta = day["calorie_target"] - plan_data["calorie_target"]
            cur.execute(
                """
                INSERT INTO plan_template_days (
                    template_id, day_index, workout_json, calorie_delta, notes
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    template_id,
                    day_index,
                    workout_json,
                    calorie_delta,
                    None,
                ),
            )
        for checkpoint in plan_data["checkpoints"]:
            cur.execute(
                """
                INSERT INTO plan_checkpoints (
                    template_id, checkpoint_week, expected_weight_kg, min_weight_kg, max_weight_kg
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    template_id,
                    checkpoint["week"],
                    checkpoint["expected_weight_kg"],
                    checkpoint["min_weight_kg"],
                    checkpoint["max_weight_kg"],
                ),
            )
        conn.commit()
    cached_context = SESSION_CACHE.get(user_id, {}).get("context") or _redis_get_json(f"user:{user_id}:profile")
    if isinstance(cached_context, dict) and "preferences" in cached_context:
        prefs = list(cached_context["preferences"])
        if len(prefs) > 2 and plan_data.get("goal_type"):
            prefs[2] = plan_data["goal_type"]
            cached_context["preferences"] = prefs
            _redis_set_json(f"user:{user_id}:profile", cached_context, ttl_seconds=CACHE_TTL_LONG)
            SESSION_CACHE.setdefault(user_id, {})["context"] = cached_context
    return {"messages": [AIMessage(content="Plan updated and saved.")]}


def build_graph() -> StateGraph:
    builder = StateGraph(AgentState)
    builder.add_node("assistant", assistant)
    builder.add_node("tools", execute_tools)
    builder.add_node("human_feedback", human_feedback)
    builder.add_node("apply_plan", apply_plan)

    builder.add_edge(START, "assistant")
    builder.add_conditional_edges(
        "assistant",
        tools_condition,
    )
    builder.add_conditional_edges("tools", route_after_tools, ["assistant", "human_feedback"])
    builder.add_edge("human_feedback", "apply_plan")
    builder.add_edge("apply_plan", "assistant")
    memory = MemorySaver()
    return builder.compile(checkpointer=memory, interrupt_before=["human_feedback"])


__all__ = [
    "AgentState",
    "assistant",
    "build_graph",
    "human_feedback",
    "route_after_tools",
    "_preload_session_cache",
    "_build_rag_index",
]
