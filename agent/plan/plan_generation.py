from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional

from agent.db.connection import get_db_conn
from agent.db import queries


def _resolve_age(age_years: Optional[int]) -> int:
    if age_years:
        return int(age_years)
    return 30


def _bmr_mifflin(weight_kg: float, height_cm: float, age: int, gender: Optional[str]) -> float:
    base = 10 * weight_kg + 6.25 * height_cm - 5 * age
    if (gender or "").lower().startswith("f"):
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


def _round_to_nearest_5(value: float) -> int:
    return int(5 * round(value / 5))


def _bmi(weight_kg: float, height_cm: float) -> float:
    height_m = height_cm / 100.0
    if height_m <= 0:
        return 0.0
    return weight_kg / (height_m ** 2)


def _calorie_minimum(goal_type: str, weight_kg: float) -> Optional[int]:
    if goal_type == "maintain":
        return 1500 if weight_kg < 60 else 1800
    return None


def _macro_targets(calories: int, weight_kg: float, goal_type: str) -> Dict[str, int]:
    if goal_type == "gain":
        protein_per_kg = 1.8
        protein_min = 1.6
        protein_max = 2.2
    elif goal_type == "maintain":
        protein_per_kg = 1.6
        protein_min = 1.4
        protein_max = 2.0
    else:
        protein_per_kg = 1.6
        protein_min = 1.4
        protein_max = 2.2

    protein_g = weight_kg * protein_per_kg
    protein_g = max(weight_kg * 1.2, protein_g)
    protein_g = min(weight_kg * 2.4, protein_g)
    protein_g = min(max(protein_g, weight_kg * protein_min), weight_kg * protein_max)

    fat_g = weight_kg * 0.8
    fat_g = min(max(fat_g, weight_kg * 0.6), weight_kg * 1.0)

    min_fat_for_20pct = (0.2 * calories) / 9.0
    fat_g = max(fat_g, min_fat_for_20pct)

    protein_cals = protein_g * 4
    fat_cals = fat_g * 9
    remaining = calories - (protein_cals + fat_cals)
    if remaining < 0:
        fat_g = max(weight_kg * 0.6, (0.2 * calories) / 9.0)
        fat_cals = fat_g * 9
        remaining = calories - (protein_cals + fat_cals)
        if remaining < 0:
            protein_g = max(weight_kg * 1.2, (calories - fat_cals) / 4)
            protein_cals = protein_g * 4
            remaining = calories - (protein_cals + fat_cals)

    carbs_g = max(0.0, remaining / 4)

    protein_g = _round_to_nearest_5(protein_g)
    fat_g = _round_to_nearest_5(fat_g)
    carbs_g = _round_to_nearest_5(carbs_g)

    total_cals = protein_g * 4 + carbs_g * 4 + fat_g * 9
    delta = calories - total_cals
    if abs(delta) > 50:
        carbs_adjust = _round_to_nearest_5(delta / 4)
        carbs_g = max(0, carbs_g + carbs_adjust)

    return {
        "protein_g": int(protein_g),
        "carbs_g": int(carbs_g),
        "fat_g": int(fat_g),
    }


def validate_macros(calories: int, protein_g: int, carbs_g: int, fat_g: int) -> bool:
    if min(protein_g, carbs_g, fat_g) < 0:
        return False
    total_cals = protein_g * 4 + carbs_g * 4 + fat_g * 9
    return abs(total_cals - calories) <= 50


def validate_protein(weight_kg: float, protein_g: int, goal_type: str) -> bool:
    per_kg = protein_g / max(weight_kg, 1)
    if per_kg < 1.2 or per_kg > 2.4:
        return False
    if goal_type == "gain":
        return 1.6 <= per_kg <= 2.2
    if goal_type == "maintain":
        return 1.4 <= per_kg <= 2.0
    return True


def validate_workout_volume(goal_type: str, sessions: int, sets_per_week: Optional[int] = None) -> bool:
    if goal_type == "gain":
        return 4 <= sessions <= 6
    if goal_type == "maintain":
        return 3 <= sessions <= 4
    return True


