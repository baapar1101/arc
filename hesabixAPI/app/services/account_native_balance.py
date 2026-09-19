"""محاسبه مبلغ بومی یک خط سند برای موجودی بانک/صندوق/تنخواه."""
from __future__ import annotations

from decimal import Decimal
from typing import Any, Optional

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine


def _d(v: Any) -> Decimal:
	try:
		return Decimal(str(v if v is not None else 0))
	except Exception:
		return Decimal(0)


def line_native_signed_amount_for_account(
	line: DocumentLine,
	document: Document,
	*,
	account_currency_id: Optional[int],
) -> Decimal:
	"""
	سهم خط در موجودی حساب به ارز همان حساب.

	Returns: مقدار علامت‌دار (بدهکار مثبت، بستانکار منفی) به ارز حساب.
	اگر ارز سند با ارز حساب ناسازگار باشد و native موجود نباشد → 0 (نادیده).
	"""
	extra = line.extra_info if isinstance(line.extra_info, dict) else {}
	native = extra.get("account_currency_amount")
	native_cur = extra.get("account_currency_id")
	use_native = (
		native is not None
		and account_currency_id is not None
		and native_cur is not None
		and int(native_cur) == int(account_currency_id)
	)
	if use_native:
		amt = _d(native)
		if _d(line.debit) > 0:
			return amt
		if _d(line.credit) > 0:
			return -amt
		return Decimal(0)

	if account_currency_id is not None and int(document.currency_id or 0) not in (0, int(account_currency_id)):
		return Decimal(0)

	return _d(line.debit) - _d(line.credit)
