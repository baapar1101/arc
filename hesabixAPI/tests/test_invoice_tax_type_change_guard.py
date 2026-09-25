from unittest.mock import MagicMock

import pytest

from app.core.responses import ApiError
from app.services.tax_reference_service import (
    build_tax_edit_constraints_for_api,
    validate_invoice_proforma_change_for_tax,
    validate_invoice_type_change_for_tax,
)


def _doc(extra: dict | None = None, *, is_proforma: bool = False) -> MagicMock:
    doc = MagicMock()
    doc.extra_info = extra or {}
    doc.is_proforma = is_proforma
    return doc


def test_constraints_allow_type_change_when_not_in_tax_workspace() -> None:
    doc = _doc()
    c = build_tax_edit_constraints_for_api(doc)
    assert c["tax_type_change_allowed"] is True
    assert c["tax_header_locked"] is False
    assert c["is_in_tax_workspace"] is False


def test_constraints_block_type_change_when_sent_to_modian() -> None:
    doc = _doc({"tax_workspace": True, "tax_status": "sent", "tax_tracking_code": "ABC123"})
    c = build_tax_edit_constraints_for_api(doc)
    assert c["tax_type_change_allowed"] is False
    assert c["tax_header_locked"] is True
    assert c["tax_type_change_block_reason"]
    assert "cancel_in_modian" in c["tax_allowed_actions"]


def test_constraints_block_type_change_when_cancelled_in_modian() -> None:
    doc = _doc({"tax_workspace": True, "tax_status": "sent", "tax_cancelled_in_modian": True})
    c = build_tax_edit_constraints_for_api(doc)
    assert c["tax_type_change_allowed"] is False
    assert c["tax_header_locked"] is True


def test_validate_type_change_noop_when_same_type() -> None:
    doc = _doc({"tax_workspace": True, "tax_status": "sent"})
    validate_invoice_type_change_for_tax(doc, "invoice_sales", "invoice_sales")


def _api_error_code(exc: ApiError) -> str:
    detail = exc.detail
    if isinstance(detail, dict):
        err = detail.get("error")
        if isinstance(err, dict):
            return str(err.get("code") or "")
    return ""


def test_validate_type_change_blocks_sent_invoice() -> None:
    doc = _doc({"tax_workspace": True, "tax_status": "finalized"})
    with pytest.raises(ApiError) as exc:
        validate_invoice_type_change_for_tax(doc, "invoice_sales", "invoice_purchase")
    assert _api_error_code(exc.value) == "TAX_TYPE_CHANGE_BLOCKED"
    assert exc.value.status_code == 409


def test_validate_type_change_blocks_purchase_in_tax_workspace() -> None:
    doc = _doc({"tax_workspace": True, "tax_status": "draft"})
    with pytest.raises(ApiError) as exc:
        validate_invoice_type_change_for_tax(doc, "invoice_sales", "invoice_purchase")
    assert _api_error_code(exc.value) == "TAX_WORKSPACE_TYPE_RESTRICTED"
    assert exc.value.status_code == 409


def test_validate_type_change_allows_sales_return_in_workspace() -> None:
    doc = _doc({"tax_workspace": True, "tax_status": "draft"})
    validate_invoice_type_change_for_tax(doc, "invoice_sales", "invoice_sales_return")


def test_validate_proforma_change_blocks_after_submission() -> None:
    doc = _doc({"tax_workspace": True, "tax_status": "accepted"})
    with pytest.raises(ApiError) as exc:
        validate_invoice_proforma_change_for_tax(doc, old_is_proforma=True, new_is_proforma=False)
    assert _api_error_code(exc.value) == "TAX_EDIT_LOCKED"


def test_validate_proforma_change_allows_before_submission() -> None:
    doc = _doc({"tax_workspace": True, "tax_status": "draft"})
    validate_invoice_proforma_change_for_tax(doc, old_is_proforma=True, new_is_proforma=False)
