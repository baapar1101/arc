"""Live SQL Server 2022 transaction app-lock tests on an ephemeral local database.

The suite is opt-in. It refuses any non-local server or non-tempdb database;
never run these tests against a production connection.
"""

from __future__ import annotations

import os
import time
from concurrent.futures import ThreadPoolExecutor
from threading import Event

import pytest
import sqlalchemy as sa
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from app.services.distribution_service import (
    _PLAN_PUBLICATION_ADVISORY_LOCK_NAMESPACE,
    _serialize_distribution_plan_mutation,
)

_DSN = os.getenv("DISTRIBUTION_MSSQL_TEST_DSN", "")
_ENABLED = os.getenv("DISTRIBUTION_MSSQL_TEST_ENABLE") == "1"

pytestmark = pytest.mark.skipif(
    not (_DSN and _ENABLED),
    reason="Only run against an ephemeral local SQL Server 2022 container",
)


@pytest.fixture(scope="module")
def engine():
    url = make_url(_DSN)
    assert url.get_backend_name() == "mssql", "SQL Server integration required"
    assert url.host in ("localhost", "127.0.0.1"), "Remote SQL Server is forbidden"
    assert url.database == "tempdb", "Only isolated SQL Server tempdb is allowed"
    assert url.port == 1433, "Tests must target the local ephemeral SQL Server port"
    db_engine = sa.create_engine(url, pool_pre_ping=True, pool_size=5)
    try:
        with db_engine.connect() as conn:
            assert conn.execute(sa.text("SELECT DB_NAME()")).scalar_one() == "tempdb"
        yield db_engine
    finally:
        db_engine.dispose()


def _resource(business_id: int) -> str:
    return (
        "hesabix:distribution:plan-mutation:"
        f"{_PLAN_PUBLICATION_ADVISORY_LOCK_NAMESPACE}:{business_id}"
    )


def _can_take_exclusive_app_lock(session: Session, business_id: int) -> bool:
    # APPLOCK_TEST checks compatibility without acquiring the lock.
    return bool(session.execute(
        sa.text("SELECT APPLOCK_TEST('public', :resource, 'Exclusive', 'Transaction')"),
        {"resource": _resource(business_id)},
    ).scalar_one())


def test_live_mssql_lock_exclusive_business_scoped_and_commit_release(engine):
    """A second session is blocked for business A but not business B."""
    with Session(engine) as owner:
        _serialize_distribution_plan_mutation(owner, 10)
        assert owner.in_transaction()
        with Session(engine) as concurrent:
            assert _can_take_exclusive_app_lock(concurrent, 10) is False
            assert _can_take_exclusive_app_lock(concurrent, 11) is True
            _serialize_distribution_plan_mutation(concurrent, 11)
            concurrent.commit()
        owner.commit()

    with Session(engine) as next_tx:
        assert _can_take_exclusive_app_lock(next_tx, 10) is True
        _serialize_distribution_plan_mutation(next_tx, 10)
        next_tx.rollback()


def test_live_mssql_rollback_releases_transaction_lock(engine):
    with Session(engine) as owner:
        _serialize_distribution_plan_mutation(owner, 30)
        with Session(engine) as concurrent:
            assert _can_take_exclusive_app_lock(concurrent, 30) is False
            concurrent.rollback()
        owner.rollback()

    with Session(engine) as next_tx:
        assert _can_take_exclusive_app_lock(next_tx, 30) is True
        next_tx.rollback()


def test_live_mssql_same_business_second_session_waits_for_commit(engine):
    """Verify real two-connection contention through the production helper."""
    started = Event()

    def second_session():
        with Session(engine) as concurrent:
            started.set()
            _serialize_distribution_plan_mutation(concurrent, 40)
            concurrent.commit()
        return True

    with Session(engine) as owner:
        _serialize_distribution_plan_mutation(owner, 40)
        with ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(second_session)
            assert started.wait(timeout=5), "Second session did not start"
            time.sleep(0.25)
            assert not future.done(), "The same-business exclusive lock was bypassed"
            owner.commit()
            assert future.result(timeout=8) is True
