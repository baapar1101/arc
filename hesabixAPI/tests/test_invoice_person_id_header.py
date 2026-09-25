"""خواندن person_id فاکتور از extra_info یا ریشهٔ payload (ابزار AI)."""
from __future__ import annotations

from app.services.invoice_service import _person_id_from_header


def test_person_id_from_extra_info():
    assert _person_id_from_header({"extra_info": {"person_id": 176105}}) == 176105


def test_person_id_from_root_payload():
    assert (
        _person_id_from_header(
            {
                "invoice_type": "invoice_sales",
                "person_id": 176105,
                "extra_info": {},
            }
        )
        == 176105
    )


def test_person_id_prefers_extra_info_over_root():
    assert (
        _person_id_from_header(
            {"person_id": 1, "extra_info": {"person_id": 99}}
        )
        == 99
    )


def test_person_id_missing_returns_none():
    assert _person_id_from_header({"extra_info": {}}) is None
    assert _person_id_from_header({}) is None
