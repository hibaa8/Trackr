from __future__ import annotations

SELECT_USER_PROFILE = """
SELECT id, name, birthdate, height_cm, weight_kg, gender FROM users WHERE id = ?
"""

SELECT_USER_PREFS = """
SELECT weekly_weight_change_kg, activity_level, goal_type, target_weight_kg FROM user_preferences WHERE user_id = ?
"""

SELECT_ACTIVE_PLAN = """
SELECT id, start_date, end_date, daily_calorie_target, protein_g, carbs_g, fat_g, status
FROM plans
WHERE user_id = ? AND status = 'active'
ORDER BY start_date DESC
LIMIT 1
"""

SELECT_PLAN_TEMPLATE = """
SELECT id, cycle_length_days, timezone, default_calories,
       default_protein_g, default_carbs_g, default_fat_g
FROM plan_templates
WHERE plan_id = ?
LIMIT 1
"""

SELECT_TEMPLATE_DAYS = """
SELECT day_index, workout_json, calorie_delta
FROM plan_template_days
WHERE template_id = ?
ORDER BY day_index
"""

SELECT_PLAN_OVERRIDES = """
SELECT date, override_type, workout_json, calorie_target, calorie_delta
FROM plan_overrides
WHERE plan_id = ? AND date BETWEEN ? AND ?
ORDER BY date
"""

SELECT_PLAN_CHECKPOINTS = """
SELECT checkpoint_week, expected_weight_kg, min_weight_kg, max_weight_kg
FROM plan_checkpoints
WHERE plan_id = ?
ORDER BY checkpoint_week
"""