def _repair_macros(calories: int, weight_kg: float, goal_type: str) -> Dict[str, int]:
    macros = _macro_targets(calories, weight_kg, goal_type)
    if not validate_macros(calories, macros["protein_g"], macros["carbs_g"], macros["fat_g"]):
        macros = _macro_targets(calories, weight_kg, goal_type)
    if not validate_protein(weight_kg, macros["protein_g"], goal_type):
        macros = _macro_targets(calories, weight_kg, goal_type)
    return macros


def _format_plan_text(plan_data: Dict[str, Any]) -> str:
    lines = [
        f"Plan length: {plan_data['days']} days",
        f"Daily calories (start): {plan_data['calorie_target']} ({plan_data.get('calorie_formula', 'formula unavailable')})",
        (
            "Macros (g): "
            f"P{plan_data['macros']['protein_g']} "
            f"C{plan_data['macros']['carbs_g']} "
            f"F{plan_data['macros']['fat_g']} "
            "(protein+carbs*4 + fat*9 ≈ calories)"
        ),
        f"Progression rule: {plan_data.get('progression_rule', 'double progression')}",
        f"Check-in rule: {plan_data.get('check_in_rule', 'Check-in every 2 weeks and adjust based on trend.')}",
        (
            "No auto calorie decrement for gain/maintain; adjust ±100–150 based on 2–3 week trends."
            if plan_data.get("decrement", 0) == 0
            else f"Adjust calories every 14 days by -{plan_data['decrement']} (if applicable)."
        ),
        "Workout schedule:",
    ]
    requested_days = plan_data.get("requested_days")
    if requested_days and requested_days != plan_data["days"]:
        lines.insert(
            1,
            f"Requested timeframe: {requested_days} days; adjusted to {plan_data['days']} days for a safer pace.",
        )
    if plan_data["checkpoints"]:
        first_checkpoint = plan_data["checkpoints"][0]
        lines.append(
            f"Current weight: {plan_data['current_weight_kg']:.1f} kg. "
            f"Expected by week {first_checkpoint['week']}: {first_checkpoint['expected_weight_kg']:.1f} kg "
            f"(range {first_checkpoint['min_weight_kg']:.1f}–{first_checkpoint['max_weight_kg']:.1f})."
        )
    for day in plan_data["plan_days"]:
        lines.append(f"{day['date']}: {day['workout']} | {day['calorie_target']} kcal")
    if len(plan_data.get("plan_days", [])) in {7, 14} and plan_data.get("end_date"):
        lines.append(f"Repeat this template until {plan_data['end_date']}.")
    if plan_data["target_weight_kg"] is not None:
        lines.append(f"Target weight: {plan_data['target_weight_kg']:.1f} kg.")
    if plan_data["checkpoints"]:
        lines.append("Expected weight checkpoints (every 2 weeks):")
        for checkpoint in plan_data["checkpoints"]:
            lines.append(
                f"Week {checkpoint['week']}: {checkpoint['expected_weight_kg']:.1f} kg "
                f"(range {checkpoint['min_weight_kg']:.1f}–{checkpoint['max_weight_kg']:.1f})"
            )
    lines.append(
        "If you are unsure how to perform any exercise, ask and I can explain it and share a video."
    )
    return "\n".join(lines)


