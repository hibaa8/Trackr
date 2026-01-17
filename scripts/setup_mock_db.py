#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sqlite3
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class UserSeed:
    id: int
    email: str
    name: str
    gender: str
    birthdate: str
    height_cm: float
    weight_kg: float


SCHEMA_SQL = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    gender TEXT,
    birthdate TEXT,
    height_cm REAL,
    weight_kg REAL,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS user_preferences (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    goal_type TEXT NOT NULL,
    target_weight_kg REAL,
    weekly_weight_change_kg REAL,
    activity_level TEXT,
    dietary_preferences TEXT,
    workout_preferences TEXT,
    timezone TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
);

CREATE TABLE IF NOT EXISTS plans (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL,
    daily_calorie_target INTEGER NOT NULL,
    protein_g INTEGER NOT NULL,
    carbs_g INTEGER NOT NULL,
    fat_g INTEGER NOT NULL,
    status TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
);

CREATE TABLE IF NOT EXISTS plan_checkpoints (
    id INTEGER PRIMARY KEY,
    plan_id INTEGER NOT NULL,
    checkpoint_week INTEGER NOT NULL,
    expected_weight_kg REAL NOT NULL,
    min_weight_kg REAL NOT NULL,
    max_weight_kg REAL NOT NULL,
    FOREIGN KEY (plan_id) REFERENCES plans (id)
);

CREATE TABLE IF NOT EXISTS plan_templates (
    id INTEGER PRIMARY KEY,
    plan_id INTEGER NOT NULL,
    cycle_length_days INTEGER NOT NULL,
    timezone TEXT,
    default_calories INTEGER NOT NULL,
    default_protein_g INTEGER NOT NULL,
    default_carbs_g INTEGER NOT NULL,
    default_fat_g INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (plan_id) REFERENCES plans (id)
);

CREATE TABLE IF NOT EXISTS plan_template_days (
    id INTEGER PRIMARY KEY,
    template_id INTEGER NOT NULL,
    day_index INTEGER NOT NULL,
    workout_json TEXT,
    calorie_delta INTEGER,
    notes TEXT,
    FOREIGN KEY (template_id) REFERENCES plan_templates (id)
);

CREATE TABLE IF NOT EXISTS plan_overrides (
    id INTEGER PRIMARY KEY,
    plan_id INTEGER NOT NULL,
    date TEXT NOT NULL,
    override_type TEXT NOT NULL,
    workout_json TEXT,
    calorie_target INTEGER,
    calorie_delta INTEGER,
    reason TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (plan_id) REFERENCES plans (id)
);

CREATE TABLE IF NOT EXISTS workout_sessions (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    date TEXT NOT NULL,
    workout_type TEXT NOT NULL,
    duration_min INTEGER NOT NULL,
    calories_burned INTEGER,
    notes TEXT,
    completed INTEGER NOT NULL,
    source TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
);

CREATE TABLE IF NOT EXISTS meal_logs (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    logged_at TEXT NOT NULL,
    photo_path TEXT,
    description TEXT,
    calories INTEGER NOT NULL,
    protein_g INTEGER NOT NULL,
    carbs_g INTEGER NOT NULL,
    fat_g INTEGER NOT NULL,
    confidence REAL,
    confirmed INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
);

CREATE TABLE IF NOT EXISTS health_activity (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    date TEXT NOT NULL,
    steps INTEGER NOT NULL,
    calories_burned INTEGER NOT NULL,
    workouts_summary TEXT,
    source TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
);

CREATE TABLE IF NOT EXISTS checkins (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    checkin_date TEXT NOT NULL,
    weight_kg REAL,
    mood TEXT,
    notes TEXT,
    FOREIGN KEY (user_id) REFERENCES users (id)
);

CREATE TABLE IF NOT EXISTS reminders (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    reminder_type TEXT NOT NULL,
    scheduled_at TEXT NOT NULL,
    status TEXT NOT NULL,
    channel TEXT NOT NULL,
    related_plan_override_id INTEGER,
    FOREIGN KEY (user_id) REFERENCES users (id),
    FOREIGN KEY (related_plan_override_id) REFERENCES plan_overrides (id)
);

