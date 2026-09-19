from decimal import Decimal
from types import SimpleNamespace

from app.services.warehouse_service import (
	_compute_line_quantities_core,
	invoice_warehouse_fulfillment_is_complete,
	line_quantities_has_remaining,
	resolve_invoice_warehouse_state,
)


def _line(invoice_item_line_id: int, product_id: int, quantity: float) -> SimpleNamespace:
	return SimpleNamespace(id=invoice_item_line_id, product_id=product_id, quantity=quantity)


def _wh(status: str, *, movement: str = "out", quantity: float = 0, line_id: int | None = None) -> SimpleNamespace:
	extra = {"invoice_item_line_id": line_id} if line_id is not None else {}
	line = SimpleNamespace(
		movement=movement,
		quantity=quantity,
		product_id=1,
		extra_info=extra,
	)
	return SimpleNamespace(status=status, lines=[line])


def test_partial_posted_delivery_keeps_remaining_and_partial_state() -> None:
	item_rows = [_line(10, 1, 100)]
	warehouse_docs = [_wh("posted", quantity=10, line_id=10)]

	line_qty = _compute_line_quantities_core("invoice_sales", item_rows, warehouse_docs)

	assert line_qty[0]["required_quantity"] == 100.0
	assert line_qty[0]["processed_quantity"] == 10.0
	assert line_qty[0]["remaining_quantity"] == 90.0
	assert line_quantities_has_remaining(line_qty) is True
	assert resolve_invoice_warehouse_state(warehouse_docs, line_qty) == "partial"
	assert invoice_warehouse_fulfillment_is_complete(warehouse_docs, line_qty) is False


def test_fully_posted_delivery_is_complete() -> None:
	item_rows = [_line(10, 1, 100)]
	warehouse_docs = [_wh("posted", quantity=100, line_id=10)]

	line_qty = _compute_line_quantities_core("invoice_sales", item_rows, warehouse_docs)

	assert line_quantities_has_remaining(line_qty) is False
	assert resolve_invoice_warehouse_state(warehouse_docs, line_qty) == "posted"
	assert invoice_warehouse_fulfillment_is_complete(warehouse_docs, line_qty) is True


def test_multiple_posted_docs_accumulate_processed_quantity() -> None:
	item_rows = [_line(10, 1, 100)]
	warehouse_docs = [
		_wh("posted", quantity=10, line_id=10),
		_wh("posted", quantity=25, line_id=10),
	]

	line_qty = _compute_line_quantities_core("invoice_sales", item_rows, warehouse_docs)

	assert line_qty[0]["processed_quantity"] == 35.0
	assert line_qty[0]["remaining_quantity"] == 65.0
	assert resolve_invoice_warehouse_state(warehouse_docs, line_qty) == "partial"


def test_draft_does_not_reduce_remaining() -> None:
	item_rows = [_line(10, 1, 100)]
	warehouse_docs = [
		_wh("posted", quantity=10, line_id=10),
		_wh("draft", quantity=90, line_id=10),
	]

	line_qty = _compute_line_quantities_core("invoice_sales", item_rows, warehouse_docs)

	assert line_qty[0]["remaining_quantity"] == 90.0
	assert resolve_invoice_warehouse_state(warehouse_docs, line_qty) == "partial"
	assert invoice_warehouse_fulfillment_is_complete(warehouse_docs, line_qty) is False


def test_no_warehouse_docs_is_missing() -> None:
	item_rows = [_line(10, 1, 100)]
	line_qty = _compute_line_quantities_core("invoice_sales", item_rows, [])

	assert resolve_invoice_warehouse_state([], line_qty) == "missing"
	assert invoice_warehouse_fulfillment_is_complete([], line_qty) is False
