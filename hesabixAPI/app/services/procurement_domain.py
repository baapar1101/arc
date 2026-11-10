"""قواعد خالص تدارکات: مقایسه، تطبیق سه‌گانه، بودجه و وضعیت.

این ماژول به دیتابیس وصل نیست تا قواعد مالی بدون زیرساخت قابل آزمون باشند.
"""
from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence

MONEY = Decimal("0.01")
QTY = Decimal("0.000001")

DEFAULT_WEIGHTS: Dict[str, Decimal] = {
	"price": Decimal("40"),
	"delivery": Decimal("20"),
	"quality": Decimal("20"),
	"payment": Decimal("10"),
	"risk": Decimal("10"),
}


def D(value: Any) -> Decimal:
	if isinstance(value, Decimal):
		return value
	if value is None or value == "":
		return Decimal("0")
	return Decimal(str(value))


def money(value: Any) -> Decimal:
	return D(value).quantize(MONEY, rounding=ROUND_HALF_UP)


def qty(value: Any) -> Decimal:
	return D(value).quantize(QTY, rounding=ROUND_HALF_UP)


def line_amount(quantity: Any, unit_price: Any, discount: Any = 0, tax: Any = 0) -> Decimal:
	gross = D(quantity) * D(unit_price)
	net = gross - D(discount)
	if net < 0:
		net = Decimal("0")
	return money(net + D(tax))


def normalize_weights(weights: Optional[Mapping[str, Any]], criteria: Sequence[str]) -> Dict[str, Decimal]:
	keys = [key for key in criteria if key]
	if not keys:
		return {}
	raw = {key: D((weights or {}).get(key, 0)) for key in keys}
	total = sum(raw.values(), Decimal("0"))
	if total <= 0:
		share = (Decimal("100") / Decimal(len(keys))).quantize(Decimal("0.0001"))
		return {key: share for key in keys}
	return {key: (raw[key] / total) * Decimal("100") for key in keys}


def _lower_better(value: Decimal, best: Decimal) -> Decimal:
	if value <= 0 and best <= 0:
		return Decimal("100")
	if value <= 0:
		return Decimal("0")
	if best <= 0:
		return Decimal("100")
	return (best / value) * Decimal("100")


def _higher_better(value: Decimal, best: Decimal) -> Decimal:
	if best <= 0:
		return Decimal("100")
	if value <= 0:
		return Decimal("0")
	return (value / best) * Decimal("100")


def compare_bids(
	rows: Sequence[Mapping[str, Any]],
	weights: Optional[Mapping[str, Any]] = None,
) -> List[Dict[str, Any]]:
	"""امتیاز وزنی پیشنهادها. معیار بدون داده برای همهٔ ردیف‌ها از مخرج خارج می‌شود."""
	if not rows:
		return []
	criteria = ["price", "delivery", "payment"]
	if all(row.get("quality") is not None for row in rows):
		criteria.append("quality")
	if all(row.get("risk") is not None for row in rows):
		criteria.append("risk")
	normalized = normalize_weights(weights or DEFAULT_WEIGHTS, criteria)
	prices = [D(row.get("price_total")) for row in rows]
	deliveries = [D(row.get("delivery_days")) for row in rows]
	payments = [D(row.get("payment_days")) for row in rows]
	best_price = min(prices)
	best_delivery = min(deliveries)
	best_payment = max(payments)
	scored: List[Dict[str, Any]] = []
	for row in rows:
		parts: Dict[str, Decimal] = {
			"price": _lower_better(D(row.get("price_total")), best_price),
			"delivery": _lower_better(D(row.get("delivery_days")), best_delivery),
			"payment": _higher_better(D(row.get("payment_days")), best_payment),
		}
		if "quality" in normalized:
			parts["quality"] = D(row.get("quality"))
		if "risk" in normalized:
			parts["risk"] = Decimal("100") - D(row.get("risk"))
		total = sum((parts[key] * normalized[key] / Decimal("100") for key in normalized), Decimal("0"))
		scored.append(
			{
				"invite_id": row.get("invite_id"),
				"total": money(total),
				"parts": {key: money(value) for key, value in parts.items() if key in normalized},
				"weights": {key: money(value) for key, value in normalized.items()},
			}
		)
	scored.sort(key=lambda item: item["total"], reverse=True)
	for index, item in enumerate(scored, start=1):
		item["rank"] = index
	return scored