def calc_targets(
    user_row: tuple,
    pref_row: Optional[tuple],
    goal_override: Optional[str] = None,
) -> Dict[str, Any]:
    birthdate, height_cm, weight_kg, gender, age_years = user_row
    weekly_delta = pref_row[0] if pref_row else -0.5
    activity_level = pref_row[1] if pref_row else "moderate"
    goal_type = goal_override or (pref_row[2] if pref_row else "lose")
    if goal_type == "lose":
        weekly_delta = -abs(weekly_delta) if weekly_delta is not None else -0.5
    elif goal_type == "gain":
        weekly_delta = abs(weekly_delta) if weekly_delta is not None else 0.25
    elif goal_type == "maintain":
        weekly_delta = 0.0

    age = _resolve_age(age_years)
    bmr = _bmr_mifflin(weight_kg, height_cm, age, gender)
    tdee = bmr * _activity_multiplier(activity_level)
    calorie_target = int(tdee)
    calorie_formula = f"TDEE {int(tdee)} kcal"

    if goal_type == "gain":
        is_underweight = _bmi(weight_kg, height_cm) < 18.5
        very_active = activity_level in {"active", "very_active"}
        surplus = 200
        if is_underweight or very_active:
            surplus = 350
        surplus = min(surplus, 500)
        calorie_target = int(tdee + surplus)
        calorie_formula = f"TDEE {int(tdee)} + surplus {surplus}"
    elif goal_type == "maintain":
        calorie_target = int(tdee)
        calorie_formula = f"TDEE {int(tdee)} (maintenance)"
    else:
        daily_delta = (weekly_delta * 7700) / 7.0
        calorie_target = int(max(1200, tdee + daily_delta))
        calorie_formula = f"TDEE {int(tdee)} + daily_delta {int(daily_delta)}"

    min_cals = _calorie_minimum(goal_type, weight_kg)
    if min_cals:
        calorie_target = max(calorie_target, min_cals)
    if goal_type == "gain":
        calorie_target = max(calorie_target, int(tdee))

    macros = _repair_macros(calorie_target, weight_kg, goal_type)

    step_goal = 10000 if goal_type == "lose" else 8000
    return {
        "goal_type": goal_type,
        "calorie_target": calorie_target,
        "macros": macros,
        "step_goal": step_goal,
        "tdee": int(tdee),
        "calorie_formula": calorie_formula,
    }


def compute_weight_checkpoints(
    user_row: tuple,
    pref_row: Optional[tuple],
    requested_days: int,
    target_weight_override: Optional[float],
    goal_override: Optional[str] = None,
    use_pref_target_weight: bool = True,
) -> Dict[str, Any]:
    weight_kg = user_row[2]
    goal_type = goal_override or (pref_row[2] if pref_row else "lose")
    target_weight = target_weight_override
    if use_pref_target_weight and target_weight is None:
        target_weight = pref_row[3] if pref_row else None
    if target_weight is None:
        if goal_type in {"gain", "maintain"}:
            planned_days = requested_days
            total_weeks = max(1, int((planned_days + 6) / 7))
            num_checkpoints = max(1, int((total_weeks + 1) / 2))
            rate_per_week = 0.002 if goal_type == "gain" else 0.0
            band = 0.01 * weight_kg
            checkpoints = []
            for i in range(1, num_checkpoints + 1):
                week = i * 2
                expected = weight_kg * (1 + rate_per_week * week)
                checkpoints.append(
                    {
                        "week": week,
                        "expected_weight_kg": expected,
                        "min_weight_kg": expected - band,
                        "max_weight_kg": expected + band,
                    }
                )
            return {"checkpoints": checkpoints, "recommended_weeks": None, "planned_days": planned_days}
        return {"checkpoints": [], "recommended_weeks": None, "planned_days": requested_days}

    delta = abs(weight_kg - target_weight)
    if delta == 0:
        return {"checkpoints": [], "recommended_weeks": None, "planned_days": requested_days}

    min_loss = 0.005 * weight_kg
    max_loss = 0.01 * weight_kg
    requested_weeks = max(1, int((requested_days + 6) / 7))
    req_loss = delta / requested_weeks

    if req_loss > max_loss:
        recommended_weeks = int((delta / max_loss) + 0.999)
    elif req_loss < min_loss:
        recommended_weeks = int((delta / min_loss) + 0.999)
    else:
        recommended_weeks = requested_weeks

    if requested_days >= 60 and recommended_weeks < 12:
        recommended_weeks = 12

    planned_days = max(requested_days, recommended_weeks * 7)
    k = int((recommended_weeks + 1) / 2 + 0.999)
    loss_per_2w = delta / k
    band = 0.01 * weight_kg
    checkpoints = []
    for i in range(1, k + 1):
        expected = weight_kg - (loss_per_2w * i) if goal_type == "lose" else weight_kg + (loss_per_2w * i)
        checkpoints.append(
            {
                "week": i * 2,
                "expected_weight_kg": expected,
                "min_weight_kg": expected - band,
                "max_weight_kg": expected + band,
            }
        )
    return {
        "checkpoints": checkpoints,
        "recommended_weeks": recommended_weeks,
        "planned_days": planned_days,
    }


