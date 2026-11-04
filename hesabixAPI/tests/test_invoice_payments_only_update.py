"""مسیر ذخیرهٔ فقط‌پرداخت بدون بازنویسی اقلام فاکتور."""
from datetime import date
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from adapters.db.models.document import Document
from adapters.db.models.fiscal_year import FiscalYear
from app.services.invoice_service import (
    _apply_invoice_payments_only_update,
    _invoice_extra_body_equal,
    _invoice_lines_economically_equal,
    _invoice_payload_preserves_invoice_body,
    update_invoice,
)


def _document(**kwargs):
    values = dict(
        id=10,
        business_id=1,
        fiscal_year_id=2,
        document_type="invoice_purchase",
        is_proforma=False,
        document_date=date(2026, 1, 15),
        currency_id=1,
        code="P-1",
        project_id=None,
        description=None,
        extra_info={
            "person_id": 7,
            "post_inventory": True,
            "auto_post_warehouse": False,
        },
    )
    values.update(kwargs)
    return SimpleNamespace(**values)


def _existing_line(**kwargs):
    values = dict(
        product_id=3,
        quantity=Decimal("1"),
        description="میز اداری",
        extra_info={
            "unit_price": 10_000_000,
            "line_discount": 0,
            "tax_amount": 900_000,
            "fixed_asset": True,
            "fixed_asset_class_id": 4,
        },
    )
    values.update(kwargs)
    return SimpleNamespace(**values)


def _incoming_line(**kwargs):
    extra = {
        "unit_price": 10_000_000.0,
        "line_discount": 0.0,
        "tax_amount": 900_000.0,
        "line_total": 10_900_000.0,
        "movement": "in",
        "fixed_asset": True,
        "fixed_asset_class_id": 4,
        "tax_snapshot": {"ignored": True},
        "inventory_posted": False,
        "fixed_asset_id": 88,
    }
    extra.update(kwargs.pop("extra_info", {}))
    values = dict(
        product_id=3,
        quantity=1,
        description="میز اداری",
        extra_info=extra,
    )
    values.update(kwargs)
    return values


def _payload(*, document=None, lines=None, extra=None, **overrides):
    document = document or _document()
    extra_info = dict(document.extra_info or {})
    extra_info.update(extra or {})
    extra_info["totals"] = {"gross": 10_000_000.0, "net": 10_900_000.0}
    extra_info["links"] = {"receipt_payment_document_ids": [41]}
    data = {
        "invoice_type": "invoice_purchase",
        "document_date": "2026-01-15",
        "currency_id": 1,
        "code": "P-1",
        "extra_info": extra_info,
        "lines": lines if lines is not None else [_incoming_line()],
        "payments": [{"type": "cash_register", "amount": 500_000, "cash_register_id": 2}],
    }
    data.update(overrides)
    return data


def _db_with_lines(lines):
    db = MagicMock()
    db.query.return_value.filter.return_value.order_by.return_value.all.return_value = lines
    return db


def test_lines_equal_despite_float_and_derived_extra_keys():
    assert _invoice_lines_economically_equal([_existing_line()], [_incoming_line()]) is True


def test_lines_not_equal_when_capital_price_changes():
    incoming = _incoming_line(extra_info={"unit_price": 11_000_000.0})
    assert _invoice_lines_economically_equal([_existing_line()], [incoming]) is False


def test_lines_equal_when_ui_adds_optional_discount_fields():
    incoming = _incoming_line(
        extra_info={
            "discount_type": "percent",
            "discount_value": 0,
            "tax_rate": 9,
            "unit": "عدد",
        }
    )
    assert _invoice_lines_economically_equal([_existing_line()], [incoming]) is True


def test_extra_ignores_links_and_totals_and_defaults_warehouse_flags():
    existing = {"person_id": 7}
    incoming = {
        "person_id": 7,
        "post_inventory": True,
        "auto_post_warehouse": False,
        "totals": {"net": 1},
        "links": {"receipt_payment_document_ids": [9]},
    }
    assert _invoice_extra_body_equal(existing, incoming) is True


def test_extra_detects_person_change():
    assert _invoice_extra_body_equal({"person_id": 7}, {"person_id": 8}) is False


def test_payload_preserves_body_when_only_payments_change():
    document = _document()
    db = _db_with_lines([_existing_line()])
    assert (
        _invoice_payload_preserves_invoice_body(
            db,
            document,
            _payload(document=document),
            inv_type="invoice_purchase",
            old_document_type="invoice_purchase",
        )
        is True
    )


def test_payload_does_not_preserve_body_when_date_changes():
    document = _document()
    db = _db_with_lines([_existing_line()])
    data = _payload(document=document, document_date="2026-02-01")
    assert (
        _invoice_payload_preserves_invoice_body(
            db,
            document,
            data,
            inv_type="invoice_purchase",
            old_document_type="invoice_purchase",
        )
        is False
    )


def test_payload_without_lines_is_payments_only():
    document = _document()
    db = MagicMock()
    data = _payload(document=document)
    data.pop("lines")
    assert (
        _invoice_payload_preserves_invoice_body(
            db,
            document,
            data,
            inv_type="invoice_purchase",
            old_document_type="invoice_purchase",
        )
        is True
    )
    db.query.assert_not_called()


@patch("app.services.invoice_service.invoice_document_to_dict", return_value={"id": 10})
@patch("app.services.invoice_service.invalidate_invoices_cache")
@patch("app.services.invoice_service._sync_invoice_linked_payments")
@patch("app.services.document_service.invalidate_documents_cache")
def test_payments_only_update_syncs_payments_and_commits(
    _mock_docs_cache,
    mock_sync,
    _mock_inv_cache,
    mock_to_dict,
):
    db = MagicMock()
    document = _document()
    data = _payload(document=document)
    result = _apply_invoice_payments_only_update(
        db,
        document=document,
        user_id=4,
        data=data,
        inv_type="invoice_purchase",
        old_document_type="invoice_purchase",
        old_change_payment_id=None,
    )
    mock_sync.assert_called_once()
    db.commit.assert_called_once()
    db.refresh.assert_called_once_with(document)
    mock_to_dict.assert_called_once()
    assert result["id"] == 10


@patch("app.services.invoice_service._apply_invoice_payments_only_update")
@patch("app.services.invoice_service._invoice_payload_preserves_invoice_body", return_value=True)
def test_update_invoice_uses_payments_only_path_when_body_unchanged(mock_preserves, mock_apply):
    mock_apply.return_value = {"id": 10, "path": "payments_only"}
    document = _document()
    fiscal = SimpleNamespace(is_last=True)

    def query_side_effect(model):
        q = MagicMock()
        if model is Document:
            q.filter.return_value.first.return_value = document
        elif model is FiscalYear:
            q.filter.return_value.first.return_value = fiscal
        else:
            q.filter.return_value.first.return_value = None
        return q

    db = MagicMock()
    db.query.side_effect = query_side_effect
    result = update_invoice(
        db,
        10,
        4,
        {"invoice_type": "invoice_purchase", "payments": [{"amount": 1}]},
    )
    mock_preserves.assert_called_once()
    mock_apply.assert_called_once()
    assert result["path"] == "payments_only"
