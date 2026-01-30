from __future__ import annotations

import os
from urllib.parse import quote_plus
from contextlib import contextmanager
from typing import Any, Iterable, Optional

import psycopg2
from psycopg2.pool import ThreadedConnectionPool


def _adapt_query(query: str) -> str:
    return query.replace("?", "%s")


class CursorAdapter:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, query: str, params: Optional[Iterable[Any]] = None):
        query = _adapt_query(query)
        if params is None:
            return self._cursor.execute(query)
        return self._cursor.execute(query, params)

    def executemany(self, query: str, params: Iterable[Iterable[Any]]):
        query = _adapt_query(query)
        return self._cursor.executemany(query, params)

    def fetchone(self):
        return self._cursor.fetchone()

    def fetchall(self):
        return self._cursor.fetchall()

    def __getattr__(self, name: str):
        return getattr(self._cursor, name)


class ConnectionAdapter:
    def __init__(self, conn, pool: Optional[ThreadedConnectionPool] = None):
        self._conn = conn
        self._pool = pool

    def cursor(self):
        return CursorAdapter(self._conn.cursor())

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
        raise RuntimeError(
            "Database connection string not set. Use SUPABASE_DATABASE_URL or SUPABASE_DB_HOST/USER/PASSWORD."
        )
    pool = _get_pool(dsn)
    conn = pool.getconn()
    adapter = ConnectionAdapter(conn, pool=pool)
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
        _POOL = ThreadedConnectionPool(minconn=1, maxconn=5, dsn=dsn, sslmode="require")
        _POOL_DSN = dsn
    return _POOL
