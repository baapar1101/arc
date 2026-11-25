from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db import models
from adapters.db.models.business import BusinessField, BusinessType
from adapters.db.models.document_monetization import DocumentUsagePolicy
from adapters.db.models.document_numbering import BusinessDocumentNumberingSetting, DocumentNumberCounter
from adapters.db.models.goods_expense_income import GoodsExpenseIncomeDocument, GoodsExpenseIncomeLine
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin
from adapters.db.models.warehouse import Warehouse
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core import cache
from app.core.responses import ApiError
from app.services import goods_expense_income_service as goods
from app.services import woocommerce_stock_push_hook
from app.services.warehouse_service import get_physical_stock

DAY = date(2026, 11, 11)
TABLES = (
    "businesses", "currencies", "fiscal_years", "products", "documents", "document_lines", "persons",
    "users", "accounts", "warehouses", "warehouse_documents", "warehouse_document_lines",
    "document_usage_policies", "warehouse_line_variant_allocations", "warehouse_line_lot_allocations",
    "invoice_item_line_variant_allocations", "invoice_item_line_lot_allocations",
    "product_instances", "business_currencies",
)


def seed(engine):
    tables = [models.Base.metadata.tables[name] for name in TABLES]
    tables += [
        InvoiceItemLine.__table__, GoodsExpenseIncomeDocument.__table__, GoodsExpenseIncomeLine.__table__,
        BusinessDocumentNumberingSetting.__table__, DocumentNumberCounter.__table__,
        BusinessPlugin.__table__, MarketplacePlugin.__table__,
    ]
    with engine.begin() as connection:
        for table in tables:
            connection.execute(CreateTable(table, include_foreign_key_constraints=[]))
    with Session(engine) as db:
        db.add_all([
            models.Business(id=1, name="Test", owner_id=1, default_currency_id=1,
                            business_type=BusinessType.SHOP, business_field=BusinessField.TRADING),
            models.Currency(id=1, name="Base", title="Base", symbol="B", code="B"),
            models.FiscalYear(id=1, business_id=1, title="FY", is_last=True, start_date=DAY, end_date=DAY),
            models.Product(id=1, business_id=1, code="P", name="P", track_inventory=True,
                           base_purchase_price=Decimal("200")),
            Warehouse(id=1, business_id=1, code="W", name="Warehouse"),
            models.Account(id=1, code="10102", name="Inventory", account_type="asset"),
            models.Account(id=2, code="70401", name="Expense", account_type="expense"),
            models.Account(id=3, code="60101", name="Income", account_type="income"),
            DocumentUsagePolicy(business_id=1, policy_type="free", title="Test", is_active=True),
        ])
        receipt = WarehouseDocument(
            business_id=1, fiscal_year_id=1, code="SEED", document_date=DAY, status="posted",
            doc_type="receipt", warehouse_id_to=1,
        )
        db.add(receipt)
        db.flush()
        db.add(WarehouseDocumentLine(
            warehouse_document_id=receipt.id, product_id=1, warehouse_id=1, movement="in", quantity=10,
        ))
        db.commit()


@pytest.fixture
def engine(tmp_path, monkeypatch):
    monkeypatch.setattr(cache, "_redis_config", {"enabled": False})
    monkeypatch.setattr(cache, "_redis_config_expires_at", float("inf"))
    monkeypatch.setattr(cache, "_redis_client", None)
    monkeypatch.setattr(cache, "_cache_service", None)
    monkeypatch.setattr(woocommerce_stock_push_hook, "_execute_stock_push", lambda payload: None)
    engine = create_engine(f"sqlite:///{tmp_path / 'goods.sqlite'}")

    @event.listens_for(engine, "connect")
    def disable_legacy_transactions(connection, _):
        connection.isolation_level = None

    @event.listens_for(engine, "begin")
    def begin_transaction(connection):
        connection.exec_driver_sql("BEGIN")

    seed(engine)
    yield engine
    engine.dispose()


def create_draft(engine, kind="goods_expense"):
    with Session(engine, autoflush=False) as db:
        draft = goods.create_document(db, 1, 1, {
            "doc_kind": kind, "document_date": DAY.isoformat(), "auto_post": False,
            "effect_account_id": 2 if kind == "goods_expense" else 3,
            "lines": [{"product_id": 1, "warehouse_id": 1, "quantity": 2}],
        })
        return draft["id"]


def inspect_post(engine, document_id):
    with Session(engine) as db:
        document = db.get(GoodsExpenseIncomeDocument, document_id)
        stock = get_physical_stock(db, 1, 1, 1, as_of_date=DAY)
        warehouse_count = db.query(WarehouseDocument).filter_by(
            source_type="goods_expense_income", source_document_id=document_id,
        ).count()
        accounting_docs = db.query(models.Document).filter(
            models.Document.document_type == document.doc_kind,
            models.Document.extra_info["goods_expense_income_id"].as_integer() == document_id,
        ).all()
        gl = sorted((line.account.code, line.debit, line.credit) for doc in accounting_docs for line in doc.lines)
        result = document.status, stock, warehouse_count, len(accounting_docs), gl
        print(f"observed={result}")
        return result


@pytest.mark.parametrize("kind,stock,entries", [
    ("goods_expense", 8, [("10102", 0, 400), ("70401", 400, 0)]),
    ("goods_income", 12, [("10102", 400, 0), ("60101", 0, 400)]),
])
def test_post_rejects_repeated_request_with_stale_or_fresh_session(engine, kind, stock, entries):
    did = create_draft(engine, kind)
    with Session(engine, autoflush=False, expire_on_commit=False) as stale:
        cached = stale.get(GoodsExpenseIncomeDocument, did)
        assert cached.status == "draft_accounting"
        stale.commit()  # Release SQLite's read lock while retaining the cached draft.
        with Session(engine, autoflush=False) as writer:
            assert writer.get(GoodsExpenseIncomeDocument, did).status == "draft_accounting"
            assert goods.post_document(writer, 1, 1, did)["status"] == "posted"
        assert cached.status == "draft_accounting"
        try:
            goods.post_document(stale, 1, 1, did)
        except ApiError as exc:
            stale.rollback()
            stale_outcome = (exc.code, exc.status_code)
        else:
            stale_outcome = "posted"
    with Session(engine, autoflush=False) as fresh:
        with pytest.raises(ApiError) as repeated:
            goods.post_document(fresh, 1, 1, did)
        assert (repeated.value.code, repeated.value.status_code) == ("INVALID_STATUS", 400)
    assert inspect_post(engine, did) == ("posted", stock, 1, 1, entries)
    assert stale_outcome == ("INVALID_STATUS", 400)


def test_rollback_after_warehouse_post_allows_retry(engine, monkeypatch):
    did = create_draft(engine)
    with Session(engine, autoflush=False) as db:
        with monkeypatch.context() as patch:
            def fail_before_gl(session, business_id, user_id, doc):
                warehouse = session.get(WarehouseDocument, doc.warehouse_document_id)
                assert warehouse.status == "posted"
                raise RuntimeError("injected GL failure")

            patch.setattr(goods, "_create_accounting_document", fail_before_gl)
            with pytest.raises(RuntimeError, match="injected GL failure"):
                goods.post_document(db, 1, 1, did)
            db.rollback()
        assert inspect_post(engine, did) == ("draft_accounting", 10, 0, 0, [])
        assert goods.post_document(db, 1, 1, did)["status"] == "posted"
    assert inspect_post(engine, did) == ("posted", 8, 1, 1, [("10102", 0, 400), ("70401", 400, 0)])
