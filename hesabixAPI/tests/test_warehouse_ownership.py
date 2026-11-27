from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.schema import CreateTable

from adapters.db import models
from adapters.db.models.business import BusinessField, BusinessType
from adapters.db.models.document_monetization import DocumentUsagePolicy
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin
from app.core import cache
from app.core.responses import ApiError
from app.services.invoice_service import create_invoice, update_invoice
from app.services.warehouse_service import create_from_invoice, post_warehouse_document

DAY = date(2026, 11, 26)
ACCOUNTS = (
    "10401",
    "10405",
    "10102",
    "10104",
    "10106",
    "10107",
    "10202",
    "20101",
    "20201",
    "40001",
    "40003",
    "50001",
    "50002",
    "50003",
    "60205",
    "70401",
    "70406",
    "70407",
    "70408",
)


@pytest.fixture
def sessions(monkeypatch):
    monkeypatch.setattr(cache, "get_redis_client", lambda *args, **kwargs: None)
    monkeypatch.setattr(cache, "_redis_config", {"enabled": False})
    monkeypatch.setattr(cache, "_redis_config_expires_at", float("inf"))
    monkeypatch.setattr(cache, "_cache_service", None)
    names = (
        "businesses",
        "warehouses",
        "currencies",
        "fiscal_years",
        "products",
        "documents",
        "document_lines",
        "invoice_item_lines",
        "invoice_item_line_variant_allocations",
        "invoice_item_line_lot_allocations",
        "warehouse_documents",
        "warehouse_document_lines",
        "warehouse_line_variant_allocations",
        "warehouse_line_lot_allocations",
        "document_usage_policies",
        "document_number_counters",
        "business_document_numbering_settings",
        "accounts",
        "persons",
        "users",
        "fa_assets",
        "fa_settings",
        "fa_classes",
        "business_currencies",
        "document_invoice_tags",
        "document_invoice_tag_links",
        "product_instances",
        "inventory_variant_balances",
    )
    with create_engine("sqlite://").connect() as connection:
        tables = models.Base.metadata.tables
        for table in [
            *(tables[name] for name in names),
            BusinessPlugin.__table__,
            MarketplacePlugin.__table__,
        ]:
            connection.execute(CreateTable(table, include_foreign_key_constraints=[]))
        connection.commit()
        factory = sessionmaker(bind=connection, autoflush=False)
        with factory.begin() as db:
            db.add_all(
                [
                    models.Business(
                        id=bid,
                        name=f"B{bid}",
                        owner_id=1,
                        default_currency_id=1,
                        business_type=BusinessType.SHOP,
                        business_field=BusinessField.TRADING,
                    )
                    for bid in (1, 2)
                ]
            )
            db.add_all(
                [
                    models.Currency(id=1, name="Base", title="Base", symbol="B", code="B"),
                    models.FiscalYear(
                        id=1, business_id=1, title="FY", start_date=DAY, end_date=DAY, is_last=True
                    ),
                    models.Product(id=1, business_id=1, code="P", name="P", track_inventory=True),
                    models.Person(
                        id=1, business_id=1, alias_name="Counterparty", person_types="[]"
                    ),
                    models.Warehouse(id=1, business_id=1, code="W", name="Own"),
                    models.Warehouse(id=2, business_id=2, code="W", name="Other"),
                    DocumentUsagePolicy(
                        business_id=1, policy_type="free", title="Test", is_active=True
                    ),
                    *(
                        models.Account(code=code, name=code, account_type="system")
                        for code in ACCOUNTS
                    ),
                ]
            )
        yield factory


def _payload(*, header=None, line=None):
    return {
        "invoice_type": "invoice_purchase",
        "currency_id": 1,
        "document_date": DAY.isoformat(),
        "extra_info": {"person_id": 1, "post_inventory": False, "warehouse_id": header},
        "lines": [
            {
                "product_id": 1,
                "quantity": 1,
                "extra_info": {"warehouse_id": line, "unit_price": 211},
            }
        ],
    }


def _expect_warehouse_not_found(error):
    assert (error.value.code, error.value.status_code) == ("WAREHOUSE_NOT_FOUND", 404)


@pytest.mark.parametrize("warehouse", [{"header": 2}, {"line": 2}, {"line": 777}])
def test_create_invoice_rejects_an_unowned_warehouse_without_accounting_writes(sessions, warehouse):
    with sessions() as db:
        with pytest.raises(ApiError) as error:
            create_invoice(db, 1, 1, _payload(**warehouse), commit=False)
        _expect_warehouse_not_found(error)
        db.rollback()

    with sessions() as db:
        assert db.scalars(select(models.Document.id)).all() == []
        assert db.scalars(select(models.DocumentLine.id)).all() == []
        assert db.scalars(select(InvoiceItemLine.id)).all() == []


