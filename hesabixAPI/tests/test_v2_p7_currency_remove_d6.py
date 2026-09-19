"""V2-P7 D6: قفل حذف ارز فرعی در صورت استفاده گسترده."""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

from app.services.business_service import get_business_currency_usage


def test_get_business_currency_usage_blocks_when_bank_uses_currency(monkeypatch):
	"""اگر فقط حساب بانکی با آن ارز باشد، can_delete=False."""

	counts = {
		"documents": 0,
		"documents_settles": 0,
		"document_lines": 0,
		"bank": 2,
		"cash": 0,
		"petty": 0,
		"check": 0,
		"product": 0,
		"price": 0,
		"secondary": 1,
	}
	call_i = {"n": 0}

	class FakeQuery:
		def __init__(self, value):
			self._value = value

		def filter(self, *a, **k):
			return self

		def join(self, *a, **k):
			return self

		def scalar(self):
			return self._value

	def fake_query(*args, **kwargs):
		# ترتیب فراخوانی‌ها مطابق get_business_currency_usage
		order = [
			"documents",
			"documents_settles",
			"document_lines",
			"bank",
			"cash",
			"petty",
			"check",
			"product",
			"price",
			"secondary",
		]
		idx = call_i["n"]
		call_i["n"] += 1
		key = order[idx] if idx < len(order) else "documents"
		return FakeQuery(counts[key])

	db = MagicMock()
	db.query.side_effect = fake_query

	usage = get_business_currency_usage(db, business_id=1, currency_id=2)
	assert usage["is_used"] is True
	assert usage["can_delete"] is False
	assert usage["breakdown"]["bank_accounts"] == 2
	assert usage["is_last_secondary"] is True
	assert any("بانک" in b for b in usage["blockers"])
	assert any("آخرین ارز فرعی" in b for b in usage["blockers"])


def test_get_business_currency_usage_allows_when_unused(monkeypatch):
	class FakeQuery:
		def filter(self, *a, **k):
			return self

		def join(self, *a, **k):
			return self

		def scalar(self):
			return 0

	db = MagicMock()
	db.query.side_effect = lambda *a, **k: FakeQuery()
	usage = get_business_currency_usage(db, business_id=1, currency_id=2)
	assert usage["can_delete"] is True
	assert usage["total"] == 0
	assert usage["blockers"] == []
