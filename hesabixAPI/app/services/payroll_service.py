"""
سرویس افزونه حقوق و دستمزد.

پوشش: تنظیمات، دسته‌بندی و آیتم‌های حقوق، پرسنل، بخش‌ها، دوره‌ها و اجرای حقوق.
"""
from __future__ import annotations

import logging
import json
import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import and_, desc, func, or_
from sqlalchemy.orm import Session

from adapters.db.models.account import Account
from adapters.db.models.business import Business
from adapters.db.models.payroll import (
	PayrollAuditLog,
	PayrollDepartment,
	PayrollDocumentLink,
	PayrollEmployee,
	PayrollItemCategory,
	PayrollItemDefinition,
	PayrollPeriod,
	PayrollRun,
	PayrollRunLine,
	PayrollRunLineItem,
	PayrollSettings,
)
from adapters.db.models.person import Person, PersonType
from adapters.db.models.document import Document
from app.core.payroll_plugin_dependency import check_payroll_plugin_active
from app.core.responses import ApiError

logger = logging.getLogger(__name__)

_ITEM_KINDS = frozenset({"earning", "deduction", "employer_cost", "informational"})
_CALCULATION_TYPES = frozenset(
	{"manual", "fixed", "percent_of_base", "percent_of_gross", "formula", "statutory"}
)
_STATUTORY_ITEM_CODES = frozenset({"insurance_employee", "insurance_employer", "tax"})
_EMPLOYMENT_TYPES = frozenset({"full_time", "part_time", "contract", "daily", "seasonal"})
_RUN_STATUSES = frozenset({"draft", "pending_approval", "approved", "finalized", "posted", "cancelled"})
_CODE_RE = re.compile(r"^[a-z][a-z0-9_]{0,63}$")


def _ensure_plugin(db: Session, business_id: int) -> None:
	if not check_payroll_plugin_active(db, business_id):
		raise ApiError(
			"PAYROLL_PLUGIN_NOT_ACTIVE",
			"افزونه حقوق و دستمزد برای این کسب‌وکار فعال نیست.",
			http_status=403,
			details={"plugin_code": "payroll"},
		)


def _decimal(value: Any, default: Decimal = Decimal("0")) -> Decimal:
	if value is None or value == "":
		return default
	try:
		return Decimal(str(value))
	except (InvalidOperation, ValueError, TypeError):
		raise ApiError("INVALID_AMOUNT", f"مقدار عددی نامعتبر: {value}", http_status=400)


def _person_has_type(person: Person, type_value: str) -> bool:
	raw = person.person_types
	if not raw:
		return False
	try:
		types = json.loads(raw)
		if isinstance(types, list):
			return type_value in types
	except (json.JSONDecodeError, TypeError):
		pass
	return f'"{type_value}"' in raw or type_value in raw


def _validate_code(code: str) -> str:
	c = str(code or "").strip().lower()
	if not c or not _CODE_RE.match(c):
		raise ApiError(
			"INVALID_CODE",
			"کد باید با حرف انگلیسی شروع شود و فقط شامل حروف کوچک، اعداد و _ باشد.",
			http_status=400,
		)
	return c


def _validate_account(db: Session, business_id: int, account_id: Optional[int]) -> None:
	if account_id is None:
		return
	acc = (
		db.query(Account)
		.filter(
			Account.id == int(account_id),
			or_(Account.business_id == business_id, Account.business_id.is_(None)),  # noqa: E711
		)
		.first()
	)
	if not acc:
		raise ApiError("ACCOUNT_NOT_FOUND", "حساب یافت نشد یا متعلق به این کسب‌وکار نیست.", http_status=404)


def _audit(
	db: Session,
	business_id: int,
	entity_type: str,
	entity_id: int,
	action: str,
	user_id: Optional[int],
	old_values: Optional[dict] = None,
	new_values: Optional[dict] = None,
) -> None:
	db.add(
		PayrollAuditLog(
			business_id=business_id,
			entity_type=entity_type,
			entity_id=entity_id,
			action=action,
			user_id=user_id,
			old_values=old_values,
			new_values=new_values,
		)
	)


# ─── تنظیمات ───────────────────────────────────────────────────────────────


def _settings_to_dict(row: PayrollSettings) -> Dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"enabled": bool(row.enabled),
		"document_code_format": row.document_code_format,
		"document_code_prefix": row.document_code_prefix,
		"wages_payable_account_id": row.wages_payable_account_id,
		"payroll_expense_account_id": row.payroll_expense_account_id,
		"tax_payable_account_id": row.tax_payable_account_id,
		"insurance_payable_account_id": row.insurance_payable_account_id,
		"default_currency_id": row.default_currency_id,
		"calculation_mode": row.calculation_mode,
		"require_approval": bool(row.require_approval),
		"auto_post_on_finalize": bool(row.auto_post_on_finalize),
		"allow_negative_net": bool(row.allow_negative_net),
		"round_amounts_to": int(row.round_amounts_to or 0),
		"payslip_template_json": row.payslip_template_json,
		"extra_settings": row.extra_settings,
		"created_at": row.created_at,
		"updated_at": row.updated_at,
	}


_DEFAULT_CATEGORIES: Tuple[Tuple[str, str, str, int], ...] = (
	("earnings", "مزایا و درآمد", "earning", 1),
	("deductions", "کسورات", "deduction", 2),
	("employer_costs", "هزینه کارفرما", "employer_cost", 3),
)

_DEFAULT_ITEMS: Tuple[Tuple[str, str, str, str, int, bool, bool], ...] = (
	("base_salary", "حقوق پایه", "earnings", "earning", 1, True, True),
	("overtime", "اضافه‌کاری", "earnings", "earning", 2, True, True),
	("housing_allowance", "حق مسکن", "earnings", "earning", 3, True, False),
	("child_allowance", "حق اولاد", "earnings", "earning", 4, True, False),
	("bonus", "پاداش", "earnings", "earning", 5, True, True),
	("insurance_employee", "بیمه سهم کارگر", "deductions", "deduction", 10, False, True),
	("tax", "مالیات حقوق", "deductions", "deduction", 11, False, False),
	("loan", "وام / مساعده", "deductions", "deduction", 12, False, False),
	("insurance_employer", "بیمه سهم کارفرما", "employer_costs", "employer_cost", 20, False, True),
)


def _seed_defaults(db: Session, business_id: int) -> None:
	existing_cat = (
		db.query(PayrollItemCategory.id)
		.filter(PayrollItemCategory.business_id == business_id)
		.limit(1)
		.first()
	)
	if existing_cat:
		return

	cat_map: Dict[str, int] = {}
	for code, name, kind, sort_order in _DEFAULT_CATEGORIES:
		cat = PayrollItemCategory(
			business_id=business_id,
			code=code,
			name=name,
			item_kind=kind,
			sort_order=sort_order,
			is_system=True,
			is_active=True,
		)
		db.add(cat)
		db.flush()
		cat_map[code] = cat.id

	for code, name, cat_code, kind, sort_order, taxable, insurable in _DEFAULT_ITEMS:
		calc_type = "statutory" if code in _STATUTORY_ITEM_CODES else "manual"
		db.add(
			PayrollItemDefinition(
				business_id=business_id,
				category_id=cat_map.get(cat_code),
				code=code,
				name=name,
				item_kind=kind,
				calculation_type=calc_type,
				affects_gross=kind == "earning",
				affects_taxable=taxable,
				affects_insurance=insurable,
				is_taxable=taxable and kind == "earning",
				is_insurable=insurable,
				show_on_payslip=True,
				sort_order=sort_order,
				is_system=True,
				is_active=True,
			)
		)
	db.flush()


def _get_or_create_settings(db: Session, business_id: int) -> PayrollSettings:
	row = db.query(PayrollSettings).filter(PayrollSettings.business_id == business_id).first()
	if row:
		return row
	business = db.query(Business).filter(Business.id == business_id).first()
	if not business:
		raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد.", http_status=404)
	row = PayrollSettings(
		business_id=business_id,
		enabled=True,
		default_currency_id=business.default_currency_id,
	)
	db.add(row)
	db.flush()
	_seed_defaults(db, business_id)
	return row


def get_settings(db: Session, business_id: int) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = _get_or_create_settings(db, business_id)
	db.commit()
	db.refresh(row)
	return _settings_to_dict(row)


