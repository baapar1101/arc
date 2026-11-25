"""Real SQL Server 2022 rollback gate for the atomic distribution setup wizard.

Runs only against the dedicated localhost/tempdb CI service. It builds an
isolated minimal schema with no production FKs/data, deliberately fails after
several staged writes, and proves a clean rollback and a subsequent successful
single-commit setup in the same database. Never enabled for remote hosts.
"""

from __future__ import annotations

import os
from datetime import date

import pytest
import sqlalchemy as sa
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable, DropTable

from adapters.db.models.person import Person
from adapters.db.models.distribution import (
    DistributionBusinessSettings, DistributionCustomerProfile,
    DistributionDailyPlanLock, DistributionRoute, DistributionRouteAssignment,
    DistributionRouteStop, DistributionTerritory,
)
from app.core.responses import ApiError
from app.services import distribution_service as dist_svc
from app.services import distribution_field_ops_service as fieldops


_DSN = os.getenv("DISTRIBUTION_MSSQL_TEST_DSN", "")
_ENABLED = os.getenv("DISTRIBUTION_MSSQL_TEST_ENABLE") == "1"

pytestmark = pytest.mark.skipif(
    not (_DSN and _ENABLED),
    reason="Requires ephemeral SQL Server 2022 CI service in local tempdb",
)


def test_mssql_setup_wizard_transaction_rolls_back_all_stages(monkeypatch):
    url = make_url(_DSN)
    assert url.get_backend_name() == "mssql"
    assert url.host in ("localhost", "127.0.0.1")
    assert url.port == 1433 and url.database == "tempdb"

    tables = (
        Person.__table__,
        DistributionBusinessSettings.__table__,
        DistributionTerritory.__table__,
        DistributionRoute.__table__,
        DistributionRouteStop.__table__,
        DistributionRouteAssignment.__table__,
        DistributionCustomerProfile.__table__,
        DistributionDailyPlanLock.__table__,
    )
    engine = sa.create_engine(url, pool_pre_ping=True)
    created = []
    try:
        with engine.begin() as conn:
            assert conn.execute(sa.text("SELECT DB_NAME()")).scalar_one() == "tempdb"
            for table in tables:
                assert not sa.inspect(conn).has_table(table.name)
                conn.execute(CreateTable(table, include_foreign_key_constraints=[]))
                created.append(table)
            conn.execute(sa.insert(Person.__table__), [
                dict(id=707, business_id=10, alias_name="Local visitor customer", person_types="[]"),
                dict(id=808, business_id=11, alias_name="Foreign customer", person_types="[]"),
            ])

        monkeypatch.setattr(dist_svc, "_ensure_plugin", lambda *_args: None)
        monkeypatch.setattr(fieldops, "business_today", lambda *_args: date(2026, 11, 25))
        base_payload = {
            "territory_code": "T-MSSQL",
            "territory_name": "Test territory",
            "route_code": "R-MSSQL",
            "route_name": "Test route",
            "weekday": 2,
            "customer_class": "A",
            "visitor_user_id": 20,
            "valid_from": "2026-11-25",
        }
        with Session(engine) as session:
            with pytest.raises(ApiError):
                fieldops.run_setup_wizard(
                    session, 10, 1,
                    {**base_payload, "person_ids": [707, 808]},
                )
            # SQL Server must not leave the transaction, settings, route or
            # customer profile persisted after the second invalid customer.
            for model in (
                DistributionBusinessSettings,
                DistributionTerritory,
                DistributionRoute,
                DistributionRouteStop,
                DistributionCustomerProfile,
                DistributionRouteAssignment,
            ):
                assert session.query(model).count() == 0, model.__tablename__

            completed = fieldops.run_setup_wizard(
                session, 10, 1, {**base_payload, "person_ids": [707]},
            )
            assert completed["ok"] is True
            assert completed["stops_created"] == 1
            assert completed["assignment"]["user_id"] == 20
            assert session.query(DistributionBusinessSettings).count() == 1
            assert session.query(DistributionTerritory).count() == 1
            assert session.query(DistributionRoute).count() == 1
            assert session.query(DistributionRouteStop).count() == 1
            assert session.query(DistributionCustomerProfile).count() == 1
            assert session.query(DistributionRouteAssignment).count() == 1

            retry = fieldops.run_setup_wizard(
                session, 10, 1, {**base_payload, "person_ids": [707]},
            )
            assert retry["stops_created"] == 0
            assert retry["assignment"]["id"] == completed["assignment"]["id"]
            assert session.query(DistributionRouteStop).count() == 1
    finally:
        with engine.begin() as conn:
            for table in reversed(created):
                conn.execute(DropTable(table, if_exists=True))
        engine.dispose()
