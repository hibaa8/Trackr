from __future__ import annotations

import os
from contextlib import contextmanager
from typing import Any, Iterable, Optional

import psycopg2
from psycopg2.pool import ThreadedConnectionPool


def _is_connection_closed_error(exc: BaseException) -> bool:
    """Detect if error indicates the DB connection was closed unexpectedly."""
    msg = str(exc).lower()
    return (
        "server closed the connection" in msg
        or "connection is closed" in msg
        or "connection reset" in msg
        or "connection refused" in msg
    )


def invalidate_pool() -> None:
    """Close and discard the connection pool. Next request will create a fresh pool."""
    global _POOL
    if _POOL is not None:
        try:
            _POOL.closeall()
        except Exception:
            pass
        _POOL = None


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
        pool: Optional[Any] = None,
        adapt_query: bool = True,
    ):
        self._conn = conn
        self._pool = pool
        self._adapt_query = adapt_query
        self._conn_bad = False

    def cursor(self):
        return CursorAdapter(self._conn.cursor(), adapt_query=self._adapt_query)

    def commit(self) -> None:
        self._conn.commit()

    def rollback(self) -> None:
        self._conn.rollback()

    def close(self) -> None:
        if self._pool is not None and not self._conn_bad:
            self._pool.putconn(self._conn)
        else:
            try:
                self._conn.close()
            except Exception:
                pass

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
    global _POOL
    if _POOL is None:
        host = os.environ.get("SUPABASE_DB_HOST")
        user = os.environ.get("SUPABASE_DB_USER")
        password = os.environ.get("SUPABASE_DB_PASSWORD")
        dbname = os.environ.get("SUPABASE_DB_NAME")
        port = int(os.environ.get("SUPABASE_DB_PORT", "5432"))
        sslmode = os.environ.get("SUPABASE_DB_SSLMODE", "require")
        minconn = int(os.environ.get("DB_POOL_MIN", "1"))
        maxconn = int(os.environ.get("DB_POOL_MAX", "15"))

        if not host or not user or not password or not dbname:
            raise RuntimeError(
                "Supabase/Postgres is required. Set SUPABASE_DB_HOST, SUPABASE_DB_USER, "
                "SUPABASE_DB_PASSWORD, SUPABASE_DB_NAME, SUPABASE_DB_PORT."
            )

        _POOL = ThreadedConnectionPool(
            minconn=minconn,
            maxconn=maxconn,
            host=host,
            user=user,
            password=password,
            dbname=dbname,
            port=port,
            sslmode=sslmode,
            keepalives=1,
            keepalives_idle=30,
            keepalives_interval=10,
            keepalives_count=5,
        )

    conn = _POOL.getconn()
    adapter = ConnectionAdapter(conn, pool=_POOL, adapt_query=True)
    try:
        yield adapter
        adapter.commit()
    except Exception as e:
        if _is_connection_closed_error(e):
            adapter._conn_bad = True
            invalidate_pool()
        try:
            adapter.rollback()
        except Exception:
            pass  # connection may be dead
        raise
    finally:
        adapter.close()


_POOL: Optional[ThreadedConnectionPool] = None
