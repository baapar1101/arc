from datetime import UTC, date, datetime
from uuid import uuid4

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db.models.document import Document
from app.core.responses import ApiError
from app.services.invoice_service import _woo_invoice_create_operation


def test_woo_create_marker_scopes_replay_and_rejects_a_different_operation():
    engine = create_engine("sqlite://")
    with engine.begin() as conn:
        conn.execute(CreateTable(Document.__table__, include_foreign_key_constraints=[]))
    request = {
        "woo_create_key": str(uuid4()),
        "invoice_type": "invoice_sales",
        "extra_info": {"source": "woocommerce", "wc_order_id": 100},
    }
    with Session(engine) as db:
        operation, replay = _woo_invoice_create_operation(db, 1, request)
        assert replay is None
        db.add(Document(
            business_id=1, fiscal_year_id=1, created_by_user_id=1, currency_id=1,
            document_type="invoice_sales", code="SALE", document_date=date(2026, 11, 11),
            registered_at=datetime.now(UTC),
            developer_settings={"woo_invoice_create": operation},
        ))
        db.commit()

    with Session(engine) as db:
        assert _woo_invoice_create_operation(db, 1, dict(reversed(list(request.items()))))[1] == {
            "id": 1, "code": "SALE", "document_type": "invoice_sales", "woo_create_replayed": True,
        }
        assert _woo_invoice_create_operation(db, 2, request)[1] is None
        assert _woo_invoice_create_operation(db, 1, {**request, "woo_create_key": str(uuid4())})[1] is None
        assert _woo_invoice_create_operation(db, 1, {"invoice_type": "invoice_sales"}) == (None, None)
        changed = {**request, "extra_info": {**request["extra_info"], "wc_order_id": 101}}
        with pytest.raises(ApiError) as error:
            _woo_invoice_create_operation(db, 1, changed)
        assert (error.value.status_code, error.value.code) == (409, "WOO_CREATE_KEY_REUSED")
    engine.dispose()


@pytest.mark.parametrize("invoice_type, order_id", [("invoice_sales_return", 100), ("invoice_sales", None)])
def test_woo_create_key_requires_a_sales_order(invoice_type, order_id):
    with pytest.raises(ApiError) as error:
        _woo_invoice_create_operation(None, 1, {
            "woo_create_key": str(uuid4()),
            "invoice_type": invoice_type,
            "extra_info": {"source": "woocommerce", "wc_order_id": order_id},
        })
    assert (error.value.status_code, error.value.code) == (422, "INVALID_WOO_CREATE_KEY")
