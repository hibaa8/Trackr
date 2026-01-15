#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sqlite3
from datetime import date, datetime, timedelta
from typing import List, Optional, Dict, Any, Annotated

from typing_extensions import TypedDict
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage, BaseMessage, AIMessage, ToolMessage
from langchain_core.tools import tool
from langgraph.graph import StateGraph, START, END, add_messages
from langgraph.checkpoint.memory import MemorySaver
from dotenv import load_dotenv
from langgraph.prebuilt import ToolNode
from langgraph.prebuilt import tools_condition
from langchain_tavily import TavilySearch

load_dotenv()

DB_PATH = "/Users/admin/Documents/AI-trainer-agent/data/ai_trainer.db"

sys_msg = SystemMessage(content="""You are an AI Trainer assistant.

If the user asks about their current plan, call the tool `get_current_plan_summary`
using user_id=1. Otherwise answer normally.

If the user asks a nutrition or exercise question that requires external info,
call the tool `search_web` with a concise search query.

If the user asks to calculate a plan for weight loss or a workout schedule,
call the tool `generate_plan` using user_id=1 and days between 14 and 60.
""")


class AgentState(TypedDict):
    messages: Annotated[List[BaseMessage], add_messages]
    approve_plan: Optional[bool]


@tool("get_current_plan_summary")
def get_current_plan_summary(user_id: int) -> str:
    """Return a basic plan summary for the given user_id."""
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT start_date, end_date, daily_calorie_target, protein_g, carbs_g, fat_g, status
            FROM plans
            WHERE user_id = ? AND status = 'active'
            ORDER BY start_date DESC
            LIMIT 1
            """,
            (user_id,),
        )
        plan_row = cur.fetchone()
        if plan_row:
            cur.execute(
                """
                SELECT workout_plan, rest_day
                FROM plan_days
                WHERE plan_id = (
                    SELECT id FROM plans WHERE user_id = ? AND status = 'active' ORDER BY start_date DESC LIMIT 1
                )
                ORDER BY date
                """,
                (user_id,),
            )
            workout_rows = cur.fetchall()
    if not plan_row:
        return "No plan found for this user."
    start_date, end_date, calories, protein, carbs, fat, status = plan_row
    workout_lines = []
    for workout_plan, rest_day in workout_rows:
        workout_lines.append("Rest day" if rest_day else workout_plan)
    workout_summary = ", ".join(workout_lines) if workout_lines else "No workouts scheduled."
    return (
        f"Plan {status}: {start_date} to {end_date}. "
        f"Calories {calories}, macros (g) P{protein}/C{carbs}/F{fat}. "
        f"Workouts: {workout_summary}."
    )

@tool("search_web")
def search_web(query: str) -> str:
    """Search the web and return formatted source snippets."""
    tavily_search = TavilySearch(max_results=3)
    data = tavily_search.invoke({"query": query})
    search_docs = data.get("results", data)
    return "\n\n---\n\n".join(
        [
            f'<Document href="{doc["url"]}"/>\n{doc["content"]}\n</Document>'
            for doc in search_docs
        ]
    )

def _age_from_birthdate(birthdate: str) -> int:
    born = datetime.strptime(birthdate, "%Y-%m-%d").date()
    today = date.today()
    return today.year - born.year - ((today.month, today.day) < (born.month, born.day))


def _bmr_mifflin(weight_kg: float, height_cm: float, age: int, gender: str) -> float:
    base = 10 * weight_kg + 6.25 * height_cm - 5 * age
    if gender.lower().startswith("f"):
        return base - 161
    return base + 5


def _activity_multiplier(activity_level: str) -> float:
    levels = {
        "sedentary": 1.2,
        "light": 1.375,
        "moderate": 1.55,
        "active": 1.725,
        "very_active": 1.9,
    }
    return levels.get(activity_level, 1.4)

def _macro_split(calories: int) -> Dict[str, int]:
    protein_cals = int(calories * 0.3)
    carbs_cals = int(calories * 0.4)
    fat_cals = calories - protein_cals - carbs_cals
    return {
        "protein_g": protein_cals // 4,
        "carbs_g": carbs_cals // 4,
        "fat_g": fat_cals // 9,
    }

def _build_plan_data(user_id: int, days: int) -> Dict[str, Any]:
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT birthdate, height_cm, weight_kg, gender FROM users WHERE id = ?",
            (user_id,),
        )
        user_row = cur.fetchone()
        if not user_row:
            return {"error": "User not found."}
        birthdate, height_cm, weight_kg, gender = user_row
        cur.execute(
            "SELECT weekly_weight_change_kg, activity_level FROM user_preferences WHERE user_id = ?",
            (user_id,),
        )
        pref_row = cur.fetchone()

    weekly_delta = pref_row[0] if pref_row else -0.5
    activity_level = pref_row[1] if pref_row else "moderate"

    age = _age_from_birthdate(birthdate)
    bmr = _bmr_mifflin(weight_kg, height_cm, age, gender)
    tdee = bmr * _activity_multiplier(activity_level)
    daily_delta = (weekly_delta * 7700) / 7.0
    calorie_target = int(max(1200, tdee + daily_delta))
    macros = _macro_split(calorie_target)

    workout_cycle = [
        "Strength",
        "Cardio",
        "Strength",
        "Active recovery",
        "Strength",
        "Cardio",
        "Rest day",
    ]

    start = date.today()
    plan_days = []
    for i in range(days):
        day = start + timedelta(days=i)
        workout = workout_cycle[i % len(workout_cycle)]
        plan_days.append({"date": day.isoformat(), "workout": workout})

    return {
        "user_id": user_id,
        "start_date": start.isoformat(),
        "end_date": (start + timedelta(days=days - 1)).isoformat(),
        "days": days,
        "calorie_target": calorie_target,
        "macros": macros,
        "plan_days": plan_days,
    }

@tool("generate_plan")
def generate_plan(user_id: int, days: int = 14) -> str:
    """Generate a simple 14-60 day plan based on user profile and preferences."""
    if days < 14:
        days = 14
    if days > 60:
        days = 60

    plan_data = _build_plan_data(user_id, days)
    if "error" in plan_data:
        return plan_data["error"]
    lines = [
        f"Plan length: {days} days",
        f"Daily calories: {plan_data['calorie_target']}",
        "Workout schedule:",
    ]
    for day in plan_data["plan_days"]:
        lines.append(f"{day['date']}: {day['workout']}")

    return "\n".join(lines)

def assistant(state: AgentState):
    return {"messages": [llm_with_tools.invoke([sys_msg] + state["messages"])]}


tools = [get_current_plan_summary, search_web, generate_plan]
llm = ChatOpenAI(model="gpt-4o", temperature=0)
llm_with_tools = llm.bind_tools(tools, parallel_tool_calls=False)

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

# added because human_feedback can only pause before a node not in the middle. Added so we can ask for input.
def human_feedback(state: AgentState) -> Dict[str, Any]:
    return {}


def apply_plan(state: AgentState) -> AgentState:
    if not state.get("approve_plan"):
        return {"messages": [AIMessage(content="Plan not changed.")]}

    messages = state.get("messages", [])
    if len(messages) < 2 or not isinstance(messages[-2], AIMessage):
        return {"messages": [AIMessage(content="No plan data to apply.")]}
    tool_calls = messages[-2].tool_calls or []
    if not tool_calls:
        return {"messages": [AIMessage(content="No plan data to apply.")]}
    args = tool_calls[0].get("args", {})
    user_id = args.get("user_id", 1)
    days = args.get("days", 14)

    plan_data = _build_plan_data(user_id, days)
    if "error" in plan_data:
        return {"messages": [AIMessage(content=plan_data["error"])]}

    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("UPDATE plans SET status = 'inactive' WHERE user_id = ?", (user_id,))
        cur.execute(
            """
            INSERT INTO plans (
                user_id, start_date, end_date, daily_calorie_target,
                protein_g, carbs_g, fat_g, status, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                datetime.now().isoformat(timespec="seconds"),
            ),
        )
        plan_id = cur.lastrowid
        for day in plan_data["plan_days"]:
            workout = day["workout"]
            rest_day = 1 if workout.lower() == "rest day" else 0
            cur.execute(
                """
                INSERT INTO plan_days (
                    plan_id, date, calorie_target, protein_g, carbs_g, fat_g, workout_plan, rest_day
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    plan_id,
                    day["date"],
                    plan_data["calorie_target"],
                    plan_data["macros"]["protein_g"],
                    plan_data["macros"]["carbs_g"],
                    plan_data["macros"]["fat_g"],
                    workout,
                    rest_day,
                ),
            )
        conn.commit()

    return {"messages": [AIMessage(content="Plan updated and saved.")]}


def build_graph() -> StateGraph:
    builder = StateGraph(AgentState)
   
    builder.add_node("assistant", assistant)
    builder.add_node("tools", ToolNode(tools))
    builder.add_node("human_feedback", human_feedback)
    builder.add_node("apply_plan", apply_plan)

    
    builder.add_edge(START, "assistant")
    builder.add_conditional_edges(
        "assistant",
        # If the latest message (result) from assistant is a tool call -> tools_condition routes to tools
        # If the latest message (result) from assistant is a not a tool call -> tools_condition routes to END
        tools_condition,
    )
    builder.add_conditional_edges("tools", route_after_tools, ["assistant", "human_feedback"])
    builder.add_edge("human_feedback", "apply_plan")
    builder.add_edge("apply_plan", "assistant")
    memory = MemorySaver()
    return builder.compile(checkpointer=memory, interrupt_before=["human_feedback"])


def run_cli() -> None:
    graph = build_graph()
    print("Basic AI Trainer agent. Type 'exit' to quit.\n")


    while True:
        user_input = input("You: ").strip()
        if user_input.lower() in {"exit", "quit"}:
            break
    
        config = {"configurable": {"thread_id": "cli"}}
        state = graph.invoke({"messages": [HumanMessage(content=user_input)]}, config)
        graph_state = graph.get_state(config)
        if graph_state.next and "human_feedback" in graph_state.next:
            plan_text = None
            for message in reversed(state["messages"]):
                if isinstance(message, ToolMessage):
                    plan_text = message.content
                    break
            if plan_text:
                print("\nAssistant (proposed plan):", plan_text, "\n")
            approval = input("Do you like this plan more than your current one? (yes/no): ").strip().lower()
            approve_plan = approval.startswith("y")
            graph.update_state(config, {"approve_plan": approve_plan}, as_node="human_feedback")
            state = graph.invoke(None, config)
        print("\nAssistant:", state["messages"][-1].content, "\n")


def main() -> None:
    
    parser = argparse.ArgumentParser(description="Run the basic AI Trainer agent.")
    _ = parser.parse_args()
    run_cli()


if __name__ == "__main__":
    main()