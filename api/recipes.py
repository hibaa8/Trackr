import os

from langchain_tavily import TavilySearch

from api._shared import json_response, read_json


def handler(request):
    if request.method != "POST":
        return json_response({"error": "Method not allowed"}, status=405)

    payload = read_json(request)
    if payload is None:
        return json_response({"error": "Invalid JSON payload."}, status=400)

    ingredients = payload.get("ingredients") or ""
    cuisine = payload.get("cuisine") or ""
    prep_time = payload.get("prep_time") or ""
    dietary = payload.get("dietary") or ""

    if not os.environ.get("TAVILY_API_KEY"):
        return json_response({"recipes": [], "deals": []})

    recipe_query = f"{cuisine} {dietary} recipes with {ingredients} prep time {prep_time} minutes"
    tavily = TavilySearch(max_results=6)
    recipe_data = tavily.invoke({"query": recipe_query})
    recipe_results = recipe_data.get("results", recipe_data)
    recipes = []
    for doc in recipe_results:
        if not doc.get("url"):
            continue
        recipes.append(
            {
                "title": doc.get("title") or "Recipe idea",
                "url": doc.get("url"),
                "meta": doc.get("content") or "",
            }
        )

    deals_query = "healthy food chain deals salad bowl discount"
    deals_data = tavily.invoke({"query": deals_query})
    deals_results = deals_data.get("results", deals_data)
    deals = []
    for doc in deals_results:
        if not doc.get("url"):
            continue
        deals.append(
            {
                "title": doc.get("title") or "Healthy food deal",
                "url": doc.get("url"),
                "meta": doc.get("content") or "",
            }
        )

    return json_response({"recipes": recipes, "deals": deals})
