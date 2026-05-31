from __future__ import annotations

from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from app.services.expense_income_service import _get_fixed_account_by_code
from app.services.legacy_import.legacy_chart_resolver import LegacyChartResolver

# نگاشت ref_id / code حساب قدیمی (hesabdari_table) به کد حساب ثابت جدید
_REF_CODE_TO_FIXED: Dict[str, str] = {
	"3": "10401",
	"8": "20201",
	"5": "10203",
	"121": "10202",
	"122": "10201",
	"123": "10202",
	"124": "10201",
	"125": "10403",
	"137": "10102",
}

_ACCOUNT_TYPE_TO_FIXED: Dict[str, str] = {
	"person": "10401",
	"bank": "10203",
	"cashdesk": "10202",
	"salary": "10201",
}


def build_ref_id_index(data_rows: list) -> Dict[int, Dict[str, Any]]:
	index: Dict[int, Dict[str, Any]] = {}
	for row in data_rows:
		rid = row.get("id")
		if rid is None:
			continue
		try:
			index[int(rid)] = row
		except (TypeError, ValueError):
			continue
	return index


class LegacySqlAccountResolver:
	"""نگاشت ref_id حساب قدیم به Account نسخه جدید (چارت عمومی + کسب‌وکار)."""

	def __init__(
		self,
		db: Session,
		business_id: int,
		ref_index: Dict[int, Dict[str, Any]],
	) -> None:
		self.db = db
		self.ref_index = ref_index
		self.chart = LegacyChartResolver(
			db,
			business_id,
			list(ref_index.values()),
		)

	def resolve_calc_account(
		self,
		ref_id: Optional[int],
		*,
		is_income: bool = False,
	) -> Optional[int]:
		"""حساب calc (هزینه/درآمد) — جستجو در چارت عمومی و تطبیق نام/کد."""
		if ref_id is None:
			return None
		try:
			rid = int(ref_id)
		except (TypeError, ValueError):
			return None
		row = self.ref_index.get(rid)
		if not row:
			return None
		account_type = str(row.get("type") or "").lower()
		if account_type and account_type != "calc":
			return self._resolve_typed_account(account_type)

		return self.chart.resolve_account_id(rid, is_income=is_income)

	def resolve_account_id_for_ref(
		self,
		ref_id: Optional[int],
		*,
		is_income: bool = False,
		fallback_expense: bool = False,
	) -> Optional[int]:
		if ref_id is None:
			return None
		try:
			rid = int(ref_id)
		except (TypeError, ValueError):
			return None
		row = self.ref_index.get(rid)
		if not row:
			return None

		code = str(row.get("code") or "").strip()
		fixed = _REF_CODE_TO_FIXED.get(code)
		if fixed:
			return _get_fixed_account_by_code(self.db, fixed).id

		account_type = str(row.get("type") or "").lower()
		typed = self._resolve_typed_account(account_type)
		if typed:
			return typed

		account_id = self.chart.resolve_account_id(rid, is_income=is_income)
		if account_id:
			return account_id

		if fallback_expense:
			fb = self.chart.resolve_account_id(None, is_income=is_income)
			return fb
		return None

	def _resolve_typed_account(self, account_type: str) -> Optional[int]:
		fixed = _ACCOUNT_TYPE_TO_FIXED.get(account_type)
		if not fixed:
			return None
		return _get_fixed_account_by_code(self.db, fixed).id


def resolve_account_id_for_ref(
	db: Session,
	ref_id: Optional[int],
	ref_index: Dict[int, Dict[str, Any]],
	*,
	business_id: int,
	is_income: bool = False,
	fallback_expense: bool = False,
) -> Optional[int]:
	"""تابع سازگار با گذشته — ترجیحاً LegacySqlAccountResolver را مستقیم استفاده کنید."""
	resolver = LegacySqlAccountResolver(db, business_id, ref_index)
	return resolver.resolve_account_id_for_ref(
		ref_id,
		is_income=is_income,
		fallback_expense=fallback_expense,
	)
