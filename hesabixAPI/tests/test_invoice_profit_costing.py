from decimal import Decimal

from app.services.invoice_service import (
    _build_cost_layers_from_movements,
    _consume_cost_layers_for_quantity,
    _normalize_invoice_profit_basis,
    _normalize_invoice_profit_method,
    _normalize_invoice_profit_overhead_type,
    _normalize_invoice_profit_type,
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


def test_profit_setting_normalizers() -> None:
    assert _normalize_invoice_profit_method("MANUAL") == "manual"
    assert _normalize_invoice_profit_method("weird") == "automatic"

    assert _normalize_invoice_profit_basis("FIFO") == "fifo"
    assert _normalize_invoice_profit_basis("unknown") == "purchase_price"

    assert _normalize_invoice_profit_overhead_type("CUSTOM_PERCENT") == "custom_percent"
    assert _normalize_invoice_profit_overhead_type("bad") == "none"

    assert _normalize_invoice_profit_type("BOTH") == "both"
    assert _normalize_invoice_profit_type("none") == "gross"