def match_line(
	*,
	ordered: Any,
	accepted: Any,
	invoice_qty: Any,
	po_price: Any,
	invoice_price: Any,
	qty_tolerance_pct: Any = 0,
	price_tolerance: Any = 0,
	item_kind: str = "goods",
	service_confirmed: bool = False,
) -> Dict[str, Any]:
	"""تطبیق یک سطر سفارش، رسید پذیرفته و فاکتور.

	مقدار بیش از سقف رسید (با تلورانس) همیشه استثناست و قابل چشم‌پوشی نیست.
	اختلاف قیمت بیش از تلورانس استثناست و فقط با تأیید صریح عبور می‌کند.
	"""
	ordered_q = D(ordered)
	accepted_q = D(accepted)
	invoice_q = D(invoice_qty)
	cap = accepted_q
	if item_kind == "service" and not service_confirmed:
		cap = Decimal("0")
	allowance = cap * (Decimal("1") + (D(qty_tolerance_pct) / Decimal("100")))
	reasons: List[str] = []
	status = "matched"
	if invoice_q - allowance > QTY:
		status = "exception"
		reasons.append("qty")
	elif invoice_q - cap > QTY:
		status = "tolerance"
		reasons.append("qty")
	diff = abs(D(invoice_price) - D(po_price))
	if diff - D(price_tolerance) > MONEY:
		status = "exception"
		reasons.append("price")
	elif diff > MONEY:
		if status == "matched":
			status = "tolerance"
		reasons.append("price")
	return {
		"status": status,
		"reasons": reasons,
		"cap": qty(cap),
		"allowance": qty(allowance),
		"price_diff": money(diff),
	}


def aggregate_match(rows: Iterable[Mapping[str, Any]]) -> str:
	statuses = [str(row.get("status") or "matched") for row in rows]
	if any(item == "exception" for item in statuses):
		return "exception"
	if any(item == "tolerance" for item in statuses):
		return "tolerance"
	return "matched"


def budget_available(
	amount: Any,
	increases: Any = 0,
	transfer_in: Any = 0,
	transfer_out: Any = 0,
	open_commitments: Any = 0,
	actuals: Any = 0,
) -> Decimal:
	"""قابل مصرف = اصل + افزایش + انتقال ورودی − انتقال خروجی − تعهد باز − مصرف."""
	return money(
		D(amount) + D(increases) + D(transfer_in) - D(transfer_out) - D(open_commitments) - D(actuals)
	)


def grade_for_score(score: Any) -> str:
	value = D(score)
	if value >= 85:
		return "A"
	if value >= 70:
		return "B"
	if value >= 50:
		return "C"
	return "D"


def supplier_score(metrics: Mapping[str, Optional[Any]], weights: Optional[Mapping[str, Any]] = None) -> Dict[str, Any]:
	"""امتیاز دوره. معیار None از مخرج وزن حذف می‌شود. هر معیار از ۰ تا ۱۰۰ است."""
	available = [key for key, value in metrics.items() if value is not None]
	normalized = normalize_weights(weights, available)
	total = sum((D(metrics[key]) * normalized[key] / Decimal("100") for key in normalized), Decimal("0"))
	total_money = money(total)
	return {
		"total": total_money,
		"grade": grade_for_score(total_money),
		"weights": {key: money(value) for key, value in normalized.items()},
	}


def suggested_buy_qty(*, on_hand: Any, open_qty: Any, reorder_point: Any, min_order_qty: Any) -> Decimal:
	"""پیشنهاد خرید از دادهٔ واقعی کالا. اگر زیر نقطهٔ سفارش نباشد صفر است."""
	gap = D(reorder_point) - D(on_hand) - D(open_qty)
	if gap <= 0:
		return Decimal("0")
	minimum = D(min_order_qty)
	if minimum > gap:
		return qty(minimum)
	return qty(gap)


def covered_by_stock(*, needed: Any, on_hand: Any, open_qty: Any) -> bool:
	return D(on_hand) + D(open_qty) + QTY >= D(needed)


REQ_TRANSITIONS = {
	"draft": {"pending_approval", "cancelled"},
	"returned": {"pending_approval", "cancelled"},
	"pending_approval": {"approved", "returned", "rejected"},
	"approved": {"converted", "cancelled"},
	"rejected": set(),
	"converted": set(),
	"cancelled": set(),
}

ORDER_TRANSITIONS = {
	"draft": {"pending_approval", "cancelled"},
	"pending_approval": {"approved", "draft", "cancelled"},
	"approved": {"sent", "cancelled"},
	"sent": {"partial", "received", "cancelled"},
	"partial": {"partial", "received", "invoiced", "cancelled"},
	"received": {"invoiced", "closed"},
	"invoiced": {"closed", "invoiced"},
	"closed": set(),
	"cancelled": set(),
}


def can_transition(table: Mapping[str, set], current: str, target: str) -> bool:
	return target in table.get(current, set())
