"""SQL Server application-lock contract tests without a production database."""

from unittest.mock import Mock

import pytest

from app.core.responses import ApiError
from app.services.distribution_service import _serialize_distribution_plan_mutation


def session_with_dialect(name: str, result: int = 0) -> Mock:
    db = Mock()
    db.get_bind.return_value.dialect.name = name
    db.execute.return_value.scalar_one.return_value = result
    return db


@pytest.mark.parametrize("result_code", [0, 1])
def test_sql_server_plan_mutations_acquire_transaction_owned_app_lock(result_code):
    db = session_with_dialect("mssql", result_code)
    _serialize_distribution_plan_mutation(db, 10)
    statement, params = db.execute.call_args.args
    query = str(statement)
    assert "sys.sp_getapplock" in query
    assert "@LockMode = 'Exclusive'" in query
    assert "@LockOwner = 'Transaction'" in query
    assert "@LockTimeout = 10000" in query
    assert "SELECT @distribution_lock_result" in query
    assert params["resource"] == "hesabix:distribution:plan-mutation:174021:10"
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


def test_sql_server_distinct_businesses_use_distinct_resources():
    first = session_with_dialect("mssql")
    other = session_with_dialect("mssql")
    _serialize_distribution_plan_mutation(first, 10)
    _serialize_distribution_plan_mutation(other, 11)
    assert first.execute.call_args.args[1]["resource"] != other.execute.call_args.args[1]["resource"]


@pytest.mark.parametrize("result_code", [-1, -2, -3, -999, None])
def test_sql_server_lock_failure_prevents_plan_mutation(result_code):
    db = session_with_dialect("mssql", result_code)
    with pytest.raises(ApiError, match="Unable to obtain the distribution plan transaction lock"):
        _serialize_distribution_plan_mutation(db, 10)
    db.commit.assert_not_called()


def test_postgresql_advisory_lock_is_preserved():
    db = session_with_dialect("postgresql")
    _serialize_distribution_plan_mutation(db, 17)
    statement, params = db.execute.call_args.args
    assert "pg_advisory_xact_lock" in str(statement)
    assert params == {"namespace": 174021, "business_id": 17}
    db.execute.return_value.scalar.assert_called_once_with()


def test_sqlite_fixture_does_not_require_server_lock():
    db = session_with_dialect("sqlite")
    _serialize_distribution_plan_mutation(db, 17)
    db.execute.assert_not_called()


def test_unknown_production_dialect_fails_closed():
    db = session_with_dialect("mysql")
    with pytest.raises(ApiError, match="transaction lock is unavailable"):
        _serialize_distribution_plan_mutation(db, 17)
    db.execute.assert_not_called()