def generate_workout_plan(
    goal: str,
    days_per_week: int = 5,
) -> List[str]:
    warmup = "Warm-up 5–10 min + ramp-up sets."
    progression = (
        "Progression: double progression (add reps to top of range, then add load)."
    )
    strength_template = (
        "Full Body Strength: Squat 3x6–10 @RPE7, Bench 3x6–10 @RPE7, "
        "Row 3x8–12 @RPE7, RDL 2x8–12 @RPE7, Plank 3x30–45s. "
    )
    cardio_zone2 = "Zone 2 Cardio: 25–40 min @RPE5."
    core = "Core: Dead bug 3x10/side, Pallof press 3x10/side."

    if goal == "gain":
        week_template = [
            f"Upper A: Bench 4x6–10 @RPE7–8, Row 4x6–10 @RPE7–8, "
            f"OHP 3x8–12 @RPE7, Pull-down 3x8–12 @RPE7. {warmup} {progression}",
            f"Lower A: Squat 4x6–10 @RPE7–8, RDL 3x8–12 @RPE7, "
            f"Lunge 3x10/side @RPE7, Calf raise 3x12–15 @RPE7. {warmup} {progression}",
            "Rest / Mobility 10 min.",
            f"Upper B: Incline bench 4x6–10 @RPE7–8, Row 4x6–10 @RPE7–8, "
            f"DB press 3x8–12 @RPE7, Curl 3x10–12 @RPE7. {warmup} {progression}",
            f"Lower B: Deadlift 3x5–8 @RPE7–8, Leg press 3x10–12 @RPE7, "
            f"Ham curl 3x10–12 @RPE7, Calf raise 3x12–15 @RPE7. {warmup} {progression}",
            "Rest / Mobility 10 min.",
            "Rest / Mobility 10 min.",
        ]
    elif goal == "maintain":
        week_template = [
            f"{strength_template} {warmup} {progression}",
            f"{cardio_zone2} Mobility 10 min.",
            f"{strength_template} {warmup} {progression}",
            f"{cardio_zone2} {core} Mobility 10 min.",
            "Rest / active recovery.",
            "Rest / active recovery.",
            "Rest / active recovery.",
        ]
    else:
        week_template = [
            f"{strength_template} {warmup} {progression}",
            f"{cardio_zone2} Mobility 10 min.",
            f"{strength_template} {warmup} {progression}",
            f"{cardio_zone2} {core} Mobility 10 min.",
            f"{strength_template} {warmup} {progression}",
            "Rest / active recovery.",
            "Rest / active recovery.",
        ]

    return week_template[:days_per_week] + week_template[days_per_week:]