def _valid_invoice(sessions):
    with sessions.begin() as db:
        result = create_invoice(db, 1, 1, _payload(line=1), commit=False)
        return result["data"]["id"]


@pytest.mark.parametrize("warehouse", [{"header": 2}, {"line": 2}])
def test_invoice_update_rejects_foreign_warehouse_and_preserves_accounting_rows(
    sessions, warehouse
):
    invoice_id = _valid_invoice(sessions)
    with sessions() as db:
        account_rows = db.execute(
            select(
                models.DocumentLine.id, models.DocumentLine.debit, models.DocumentLine.credit
            ).order_by(models.DocumentLine.id)
        ).all()
        assert account_rows
        lines = db.execute(select(InvoiceItemLine.id, InvoiceItemLine.extra_info)).all()

    with sessions() as db:
        with pytest.raises(ApiError) as error:
            update_invoice(db, invoice_id, 1, _payload(**warehouse))
        _expect_warehouse_not_found(error)
        db.rollback()

    with sessions() as db:
        assert db.get(models.Document, invoice_id).extra_info.get("warehouse_id") is None
        assert db.execute(select(InvoiceItemLine.id, InvoiceItemLine.extra_info)).all() == lines
        assert (
            db.execute(
                select(
                    models.DocumentLine.id, models.DocumentLine.debit, models.DocumentLine.credit
                ).order_by(models.DocumentLine.id)
            ).all()
            == account_rows
        )


def test_linked_receipt_rejects_a_foreign_line_warehouse(sessions):
    invoice_id = _valid_invoice(sessions)
    with sessions() as db:
        item_id = db.scalars(select(InvoiceItemLine.id)).one()
        invoice = db.get(models.Document, invoice_id)
        with pytest.raises(ApiError) as error:
            create_from_invoice(
                db,
                1,
                invoice,
                [
                    {
                        "invoice_item_line_id": item_id,
                        "product_id": 1,
                        "quantity": 1,
                        "warehouse_id": 2,
                    }
                ],
                "receipt",
                1,
            )
        _expect_warehouse_not_found(error)
        db.rollback()

    with sessions() as db:
        assert db.scalars(select(models.WarehouseDocument.id)).all() == []
        assert db.scalars(select(models.WarehouseDocumentLine.id)).all() == []


def test_linked_receipt_can_be_created_and_posted_with_a_same_business_warehouse(sessions):
    invoice_id = _valid_invoice(sessions)
    with sessions.begin() as db:
        item_id = db.scalars(select(InvoiceItemLine.id)).one()
        invoice = db.get(models.Document, invoice_id)
        draft = create_from_invoice(
            db,
            1,
            invoice,
            [{"invoice_item_line_id": item_id, "product_id": 1, "quantity": 1, "warehouse_id": 1}],
            "receipt",
            1,
        )
        draft_id = draft.id

    with sessions.begin() as db:
        assert post_warehouse_document(db, draft_id)["status"] == "posted"

    with sessions() as db:
        assert db.get(models.WarehouseDocument, draft_id).status == "posted"
        line = db.scalars(select(models.WarehouseDocumentLine)).one()
        assert (line.warehouse_id, line.quantity) == (1, Decimal(1))


@pytest.mark.parametrize("header", [False, True])
def test_post_rejects_legacy_draft_and_keeps_it_draft(sessions, header):
    with sessions.begin() as db:
        db.add(
            models.WarehouseDocument(
                id=1,
                business_id=1,
                code="LEGACY",
                document_date=DAY,
                doc_type="receipt",
                status="draft",
                source_type="manual",
                warehouse_id_to=2 if header else 1,
            )
        )
        db.add(
            models.WarehouseDocumentLine(
                warehouse_document_id=1,
                product_id=1,
                warehouse_id=1 if header else 2,
                movement="in",
                quantity=Decimal(1),
            )
        )

    with sessions() as db:
        with pytest.raises(ApiError) as error:
            post_warehouse_document(db, 1)
        _expect_warehouse_not_found(error)
        db.rollback()

    with sessions() as db:
        assert db.get(models.WarehouseDocument, 1).status == "draft"
        assert db.scalars(select(models.DocumentLine.id)).all() == []
