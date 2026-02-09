from __future__ import annotations

import os
import sqlite3
from urllib.parse import quote_plus
from contextlib import contextmanager
from typing import Any, Iterable, Optional

import psycopg2
from psycopg2.pool import ThreadedConnectionPool
from agent.config.constants import DB_PATH


def _adapt_query(query: str) -> str:
    return query.replace("?", "%s")


class CursorAdapter:
    def __init__(self, cursor, adapt_query: bool = True):
        self._cursor = cursor
        self._adapt_query = adapt_query

    def execute(self, query: str, params: Optional[Iterable[Any]] = None):
        if self._adapt_query:
            query = _adapt_query(query)
        if params is None:
            return self._cursor.execute(query)
        return self._cursor.execute(query, params)

    def executemany(self, query: str, params: Iterable[Iterable[Any]]):
        if self._adapt_query:
            query = _adapt_query(query)
        return self._cursor.executemany(query, params)

    def fetchone(self):
        return self._cursor.fetchone()

    def fetchall(self):
        return self._cursor.fetchall()

    def __getattr__(self, name: str):
        return getattr(self._cursor, name)


class ConnectionAdapter:
    def __init__(
        self,
        conn,
        pool: Optional[ThreadedConnectionPool] = None,
        adapt_query: bool = True,
    ):
        self._conn = conn
        self._pool = pool
        self._adapt_query = adapt_query

    def cursor(self):
        return CursorAdapter(self._conn.cursor(), adapt_query=self._adapt_query)

    def commit(self) -> None:
        self._conn.commit()

    def rollback(self) -> None:
        self._conn.rollback()

    def close(self) -> None:
        if self._pool is not None:
            self._pool.putconn(self._conn)
        else:
            self._conn.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        if exc_type:
            self.rollback()
        else:
            self.commit()
        self.close()
        return False


@contextmanager
def get_db_conn():
    dsn = os.environ.get("SUPABASE_DATABASE_URL") or os.environ.get("DATABASE_URL")
    if not dsn:
        host = os.environ.get("SUPABASE_DB_HOST")
        user = os.environ.get("SUPABASE_DB_USER")
        password = os.environ.get("SUPABASE_DB_PASSWORD")
        dbname = os.environ.get("SUPABASE_DB_NAME", "postgres")
        port = os.environ.get("SUPABASE_DB_PORT", "5432")
        if host and user and password:
            safe_user = quote_plus(user)
            safe_password = quote_plus(password)
            dsn = f"postgresql://{safe_user}:{safe_password}@{host}:{port}/{dbname}"
    if not dsn:
        conn = sqlite3.connect(DB_PATH, check_same_thread=False)
        adapter = ConnectionAdapter(conn, pool=None, adapt_query=False)
        try:
            yield adapter
            adapter.commit()
        except Exception:
            adapter.rollback()
            raise
        finally:
            adapter.close()
        return
    pool = _get_pool(dsn)
    conn = pool.getconn()
    adapter = ConnectionAdapter(conn, pool=pool, adapt_query=True)
    try:
        yield adapter
        adapter.commit()
    except Exception:
        adapter.rollback()
        raise
    finally:
        adapter.close()


_POOL: Optional[ThreadedConnectionPool] = None
_POOL_DSN: Optional[str] = None


def _get_pool(dsn: str) -> ThreadedConnectionPool:
    global _POOL, _POOL_DSN
    if _POOL is None or _POOL_DSN != dsn:
        _POOL = ThreadedConnectionPool(minconn=1, maxconn=15, dsn=dsn, sslmode="require")
        _POOL_DSN = dsn
    return _POOL
