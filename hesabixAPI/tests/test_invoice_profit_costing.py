from datetime import datetime
from decimal import Decimal

from app.services.invoice_service import (
    _build_cost_layers_from_movements,
    _consume_cost_layers_for_quantity,
    _movement_sort_key,
    _normalize_invoice_profit_basis,
    _normalize_invoice_profit_fifo_shortage_mode,
    _normalize_invoice_profit_method,
    _normalize_invoice_profit_overhead_type,
    _normalize_invoice_profit_type,
    _unit_cost_fifo_jbfn_at_target_outbound_line,
    _unit_wma_cost_at_target_outbound_line,
)


def _movement(doc_id: int, d: str, movement: str, qty: str, cost: str | None = None):
    return {
        "document_id": doc_id,
        "document_date": d,
        "movement": movement,
        "quantity": Decimal(qty),
        "cost_price": Decimal(cost) if cost is not None else None,
    }


def test_fifo_layers_respect_historical_outgoing() -> None:
    movements = [
        _movement(1, "2026-01-01", "in", "100", "10"),
        _movement(2, "2026-01-02", "in", "50", "20"),
        _movement(3, "2026-01-03", "out", "80"),
    ]
    layers = _build_cost_layers_from_movements(movements, reverse=False)
    unit_cost = _consume_cost_layers_for_quantity(layers, Decimal("20"))
    assert unit_cost == Decimal("10")


def test_lifo_layers_respect_historical_outgoing() -> None:
    movements = [
        _movement(1, "2026-01-01", "in", "100", "10"),
        _movement(2, "2026-01-02", "in", "50", "20"),
        _movement(3, "2026-01-03", "out", "30"),
    ]
    layers = _build_cost_layers_from_movements(movements, reverse=True)
    unit_cost = _consume_cost_layers_for_quantity(layers, Decimal("10"))
    assert unit_cost == Decimal("20")


def test_consume_layers_fallback_to_last_known_cost() -> None:
    movements = [
        _movement(1, "2026-01-01", "in", "2", "15"),
    ]
    layers = _build_cost_layers_from_movements(movements, reverse=False)
    unit_cost = _consume_cost_layers_for_quantity(layers, Decimal("5"))
    assert unit_cost == Decimal("15")


def test_consume_layers_average_on_shortage() -> None:
    """بخش بدون لایه با average_purchase_on_shortage."""
    movements = [
        _movement(1, "2026-01-01", "in", "2", "15"),
    ]
    layers = _build_cost_layers_from_movements(movements, reverse=False)
    unit_cost = _consume_cost_layers_for_quantity(
        layers,
        Decimal("5"),
        fifo_shortage_mode="average_purchase_on_shortage",
        average_unit_for_shortage=Decimal("20"),
    )
    # 2*15 + 3*20 = 90 / 5 = 18
    assert unit_cost == Decimal("18")


def test_movement_sort_same_day_registered_at_before_document_id() -> None:
    """در یک روز، زمان ثبت سند از شناسهٔ سند برای ترتیب FIFO مهم‌تر است."""
    later_id_earlier_time = {
        "document_date": "2026-01-01",
        "registered_at": datetime(2026, 1, 1, 9, 0, 0),
        "document_id": 99,
        "invoice_item_line_id": 1,
        "movement": "in",
        "quantity": Decimal("1"),
        "cost_price": Decimal("150"),
    }
    earlier_id_later_time = {
        "document_date": "2026-01-01",
        "registered_at": datetime(2026, 1, 1, 11, 0, 0),
        "document_id": 50,
        "invoice_item_line_id": 1,
        "movement": "in",
        "quantity": Decimal("1"),
        "cost_price": Decimal("999"),
    }
    ordered = sorted([earlier_id_later_time, later_id_earlier_time], key=_movement_sort_key)
    assert ordered[0]["document_id"] == 99


def _mv_wma(
    doc_id: int,
    line_id: int,
    d: str,
    movement: str,
    qty: str,
    cost: str | None = None,
    reg_at: datetime | None = None,
):
    return {
        "document_id": doc_id,
        "document_date": d,
        "registered_at": reg_at or datetime.min,
        "invoice_item_line_id": line_id,
        "movement": movement,
        "quantity": Decimal(qty),
        "cost_price": Decimal(cost) if cost is not None else None,
    }


def test_wma_unit_cost_at_target_after_two_purchases() -> None:
    movements = [
        _mv_wma(1, 1, "2026-01-01", "in", "100", "10"),
        _mv_wma(2, 2, "2026-01-02", "in", "50", "20"),
        _mv_wma(3, 3, "2026-01-03", "out", "60"),
    ]
    unit = _unit_wma_cost_at_target_outbound_line(
        movements,
        Decimal("60"),
        3,
        3,
        fifo_shortage_mode="perpetual_mixed",
    )
    assert unit == Decimal("40") / Decimal("3")


def test_wma_after_partial_sale_and_new_purchase() -> None:
    movements = [
        _mv_wma(1, 1, "2026-01-01", "in", "100", "10"),
        _mv_wma(2, 2, "2026-01-02", "out", "80"),
        _mv_wma(3, 3, "2026-01-03", "in", "50", "20"),
        _mv_wma(4, 4, "2026-01-04", "out", "10"),
    ]
    unit = _unit_wma_cost_at_target_outbound_line(
        movements,
        Decimal("10"),
        4,
        4,
        fifo_shortage_mode="perpetual_mixed",
    )
    assert unit == Decimal("1200") / Decimal("70")