def update_settings(
	db: Session,
	business_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = _get_or_create_settings(db, business_id)
	old = _settings_to_dict(row)

	for field in (
		"enabled",
		"document_code_format",
		"document_code_prefix",
		"calculation_mode",
		"require_approval",
		"auto_post_on_finalize",
		"allow_negative_net",
		"payslip_template_json",
		"extra_settings",
	):
		if field in payload:
			setattr(row, field, payload[field])

	if "round_amounts_to" in payload:
		row.round_amounts_to = int(payload["round_amounts_to"] or 0)

	for acct_field in (
		"wages_payable_account_id",
		"payroll_expense_account_id",
		"tax_payable_account_id",
		"insurance_payable_account_id",
	):
		if acct_field in payload:
			val = payload[acct_field]
			aid = int(val) if val is not None else None
			_validate_account(db, business_id, aid)
			setattr(row, acct_field, aid)

	if "default_currency_id" in payload:
		val = payload["default_currency_id"]
		row.default_currency_id = int(val) if val is not None else None

	row.updated_at = datetime.utcnow()
	_audit(db, business_id, "payroll_settings", row.id, "update", user_id, old, _settings_to_dict(row))
	db.commit()
	db.refresh(row)
	return _settings_to_dict(row)


# ─── دسته‌بندی آیتم‌ها ─────────────────────────────────────────────────────


def _category_to_dict(row: PayrollItemCategory) -> Dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"code": row.code,
		"name": row.name,
		"item_kind": row.item_kind,
		"sort_order": row.sort_order,
		"is_system": bool(row.is_system),
		"is_active": bool(row.is_active),
		"description": row.description,
	}


def list_item_categories(db: Session, business_id: int, include_inactive: bool = False) -> List[Dict[str, Any]]:
	_ensure_plugin(db, business_id)
	_get_or_create_settings(db, business_id)
	q = db.query(PayrollItemCategory).filter(PayrollItemCategory.business_id == business_id)
	if not include_inactive:
		q = q.filter(PayrollItemCategory.is_active == True)  # noqa: E712
	rows = q.order_by(PayrollItemCategory.sort_order, PayrollItemCategory.id).all()
	return [_category_to_dict(r) for r in rows]


