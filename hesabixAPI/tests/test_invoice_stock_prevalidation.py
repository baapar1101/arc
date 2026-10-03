"""Regression tests for invoice stock validation before warehouse posting."""

from datetime import date
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from adapters.db.models.business import Business
from adapters.db.models.product import Product
from app.services import invoice_service
from app.services.invoice_service import (
    INVOICE_SALES,
    _ensure_stock_sufficient,
    _validate_outgoing_stock_before_invoice_commit,
)


def _prevalidation_db() -> MagicMock:
    db = MagicMock()

    def _query(model, *unused_models):
        query = MagicMock()
        if model is Product:
            query.filter.return_value.first.return_value = SimpleNamespace(
                id=520098,
                track_inventory=True,
            )
        elif model is Business:
            query.filter.return_value.first.return_value = SimpleNamespace(
                allow_negative_inventory_for_bulk=False,
                allow_negative_inventory_for_unique=False,
                warehouse_transfer_require_positive_stock=True,
            )
        return query

    db.query.side_effect = _query
    return db


def test_precommit_validation_excludes_current_invoice_from_available_stock() -> None:
    """The flushed sales line must not reduce stock before its own validation."""
    db = _prevalidation_db()
    document = SimpleNamespace(
        id=731,
        is_proforma=False,
        document_date=date(2026, 10, 3),
        extra_info={"auto_post_warehouse": True, "warehouse_id": 9},
    )
    lines = [{"product_id": 520098, "quantity": 1, "extra_info": {}}]
    data = {"extra_info": {"post_inventory": True}}

    with (
        patch(
            "app.services.warehouse_service.invoice_lines_have_trackable_inventory_products",
            return_value=True,
        ),
        patch.object(
            invoice_service,
            "filter_outgoing_lines_for_stock_enforcement",
            side_effect=lambda _db, _business_id, outgoing_lines, **_kwargs: outgoing_lines,
        ),
        patch.object(invoice_service, "_ensure_stock_sufficient") as ensure_stock,
    ):
        _validate_outgoing_stock_before_invoice_commit(
            db,
            business_id=17,
            document=document,
            invoice_type=INVOICE_SALES,
            lines_input=lines,
            data=data,
        )

    ensure_stock.assert_called_once()
    assert ensure_stock.call_args.kwargs["exclude_document_id"] == document.id


def test_stock_validation_accepts_quantity_equal_to_available_stock() -> None:
    """Equality is sufficient: one available item can satisfy a one-item sale."""
    db = MagicMock()
    query = db.query.return_value
    query.filter.return_value.all.side_effect = [
        [SimpleNamespace(id=520098, name="کالای نمونه", code="520098")],
        [SimpleNamespace(id=9, name="انبار اصلی")],
    ]
    outgoing_lines = [
        {
            "product_id": 520098,
            "quantity": 1,
            "extra_info": {"warehouse_id": 9, "movement": "out"},
        }
    ]

    with patch.object(
        invoice_service,
        "_compute_available_stock",
        return_value=Decimal("1"),
    ):
        _ensure_stock_sufficient(
            db,
            business_id=17,
            document_date=date(2026, 10, 3),
            outgoing_lines=outgoing_lines,
            exclude_document_id=731,
        )
