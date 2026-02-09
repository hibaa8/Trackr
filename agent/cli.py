from __future__ import annotations

import argparse
import json
import os

from dotenv import load_dotenv

from langchain_core.messages import HumanMessage, ToolMessage

from agent.config.constants import DEFAULT_USER_ID
from agent.graph.graph import build_graph, _preload_session_cache
from agent.rag.rag import _build_rag_index


def run_cli() -> None:
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    load_dotenv(dotenv_path=os.path.join(root_dir, ".env"))
    load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), ".env"))
    graph = build_graph()
    print("Basic AI Trainer agent. Type 'exit' to quit.\n")

    config = {"configurable": {"thread_id": "cli"}}
    preload = _preload_session_cache(DEFAULT_USER_ID)
    _build_rag_index()

    while True:
        user_input = input("You: ").strip()
        if user_input.lower() in {"exit", "quit"}:
            break

        state = graph.invoke(
            {
                "messages": [HumanMessage(content=user_input)],
                "context": preload.get("context"),
                "active_plan": preload.get("active_plan"),
            },
            config,
        )
        graph_state = graph.get_state(config)
        if graph_state.next and "human_feedback" in graph_state.next:
            plan_text = None
            proposed_plan = None
            for message in reversed(state["messages"]):
                if isinstance(message, ToolMessage):
                    try:
                        payload = json.loads(message.content)
                    except json.JSONDecodeError:
                        payload = None
                    if isinstance(payload, dict):
                        plan_text = payload.get("plan_text")
                        proposed_plan = payload.get("plan_data")
                    else:
                        plan_text = message.content
                    break
            if plan_text:
                print("\nAssistant (proposed plan):", plan_text, "\n")
            approval = input("Do you like this plan more than your current one? (yes/no): ").strip().lower()
            approve_plan = approval.startswith("y")
            graph.update_state(
                config,
                {"approve_plan": approve_plan, "proposed_plan": proposed_plan},
                as_node="human_feedback",
            )
            state = graph.invoke(None, config)
        print("\nAssistant:", state["messages"][-1].content, "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the basic AI Trainer agent.")
    _ = parser.parse_args()
    run_cli()


if __name__ == "__main__":
    main()
