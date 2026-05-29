from __future__ import annotations

from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from app.services.expense_income_service import _get_fixed_account_by_code
from app.services.legacy_sql.sql_dump_reader import LegacySqlData

# نگاشت کد حساب قدیمی (hesabdari_table.code) به کد حساب ثابت جدید
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


def build_ref_id_index(data: LegacySqlData) -> Dict[int, Dict[str, Any]]:
	index: Dict[int, Dict[str, Any]] = {}
	for row in data.rows("hesabdari_table"):
		rid = row.get("id")
		if rid is None:
			continue
		try:
			index[int(rid)] = row
		except (TypeError, ValueError):
			continue
	return index


def resolve_account_id_for_ref(
	db: Session,
	ref_id: Optional[int],
	ref_index: Dict[int, Dict[str, Any]],
	*,
	fallback_expense: bool = False,
) -> Optional[int]:
	if ref_id is None:
		return None
	try:
		rid = int(ref_id)
	except (TypeError, ValueError):
		return None
	row = ref_index.get(rid)
	if not row:
		return None
	account_type = str(row.get("type") or "").lower()
	code = str(row.get("code") or "").strip()
	fixed = _REF_CODE_TO_FIXED.get(code)
	if fixed:
		return _get_fixed_account_by_code(db, fixed).id
	if account_type == "person":
		return _get_fixed_account_by_code(db, "10401").id
	if account_type == "bank":
		return _get_fixed_account_by_code(db, "10203").id
	if account_type == "cashdesk":
		return _get_fixed_account_by_code(db, "10202").id
	if account_type == "salary":
		return _get_fixed_account_by_code(db, "10201").id
	if fallback_expense:
		return _get_fixed_account_by_code(db, "5111").id
	return None
