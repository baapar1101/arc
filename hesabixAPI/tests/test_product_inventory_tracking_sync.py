from unittest.mock import MagicMock

from app.services.product_inventory_tracking_sync import (
    _set_line_inventory_tracked,
    product_has_stale_inventory_tracking_lines,
    sync_product_inventory_tracking_change,
)


def test_set_line_inventory_tracked_updates_when_different() -> None:
    line = MagicMock()
    line.extra_info = {"inventory_tracked": False, "movement": "in"}
    changed = _set_line_inventory_tracked(line, True)
    assert changed is True
    assert line.extra_info["inventory_tracked"] is True


def test_set_line_inventory_tracked_skips_when_same() -> None:
    line = MagicMock()
    line.extra_info = {"inventory_tracked": True}
    changed = _set_line_inventory_tracked(line, True)
    assert changed is False


def test_product_has_stale_inventory_tracking_lines_detects_mismatch() -> None:
    line = MagicMock()
    line.extra_info = {"inventory_tracked": False}
    document = MagicMock()
    db = MagicMock()
    db.query.return_value.join.return_value.filter.return_value.order_by.return_value.all.return_value = [
        (line, document)
    ]
    assert product_has_stale_inventory_tracking_lines(
        db,
        business_id=1,
        product_id=10,
        expected_tracked=True,
    )


def test_sync_noop_when_already_consistent(monkeypatch) -> None:
    db = MagicMock()
    monkeypatch.setattr(
        "app.services.product_inventory_tracking_sync._invoice_lines_for_product",
        lambda *args, **kwargs: [],
    )
    result = sync_product_inventory_tracking_change(
        db,
        business_id=1,
        product_id=10,
        old_track_inventory=True,
        new_track_inventory=True,
    )
    assert result["changed"] is False
    assert result["lines_updated"] == 0
