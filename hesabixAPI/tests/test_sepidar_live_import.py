"""Integration checks against an isolated PostgreSQL database.

Set SEPIDAR_TEST_DSN to a disposable database ending in `_sepidar_test`.
The SQL Server source is simulated; no customer data or SQL Server writes occur.
"""
import os
from datetime import datetime
from decimal import Decimal
from uuid import UUID

import pytest
from sqlalchemy import Column, Integer, MetaData, Table, create_engine, select
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from adapters.db.models.sepidar_live_import import SepidarImportRow, SepidarImportRun, SepidarImportSetting
from app.services import sepidar_import_service as service


@pytest.fixture
def db():
    dsn = os.getenv("SEPIDAR_TEST_DSN")
    if not dsn:
        pytest.skip("SEPIDAR_TEST_DSN is not set")
    assert make_url(dsn).database.endswith("_sepidar_test"), "Refusing to modify a non-test database"
    engine = create_engine(dsn)
    metadata = MetaData()
    Table("businesses", metadata, Column("id", Integer, primary_key=True))
    for model in (SepidarImportSetting, SepidarImportRow, SepidarImportRun):
        model.__table__.to_metadata(metadata)
    metadata.create_all(engine)
    try:
        with Session(engine, expire_on_commit=False) as session:
            session.execute(metadata.tables["businesses"].insert().values(id=1))
            session.commit()
            yield session
    finally:
        metadata.drop_all(engine)
        engine.dispose()


def configure(db):
    return service.save_setting(db, 1, {
        "host": "source.invalid", "database_name": "test", "username": "reader",
        "password": "test-secret-only", "enabled": True, "batch_size": 50,
    })


def source(monkeypatch, rows, *, keys=("ID",)):
    class Cursor:
        def execute(self, query):
            assert query.startswith("SELECT * FROM [dbo].[Items]")
            self.offset = 0

        def fetchmany(self, count):
            result = rows[self.offset:self.offset + count]
            self.offset += count
            return result

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def cursor(self, **kwargs):
            return Cursor()

    monkeypatch.setattr(service, "discover", lambda setting: [{"schema": "dbo", "table": "Items", "rows": len(rows)}])
    monkeypatch.setattr(service, "_connect", lambda setting: Connection())
    monkeypatch.setattr(service, "_primary_keys", lambda *args: keys)


def test_repeat_sync_updates_without_duplicates(db, monkeypatch):
    configure(db)
    rows = [{"ID": i, "Price": Decimal("12.35"), "Data": b"\x00\xff",
             "Guid": UUID(int=i), "Date": datetime(2026, 10, 22)} for i in range(1, 62)]
    source(monkeypatch, rows)
    assert service.run_sync(db, 1)["rows_changed"] == 61
    assert service.run_sync(db, 1)["rows_changed"] == 0
    rows[0]["Price"] = Decimal("15.00")
    assert service.run_sync(db, 1)["rows_changed"] == 1
    stored = db.scalars(select(SepidarImportRow)).all()
    assert len(stored) == 61
    first = next(r for r in stored if r.payload["ID"] == 1)
    assert first.payload["Price"] == "15.00"
    assert first.payload["Data"] == "00ff"


def test_no_primary_key_preserves_duplicates_and_ignores_row_order(db, monkeypatch):
    configure(db)
    rows = [{"Name": "الف"}, {"Name": "ب"}, {"Name": "الف"}]
    source(monkeypatch, rows, keys=())
    assert service.run_sync(db, 1)["rows_changed"] == 3
    rows.reverse()
    rows.insert(0, rows.pop(1))
    assert service.run_sync(db, 1)["rows_changed"] == 0
    assert len(db.scalars(select(SepidarImportRow)).all()) == 3


def test_lock_survives_batch_commit_and_releases_after_failure(db):
    with pytest.raises(RuntimeError):
        with service._sync_lock(db, 1):
            db.commit()
            with pytest.raises(service.SyncAlreadyRunning):
                with service._sync_lock(db, 1):
                    pytest.fail("A competing sync acquired the lock")
            raise RuntimeError("simulated worker failure")
    with service._sync_lock(db, 1):
        pass


def test_settings_encrypt_secret_and_do_not_return_it(db):
    setting = configure(db)
    assert "test-secret-only" not in setting.password_encrypted
    assert service.EncryptionService().decrypt(setting.password_encrypted) == "test-secret-only"
    response = service.public_setting(setting)
    assert "password" not in response
    assert "password_encrypted" not in response
    assert response["password_configured"] is True


def test_source_failure_is_audited_without_sensitive_parameters(db, monkeypatch):
    configure(db)

    def fail(setting):
        raise RuntimeError("customer payload and test-secret-only must not be persisted")

    monkeypatch.setattr(service, "discover", fail)
    with pytest.raises(RuntimeError):
        service.run_sync(db, 1)
    run = db.scalars(select(SepidarImportRun)).one()
    assert run.status == "failed"
    assert "test-secret-only" not in run.error
    assert "customer payload" not in run.error


def test_scheduler_rechecks_license_and_due_time_inside_lock(db, monkeypatch):
    setting = configure(db)
    monkeypatch.setattr(service, "plugin_active", lambda *args: False)
    assert service.run_sync(db, 1, scheduled=True)["status"] == "skipped"
    monkeypatch.setattr(service, "plugin_active", lambda *args: True)
    setting.last_started_at = datetime.utcnow()
    db.commit()
    assert service.run_sync(db, 1, scheduled=True)["status"] == "skipped"
    assert db.scalars(select(SepidarImportRun)).first() is None
