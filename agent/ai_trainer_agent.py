#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sqlite3
from datetime import date, datetime, timedelta
from typing import List

from typing_extensions import TypedDict
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage, BaseMessage
from langchain_core.tools import tool
from langgraph.graph import StateGraph, START, END, MessagesState
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


@tool("get_current_plan_summary")
def get_current_plan_summary(user_id: int) -> str:
    """Return a basic plan summary for the given user_id."""
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT start_date, end_date, daily_calorie_target, protein_g, carbs_g, fat_g, status
            FROM plans
            WHERE user_id = ?
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
                    SELECT id FROM plans WHERE user_id = ? ORDER BY start_date DESC LIMIT 1
                )
                ORDER BY date
                LIMIT 7
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


@tool("generate_plan")
def generate_plan(user_id: int, days: int = 14) -> str:
    """Generate a simple 14-60 day plan based on user profile and preferences."""
    if days < 14:
        days = 14
    if days > 60:
        days = 60

    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT birthdate, height_cm, weight_kg, gender FROM users WHERE id = ?",
            (user_id,),
        )
        user_row = cur.fetchone()
        if not user_row:
            return "User not found."
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
    lines = [
        f"Plan length: {days} days",
        f"Daily calories: {calorie_target}",
        "Workout schedule:",
    ]
    for i in range(days):
        day = start + timedelta(days=i)
        workout = workout_cycle[i % len(workout_cycle)]
        lines.append(f"{day.isoformat()}: {workout}")

    return "\n".join(lines)

def assistant(state: MessagesState):
    return {"messages": [llm_with_tools.invoke([sys_msg] + state["messages"])]}


tools = [get_current_plan_summary, search_web, generate_plan]
llm = ChatOpenAI(model="gpt-4o", temperature=0)
llm_with_tools = llm.bind_tools(tools, parallel_tool_calls=False)

def build_graph() -> StateGraph:
    builder = StateGraph(MessagesState)
   
    builder.add_node("assistant", assistant)
    builder.add_node("tools", ToolNode(tools))

    
    builder.add_edge(START, "assistant")
    builder.add_conditional_edges(
        "assistant",
        # If the latest message (result) from assistant is a tool call -> tools_condition routes to tools
        # If the latest message (result) from assistant is a not a tool call -> tools_condition routes to END
        tools_condition,
    )
    builder.add_edge("tools", "assistant")
    return builder.compile()


def run_cli() -> None:
    graph = build_graph()
    print("Basic AI Trainer agent. Type 'exit' to quit.\n")


    while True:
        user_input = input("You: ").strip()
        if user_input.lower() in {"exit", "quit"}:
            break
    
        state = graph.invoke({"messages": [HumanMessage(content=user_input)]})
        print("\nAssistant:", state["messages"][-1].content, "\n")


def main() -> None:
    
    parser = argparse.ArgumentParser(description="Run the basic AI Trainer agent.")
    _ = parser.parse_args()
    run_cli()


if __name__ == "__main__":
    main()