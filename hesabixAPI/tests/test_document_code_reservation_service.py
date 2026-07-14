"""تست سرویس رزرو شماره سند."""

from datetime import date, datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest

from adapters.db.models.document_numbering import DocumentCodeReservation
from app.core.responses import ApiError
from app.services.document_code_reservation_service import (
    cancel_document_code_reservation,
    mark_reservation_used,
    reserve_document_code,
    validate_reservation_for_invoice_create,
)


def _active_reservation(**overrides):
    now = datetime.now(timezone.utc)
    data = {
        "id": "res-1",
        "business_id": 10,
        "reserved_by_user_id": 5,
        "document_type": "invoice_sales",
        "document_date": date(2026, 7, 14),
        "code": "INV-20260714-0001",
        "status": "active",
        "expires_at": now + timedelta(hours=4),
        "created_at": now,
        "used_at": None,
        "cancelled_at": None,
    }
    data.update(overrides)
    return DocumentCodeReservation(**data)


def _api_error_code(exc: ApiError) -> str:
    return exc.detail["error"]["code"]


@patch("app.services.document_code_reservation_service.generate_document_code")
@patch("app.services.document_code_reservation_service.expire_stale_reservations")
def test_reserve_document_code_returns_payload(mock_expire, mock_generate):
    mock_generate.return_value = "INV-20260714-0007"
    db = MagicMock()
    db.flush.side_effect = lambda: None

    result = reserve_document_code(
        db,
        business_id=10,
        user_id=5,
        document_type="invoice_sales",
        document_date=date(2026, 7, 14),
    )

    assert result["code"] == "INV-20260714-0007"
    assert result["document_type"] == "invoice_sales"
    assert result["document_date"] == "2026-07-14"
    assert result["status"] == "active"
    assert result["reservation_id"]
    db.add.assert_called_once()
    mock_expire.assert_called_once_with(db, business_id=10)


def test_reserve_document_code_rejects_invalid_type():
    db = MagicMock()
    with pytest.raises(ApiError) as exc:
        reserve_document_code(
            db,
            business_id=10,
            user_id=5,
            document_type="receipt",
            document_date=date(2026, 7, 14),
        )
    assert _api_error_code(exc.value) == "INVALID_DOCUMENT_TYPE"


def test_validate_reservation_for_invoice_create_checks_mismatch():
    db = MagicMock()
    reservation = _active_reservation()
    query = MagicMock()
    query.filter.return_value = query
    query.with_for_update.return_value = query
    query.first.return_value = reservation
    db.query.return_value = query

    with pytest.raises(ApiError) as exc:
        validate_reservation_for_invoice_create(
            db,
            business_id=10,
            user_id=5,
            reservation_id="res-1",
            invoice_type="invoice_purchase",
            document_date=date(2026, 7, 14),
        )
    assert _api_error_code(exc.value) == "CODE_RESERVATION_MISMATCH"


def test_validate_reservation_for_invoice_create_success():
    db = MagicMock()
    reservation = _active_reservation()
    query = MagicMock()
    query.filter.return_value = query
    query.with_for_update.return_value = query
    query.first.return_value = reservation
    db.query.return_value = query

    result = validate_reservation_for_invoice_create(
        db,
        business_id=10,
        user_id=5,
        reservation_id="res-1",
        invoice_type="invoice_sales",
        document_date=date(2026, 7, 14),
    )
    assert result.code == "INV-20260714-0001"


def test_cancel_document_code_reservation_marks_cancelled():
    db = MagicMock()
    reservation = _active_reservation()
    query = MagicMock()
    query.filter.return_value = query
    query.with_for_update.return_value = query
    query.first.return_value = reservation
    db.query.return_value = query

    cancelled = cancel_document_code_reservation(
        db,
        business_id=10,
        user_id=5,
        reservation_id="res-1",
    )
    assert cancelled is True
    assert reservation.status == "cancelled"
    assert reservation.cancelled_at is not None


def test_mark_reservation_used():
    db = MagicMock()
    reservation = _active_reservation()
    mark_reservation_used(db, reservation)
    assert reservation.status == "used"
    assert reservation.used_at is not None


def test_reserve_and_cancel_integration_roundtrip():
    from datetime import date

    from adapters.db.session import get_db_session
    from adapters.db.models.document_numbering import DocumentCodeReservation
    from app.services.document_code_reservation_service import (
        cancel_document_code_reservation,
        reserve_document_code,
    )

    with get_db_session() as db:
        result = reserve_document_code(
            db,
            business_id=1,
            user_id=1,
            document_type="invoice_sales",
            document_date=date(2026, 7, 14),
        )
        db.commit()

        reservation_id = result["reservation_id"]
        assert result["code"]
        assert result["status"] == "active"

        row = db.get(DocumentCodeReservation, reservation_id)
        assert row is not None
        assert row.code == result["code"]
        assert row.status == "active"

        cancelled = cancel_document_code_reservation(
            db,
            business_id=1,
            user_id=1,
            reservation_id=reservation_id,
        )
        db.commit()
        assert cancelled is True

        db.refresh(row)
        assert row.status == "cancelled"


def test_reserve_assigns_unique_codes_sequentially():
    from datetime import date

    from adapters.db.session import get_db_session
    from app.services.document_code_reservation_service import (
        cancel_document_code_reservation,
        reserve_document_code,
    )

    with get_db_session() as db:
        first = reserve_document_code(
            db,
            business_id=1,
            user_id=1,
            document_type="invoice_sales",
            document_date=date(2026, 7, 14),
        )
        second = reserve_document_code(
            db,
            business_id=1,
            user_id=1,
            document_type="invoice_sales",
            document_date=date(2026, 7, 14),
        )
        db.commit()

        assert first["code"] != second["code"]

        for rid in (first["reservation_id"], second["reservation_id"]):
            cancel_document_code_reservation(
                db,
                business_id=1,
                user_id=1,
                reservation_id=rid,
            )
        db.commit()
