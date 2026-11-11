from datetime import date
from pathlib import Path

from adapters.db.models import Base, Document, FiscalYear
from adapters.db.models.document_monetization import DocumentUsagePolicy
from app.services.invoice_service import create_invoice
from tests.test_invoice_cancel_zero_cost import sale as sale


def test_invoice_keeps_payload_date_outside_active_fiscal_year(sale):
    db, _ = sale
    for name in ("document_usage_policies", "invoice_item_line_variant_allocations", "invoice_item_line_lot_allocations"):
        Base.metadata.tables[name].create(db.connection())
    db.add(DocumentUsagePolicy(business_id=1, policy_type="free", title="Test", is_active=True))
    db.flush()
    sent = date(2025, 12, 31)
    payload = {"invoice_type": "invoice_sales", "currency_id": 1, "code": "H10", "is_proforma": True,
               "document_date": sent.isoformat(), "extra_info": {"person_id": 1, "post_inventory": False},
               "lines": [{"product_id": 1, "quantity": 1, "extra_info": {"unit_price": 100}}]}
    result = create_invoice(db, 1, 1, payload, commit=False)
    document = db.get(Document, result["data"]["id"])
    active_year = db.query(FiscalYear).filter_by(business_id=1, is_last=True).one()
    assert document.document_date == sent < active_year.start_date
    assert document.fiscal_year_id == active_year.id


def test_woocommerce_plugin_owns_fiscal_date_policy():
    plugin = Path(__file__).resolve().parents[2] / "extraScripts" / "arcwoc"
    service = (plugin / "includes/class-hesabix-v2-order-fiscal-service.php").read_text(encoding="utf-8")
    assert all(f"$policy === '{mode}'" in service for mode in ("keep", "clamp", "skip"))
