from __future__ import annotations

from typing import Any, Dict, List


def _is_cardio_exercise(name: str) -> bool:
    lower = name.lower()
    keywords = [
        "run",
        "jog",
        "bike",
        "cycle",
        "rowing",
        "rower",
        "elliptical",
        "swim",
        "walk",
        "cardio",
        "hiit",
        "treadmill",
    ]
    return any(keyword in lower for keyword in keywords)


def _estimate_met_for_exercise(name: str) -> float:
    lower = name.lower()
    if any(k in lower for k in ["run", "jog", "treadmill"]):
        return 9.0
    if any(k in lower for k in ["bike", "cycle"]):
        return 7.0
    if "row" in lower:
        return 7.0
    if any(k in lower for k in ["elliptical", "swim"]):
        return 6.5
    if "walk" in lower:
        return 4.0
    if "hiit" in lower:
        return 10.0
    return 6.0


def _estimate_workout_calories(
    weight_kg: float,
    exercises: List[Dict[str, Any]],
    duration_min: int,
) -> int:
    if weight_kg <= 0:
        return 0
    if not exercises:
        met = 6.0
        return int((met * 3.5 * weight_kg / 200) * max(1, duration_min))
    total = 0.0
    fallback_per_ex = max(1, int(duration_min / max(1, len(exercises))))
    for exercise in exercises:
        if not isinstance(exercise, dict):
            continue
        name = str(exercise.get("name") or exercise.get("exercise") or "").strip()
        minutes = exercise.get("duration_min")
        if minutes is None:
            minutes = fallback_per_ex
        if _is_cardio_exercise(name):
            met = _estimate_met_for_exercise(name)
        else:
            met = 6.0
        total += (met * 3.5 * weight_kg / 200) * max(1, int(minutes))
    return int(total)
