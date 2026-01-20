from __future__ import annotations

import sqlite3

from agent.config.constants import DB_PATH


def get_sqlite_conn() -> sqlite3.Connection:
    return sqlite3.connect(DB_PATH)