def create_item_category(
	db: Session,
	business_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	code = _validate_code(payload.get("code"))
	kind = str(payload.get("item_kind") or "earning")
	if kind not in _ITEM_KINDS:
		raise ApiError("INVALID_ITEM_KIND", f"نوع آیتم نامعتبر: {kind}", http_status=400)
	dup = (
		db.query(PayrollItemCategory)
		.filter(PayrollItemCategory.business_id == business_id, PayrollItemCategory.code == code)
		.first()
	)
	if dup:
		raise ApiError("DUPLICATE_CODE", f"دسته با کد {code} از قبل وجود دارد.", http_status=409)
	name = str(payload.get("name") or "").strip()
	if not name:
		raise ApiError("NAME_REQUIRED", "نام دسته الزامی است.", http_status=400)
	row = PayrollItemCategory(
		business_id=business_id,
		code=code,
		name=name,
		item_kind=kind,
		sort_order=int(payload.get("sort_order") or 0),
		is_system=False,
		is_active=bool(payload.get("is_active", True)),
		description=payload.get("description"),
	)
	db.add(row)
	db.flush()
	_audit(db, business_id, "payroll_item_category", row.id, "create", user_id, None, _category_to_dict(row))
	db.commit()
	db.refresh(row)
	return _category_to_dict(row)


def update_item_category(
	db: Session,
	business_id: int,
	category_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = (
		db.query(PayrollItemCategory)
		.filter(PayrollItemCategory.business_id == business_id, PayrollItemCategory.id == category_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "دسته یافت نشد.", http_status=404)
	old = _category_to_dict(row)
	if row.is_system and payload.get("code") and payload["code"] != row.code:
		raise ApiError("SYSTEM_CATEGORY_LOCKED", "کد دسته سیستمی قابل تغییر نیست.", http_status=400)
	for field in ("name", "description", "sort_order", "is_active"):
		if field in payload:
			setattr(row, field, payload[field])
	if "item_kind" in payload and not row.is_system:
		kind = str(payload["item_kind"])
		if kind not in _ITEM_KINDS:
			raise ApiError("INVALID_ITEM_KIND", f"نوع آیتم نامعتبر: {kind}", http_status=400)
		row.item_kind = kind
	row.updated_at = datetime.utcnow()
	_audit(db, business_id, "payroll_item_category", row.id, "update", user_id, old, _category_to_dict(row))
	db.commit()
	db.refresh(row)
	return _category_to_dict(row)


def delete_item_category(
	db: Session,
	business_id: int,
	category_id: int,
	user_id: Optional[int] = None,
) -> None:
	_ensure_plugin(db, business_id)
	row = (
		db.query(PayrollItemCategory)
		.filter(PayrollItemCategory.business_id == business_id, PayrollItemCategory.id == category_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "دسته یافت نشد.", http_status=404)
	if row.is_system:
		raise ApiError("SYSTEM_CATEGORY_LOCKED", "دسته سیستمی قابل حذف نیست.", http_status=400)
	has_items = (
		db.query(PayrollItemDefinition.id)
		.filter(PayrollItemDefinition.category_id == row.id)
		.limit(1)
		.first()
	)
	if has_items:
		raise ApiError("CATEGORY_HAS_ITEMS", "ابتدا آیتم‌های این دسته را حذف یا منتقل کنید.", http_status=409)
	old = _category_to_dict(row)
	db.delete(row)
	_audit(db, business_id, "payroll_item_category", category_id, "delete", user_id, old, None)
	db.commit()


# ─── آیتم‌های حقوق ─────────────────────────────────────────────────────────


def _item_to_dict(row: PayrollItemDefinition) -> Dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"category_id": row.category_id,
		"code": row.code,
		"name": row.name,
		"item_kind": row.item_kind,
		"account_id": row.account_id,
		"counter_account_id": row.counter_account_id,
		"calculation_type": row.calculation_type,
		"default_amount": float(row.default_amount) if row.default_amount is not None else None,
		"percent_value": float(row.percent_value) if row.percent_value is not None else None,
		"formula_expression": row.formula_expression,
		"affects_gross": bool(row.affects_gross),
		"affects_taxable": bool(row.affects_taxable),
		"affects_insurance": bool(row.affects_insurance),
		"is_taxable": bool(row.is_taxable),
		"is_insurable": bool(row.is_insurable),
		"show_on_payslip": bool(row.show_on_payslip),
		"sort_order": row.sort_order,
		"is_system": bool(row.is_system),
		"is_active": bool(row.is_active),
		"extra_config": row.extra_config,
	}


def list_item_definitions(
	db: Session,
	business_id: int,
	*,
	item_kind: Optional[str] = None,
	include_inactive: bool = False,
) -> List[Dict[str, Any]]:
	_ensure_plugin(db, business_id)
	_get_or_create_settings(db, business_id)
	q = db.query(PayrollItemDefinition).filter(PayrollItemDefinition.business_id == business_id)
	if not include_inactive:
		q = q.filter(PayrollItemDefinition.is_active == True)  # noqa: E712
	if item_kind:
		q = q.filter(PayrollItemDefinition.item_kind == item_kind)
	rows = q.order_by(PayrollItemDefinition.sort_order, PayrollItemDefinition.id).all()
	return [_item_to_dict(r) for r in rows]


def create_item_definition(
	db: Session,
	business_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	code = _validate_code(payload.get("code"))
	kind = str(payload.get("item_kind") or "earning")
	if kind not in _ITEM_KINDS:
		raise ApiError("INVALID_ITEM_KIND", f"نوع آیتم نامعتبر: {kind}", http_status=400)
	calc = str(payload.get("calculation_type") or "manual")
	if calc not in _CALCULATION_TYPES:
		raise ApiError("INVALID_CALCULATION_TYPE", f"نوع محاسبه نامعتبر: {calc}", http_status=400)
	dup = (
		db.query(PayrollItemDefinition)
		.filter(PayrollItemDefinition.business_id == business_id, PayrollItemDefinition.code == code)
		.first()
	)
	if dup:
		raise ApiError("DUPLICATE_CODE", f"آیتم با کد {code} از قبل وجود دارد.", http_status=409)
	name = str(payload.get("name") or "").strip()
	if not name:
		raise ApiError("NAME_REQUIRED", "نام آیتم الزامی است.", http_status=400)

	category_id = payload.get("category_id")
	if category_id is not None:
		cat = (
			db.query(PayrollItemCategory)
			.filter(
				PayrollItemCategory.business_id == business_id,
				PayrollItemCategory.id == int(category_id),
			)
			.first()
		)
		if not cat:
			raise ApiError("CATEGORY_NOT_FOUND", "دسته یافت نشد.", http_status=404)

	account_id = payload.get("account_id")
	counter_account_id = payload.get("counter_account_id")
	_validate_account(db, business_id, int(account_id) if account_id is not None else None)
	_validate_account(db, business_id, int(counter_account_id) if counter_account_id is not None else None)

	row = PayrollItemDefinition(
		business_id=business_id,
		category_id=int(category_id) if category_id is not None else None,
		code=code,
		name=name,
		item_kind=kind,
		account_id=int(account_id) if account_id is not None else None,
		counter_account_id=int(counter_account_id) if counter_account_id is not None else None,
		calculation_type=calc,
		default_amount=_decimal(payload["default_amount"]) if payload.get("default_amount") is not None else None,
		percent_value=_decimal(payload["percent_value"]) if payload.get("percent_value") is not None else None,
		formula_expression=payload.get("formula_expression"),
		affects_gross=bool(payload.get("affects_gross", kind == "earning")),
		affects_taxable=bool(payload.get("affects_taxable", True)),
		affects_insurance=bool(payload.get("affects_insurance", True)),
		is_taxable=bool(payload.get("is_taxable", False)),
		is_insurable=bool(payload.get("is_insurable", True)),
		show_on_payslip=bool(payload.get("show_on_payslip", True)),
		sort_order=int(payload.get("sort_order") or 0),
		is_system=False,
		is_active=bool(payload.get("is_active", True)),
		extra_config=payload.get("extra_config"),
	)
	db.add(row)
	db.flush()
	_audit(db, business_id, "payroll_item_definition", row.id, "create", user_id, None, _item_to_dict(row))
	db.commit()
	db.refresh(row)
	return _item_to_dict(row)


def update_item_definition(
	db: Session,
	business_id: int,
	item_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = (
		db.query(PayrollItemDefinition)
		.filter(PayrollItemDefinition.business_id == business_id, PayrollItemDefinition.id == item_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "آیتم یافت نشد.", http_status=404)
	old = _item_to_dict(row)
	if row.is_system and payload.get("code") and payload["code"] != row.code:
		raise ApiError("SYSTEM_ITEM_LOCKED", "کد آیتم سیستمی قابل تغییر نیست.", http_status=400)

	for field in (
		"name",
		"formula_expression",
		"affects_gross",
		"affects_taxable",
		"affects_insurance",
		"is_taxable",
		"is_insurable",
		"show_on_payslip",
		"sort_order",
		"is_active",
		"extra_config",
	):
		if field in payload:
			setattr(row, field, payload[field])

	if "category_id" in payload:
		cid = payload["category_id"]
		if cid is not None:
			cat = (
				db.query(PayrollItemCategory)
				.filter(PayrollItemCategory.business_id == business_id, PayrollItemCategory.id == int(cid))
				.first()
			)
			if not cat:
				raise ApiError("CATEGORY_NOT_FOUND", "دسته یافت نشد.", http_status=404)
		row.category_id = int(cid) if cid is not None else None

	if "account_id" in payload:
		aid = payload["account_id"]
		_validate_account(db, business_id, int(aid) if aid is not None else None)
		row.account_id = int(aid) if aid is not None else None

	if "counter_account_id" in payload:
		caid = payload["counter_account_id"]
		_validate_account(db, business_id, int(caid) if caid is not None else None)
		row.counter_account_id = int(caid) if caid is not None else None

	if "default_amount" in payload:
		val = payload["default_amount"]
		row.default_amount = _decimal(val) if val is not None else None

	if "percent_value" in payload:
		val = payload["percent_value"]
		row.percent_value = _decimal(val) if val is not None else None

	if not row.is_system:
		if "item_kind" in payload:
			kind = str(payload["item_kind"])
			if kind not in _ITEM_KINDS:
				raise ApiError("INVALID_ITEM_KIND", f"نوع آیتم نامعتبر: {kind}", http_status=400)
			row.item_kind = kind
		if "calculation_type" in payload:
			calc = str(payload["calculation_type"])
			if calc not in _CALCULATION_TYPES:
				raise ApiError("INVALID_CALCULATION_TYPE", f"نوع محاسبه نامعتبر: {calc}", http_status=400)
			row.calculation_type = calc

	row.updated_at = datetime.utcnow()
	_audit(db, business_id, "payroll_item_definition", row.id, "update", user_id, old, _item_to_dict(row))
	db.commit()
	db.refresh(row)
	return _item_to_dict(row)


def delete_item_definition(
	db: Session,
	business_id: int,
	item_id: int,
	user_id: Optional[int] = None,
) -> None:
	_ensure_plugin(db, business_id)
	row = (
		db.query(PayrollItemDefinition)
		.filter(PayrollItemDefinition.business_id == business_id, PayrollItemDefinition.id == item_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "آیتم یافت نشد.", http_status=404)
	if row.is_system:
		raise ApiError("SYSTEM_ITEM_LOCKED", "آیتم سیستمی قابل حذف نیست؛ می‌توانید آن را غیرفعال کنید.", http_status=400)
	old = _item_to_dict(row)
	row.is_active = False
	row.updated_at = datetime.utcnow()
	_audit(db, business_id, "payroll_item_definition", row.id, "deactivate", user_id, old, _item_to_dict(row))
	db.commit()


# ─── بخش‌ها ────────────────────────────────────────────────────────────────


def _department_to_dict(row: PayrollDepartment) -> Dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"parent_id": row.parent_id,
		"code": row.code,
		"name": row.name,
		"is_active": bool(row.is_active),
		"sort_order": row.sort_order,
	}


def list_departments(db: Session, business_id: int, include_inactive: bool = False) -> List[Dict[str, Any]]:
	_ensure_plugin(db, business_id)
	q = db.query(PayrollDepartment).filter(PayrollDepartment.business_id == business_id)
	if not include_inactive:
		q = q.filter(PayrollDepartment.is_active == True)  # noqa: E712
	rows = q.order_by(PayrollDepartment.sort_order, PayrollDepartment.name).all()
	return [_department_to_dict(r) for r in rows]


def create_department(
	db: Session,
	business_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	code = _validate_code(payload.get("code"))
	name = str(payload.get("name") or "").strip()
	if not name:
		raise ApiError("NAME_REQUIRED", "نام بخش الزامی است.", http_status=400)
	dup = (
		db.query(PayrollDepartment)
		.filter(PayrollDepartment.business_id == business_id, PayrollDepartment.code == code)
		.first()
	)
	if dup:
		raise ApiError("DUPLICATE_CODE", f"بخش با کد {code} از قبل وجود دارد.", http_status=409)
	parent_id = payload.get("parent_id")
	if parent_id is not None:
		parent = (
			db.query(PayrollDepartment)
			.filter(PayrollDepartment.business_id == business_id, PayrollDepartment.id == int(parent_id))
			.first()
		)
		if not parent:
			raise ApiError("PARENT_NOT_FOUND", "بخش والد یافت نشد.", http_status=404)
	row = PayrollDepartment(
		business_id=business_id,
		parent_id=int(parent_id) if parent_id is not None else None,
		code=code,
		name=name,
		is_active=bool(payload.get("is_active", True)),
		sort_order=int(payload.get("sort_order") or 0),
	)
	db.add(row)
	db.flush()
	_audit(db, business_id, "payroll_department", row.id, "create", user_id, None, _department_to_dict(row))
	db.commit()
	db.refresh(row)
	return _department_to_dict(row)


# ─── پرسنل ──────────────────────────────────────────────────────────────────


def _employee_to_dict(row: PayrollEmployee, person: Optional[Person] = None) -> Dict[str, Any]:
	data: Dict[str, Any] = {
		"id": row.id,
		"business_id": row.business_id,
		"person_id": row.person_id,
		"department_id": row.department_id,
		"employee_code": row.employee_code,
		"job_title": row.job_title,
		"employment_type": row.employment_type,
		"hire_date": row.hire_date.isoformat() if row.hire_date else None,
		"termination_date": row.termination_date.isoformat() if row.termination_date else None,
		"base_salary": float(row.base_salary) if row.base_salary is not None else None,
		"insurance_number": row.insurance_number,
		"tax_id": row.tax_id,
		"bank_account_info": row.bank_account_info,
		"is_active": bool(row.is_active),
		"extra_info": row.extra_info,
	}
	if person:
		data["person_name"] = person.name
		data["person_code"] = person.code
	return data


def list_employees(
	db: Session,
	business_id: int,
	*,
	include_inactive: bool = False,
	department_id: Optional[int] = None,
	limit: int = 100,
	skip: int = 0,
) -> Tuple[List[Dict[str, Any]], int]:
	_ensure_plugin(db, business_id)
	q = (
		db.query(PayrollEmployee, Person)
		.join(Person, Person.id == PayrollEmployee.person_id)
		.filter(PayrollEmployee.business_id == business_id)
	)
	if not include_inactive:
		q = q.filter(PayrollEmployee.is_active == True)  # noqa: E712
	if department_id is not None:
		q = q.filter(PayrollEmployee.department_id == int(department_id))
	total = q.count()
	rows = q.order_by(PayrollEmployee.employee_code).offset(skip).limit(limit).all()
	return [_employee_to_dict(emp, person) for emp, person in rows], total


def create_employee(
	db: Session,
	business_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	person_id = payload.get("person_id")
	if person_id is None:
		raise ApiError("PERSON_REQUIRED", "انتخاب شخص الزامی است.", http_status=400)
	person = (
		db.query(Person)
		.filter(Person.business_id == business_id, Person.id == int(person_id))
		.first()
	)
	if not person:
		raise ApiError("PERSON_NOT_FOUND", "شخص یافت نشد.", http_status=404)
	if not _person_has_type(person, PersonType.EMPLOYEE.value):
		raise ApiError(
			"PERSON_NOT_EMPLOYEE",
			"شخص انتخاب‌شده باید از نوع کارمند باشد.",
			http_status=400,
		)
	emp_code = str(payload.get("employee_code") or "").strip()
	if not emp_code:
		emp_code = person.code or f"EMP{person.id}"
	dup = (
		db.query(PayrollEmployee)
		.filter(
			PayrollEmployee.business_id == business_id,
			or_(
				PayrollEmployee.employee_code == emp_code,
				PayrollEmployee.person_id == int(person_id),
			),
		)
		.first()
	)
	if dup:
		raise ApiError("EMPLOYEE_EXISTS", "این شخص یا کد پرسنلی قبلاً ثبت شده است.", http_status=409)
	emp_type = str(payload.get("employment_type") or "full_time")
	if emp_type not in _EMPLOYMENT_TYPES:
		raise ApiError("INVALID_EMPLOYMENT_TYPE", f"نوع استخدام نامعتبر: {emp_type}", http_status=400)
	row = PayrollEmployee(
		business_id=business_id,
		person_id=int(person_id),
		department_id=int(payload["department_id"]) if payload.get("department_id") is not None else None,
		employee_code=emp_code,
		job_title=payload.get("job_title"),
		employment_type=emp_type,
		hire_date=date.fromisoformat(payload["hire_date"]) if payload.get("hire_date") else None,
		base_salary=_decimal(payload["base_salary"]) if payload.get("base_salary") is not None else None,
		insurance_number=payload.get("insurance_number"),
		tax_id=payload.get("tax_id"),
		bank_account_info=payload.get("bank_account_info"),
		is_active=bool(payload.get("is_active", True)),
		extra_info=payload.get("extra_info"),
	)
	db.add(row)
	db.flush()
	data = _employee_to_dict(row, person)
	_audit(db, business_id, "payroll_employee", row.id, "create", user_id, None, data)
	db.commit()
	db.refresh(row)
	return data


# ─── دوره‌ها ─────────────────────────────────────────────────────────────────


def _period_to_dict(row: PayrollPeriod) -> Dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"year": row.year,
		"month": row.month,
		"title": row.title,
		"start_date": row.start_date.isoformat() if row.start_date else None,
		"end_date": row.end_date.isoformat() if row.end_date else None,
		"status": row.status,
		"closed_at": row.closed_at,
	}


def list_periods(db: Session, business_id: int, limit: int = 24, skip: int = 0) -> Tuple[List[Dict[str, Any]], int]:
	_ensure_plugin(db, business_id)
	q = db.query(PayrollPeriod).filter(PayrollPeriod.business_id == business_id)
	total = q.count()
	rows = q.order_by(desc(PayrollPeriod.year), desc(PayrollPeriod.month)).offset(skip).limit(limit).all()
	return [_period_to_dict(r) for r in rows], total


def create_period(
	db: Session,
	business_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	year = int(payload.get("year") or 0)
	month = int(payload.get("month") or 0)
	if year < 1300 or year > 1500 or month < 1 or month > 12:
		raise ApiError("INVALID_PERIOD", "سال یا ماه دوره نامعتبر است.", http_status=400)
	dup = (
		db.query(PayrollPeriod)
		.filter(PayrollPeriod.business_id == business_id, PayrollPeriod.year == year, PayrollPeriod.month == month)
		.first()
	)
	if dup:
		raise ApiError("PERIOD_EXISTS", "دوره این ماه از قبل وجود دارد.", http_status=409)
	title = str(payload.get("title") or "").strip() or f"حقوق {year}/{month:02d}"
	row = PayrollPeriod(
		business_id=business_id,
		year=year,
		month=month,
		title=title,
		start_date=date.fromisoformat(payload["start_date"]) if payload.get("start_date") else None,
		end_date=date.fromisoformat(payload["end_date"]) if payload.get("end_date") else None,
		status="open",
	)
	db.add(row)
	db.flush()
	data = _period_to_dict(row)
	_audit(db, business_id, "payroll_period", row.id, "create", user_id, None, data)
	db.commit()
	db.refresh(row)
	return data


# ─── اجرای حقوق (لیست — فاز بعدی تکمیل CRUD) ───────────────────────────────


def _run_to_dict(row: PayrollRun) -> Dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"period_id": row.period_id,
		"code": row.code,
		"title": row.title,
		"run_date": row.run_date.isoformat() if row.run_date else None,
		"description": row.description,
		"status": row.status,
		"gross_total": float(row.gross_total),
		"deduction_total": float(row.deduction_total),
		"net_total": float(row.net_total),
		"employer_cost_total": float(row.employer_cost_total),
		"finalized_at": row.finalized_at,
		"approved_at": row.approved_at,
		"posted_at": row.posted_at,
		"extra_info": row.extra_info,
		"created_at": row.created_at,
		"updated_at": row.updated_at,
	}


def list_runs(
	db: Session,
	business_id: int,
	*,
	status: Optional[str] = None,
	period_id: Optional[int] = None,
	limit: int = 50,
	skip: int = 0,
) -> Tuple[List[Dict[str, Any]], int]:
	_ensure_plugin(db, business_id)
	q = db.query(PayrollRun).filter(PayrollRun.business_id == business_id)
	if status:
		q = q.filter(PayrollRun.status == status)
	if period_id is not None:
		q = q.filter(PayrollRun.period_id == int(period_id))
	total = q.count()
	rows = q.order_by(desc(PayrollRun.run_date), desc(PayrollRun.id)).offset(skip).limit(limit).all()
	return [_run_to_dict(r) for r in rows], total


def get_dashboard_summary(db: Session, business_id: int) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	_get_or_create_settings(db, business_id)
	emp_count = (
		db.query(func.count(PayrollEmployee.id))
		.filter(PayrollEmployee.business_id == business_id, PayrollEmployee.is_active == True)  # noqa: E712
		.scalar()
		or 0
	)
	item_count = (
		db.query(func.count(PayrollItemDefinition.id))
		.filter(
			PayrollItemDefinition.business_id == business_id,
			PayrollItemDefinition.is_active == True,  # noqa: E712
		)
		.scalar()
		or 0
	)
	run_count = (
		db.query(func.count(PayrollRun.id)).filter(PayrollRun.business_id == business_id).scalar() or 0
	)
	draft_runs = (
		db.query(func.count(PayrollRun.id))
		.filter(PayrollRun.business_id == business_id, PayrollRun.status == "draft")
		.scalar()
		or 0
	)
	pending_approvals = (
		db.query(func.count(PayrollRun.id))
		.filter(PayrollRun.business_id == business_id, PayrollRun.status == "pending_approval")
		.scalar()
		or 0
	)
	db.commit()
	return {
		"active_employees": int(emp_count),
		"active_items": int(item_count),
		"total_runs": int(run_count),
		"draft_runs": int(draft_runs),
		"pending_approvals": int(pending_approvals),
	}


# ─── محاسبات و کدگذاری اجرای حقوق ─────────────────────────────────────────


def _round_amount(amount: Decimal, round_to: int) -> Decimal:
	if round_to <= 0:
		return amount.quantize(Decimal("1"))
	step = Decimal(10) ** (-int(round_to))
	return amount.quantize(step)


def _generate_run_code(db: Session, business_id: int, settings: PayrollSettings) -> str:
	import secrets

	prefix = (settings.document_code_prefix or "PAY").strip() or "PAY"
	fmt = settings.document_code_format or "sequential"
	if fmt == "random":
		for _ in range(20):
			code = f"{prefix}-{secrets.token_hex(4).upper()}"
			exists = (
				db.query(PayrollRun.id)
				.filter(PayrollRun.business_id == business_id, PayrollRun.code == code)
				.first()
			)
			if not exists:
				return code
		raise ApiError("CODE_GENERATION_FAILED", "تولید کد یکتا ناموفق بود.", http_status=500)
	year = datetime.utcnow().year
	count = (
		db.query(func.count(PayrollRun.id)).filter(PayrollRun.business_id == business_id).scalar() or 0
	)
	return f"{prefix}-{year}-{int(count) + 1:04d}"


def _get_active_items_map(db: Session, business_id: int) -> Dict[int, PayrollItemDefinition]:
	rows = (
		db.query(PayrollItemDefinition)
		.filter(
			PayrollItemDefinition.business_id == business_id,
			PayrollItemDefinition.is_active == True,  # noqa: E712
		)
		.order_by(PayrollItemDefinition.sort_order, PayrollItemDefinition.id)
		.all()
	)
	return {r.id: r for r in rows}


def _resolve_item_amount(
	item_def: PayrollItemDefinition,
	amount_override: Any,
	base_salary: Decimal,
	gross_earnings: Decimal,
) -> Tuple[Decimal, bool]:
	"""برگرداند (مبلغ، محاسبه‌شده؟)."""
	if amount_override is not None and amount_override != "":
		return _decimal(amount_override), False
	calc = item_def.calculation_type or "manual"
	if calc == "fixed" and item_def.default_amount is not None:
		return item_def.default_amount, True
	if calc == "percent_of_base" and item_def.percent_value is not None:
		return (base_salary * item_def.percent_value / Decimal("100")), True
	if calc == "percent_of_gross" and item_def.percent_value is not None:
		return (gross_earnings * item_def.percent_value / Decimal("100")), True
	if calc == "statutory" or item_def.code in _STATUTORY_ITEM_CODES:
		return Decimal("0"), False
	return Decimal("0"), False


def _compute_amounts_from_items(
	items: List[Tuple[PayrollItemDefinition, Decimal]],
	settings: PayrollSettings,
) -> Tuple[Decimal, Decimal, Decimal, Decimal]:
	gross = Decimal("0")
	deductions = Decimal("0")
	employer = Decimal("0")
	rt = int(settings.round_amounts_to or 0)

	for item_def, amount in items:
		amt = _round_amount(_decimal(amount), rt)
		kind = item_def.item_kind
		if kind == "earning" and item_def.affects_gross:
			gross += amt
		elif kind == "deduction":
			deductions += amt
		elif kind == "employer_cost":
			employer += amt

	gross = _round_amount(gross, rt)
	deductions = _round_amount(deductions, rt)
	employer = _round_amount(employer, rt)
	net = _round_amount(gross - deductions, rt)
	return gross, deductions, net, employer


def _build_default_line_items(
	employee: PayrollEmployee,
	items_map: Dict[int, PayrollItemDefinition],
	explicit_items: Optional[List[Dict[str, Any]]] = None,
	settings: Optional[PayrollSettings] = None,
) -> List[Tuple[PayrollItemDefinition, Decimal, bool]]:
	base_salary = _decimal(employee.base_salary) if employee.base_salary is not None else Decimal("0")
	explicit_by_id: Dict[int, Any] = {}
	if explicit_items:
		for row in explicit_items:
			iid = row.get("item_definition_id")
			if iid is not None:
				explicit_by_id[int(iid)] = row.get("amount")

	# پاس اول: درآمدها برای محاسبه percent_of_gross
	gross_pass = Decimal("0")
	pending: List[Tuple[PayrollItemDefinition, Decimal, bool]] = []
	for item_def in items_map.values():
		if item_def.item_kind != "earning" or not item_def.affects_gross:
			continue
		amt, computed = _resolve_item_amount(
			item_def, explicit_by_id.get(item_def.id), base_salary, gross_pass
		)
		if item_def.code == "base_salary" and amt == 0 and base_salary > 0:
			amt = base_salary
			computed = True
		pending.append((item_def, amt, computed))
		gross_pass += amt

	# پاس دوم: سایر آیتم‌ها
	for item_def in items_map.values():
		if item_def.item_kind == "earning" and item_def.affects_gross:
			continue
		amt, computed = _resolve_item_amount(
			item_def, explicit_by_id.get(item_def.id), base_salary, gross_pass
		)
		pending.append((item_def, amt, computed))

	if settings is not None:
		from app.services.payroll_statutory import apply_statutory_rules

		pending = apply_statutory_rules(pending, explicit_by_id, settings)
	return pending


def _line_item_to_dict(
	line_item: PayrollRunLineItem, item_def: Optional[PayrollItemDefinition] = None
) -> Dict[str, Any]:
	data = {
		"id": line_item.id,
		"item_definition_id": line_item.item_definition_id,
		"amount": float(line_item.amount),
		"quantity": float(line_item.quantity) if line_item.quantity is not None else None,
		"is_computed": bool(line_item.is_computed),
		"notes": line_item.notes,
	}
	if item_def:
		data["item_code"] = item_def.code
		data["item_name"] = item_def.name
		data["item_kind"] = item_def.item_kind
	return data


def _line_to_dict(
	line: PayrollRunLine,
	employee: Optional[PayrollEmployee] = None,
	person: Optional[Person] = None,
	items: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
	data: Dict[str, Any] = {
		"id": line.id,
		"run_id": line.run_id,
		"employee_id": line.employee_id,
		"person_id": line.person_id,
		"line_number": line.line_number,
		"notes": line.notes,
		"gross_amount": float(line.gross_amount),
		"deduction_amount": float(line.deduction_amount),
		"net_amount": float(line.net_amount),
		"employer_cost_amount": float(line.employer_cost_amount),
	}
	if employee:
		data["employee_code"] = employee.employee_code
		data["job_title"] = employee.job_title
	if person:
		data["person_name"] = person.name
	if items is not None:
		data["items"] = items
	return data


def _document_link_to_dict(link: PayrollDocumentLink, document: Optional[Document] = None) -> Dict[str, Any]:
	data: Dict[str, Any] = {
		"id": link.id,
		"run_id": link.run_id,
		"document_id": link.document_id,
		"link_type": link.link_type,
		"created_at": link.created_at,
	}
	if document:
		data["document_code"] = document.code
		data["document_date"] = document.document_date.isoformat() if document.document_date else None
	return data


def _load_document_links(db: Session, run_id: int) -> List[Dict[str, Any]]:
	rows = (
		db.query(PayrollDocumentLink, Document)
		.join(Document, Document.id == PayrollDocumentLink.document_id)
		.filter(PayrollDocumentLink.run_id == run_id)
		.order_by(PayrollDocumentLink.id)
		.all()
	)
	return [_document_link_to_dict(link, doc) for link, doc in rows]


def _run_to_detail_dict(
	run: PayrollRun,
	period: Optional[PayrollPeriod] = None,
	lines: Optional[List[Dict[str, Any]]] = None,
	document_links: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
	data = _run_to_dict(run)
	if period:
		data["period"] = _period_to_dict(period)
	if lines is not None:
		data["lines"] = lines
	if document_links is not None:
		data["document_links"] = document_links
	return data


def _ensure_run_editable(run: PayrollRun) -> None:
	if run.status not in ("draft",):
		raise ApiError(
			"RUN_NOT_EDITABLE",
			f"اجرای حقوق در وضعیت {run.status} قابل ویرایش نیست.",
			http_status=409,
		)


def _get_run_row(db: Session, business_id: int, run_id: int) -> PayrollRun:
	run = (
		db.query(PayrollRun)
		.filter(PayrollRun.business_id == business_id, PayrollRun.id == run_id)
		.first()
	)
	if not run:
		raise ApiError("NOT_FOUND", "اجرای حقوق یافت نشد.", http_status=404)
	return run


def _persist_run_lines(
	db: Session,
	business_id: int,
	run: PayrollRun,
	lines_payload: List[Dict[str, Any]],
	settings: PayrollSettings,
) -> Tuple[Decimal, Decimal, Decimal, Decimal]:
	items_map = _get_active_items_map(db, business_id)
	if not items_map:
		raise ApiError("NO_PAYROLL_ITEMS", "هیچ آیتم حقوق فعالی تعریف نشده است.", http_status=400)

	# حذف ردیف‌های قبلی
	db.query(PayrollRunLine).filter(PayrollRunLine.run_id == run.id).delete(synchronize_session=False)
	db.flush()

	total_gross = Decimal("0")
	total_deduction = Decimal("0")
	total_net = Decimal("0")
	total_employer = Decimal("0")

	for idx, line_payload in enumerate(lines_payload, start=1):
		employee_id = line_payload.get("employee_id")
		if employee_id is None:
			raise ApiError("EMPLOYEE_REQUIRED", "employee_id در هر ردیف الزامی است.", http_status=400)
		employee = (
			db.query(PayrollEmployee)
			.filter(
				PayrollEmployee.business_id == business_id,
				PayrollEmployee.id == int(employee_id),
				PayrollEmployee.is_active == True,  # noqa: E712
			)
			.first()
		)
		if not employee:
			raise ApiError("EMPLOYEE_NOT_FOUND", f"پرسنل {employee_id} یافت نشد یا غیرفعال است.", http_status=404)

		explicit_items = line_payload.get("items")
		built = _build_default_line_items(
			employee,
			items_map,
			explicit_items if isinstance(explicit_items, list) else None,
			settings=settings,
		)
		amount_pairs = [(d, a) for d, a, _ in built]
		gross, deductions, net, employer = _compute_amounts_from_items(amount_pairs, settings)

		if not settings.allow_negative_net and net < 0:
			raise ApiError(
				"NEGATIVE_NET_NOT_ALLOWED",
				f"خالص پرداختی پرسنل {employee.employee_code} منفی است.",
				http_status=400,
			)

		line = PayrollRunLine(
			run_id=run.id,
			employee_id=employee.id,
			person_id=employee.person_id,
			line_number=idx,
			notes=line_payload.get("notes"),
			gross_amount=gross,
			deduction_amount=deductions,
			net_amount=net,
			employer_cost_amount=employer,
		)
		db.add(line)
		db.flush()

		for item_def, amount, is_computed in built:
			if amount == 0 and item_def.calculation_type == "manual" and not (
				isinstance(explicit_items, list)
				and any(int(x.get("item_definition_id", -1)) == item_def.id for x in explicit_items)
			):
				continue
			db.add(
				PayrollRunLineItem(
					run_line_id=line.id,
					item_definition_id=item_def.id,
					amount=amount,
					is_computed=is_computed,
					notes=None,
				)
			)

		total_gross += gross
		total_deduction += deductions
		total_net += net
		total_employer += employer

	rt = int(settings.round_amounts_to or 0)
	run.gross_total = _round_amount(total_gross, rt)
	run.deduction_total = _round_amount(total_deduction, rt)
	run.net_total = _round_amount(total_net, rt)
	run.employer_cost_total = _round_amount(total_employer, rt)
	return run.gross_total, run.deduction_total, run.net_total, run.employer_cost_total


def get_run(db: Session, business_id: int, run_id: int) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	run = _get_run_row(db, business_id, run_id)
	period = None
	if run.period_id:
		period = db.query(PayrollPeriod).filter(PayrollPeriod.id == run.period_id).first()

	lines_q = (
		db.query(PayrollRunLine, PayrollEmployee, Person)
		.join(PayrollEmployee, PayrollEmployee.id == PayrollRunLine.employee_id)
		.join(Person, Person.id == PayrollRunLine.person_id)
		.filter(PayrollRunLine.run_id == run.id)
		.order_by(PayrollRunLine.line_number)
		.all()
	)

	line_ids = [ln.id for ln, _, _ in lines_q]
	items_by_line: Dict[int, List[Dict[str, Any]]] = {lid: [] for lid in line_ids}
	if line_ids:
		item_rows = (
			db.query(PayrollRunLineItem, PayrollItemDefinition)
			.join(
				PayrollItemDefinition,
				PayrollItemDefinition.id == PayrollRunLineItem.item_definition_id,
			)
			.filter(PayrollRunLineItem.run_line_id.in_(line_ids))
			.all()
		)
		for li, idef in item_rows:
			items_by_line.setdefault(li.run_line_id, []).append(_line_item_to_dict(li, idef))

	lines_out = [
		_line_to_dict(ln, emp, person, items_by_line.get(ln.id, []))
		for ln, emp, person in lines_q
	]
	doc_links = _load_document_links(db, run.id)
	return _run_to_detail_dict(run, period, lines_out, doc_links)


def create_run(
	db: Session,
	business_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	if not settings.enabled:
		raise ApiError("PAYROLL_DISABLED", "ماژول حقوق غیرفعال است.", http_status=400)

	period_id = payload.get("period_id")
	period = None
	if period_id is not None:
		period = (
			db.query(PayrollPeriod)
			.filter(PayrollPeriod.business_id == business_id, PayrollPeriod.id == int(period_id))
			.first()
		)
		if not period:
			raise ApiError("PERIOD_NOT_FOUND", "دوره حقوق یافت نشد.", http_status=404)
		if period.status == "closed":
			raise ApiError("PERIOD_CLOSED", "دوره بسته شده و قابل ثبت نیست.", http_status=400)

	run_date_raw = payload.get("run_date")
	run_date = date.fromisoformat(run_date_raw) if run_date_raw else date.today()
	title = str(payload.get("title") or "").strip()
	if not title and period:
		title = period.title
	if not title:
		title = f"حقوق {run_date.isoformat()}"

	code = str(payload.get("code") or "").strip() or _generate_run_code(db, business_id, settings)

	run = PayrollRun(
		business_id=business_id,
		period_id=int(period_id) if period_id is not None else None,
		code=code,
		title=title,
		run_date=run_date,
		description=payload.get("description"),
		status="draft",
		created_by_user_id=user_id,
	)
	db.add(run)
	db.flush()

	lines_payload = payload.get("lines")
	if not lines_payload:
		employee_ids = payload.get("employee_ids")
		q = db.query(PayrollEmployee).filter(
			PayrollEmployee.business_id == business_id,
			PayrollEmployee.is_active == True,  # noqa: E712
		)
		if employee_ids:
			q = q.filter(PayrollEmployee.id.in_([int(x) for x in employee_ids]))
		employees = q.order_by(PayrollEmployee.employee_code).all()
		if not employees:
			raise ApiError("NO_EMPLOYEES", "هیچ پرسنل فعالی برای ثبت حقوق یافت نشد.", http_status=400)
		lines_payload = [{"employee_id": e.id} for e in employees]

	if not isinstance(lines_payload, list) or not lines_payload:
		raise ApiError("LINES_REQUIRED", "حداقل یک ردیف پرسنل الزامی است.", http_status=400)

	_persist_run_lines(db, business_id, run, lines_payload, settings)
	run.updated_at = datetime.utcnow()
	_audit(db, business_id, "payroll_run", run.id, "create", user_id, None, _run_to_dict(run))
	db.commit()
	return get_run(db, business_id, run.id)


def update_run(
	db: Session,
	business_id: int,
	run_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	run = _get_run_row(db, business_id, run_id)
	_ensure_run_editable(run)
	old = _run_to_dict(run)

	for field in ("title", "description"):
		if field in payload:
			setattr(run, field, payload[field])
	if "run_date" in payload and payload["run_date"]:
		run.run_date = date.fromisoformat(payload["run_date"])
	if "period_id" in payload:
		pid = payload["period_id"]
		if pid is not None:
			period = (
				db.query(PayrollPeriod)
				.filter(PayrollPeriod.business_id == business_id, PayrollPeriod.id == int(pid))
				.first()
			)
			if not period:
				raise ApiError("PERIOD_NOT_FOUND", "دوره حقوق یافت نشد.", http_status=404)
		run.period_id = int(pid) if pid is not None else None

	if "lines" in payload:
		lines_payload = payload["lines"]
		if not isinstance(lines_payload, list) or not lines_payload:
			raise ApiError("LINES_REQUIRED", "حداقل یک ردیف پرسنل الزامی است.", http_status=400)
		_persist_run_lines(db, business_id, run, lines_payload, settings)

	run.updated_at = datetime.utcnow()
	_audit(db, business_id, "payroll_run", run.id, "update", user_id, old, _run_to_dict(run))
	db.commit()
	return get_run(db, business_id, run.id)


def delete_run(
	db: Session,
	business_id: int,
	run_id: int,
	user_id: Optional[int] = None,
) -> None:
	_ensure_plugin(db, business_id)
	run = _get_run_row(db, business_id, run_id)
	_ensure_run_editable(run)
	old = _run_to_dict(run)
	db.delete(run)
	_audit(db, business_id, "payroll_run", run_id, "delete", user_id, old, None)
	db.commit()


def finalize_run(
	db: Session,
	business_id: int,
	run_id: int,
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	run = _get_run_row(db, business_id, run_id)
	if run.status != "draft":
		raise ApiError("INVALID_STATUS", "فقط پیش‌نویس قابل قطعی‌سازی است.", http_status=400)

	line_count = db.query(func.count(PayrollRunLine.id)).filter(PayrollRunLine.run_id == run.id).scalar() or 0
	if line_count == 0:
		raise ApiError("NO_LINES", "سند حقوق بدون ردیف پرسنل قابل قطعی‌سازی نیست.", http_status=400)

	old = _run_to_dict(run)
	if settings.require_approval:
		run.status = "pending_approval"
	else:
		run.status = "finalized"
		run.finalized_at = datetime.utcnow()
		run.finalized_by_user_id = user_id
	run.updated_at = datetime.utcnow()
	_audit(db, business_id, "payroll_run", run.id, "finalize", user_id, old, _run_to_dict(run))
	db.flush()

	if run.status == "finalized" and settings.auto_post_on_finalize and user_id is not None:
		try:
			post_run_to_accounting(db, business_id, run.id, user_id=user_id, auto=True)
		except ApiError as exc:
			logger.warning(
				"payroll_auto_post_failed",
				extra={"run_id": run.id, "business_id": business_id, "error": exc.message},
			)

	db.commit()
	return get_run(db, business_id, run.id)


def cancel_run(
	db: Session,
	business_id: int,
	run_id: int,
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	run = _get_run_row(db, business_id, run_id)
	if run.status not in ("draft", "pending_approval"):
		raise ApiError("INVALID_STATUS", "این اجرا در وضعیت فعلی قابل لغو نیست.", http_status=400)
	if _load_document_links(db, run.id):
		raise ApiError("RUN_HAS_ACCOUNTING", "سند دارای پیوند حسابداری است و قابل لغو نیست.", http_status=409)
	old = _run_to_dict(run)
	run.status = "cancelled"
	run.cancelled_at = datetime.utcnow()
	run.updated_at = datetime.utcnow()
	_audit(db, business_id, "payroll_run", run.id, "cancel", user_id, old, _run_to_dict(run))
	db.commit()
	return get_run(db, business_id, run.id)


def update_employee(
	db: Session,
	business_id: int,
	employee_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = (
		db.query(PayrollEmployee)
		.filter(PayrollEmployee.business_id == business_id, PayrollEmployee.id == employee_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "پرسنل یافت نشد.", http_status=404)
	person = db.query(Person).filter(Person.id == row.person_id).first()
	old = _employee_to_dict(row, person)

	for field in ("job_title", "insurance_number", "tax_id", "bank_account_info", "extra_info", "is_active"):
		if field in payload:
			setattr(row, field, payload[field])
	if "department_id" in payload:
		did = payload["department_id"]
		row.department_id = int(did) if did is not None else None
	if "employment_type" in payload:
		et = str(payload["employment_type"])
		if et not in _EMPLOYMENT_TYPES:
			raise ApiError("INVALID_EMPLOYMENT_TYPE", f"نوع استخدام نامعتبر: {et}", http_status=400)
		row.employment_type = et
	if "hire_date" in payload:
		val = payload["hire_date"]
		row.hire_date = date.fromisoformat(val) if val else None
	if "termination_date" in payload:
		val = payload["termination_date"]
		row.termination_date = date.fromisoformat(val) if val else None
	if "base_salary" in payload:
		val = payload["base_salary"]
		row.base_salary = _decimal(val) if val is not None else None
	if "employee_code" in payload:
		code = str(payload["employee_code"] or "").strip()
		if code and code != row.employee_code:
			dup = (
				db.query(PayrollEmployee)
				.filter(
					PayrollEmployee.business_id == business_id,
					PayrollEmployee.employee_code == code,
					PayrollEmployee.id != row.id,
				)
				.first()
			)
			if dup:
				raise ApiError("DUPLICATE_CODE", "کد پرسنلی تکراری است.", http_status=409)
			row.employee_code = code

	row.updated_at = datetime.utcnow()
	data = _employee_to_dict(row, person)
	_audit(db, business_id, "payroll_employee", row.id, "update", user_id, old, data)
	db.commit()
	db.refresh(row)
	return data


def update_department(
	db: Session,
	business_id: int,
	department_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = (
		db.query(PayrollDepartment)
		.filter(PayrollDepartment.business_id == business_id, PayrollDepartment.id == department_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "بخش یافت نشد.", http_status=404)
	old = _department_to_dict(row)
	for field in ("name", "sort_order", "is_active"):
		if field in payload:
			setattr(row, field, payload[field])
	if "parent_id" in payload:
		pid = payload["parent_id"]
		row.parent_id = int(pid) if pid is not None else None
	row.updated_at = datetime.utcnow()
	data = _department_to_dict(row)
	_audit(db, business_id, "payroll_department", row.id, "update", user_id, old, data)
	db.commit()
	db.refresh(row)
	return data


# ─── فاز ۲: بستن دوره، کپی سند، فیش حقوق، گزارش ───────────────────────────


def close_period(
	db: Session,
	business_id: int,
	period_id: int,
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = (
		db.query(PayrollPeriod)
		.filter(PayrollPeriod.business_id == business_id, PayrollPeriod.id == period_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "دوره حقوق یافت نشد.", http_status=404)
	if row.status == "closed":
		raise ApiError("PERIOD_ALREADY_CLOSED", "این دوره قبلاً بسته شده است.", http_status=409)

	draft_count = (
		db.query(func.count(PayrollRun.id))
		.filter(
			PayrollRun.business_id == business_id,
			PayrollRun.period_id == period_id,
			PayrollRun.status == "draft",
		)
		.scalar()
		or 0
	)
	if draft_count > 0:
		raise ApiError(
			"DRAFT_RUNS_EXIST",
			"قبل از بستن دوره، پیش‌نویس‌های حقوق این دوره را قطعی یا لغو کنید.",
			http_status=400,
		)

	old = _period_to_dict(row)
	row.status = "closed"
	row.closed_at = datetime.utcnow()
	row.closed_by_user_id = user_id
	_audit(db, business_id, "payroll_period", row.id, "close", user_id, old, _period_to_dict(row))
	db.commit()
	db.refresh(row)
	return _period_to_dict(row)


def copy_run(
	db: Session,
	business_id: int,
	run_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	source = _get_run_row(db, business_id, run_id)

	target_period_id = payload.get("period_id", source.period_id)
	period = None
	if target_period_id is not None:
		period = (
			db.query(PayrollPeriod)
			.filter(PayrollPeriod.business_id == business_id, PayrollPeriod.id == int(target_period_id))
			.first()
		)
		if not period:
			raise ApiError("PERIOD_NOT_FOUND", "دوره حقوق یافت نشد.", http_status=404)
		if period.status == "closed":
			raise ApiError("PERIOD_CLOSED", "دوره بسته شده و قابل ثبت نیست.", http_status=400)

	source_lines = (
		db.query(PayrollRunLine)
		.filter(PayrollRunLine.run_id == source.id)
		.order_by(PayrollRunLine.line_number)
		.all()
	)
	if not source_lines:
		raise ApiError("NO_LINES", "سند مبدأ بدون ردیف پرسنل است.", http_status=400)

	line_ids = [ln.id for ln in source_lines]
	item_rows = (
		db.query(PayrollRunLineItem)
		.filter(PayrollRunLineItem.run_line_id.in_(line_ids))
		.all()
	)
	items_by_line: Dict[int, List[Dict[str, Any]]] = {}
	for li in item_rows:
		items_by_line.setdefault(li.run_line_id, []).append(
			{"item_definition_id": li.item_definition_id, "amount": float(li.amount)}
		)

	lines_payload = [
		{
			"employee_id": ln.employee_id,
			"notes": ln.notes,
			"items": items_by_line.get(ln.id, []),
		}
		for ln in source_lines
	]

	title = str(payload.get("title") or "").strip()
	if not title:
		title = f"کپی {source.title or source.code}"
	run_date_raw = payload.get("run_date")
	run_date = date.fromisoformat(run_date_raw) if run_date_raw else date.today()

	new_run = PayrollRun(
		business_id=business_id,
		period_id=int(target_period_id) if target_period_id is not None else None,
		code=_generate_run_code(db, business_id, settings),
		title=title,
		run_date=run_date,
		description=payload.get("description") or source.description,
		status="draft",
		created_by_user_id=user_id,
	)
	db.add(new_run)
	db.flush()
	_persist_run_lines(db, business_id, new_run, lines_payload, settings)
	new_run.updated_at = datetime.utcnow()
	_audit(db, business_id, "payroll_run", new_run.id, "copy", user_id, None, _run_to_dict(new_run))
	db.commit()
	return get_run(db, business_id, new_run.id)


def build_payslip_render_context(
	db: Session,
	business_id: int,
	run_id: int,
	*,
	line_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	run_detail = get_run(db, business_id, run_id)
	business = db.query(Business).filter(Business.id == business_id).first()
	business_name = business.name if business else ""

	lines = run_detail.get("lines") or []
	if line_id is not None:
		lines = [ln for ln in lines if ln.get("id") == int(line_id)]
		if not lines:
			raise ApiError("LINE_NOT_FOUND", "ردیف پرسنل در این سند یافت نشد.", http_status=404)

	payslips: List[Dict[str, Any]] = []
	for ln in lines:
		earnings: List[Dict[str, Any]] = []
		deductions: List[Dict[str, Any]] = []
		employer_costs: List[Dict[str, Any]] = []
		for it in ln.get("items") or []:
			kind = it.get("item_kind")
			entry = {
				"name": it.get("item_name"),
				"code": it.get("item_code"),
				"amount": it.get("amount"),
			}
			if kind == "earning":
				earnings.append(entry)
			elif kind == "deduction":
				deductions.append(entry)
			elif kind == "employer_cost":
				employer_costs.append(entry)

		payslips.append(
			{
				"employee_code": ln.get("employee_code"),
				"person_name": ln.get("person_name"),
				"job_title": ln.get("job_title"),
				"earnings": earnings,
				"deductions": deductions,
				"employer_costs": employer_costs,
				"gross_amount": ln.get("gross_amount"),
				"deduction_amount": ln.get("deduction_amount"),
				"net_amount": ln.get("net_amount"),
				"employer_cost_amount": ln.get("employer_cost_amount"),
			}
		)

	period = run_detail.get("period") or {}
	return {
		"business_name": business_name,
		"run": {
			"code": run_detail.get("code"),
			"title": run_detail.get("title"),
			"run_date": run_detail.get("run_date"),
			"status": run_detail.get("status"),
			"gross_total": run_detail.get("gross_total"),
			"deduction_total": run_detail.get("deduction_total"),
			"net_total": run_detail.get("net_total"),
		},
		"period": period,
		"payslips": payslips,
	}


def get_run_department_summary(
	db: Session,
	business_id: int,
	*,
	period_id: Optional[int] = None,
	run_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	if period_id is None and run_id is None:
		raise ApiError("FILTER_REQUIRED", "period_id یا run_id الزامی است.", http_status=400)

	q = (
		db.query(
			PayrollDepartment.id,
			PayrollDepartment.name,
			PayrollDepartment.code,
			func.count(PayrollRunLine.id),
			func.coalesce(func.sum(PayrollRunLine.gross_amount), 0),
			func.coalesce(func.sum(PayrollRunLine.deduction_amount), 0),
			func.coalesce(func.sum(PayrollRunLine.net_amount), 0),
		)
		.select_from(PayrollRunLine)
		.join(PayrollRun, PayrollRun.id == PayrollRunLine.run_id)
		.join(PayrollEmployee, PayrollEmployee.id == PayrollRunLine.employee_id)
		.outerjoin(PayrollDepartment, PayrollDepartment.id == PayrollEmployee.department_id)
		.filter(PayrollRun.business_id == business_id)
	)
	if run_id is not None:
		q = q.filter(PayrollRun.id == int(run_id))
	if period_id is not None:
		q = q.filter(PayrollRun.period_id == int(period_id))
	q = q.filter(PayrollRun.status.notin_(["cancelled", "draft"]))

	rows = q.group_by(PayrollDepartment.id, PayrollDepartment.name, PayrollDepartment.code).all()
	items = []
	total_gross = Decimal("0")
	total_deduction = Decimal("0")
	total_net = Decimal("0")
	for dept_id, name, code, cnt, gross, ded, net in rows:
		g = _decimal(gross)
		d = _decimal(ded)
		n = _decimal(net)
		total_gross += g
		total_deduction += d
		total_net += n
		items.append(
			{
				"department_id": dept_id,
				"department_name": name or ("بدون بخش" if dept_id is None else name),
				"department_code": code,
				"employee_count": int(cnt),
				"gross_total": float(g),
				"deduction_total": float(d),
				"net_total": float(n),
			}
		)

	return {
		"period_id": period_id,
		"run_id": run_id,
		"items": items,
		"totals": {
			"gross_total": float(total_gross),
			"deduction_total": float(total_deduction),
			"net_total": float(total_net),
		},
	}


# ─── فاز ۳: تأیید و ثبت حسابداری ───────────────────────────────────────────


def approve_run(
	db: Session,
	business_id: int,
	run_id: int,
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	run = _get_run_row(db, business_id, run_id)
	if run.status != "pending_approval":
		raise ApiError("INVALID_STATUS", "فقط اجراهای در انتظار تأیید قابل تأیید هستند.", http_status=400)

	old = _run_to_dict(run)
	run.status = "finalized"
	run.approved_at = datetime.utcnow()
	run.approved_by_user_id = user_id
	run.finalized_at = datetime.utcnow()
	run.finalized_by_user_id = user_id
	run.updated_at = datetime.utcnow()
	_audit(db, business_id, "payroll_run", run.id, "approve", user_id, old, _run_to_dict(run))
	db.flush()

	if settings.auto_post_on_finalize and user_id is not None:
		try:
			post_run_to_accounting(db, business_id, run.id, user_id=user_id, auto=True)
		except ApiError as exc:
			logger.warning(
				"payroll_auto_post_failed",
				extra={"run_id": run.id, "business_id": business_id, "error": exc.message},
			)

	db.commit()
	return get_run(db, business_id, run.id)


def reject_run(
	db: Session,
	business_id: int,
	run_id: int,
	user_id: Optional[int] = None,
	*,
	reason: Optional[str] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	run = _get_run_row(db, business_id, run_id)
	if run.status != "pending_approval":
		raise ApiError("INVALID_STATUS", "فقط اجراهای در انتظار تأیید قابل رد هستند.", http_status=400)

	old = _run_to_dict(run)
	extra = dict(run.extra_info or {})
	extra["rejection"] = {
		"reason": (reason or "").strip() or None,
		"rejected_at": datetime.utcnow().isoformat(),
		"rejected_by_user_id": user_id,
	}
	run.extra_info = extra
	run.status = "draft"
	run.approved_at = None
	run.approved_by_user_id = None
	run.updated_at = datetime.utcnow()
	_audit(db, business_id, "payroll_run", run.id, "reject", user_id, old, _run_to_dict(run))
	db.commit()
	return get_run(db, business_id, run.id)


def post_run_to_accounting(
	db: Session,
	business_id: int,
	run_id: int,
	user_id: int,
	*,
	auto: bool = False,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	run = _get_run_row(db, business_id, run_id)

	if run.status not in ("finalized", "posted"):
		raise ApiError(
			"INVALID_STATUS",
			"فقط اجرای قطعی‌شده قابل ثبت سند حسابداری است.",
			http_status=400,
		)

	from app.services.payroll_accounting import post_payroll_accrual_document

	old = _run_to_dict(run)
	result = post_payroll_accrual_document(db, business_id, user_id, run, settings)
	run.status = "posted"
	run.posted_at = datetime.utcnow()
	run.posted_by_user_id = user_id
	run.updated_at = datetime.utcnow()
	action = "auto_post" if auto else "post"
	_audit(db, business_id, "payroll_run", run.id, action, user_id, old, _run_to_dict(run))

	if not auto:
		db.commit()
	return {**get_run(db, business_id, run.id), "accounting": result}


def post_run_payment(
	db: Session,
	business_id: int,
	run_id: int,
	user_id: int,
	payment_account_id: int,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	run = _get_run_row(db, business_id, run_id)

	if run.status not in ("posted",):
		accrual = (
			db.query(PayrollDocumentLink)
			.filter(PayrollDocumentLink.run_id == run.id, PayrollDocumentLink.link_type == "accrual")
			.first()
		)
		if not accrual:
			raise ApiError("ACCRUAL_REQUIRED", "ابتدا سند تعهدی حقوق را ثبت کنید.", http_status=400)

	from app.services.payroll_accounting import post_payroll_payment_document

	old = _run_to_dict(run)
	result = post_payroll_payment_document(
		db, business_id, user_id, run, settings, int(payment_account_id)
	)
	run.updated_at = datetime.utcnow()
	_audit(db, business_id, "payroll_run", run.id, "post_payment", user_id, old, _run_to_dict(run))
	db.commit()
	return {**get_run(db, business_id, run.id), "accounting": result}
