"""Financial voucher posting must lock and refresh status before side effects.

SQLite checks the identity-map regression and transaction boundaries; the
separately enabled SQL Server test verifies real two-connection lock waiting.
No test connects to a production database.
"""

from __future__ import annotations

import os
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from threading import Event

import pytest
import sqlalchemy as sa
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable, DropTable

from adapters.db.models.goods_expense_income import (
    GoodsExpenseIncomeDocument,
    GoodsExpenseIncomeLine,
)
from adapters.db.models.account import Account
from adapters.db.models.person import Person
from app.core.responses import ApiError
from app.services import goods_expense_income_service as goods

DAY = date(2026, 11, 22)


def _seed(session, *, business_id=10):
    document = GoodsExpenseIncomeDocument(
        business_id=business_id, fiscal_year_id=1,
        code=f"SAFETY-{business_id}", document_date=DAY,
        doc_kind="goods_expense", status="draft_ops", currency_id=1,
    )
    session.add(document)
    session.commit()
    return document.id


@pytest.fixture
def sqlite_engine(tmp_path):
    engine = sa.create_engine(f"sqlite:///{tmp_path / 'goods-post.sqlite'}")
    with engine.begin() as conn:
        for model in (Account, Person, GoodsExpenseIncomeDocument, GoodsExpenseIncomeLine):
            conn.execute(CreateTable(model.__table__, include_foreign_key_constraints=[]))
    try:
        yield engine
    finally:
        engine.dispose()


def test_stale_session_cannot_post_document_twice(sqlite_engine, monkeypatch):
    calls = []

    def fake_financial_post(db, business_id, user_id, document):
        calls.append((business_id, user_id, document.id))
        document.status = goods.STATUS_POSTED

    monkeypatch.setattr(goods, "_post_document_internal", fake_financial_post)
    with Session(sqlite_engine) as seed:
        document_id = _seed(seed)
    with Session(sqlite_engine, expire_on_commit=False) as stale:
        cached = stale.get(GoodsExpenseIncomeDocument, document_id)
        assert cached.status == "draft_ops"
        stale.commit()  # Retain stale identity-map state, release read txn.

        with Session(sqlite_engine) as writer:
            first = goods.post_document(writer, 10, 1, document_id)
            assert first["status"] == "posted"

        assert cached.status == "draft_ops"
        with pytest.raises(ApiError) as raised:
            goods.post_document(stale, 10, 1, document_id)
        assert (raised.value.code, raised.value.status_code) == ("INVALID_STATUS", 400)
        stale.rollback()

    with Session(sqlite_engine) as check:
        assert check.get(GoodsExpenseIncomeDocument, document_id).status == "posted"
    assert calls == [(10, 1, document_id)]


def test_posting_is_business_scoped_and_caller_rollback_restores_draft(sqlite_engine, monkeypatch):
    calls = []
    def fake_financial_post(db, business_id, user_id, document):
        calls.append(document.id)
        document.status = goods.STATUS_POSTED

    monkeypatch.setattr(goods, "_post_document_internal", fake_financial_post)
    with Session(sqlite_engine) as seed:
        document_id = _seed(seed)
    with Session(sqlite_engine) as db:
        with pytest.raises(ApiError) as wrong_business:
            goods.post_document(db, 11, 1, document_id)
        assert wrong_business.value.code == "NOT_FOUND"
        db.rollback()
        result = goods.post_document(db, 10, 1, document_id, commit=False)
        assert result["status"] == "posted"
        db.rollback()

    with Session(sqlite_engine) as check:
        assert check.get(GoodsExpenseIncomeDocument, document_id).status == "draft_ops"
    assert calls == [document_id]


@pytest.mark.skipif(
    not (os.getenv("DISTRIBUTION_MSSQL_TEST_DSN") and
         os.getenv("DISTRIBUTION_MSSQL_TEST_ENABLE") == "1"),
    reason="Requires ephemeral local SQL Server 2022 CI container",
)
def test_live_mssql_posting_lock_blocks_until_owner_commits():
    url = make_url(os.environ["DISTRIBUTION_MSSQL_TEST_DSN"])
    assert url.get_backend_name() == "mssql"
    assert url.host in ("localhost", "127.0.0.1")
    assert url.database == "tempdb" and url.port == 1433

    engine = sa.create_engine(url, pool_pre_ping=True, pool_size=5)
    table = GoodsExpenseIncomeDocument.__table__
    with engine.begin() as conn:
        assert conn.execute(sa.text("SELECT DB_NAME()")).scalar_one() == "tempdb"
        assert not sa.inspect(conn).has_table(table.name)
        conn.execute(CreateTable(table, include_foreign_key_constraints=[]))

    try:
        with Session(engine) as seed:
            document_id = _seed(seed)
        started = Event()

        def second_session():
            with Session(engine) as concurrent:
                started.set()
                document = goods._load_document(
                    concurrent, 10, document_id, with_lines=False, for_update=True
                )
                observed = document.status
                concurrent.rollback()
                return observed

        with Session(engine) as owner:
            document = goods._load_document(
                owner, 10, document_id, with_lines=False, for_update=True
            )
            assert document.status == "draft_ops"
            with ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(second_session)
                assert started.wait(timeout=5)
                time.sleep(0.25)
                assert not future.done(), "Second SQL Server session bypassed UPDLOCK"
                document.status = "posted"
                owner.commit()
                assert future.result(timeout=8) == "posted"
    finally:
        with engine.begin() as conn:
            conn.execute(DropTable(table))
        engine.dispose()
