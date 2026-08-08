"""Regression: Moadian NOT_FOUND must not wipe a successful send status."""

from __future__ import annotations

from types import SimpleNamespace

from app.services.tax_submission_service import (
    _apply_inquiry_result_to_document,
    _map_inquiry_status,
    normalize_stored_tax_status,
)


def test_map_inquiry_not_found_is_noop() -> None:
    assert _map_inquiry_status("NOT_FOUND") is None
    assert _map_inquiry_status("unknown") is None
    assert _map_inquiry_status("SUCCESS") == "finalized"
    assert _map_inquiry_status("IN_PROGRESS") == "pending"


def test_apply_inquiry_not_found_keeps_sent_status() -> None:
    doc = SimpleNamespace(
        extra_info={
            "tax_status": "sent",
            "tax_tracking_code": "MHf-test-ref",
        }
    )
    _apply_inquiry_result_to_document(
        doc,
        {
            "status": "NOT_FOUND",
            "raw_data": {"status": "NOT_FOUND", "referenceNumber": "MHf-test-ref"},
        },
        now="2026-08-08T08:18:19",
    )
    assert doc.extra_info["tax_status"] == "sent"
    assert doc.extra_info["tax_tracking_code"] == "MHf-test-ref"
    assert doc.extra_info["tax_last_inquiry_response"]["status"] == "NOT_FOUND"


def test_apply_inquiry_not_found_repairs_corrupt_not_found_status() -> None:
    doc = SimpleNamespace(
        extra_info={
            "tax_status": "not_found",
            "tax_tracking_code": "MHf-test-ref",
        }
    )
    _apply_inquiry_result_to_document(
        doc,
        {"status": "NOT_FOUND", "raw_data": {"status": "NOT_FOUND"}},
        now="2026-08-08T08:18:19",
    )
    assert doc.extra_info["tax_status"] == "sent"


def test_normalize_stored_tax_status_maps_not_found_with_tracking() -> None:
    assert (
        normalize_stored_tax_status(
            {"tax_status": "not_found", "tax_tracking_code": "X"}
        )
        == "sent"
    )
    assert normalize_stored_tax_status({"tax_status": "not_found"}) == "not_found"
    assert normalize_stored_tax_status({"tax_tracking_code": "X"}) == "sent"
