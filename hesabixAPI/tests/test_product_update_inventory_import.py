"""Regression: inventory sync helpers must be module-level in product_service."""

from pathlib import Path


def test_update_product_does_not_import_inventory_sync_inside_condition() -> None:
    path = Path(__file__).resolve().parents[1] / "app" / "services" / "product_service.py"
    text = path.read_text(encoding="utf-8")
    start = text.find("def update_product(")
    assert start >= 0
    end = text.find("\ndef ", start + 1)
    body = text[start:end] if end >= 0 else text[start:]
    assert "from app.services.product_inventory_tracking_sync import" not in body
