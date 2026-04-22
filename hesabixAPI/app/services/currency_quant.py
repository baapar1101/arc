"""تبدیل تنظیمات ارز به quant برای Decimal (گرد کردن مبلغ)."""
from __future__ import annotations

from decimal import Decimal
from typing import Optional

from sqlalchemy.orm import Session

from adapters.db.models.currency import Currency


def decimal_places_to_quant(decimal_places: int) -> Decimal:
	"""مثلاً 0 → 1 (ریال)، 2 → 0.01 (دلار)."""
	d = max(0, min(8, int(decimal_places)))
	if d == 0:
		return Decimal("1")
	return Decimal("1") / (Decimal(10) ** d)


def get_currency_quant_and_round(
	db: Session,
	currency_id: Optional[int],
) -> tuple[Decimal, bool]:
	"""
	برمی‌گرداند (quant برای گرد کردن، آیا به واحد پول گرد شود).
	اگر ارز پیدا نشود: quant=1، round=True (رفتار قبلی).
	"""
	if currency_id is None:
		return Decimal("1"), True
	row = db.query(Currency).filter(Currency.id == int(currency_id)).first()
	if row is None:
		return Decimal("1"), True
	dp = int(row.decimal_places) if row.decimal_places is not None else 2
	round_on = bool(row.round_monetary_amounts) if row.round_monetary_amounts is not None else True
	return decimal_places_to_quant(dp), round_on