def test_wma_shortage_uses_last_wac_perpetual() -> None:
    movements = [
        _mv_wma(1, 1, "2026-01-01", "in", "100", "10"),
        _mv_wma(2, 2, "2026-01-02", "out", "120"),
    ]
    unit = _unit_wma_cost_at_target_outbound_line(
        movements,
        Decimal("120"),
        2,
        2,
        fifo_shortage_mode="perpetual_mixed",
    )
    assert unit == Decimal("10")


def test_wma_shortage_uses_average_purchase_when_configured() -> None:
    movements = [
        _mv_wma(1, 1, "2026-01-01", "in", "100", "10"),
        _mv_wma(2, 2, "2026-01-02", "out", "120"),
    ]
    unit = _unit_wma_cost_at_target_outbound_line(
        movements,
        Decimal("120"),
        2,
        2,
        fifo_shortage_mode="average_purchase_on_shortage",
        average_unit_for_shortage=Decimal("25"),
    )
    assert unit == (Decimal("1000") + Decimal("20") * Decimal("25")) / Decimal("120")


def _mv_jbfn(
    doc_id: int,
    line_id: int,
    d: str,
    movement: str,
    qty: str,
    cost: str | None = None,
    reg_at: datetime | None = None,
):
    return {
        "document_id": doc_id,
        "document_date": d,
        "registered_at": reg_at or datetime.min,
        "invoice_item_line_id": line_id,
        "movement": movement,
        "quantity": Decimal(qty),
        "cost_price": Decimal(cost) if cost is not None else None,
    }


def test_fifo_jbfn_sale_before_purchase_borrows_future_in() -> None:
    """خروج پیش از ورود: هزینه از خرید بعدی در همان زنجیره."""
    movements = [
        _mv_jbfn(1, 101, "2026-01-02", "out", "10"),
        _mv_jbfn(2, 201, "2026-01-05", "in", "10", "100"),
    ]
    unit = _unit_cost_fifo_jbfn_at_target_outbound_line(
        movements,
        Decimal("10"),
        1,
        101,
        fifo_shortage_mode="perpetual_mixed",
    )
    assert unit == Decimal("100")


def test_fifo_jbfn_two_sales_then_one_purchase() -> None:
    movements = [
        _mv_jbfn(1, 1, "2026-01-01", "out", "5"),
        _mv_jbfn(2, 2, "2026-01-02", "out", "7"),
        _mv_jbfn(3, 3, "2026-01-03", "in", "15", "40"),
    ]
    u1 = _unit_cost_fifo_jbfn_at_target_outbound_line(
        movements, Decimal("5"), 1, 1, fifo_shortage_mode="perpetual_mixed"
    )
    u2 = _unit_cost_fifo_jbfn_at_target_outbound_line(
        movements, Decimal("7"), 2, 2, fifo_shortage_mode="perpetual_mixed"
    )
    assert u1 == Decimal("40")
    assert u2 == Decimal("40")


def test_fifo_jbfn_end_chain_shortage_perpetual_zero_without_layer() -> None:
    """بدون هیچ ورودی در دنباله؛ کسری مانند FIFO دائمی بدون لایه → صفر برای باقیمانده."""
    movements = [
        _mv_jbfn(1, 1, "2026-01-01", "out", "10"),
    ]
    unit = _unit_cost_fifo_jbfn_at_target_outbound_line(
        movements,
        Decimal("10"),
        1,
        1,
        fifo_shortage_mode="perpetual_mixed",
    )
    assert unit == Decimal("0")


def test_fifo_jbfn_end_chain_shortage_uses_average_when_configured() -> None:
    movements = [
        _mv_jbfn(1, 1, "2026-01-01", "out", "10"),
    ]
    unit = _unit_cost_fifo_jbfn_at_target_outbound_line(
        movements,
        Decimal("10"),
        1,
        1,
        fifo_shortage_mode="average_purchase_on_shortage",
        average_unit_for_shortage=Decimal("25"),
    )
    assert unit == Decimal("25")


def test_profit_setting_normalizers() -> None:
    assert _normalize_invoice_profit_method("MANUAL") == "manual"
    assert _normalize_invoice_profit_method("weird") == "automatic"

    assert _normalize_invoice_profit_basis("FIFO") == "fifo"
    assert _normalize_invoice_profit_basis("fifo_jbfn") == "fifo_jbfn"
    assert _normalize_invoice_profit_basis("wma") == "moving_weighted_average"
    assert _normalize_invoice_profit_basis("unknown") == "purchase_price"

    assert _normalize_invoice_profit_fifo_shortage_mode(None) == "perpetual_mixed"
    assert _normalize_invoice_profit_fifo_shortage_mode("AVERAGE_purchase_on_shortage") == (
        "average_purchase_on_shortage"
    )

    assert _normalize_invoice_profit_overhead_type("CUSTOM_PERCENT") == "custom_percent"
    assert _normalize_invoice_profit_overhead_type("bad") == "none"

    assert _normalize_invoice_profit_type("BOTH") == "both"
    assert _normalize_invoice_profit_type("none") == "gross"
