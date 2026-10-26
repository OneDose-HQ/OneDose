# File: backend/db.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: The ONLY file that talks to the database. Runs SQL functions and reads views, switches database role per request, retries on serialization failure.
# Inputs: A role name ('clinician', 'pharmacist', 'admin', 'scanner' or None) and the login name, then SQL with parameters.
# Outputs: Rows as dictionaries plus timing and the SQL text (for the SqlPeek panel).
# Depends on: config.py
#
# Every request is ONE transaction:  SET LOCAL ROLE onedose_<role>;  set_config('onedose.user', <login>, true);  queries...
# so row-level security (08) and the audit log (07) always know who is acting. role=None runs as the API login itself
# (only fn_login is allowed there). serializable=True is used for writes, and run() retries it on a serialization failure.
import asyncio
import time
from contextlib import contextmanager

import psycopg
from fastapi import HTTPException
from psycopg import errors, sql
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from starlette.concurrency import run_in_threadpool

from config import settings

ROLES = {"clinician", "pharmacist", "admin", "scanner"}
_pool: ConnectionPool | None = None


def open_pool() -> None:
    global _pool
    conninfo = make_conninfo(host=settings.db_host, port=settings.db_port, dbname=settings.db_name,
                             user=settings.db_user, password=settings.db_password or None,
                             sslmode=settings.db_sslmode)
    # check= tests a connection before it is handed out and replaces a dead one. A serverless database (Neon)
    # closes idle connections after a few minutes, so without this the first request after a quiet spell fails.
    _pool = ConnectionPool(conninfo, min_size=1, max_size=10, open=True, kwargs={"autocommit": False},
                           check=ConnectionPool.check_connection, max_idle=240, max_lifetime=1800)


def close_pool() -> None:
    if _pool is not None:
        _pool.close()


def ping() -> bool:
    try:
        with tx() as t:
            return t.one("SELECT 1 AS ok", show=False)["ok"] == 1
    except Exception:
        return False


class Tx:
    """One open transaction. query() returns rows as dicts and remembers the SQL and timing."""

    def __init__(self, conn: psycopg.Connection, cur: psycopg.Cursor):
        self._conn, self._cur, self._shown = conn, cur, []

    def query(self, text: str, params=None, show: bool = True) -> list[dict]:
        started = time.perf_counter()
        self._cur.execute(text, params)
        rows = self._cur.fetchall() if self._cur.description else []
        if show:  # the text as it ran, parameters filled in, for the Under-the-hood panel
            shown = psycopg.ClientCursor(self._conn).mogrify(text, params)
            self._shown.append((" ".join(shown.split()), (time.perf_counter() - started) * 1000))
        return rows

    def one(self, text: str, params=None, show: bool = True) -> dict | None:
        rows = self.query(text, params, show)
        return rows[0] if rows else None

    def require_consent(self, patient_id: int) -> None:
        if not self.one("SELECT fn_has_consent(%s) AS ok", (patient_id,), show=False)["ok"]:
            raise HTTPException(403, "No active consent for this patient")

    def log_read(self, table: str, pk) -> None:
        self.query("SELECT fn_log_read(%s, %s)", (table, str(pk)), show=False)

    @property
    def debug(self) -> dict:
        return {"text": "\n".join(s for s, _ in self._shown),
                "elapsed_ms": round(sum(ms for _, ms in self._shown), 1)}


@contextmanager
def tx(role: str | None = None, user: str | None = None, serializable: bool = False):
    with _pool.connection() as conn:  # commits on success, rolls back on any exception
        conn.isolation_level = psycopg.IsolationLevel.SERIALIZABLE if serializable else None
        with conn.cursor(row_factory=dict_row) as cur:
            if role is not None:
                if role not in ROLES:
                    raise ValueError(f"unknown role {role!r}")
                cur.execute(sql.SQL("SET LOCAL ROLE {}").format(sql.Identifier(f"onedose_{role}")))
            cur.execute("SELECT set_config('onedose.user', %s, true)", (user or "",))
            yield Tx(conn, cur)


async def run(work, retries: int = 3):
    """Run a blocking function (it opens its own tx) in a thread; retry if the database says 'try again'."""
    for attempt in range(1, retries + 1):
        try:
            return await run_in_threadpool(work)
        except (errors.SerializationFailure, errors.DeadlockDetected):
            if attempt == retries:
                raise
            await asyncio.sleep(0.05 * attempt)


def error_to_http(exc: psycopg.Error) -> HTTPException:
    """Turn a database error into a safe HTTP error (the raw message is never sent to the client)."""
    if isinstance(exc, errors.InsufficientPrivilege):
        return HTTPException(403, "You are not allowed to do that")
    if isinstance(exc, errors.ExclusionViolation):
        return HTTPException(409, "This patient already takes this medicine in an overlapping period")
    if isinstance(exc, (errors.SerializationFailure, errors.DeadlockDetected)):
        return HTTPException(409, "Another change happened at the same moment. Please try again")
    if isinstance(exc, errors.ForeignKeyViolation):
        return HTTPException(404, "Unknown patient, medicine or clinician")
    if isinstance(exc, (errors.CheckViolation, errors.InvalidParameterValue, errors.NumericValueOutOfRange)):
        return HTTPException(422, "Some values were not accepted by the database")
    return HTTPException(500, "Database error")