def _build_plan_data(
    user_id: int,
    days: int,
    target_loss_lbs: Optional[float],
    goal_override: Optional[str] = None,
) -> Dict[str, Any]:
    def _normalize_pref(value: Any) -> Optional[str]:
        if value is None:
            return None
        text = str(value).strip()
        if not text:
            return None
        if text.lower() in {"none", "no preference", "n/a", "na", "skip"}:
            return None
        return text

    def _extract_days_per_week(value: Optional[str]) -> Optional[int]:
        if not value:
            return None
        digits = "".join(ch if ch.isdigit() else " " for ch in value).split()
        if not digits:
            return None
        try:
            parsed = int(digits[0])
        except ValueError:
            return None
        if 2 <= parsed <= 6:
            return parsed
        return None

    requested_days = days
    with get_db_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT birthdate, height_cm, weight_kg, gender, age_years FROM users WHERE id = ?",
            (user_id,),
        )
        user_row = cur.fetchone()
        if not user_row:
            return {"error": "User not found."}
        cur.execute(queries.SELECT_USER_PREFS, (user_id,))
        pref_row = cur.fetchone()
        try:
            cur.execute(
                """
                SELECT workout_preferences, muscle_group_preferences, sports_preferences, location_context
                FROM user_preferences
                WHERE user_id = ?
                LIMIT 1
                """,
                (user_id,),
            )
            context_row = cur.fetchone()
        except Exception:
            context_row = None

    targets = calc_targets(user_row, pref_row, goal_override=goal_override)
    workout_preference_text = _normalize_pref(context_row[0]) if context_row else None
    muscle_group_preferences = _normalize_pref(context_row[1]) if context_row else None
    sports_preferences = _normalize_pref(context_row[2]) if context_row else None
    location_context = _normalize_pref(context_row[3]) if context_row else None
    target_weight_override = None
    if target_loss_lbs:
        target_weight_override = user_row[2] - (target_loss_lbs * 0.453592)
    weight_info = compute_weight_checkpoints(
        user_row,
        pref_row,
        days,
        target_weight_override,
        goal_override=goal_override,
        use_pref_target_weight=target_loss_lbs is not None,
    )
    days = weight_info["planned_days"]
    if targets["goal_type"] == "gain":
        days_per_week = 5
    elif targets["goal_type"] == "maintain":
        days_per_week = 4
    else:
        days_per_week = 4
    preferred_days = _extract_days_per_week(workout_preference_text)
    if preferred_days is not None:
        days_per_week = preferred_days
    if not validate_workout_volume(targets["goal_type"], days_per_week):
        days_per_week = 5 if targets["goal_type"] == "gain" else 4
    workout_cycle = generate_workout_plan(targets["goal_type"], days_per_week=days_per_week)

    start = date.today()
    plan_days = []
    decrement = 0
    if days > 14 and targets["goal_type"] == "lose":
        decrement = 300
    for i in range(days):
        day = start + timedelta(days=i)
        workout = workout_cycle[i % len(workout_cycle)]
        if muscle_group_preferences or sports_preferences:
            lowered = workout.lower()
            if "rest" not in lowered and "mobility" not in lowered:
                context_bits: List[str] = []
                if muscle_group_preferences:
                    context_bits.append(f"prioritize {muscle_group_preferences}")
                if sports_preferences:
                    context_bits.append(f"support {sports_preferences}")
                if context_bits:
                    workout = f"{workout} Preference context: {'; '.join(context_bits)}."
        block_index = i // 14
        calorie_target = max(1200, targets["calorie_target"] - (block_index * decrement))
        plan_days.append(
            {
                "date": day.isoformat(),
                "workout": workout,
                "calorie_target": calorie_target,
            }
        )

    if targets["goal_type"] == "gain":
        check_in_rule = (
            "Check-in every 2 weeks: if gain <0.1%/week → +100–150 kcal; "
            "if gain >0.5%/week → −100–150 kcal; if strength up and weight flat, hold."
        )
    elif targets["goal_type"] == "maintain":
        check_in_rule = (
            "Check-in every 2–4 weeks: if weight drifts >1% → adjust ±100 kcal; "
            "if low energy, reduce volume 10–20% before calories."
        )
    else:
        check_in_rule = "Check-in every 2 weeks and adjust calories based on trend."

    plan_data = {
        "user_id": user_id,
        "goal_type": targets["goal_type"],
        "current_weight_kg": user_row[2],
        "target_weight_kg": target_weight_override,
        "start_date": start.isoformat(),
        "end_date": (start + timedelta(days=days - 1)).isoformat(),
        "days": days,
        "requested_days": requested_days,
        "calorie_target": targets["calorie_target"],
        "macros": targets["macros"],
        "step_goal": targets["step_goal"],
        "decrement": decrement,
        "checkpoints": weight_info["checkpoints"],
        "recommended_weeks": weight_info["recommended_weeks"],
        "plan_days": plan_days,
        "tdee": targets.get("tdee"),
        "calorie_formula": targets.get("calorie_formula"),
        "progression_rule": "double progression",
        "check_in_rule": check_in_rule,
        "user_context": {
            "location_context": location_context,
            "workout_preference": workout_preference_text,
            "muscle_group_preferences": muscle_group_preferences,
            "sports_preferences": sports_preferences,
        },
    }
    if not validate_macros(
        plan_data["calorie_target"],
        plan_data["macros"]["protein_g"],
        plan_data["macros"]["carbs_g"],
        plan_data["macros"]["fat_g"],
    ):
        plan_data["macros"] = _repair_macros(plan_data["calorie_target"], user_row[2], targets["goal_type"])
    if not validate_protein(user_row[2], plan_data["macros"]["protein_g"], targets["goal_type"]):
        plan_data["macros"] = _repair_macros(plan_data["calorie_target"], user_row[2], targets["goal_type"])
    return plan_data