CREATE TABLE IF NOT EXISTS ai_suggestions (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    suggestion_type TEXT NOT NULL,
    rationale TEXT NOT NULL,
    suggestion_text TEXT NOT NULL,
    status TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
);

CREATE TABLE IF NOT EXISTS streaks (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    streak_type TEXT NOT NULL,
    current_count INTEGER NOT NULL,
    best_count INTEGER NOT NULL,
    last_date TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
);

CREATE TABLE IF NOT EXISTS points (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    points INTEGER NOT NULL,
    reason TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
);

CREATE TABLE IF NOT EXISTS calendar_blocks (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    start_at TEXT NOT NULL,
    end_at TEXT NOT NULL,
    title TEXT NOT NULL,
    source TEXT NOT NULL,
    status TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
);
"""


def ensure_db_path(db_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)


def reset_db(db_path: Path) -> None:
    if db_path.exists():
        db_path.unlink()


def create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA_SQL)
    conn.commit()


def iso_dt(dt: datetime) -> str:
    return dt.replace(microsecond=0).isoformat()


def iso_date(d: date) -> str:
    return d.isoformat()


def insert_many(conn: sqlite3.Connection, sql: str, rows: Iterable[tuple]) -> None:
    conn.executemany(sql, list(rows))


def seed_data(conn: sqlite3.Connection) -> None:
    now = datetime.now()
    today = date.today()

    users = [
        UserSeed(
            id=1,
            email="alex.rivera@example.com",
            name="Alex Rivera",
            gender="male",
            birthdate="1994-06-12",
            height_cm=180.3,
            weight_kg=88.4,
        ),
        UserSeed(
            id=2,
            email="jamie.chen@example.com",
            name="Jamie Chen",
            gender="female",
            birthdate="1990-02-28",
            height_cm=165.2,
            weight_kg=72.1,
        ),
    ]

    insert_many(
        conn,
        """
        INSERT INTO users (id, email, name, gender, birthdate, height_cm, weight_kg, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            (
                user.id,
                user.email,
                user.name,
                user.gender,
                user.birthdate,
                user.height_cm,
                user.weight_kg,
                iso_dt(now - timedelta(days=30)),
            )
            for user in users
        ],
    )

    insert_many(
        conn,
        """
        INSERT INTO user_preferences (
            user_id, goal_type, target_weight_kg, weekly_weight_change_kg,
            activity_level, dietary_preferences, workout_preferences, timezone, created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            (
                1,
                "lose",
                82.0,
                -0.5,
                "moderate",
                "high_protein,low_added_sugar",
                "strength_training,2x_cardio",
                "America/Los_Angeles",
                iso_dt(now - timedelta(days=27)),
            ),
            (
                2,
                "recomposition",
                70.0,
                -0.25,
                "light",
                "flexible,vegetarian",
                "pilates,walking",
                "America/New_York",
                iso_dt(now - timedelta(days=25)),
            ),
        ],
    )

    plan_start = today - timedelta(days=3)
    plan_end = plan_start + timedelta(days=6)

    insert_many(
        conn,
        """
        INSERT INTO plans (
            id, user_id, start_date, end_date, daily_calorie_target,
            protein_g, carbs_g, fat_g, status, created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            (
                1,
                1,
                iso_date(plan_start),
                iso_date(plan_end),
                2200,
                170,
                220,
                70,
                "active",
                iso_dt(now - timedelta(days=3)),
            ),
            (
                2,
                2,
                iso_date(plan_start),
                iso_date(plan_end),
                1900,
                130,
                200,
                60,
                "active",
                iso_dt(now - timedelta(days=3)),
            ),
        ],
    )

    workouts = [
        "Upper body strength",
        "Lower body strength",
        "Interval cardio",
        "Full body circuit",
        "Active recovery walk",
        "Yoga + core",
        "Rest day",
    ]
    insert_many(
        conn,
        """
        INSERT INTO plan_templates (
            id, plan_id, cycle_length_days, timezone, default_calories,
            default_protein_g, default_carbs_g, default_fat_g, created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            (
                1,
                1,
                7,
                "America/Los_Angeles",
                2200,
                170,
                220,
                70,
                iso_dt(now - timedelta(days=3)),
            ),
            (
                2,
                2,
                7,
                "America/New_York",
                1900,
                130,
                200,
                60,
                iso_dt(now - timedelta(days=3)),
            ),
        ],
    )
    template_day_rows = []
    for day_index in range(7):
        template_day_rows.append(
            (
                1,
                day_index,
                f'{{"label":"{workouts[day_index]}"}}',
                0,
                None,
            )
        )
        template_day_rows.append(
            (
                2,
                day_index,
                f'{{"label":"{"Pilates + walk" if workouts[day_index] != "Rest day" else "Rest day"}"}}',
                0,
                None,
            )
        )
    insert_many(
        conn,
        """
        INSERT INTO plan_template_days (
            template_id, day_index, workout_json, calorie_delta, notes
        )
        VALUES (?, ?, ?, ?, ?)
        """,
        template_day_rows,
    )

    workout_rows = [
        (
            1,
            iso_date(today - timedelta(days=2)),
            "Upper body strength",
            55,
            360,
            "Felt strong, added extra set on bench.",
            1,
            "manual",
        ),
        (
            1,
            iso_date(today - timedelta(days=1)),
            "Interval cardio",
            30,
            290,
            "Skipped the last interval due to time.",
            0,
            "manual",
        ),
        (
            1,
            iso_date(today),
            "Lower body strength",
            50,
            410,
            "Soreness in hamstrings, reduced load.",
            1,
            "healthkit",
        ),
        (
            2,
            iso_date(today - timedelta(days=2)),
            "Pilates",
            45,
            220,
            "Good mobility session.",
            1,
            "manual",
        ),
        (
            2,
            iso_date(today - timedelta(days=1)),
            "Walk",
            40,
            180,
            "Easy pace, short hills.",
            1,
            "healthkit",
        ),
    ]

    insert_many(
        conn,
        """
        INSERT INTO workout_sessions (
            user_id, date, workout_type, duration_min, calories_burned, notes, completed, source
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        workout_rows,
    )

    meal_rows = [
        (
            1,
            iso_dt(now - timedelta(hours=5)),
            "photos/alex_breakfast.jpg",
            "Greek yogurt, berries, granola",
            420,
            32,
            48,
            12,
            0.82,
            1,
        ),
        (
            1,
            iso_dt(now - timedelta(hours=1)),
            "photos/alex_lunch.jpg",
            "Chicken quinoa bowl",
            610,
            45,
            55,
            18,
            0.9,
            1,
        ),
        (
            1,
            iso_dt(now + timedelta(hours=2)),
            "photos/alex_snack.jpg",
            "Protein shake + banana",
            280,
            32,
            32,
            4,
            0.76,
            0,
        ),
        (
            2,
            iso_dt(now - timedelta(hours=6)),
            "photos/jamie_breakfast.jpg",
            "Overnight oats with almond butter",
            390,
            18,
            46,
            14,
            0.8,
            1,
        ),
        (
            2,
            iso_dt(now - timedelta(hours=2)),
            "photos/jamie_lunch.jpg",
            "Tofu stir fry with brown rice",
            540,
            28,
            64,
            16,
            0.88,
            1,
        ),
    ]

    insert_many(
        conn,
        """
        INSERT INTO meal_logs (
            user_id, logged_at, photo_path, description, calories, protein_g, carbs_g, fat_g, confidence, confirmed
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        meal_rows,
    )

    activity_rows = []
    for day_offset in range(3):
        activity_date = today - timedelta(days=day_offset)
        activity_rows.append(
            (
                1,
                iso_date(activity_date),
                8200 + day_offset * 350,
                520 + day_offset * 40,
                "1 workout logged",
                "healthkit",
            )
        )
        activity_rows.append(
            (
                2,
                iso_date(activity_date),
                7600 + day_offset * 400,
                430 + day_offset * 35,
                "Walking + pilates",
                "healthkit",
            )
        )

    insert_many(
        conn,
        """
        INSERT INTO health_activity (
            user_id, date, steps, calories_burned, workouts_summary, source
        )
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        activity_rows,
    )

    insert_many(
        conn,
        """
        INSERT INTO checkins (
            user_id, checkin_date, weight_kg, mood, notes
        )
        VALUES (?, ?, ?, ?, ?)
        """,
        [
            (1, iso_date(today - timedelta(days=7)), 88.8, "motivated", "Energy high, sleep improving."),
            (1, iso_date(today), 87.9, "focused", "Skipped a cardio session, want to swap days."),
            (2, iso_date(today - timedelta(days=7)), 72.6, "steady", "Work travel made meals harder."),
            (2, iso_date(today), 71.9, "optimistic", "More consistent walks this week."),
        ],
    )

    insert_many(
        conn,
        """
        INSERT INTO reminders (
            user_id, reminder_type, scheduled_at, status, channel, related_plan_override_id
        )
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
            (1, "workout", iso_dt(now + timedelta(hours=3)), "pending", "push", None),
            (2, "checkin", iso_dt(now + timedelta(days=1)), "scheduled", "local", None),
        ],
    )

    insert_many(
        conn,
        """
        INSERT INTO ai_suggestions (
            user_id, created_at, suggestion_type, rationale, suggestion_text, status
        )
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
            (
                1,
                iso_dt(now - timedelta(hours=4)),
                "diet",
                "Protein intake has been below target for 2 days.",
                "Add a 25g protein snack this afternoon (e.g., Greek yogurt).",
                "pending",
            ),
            (
                2,
                iso_dt(now - timedelta(days=1)),
                "workout",
                "Two consecutive light-activity days logged.",
                "Swap tomorrow's walk with a 20-minute cardio circuit.",
                "accepted",
            ),
        ],
    )

    insert_many(
        conn,
        """
        INSERT INTO streaks (
            user_id, streak_type, current_count, best_count, last_date
        )
        VALUES (?, ?, ?, ?, ?)
        """,
        [
            (1, "workout", 2, 5, iso_date(today)),
            (1, "meal_logging", 4, 7, iso_date(today)),
            (2, "workout", 3, 6, iso_date(today - timedelta(days=1))),
            (2, "meal_logging", 5, 9, iso_date(today)),
        ],
    )

    insert_many(
        conn,
        """
        INSERT INTO points (
            user_id, points, reason, created_at
        )
        VALUES (?, ?, ?, ?)
        """,
        [
            (1, 120, "Completed strength workout", iso_dt(now - timedelta(days=2))),
            (1, 60, "Logged 3 meals", iso_dt(now - timedelta(days=1))),
            (2, 90, "Hit step goal", iso_dt(now - timedelta(days=1))),
            (2, 40, "Weekly check-in submitted", iso_dt(now)),
        ],
    )

    insert_many(
        conn,
        """
        INSERT INTO calendar_blocks (
            user_id, start_at, end_at, title, source, status
        )
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
            (
                1,
                iso_dt(now.replace(hour=18, minute=0, second=0) + timedelta(days=1)),
                iso_dt(now.replace(hour=19, minute=0, second=0) + timedelta(days=1)),
                "Gym - Lower body",
                "google",
                "confirmed",
            ),
            (
                2,
                iso_dt(now.replace(hour=7, minute=30, second=0) + timedelta(days=2)),
                iso_dt(now.replace(hour=8, minute=15, second=0) + timedelta(days=2)),
                "Morning walk",
                "google",
                "tentative",
            ),
        ],
    )

    conn.commit()


def print_counts(conn: sqlite3.Connection) -> None:
    tables = [
        "users",
        "user_preferences",
        "plans",
        "plan_templates",
        "plan_template_days",
        "plan_overrides",
        "workout_sessions",
        "meal_logs",
        "health_activity",
        "checkins",
        "reminders",
        "ai_suggestions",
        "streaks",
        "points",
        "calendar_blocks",
    ]
    for table in tables:
        count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"{table}: {count}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a mock AI Trainer sqlite database.")
    parser.add_argument(
        "--db-path",
        default=str(Path(__file__).resolve().parents[1] / "data" / "ai_trainer.db"),
        help="Path to the sqlite database file.",
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Delete the existing database file before creating a new one.",
    )
    args = parser.parse_args()

    db_path = Path(args.db_path).expanduser().resolve()
    ensure_db_path(db_path)
    if args.reset:
        reset_db(db_path)

    with sqlite3.connect(db_path) as conn:
        create_schema(conn)
        seed_data(conn)
        print_counts(conn)

    print(f"Mock database created at {db_path}")


if __name__ == "__main__":
    main()
