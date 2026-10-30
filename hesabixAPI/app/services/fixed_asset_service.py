"""سرویس کنترل اموال و دارایی ثابت."""
from __future__ import annotations

import logging
import re
from datetime import date, datetime, timedelta
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import func, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from adapters.db.models.account import Account
from adapters.db.models.business import Business
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fixed_asset import (
	FixedAsset,
	FixedAssetClass,
	FixedAssetDepreciationRun,
	FixedAssetDepreciationRunLine,
	FixedAssetEstimateChange,
	FixedAssetLocation,
	FixedAssetSettings,
	FixedAssetSubsequentExpenditure,
)
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from app.core.fixed_asset_accounts import (
	GAIN_DISPOSAL,
	LOSS_DISPOSAL,
	REPAIR_EXPENSE,
	SYSTEM_CLASSES,
	VAT_INPUT,
	VAT_OUTPUT,
)
from app.core.fixed_assets_plugin_dependency import check_fixed_assets_plugin_active
from app.core.responses import ApiError
from app.services.currency_quant import get_currency_quant_and_round
from app.services.fixed_asset_accounting import (
	class_accum_account,
	class_cost_account,
	class_expense_account,
	post_acquisition_document,
	post_depreciation_run_document,
	post_disposal_document,
	post_subsequent_expenditure_document,
	q_amount,
	resolve_counterparty,
)
from app.services.fixed_asset_depreciation_engine import (
	ACCOUNTING_IDLE_FACTOR,
	CONVENTION_FROM_READY,
	TAX_IDLE_FACTOR_AFTER,
	TAX_IDLE_MONTHS,
	DepreciationEngineError,
	DepreciationPeriodInput,
	METHOD_DECLINING,
	METHOD_STRAIGHT_LINE,
	METHOD_UNITS,
	SUPPORTED_CONVENTIONS,
	SUPPORTED_METHODS,
	compute_period_depreciation,
	depreciation_start_date,
	month_end,
	month_start,
	prospective_straight_line_monthly,
	remaining_depreciable,
	tax_idle_factor,
)
from app.services.fixed_asset_disposal_plan import (
	EXP_MAJOR,
	EXP_ROUTINE,
	KIND_SALE,
	KIND_SCRAP,
	SUPPORTED_DISPOSAL_KINDS,
	SUPPORTED_EXPENDITURE_KINDS,
)

logger = logging.getLogger(__name__)

_CODE_RE = re.compile(r"^[a-z][a-z0-9_]{0,63}$")
_ASSET_STATUSES = frozenset({"draft", "capitalized", "idle", "disposed"})
_ACQUISITION_KINDS = frozenset({"purchase", "opening"})
_EDITABLE_WHEN_CAPITALIZED = frozenset(
	{
		"name",
		"description",
		"serial_number",
		"location_id",
		"custodian_person_id",
		"project_id",
		"status",
		"idle_from",
	}
)


def _ensure_plugin(db: Session, business_id: int) -> None:
	if not check_fixed_assets_plugin_active(db, business_id):
		raise ApiError(
			"FIXED_ASSETS_PLUGIN_NOT_ACTIVE",
			"افزونه کنترل اموال و دارایی ثابت برای این کسب‌وکار فعال نیست.",
			http_status=403,
			details={"plugin_code": "fixed_assets"},
		)


def _decimal(value: Any, default: Decimal = Decimal("0")) -> Decimal:
	if value is None or value == "":
		return default
	try:
		return Decimal(str(value))
	except (InvalidOperation, ValueError, TypeError):
		raise ApiError("INVALID_AMOUNT", f"مقدار عددی نامعتبر: {value}", http_status=400)


def _parse_date(value: Any, field: str) -> date:
	if isinstance(value, datetime):
		return value.date()
	if isinstance(value, date):
		return value
	if isinstance(value, str) and value.strip():
		try:
			return date.fromisoformat(value.strip().split("T")[0])
		except ValueError as exc:
			raise ApiError("INVALID_DATE", f"تاریخ {field} نامعتبر است.", http_status=400) from exc
	raise ApiError("DATE_REQUIRED", f"تاریخ {field} الزامی است.", http_status=400)


def _optional_int(value: Any) -> Optional[int]:
	if value is None or value == "":
		return None
	return int(value)


def _validate_class_code(code: str) -> str:
	c = str(code or "").strip().lower()
	if not c or not _CODE_RE.match(c):
		raise ApiError(
			"INVALID_CODE",
			"کد باید با حرف انگلیسی شروع شود و فقط شامل حروف کوچک، اعداد و _ باشد.",
			http_status=400,
		)
	return c


def _quant_for_settings(db: Session, settings: FixedAssetSettings) -> Decimal:
	quant, _round_on = get_currency_quant_and_round(db, settings.default_currency_id)
	return quant


def _factor_or_default(value: Any, default: Decimal) -> Decimal:
	if value is None:
		return default
	return Decimal(str(value))


def _settings_tax_idle_months(settings: Optional[FixedAssetSettings]) -> int:
	if settings is None or settings.tax_idle_months is None:
		return TAX_IDLE_MONTHS
	return int(settings.tax_idle_months)


def _settings_tax_idle_factor(settings: Optional[FixedAssetSettings]) -> Decimal:
	if settings is None:
		return TAX_IDLE_FACTOR_AFTER
	return _factor_or_default(settings.tax_idle_factor, TAX_IDLE_FACTOR_AFTER)


def _settings_accounting_idle_factor(settings: Optional[FixedAssetSettings], *, idle: bool) -> Decimal:
	if not idle:
		return Decimal("1")
	if settings is None:
		return ACCOUNTING_IDLE_FACTOR
	return _factor_or_default(settings.accounting_idle_factor, ACCOUNTING_IDLE_FACTOR)


def _settings_to_dict(row: FixedAssetSettings) -> Dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"enabled": bool(row.enabled),
		"default_currency_id": row.default_currency_id,
		"vat_account_id": row.vat_account_id,
		"vat_output_account_id": row.vat_output_account_id,
		"opening_equity_account_id": row.opening_equity_account_id,
		"disposal_gain_account_id": row.disposal_gain_account_id,
		"disposal_loss_account_id": row.disposal_loss_account_id,
		"repair_expense_account_id": row.repair_expense_account_id,
		"accounting_convention": row.accounting_convention,
		"tax_idle_months": _settings_tax_idle_months(row),
		"tax_idle_factor": str(_settings_tax_idle_factor(row)),
		"accounting_idle_factor": str(_settings_accounting_idle_factor(row, idle=True)),
		"require_custodian": bool(row.require_custodian),
		"plaque_prefix": row.plaque_prefix,
		"extra_settings": row.extra_settings,
		"default_codes": {
			"vat_input": VAT_INPUT,
			"vat_output": VAT_OUTPUT,
			"gain_disposal": GAIN_DISPOSAL,
			"loss_disposal": LOSS_DISPOSAL,
			"repair_expense": REPAIR_EXPENSE,
		},
		"created_at": row.created_at,
		"updated_at": row.updated_at,
	}


def _class_to_dict(row: FixedAssetClass) -> Dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"code": row.code,
		"name": row.name,
		"cost_account_id": row.cost_account_id,
		"accum_dep_account_id": row.accum_dep_account_id,
		"dep_expense_account_id": row.dep_expense_account_id,
		"cost_account_code": row.cost_account_code,
		"accum_dep_account_code": row.accum_dep_account_code,
		"dep_expense_account_code": row.dep_expense_account_code,
		"depreciable": bool(row.depreciable),
		"default_method": row.default_method,
		"default_useful_life_months": row.default_useful_life_months,
		"default_declining_rate": str(row.default_declining_rate) if row.default_declining_rate is not None else None,
		"tax_table_key": row.tax_table_key,
		"is_system": bool(row.is_system),
		"is_active": bool(row.is_active),
		"sort_order": int(row.sort_order or 0),
	}


def _location_to_dict(row: FixedAssetLocation) -> Dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"parent_id": row.parent_id,
		"code": row.code,
		"name": row.name,
		"is_active": bool(row.is_active),
	}


def _asset_to_dict(
	row: FixedAsset,
	cls: Optional[FixedAssetClass] = None,
	settings: Optional[FixedAssetSettings] = None,
) -> Dict[str, Any]:
	cost = Decimal(str(row.cost or 0))
	accum = Decimal(str(row.accum_depreciation or 0))
	return {
		"id": row.id,
		"business_id": row.business_id,
		"class_id": row.class_id,
		"class_code": cls.code if cls is not None else None,
		"class_name": cls.name if cls is not None else None,
		"code": row.code,
		"name": row.name,
		"description": row.description,
		"serial_number": row.serial_number,
		"status": row.status,
		"acquisition_kind": row.acquisition_kind,
		"acquisition_date": row.acquisition_date.isoformat() if row.acquisition_date else None,
		"commission_date": row.commission_date.isoformat() if row.commission_date else None,
		"cost": str(cost),
		"salvage": str(row.salvage or 0),
		"vat_amount": str(row.vat_amount or 0),
		"accum_depreciation": str(accum),
		"opening_accum_depreciation": str(row.opening_accum_depreciation or 0),
		"net_book_value": str(cost - accum),
		"method": row.method,
		"useful_life_months": row.useful_life_months,
		"declining_annual_rate": str(row.declining_annual_rate) if row.declining_annual_rate is not None else None,
		"location_id": row.location_id,
		"custodian_person_id": row.custodian_person_id,
		"project_id": row.project_id,
		"acquisition_document_id": row.acquisition_document_id,
		"invoice_id": row.invoice_id,
		"invoice_item_line_id": row.invoice_item_line_id,
		"idle_from": row.idle_from.isoformat() if row.idle_from else None,
		"disposed_at": row.disposed_at.isoformat() if row.disposed_at else None,
		"disposal_kind": row.disposal_kind,
		"disposal_proceeds": str(row.disposal_proceeds or 0),
		"disposal_document_id": row.disposal_document_id,
		"sl_monthly_override": str(row.sl_monthly_override) if row.sl_monthly_override is not None else None,
		"estimate_effective_date": row.estimate_effective_date.isoformat() if row.estimate_effective_date else None,
		"tax_idle_factor": str(
			tax_idle_factor(
				row.idle_from if row.status == "idle" else None,
				date.today(),
				idle_months=_settings_tax_idle_months(settings),
				factor_after=_settings_tax_idle_factor(settings),
			)
		),
		"extra_info": row.extra_info,
		"created_at": row.created_at,
		"updated_at": row.updated_at,
	}


def _run_to_dict(row: FixedAssetDepreciationRun, include_lines: bool = False) -> Dict[str, Any]:
	data: Dict[str, Any] = {
		"id": row.id,
		"business_id": row.business_id,
		"period_year": row.period_year,
		"period_month": row.period_month,
		"period_start": row.period_start.isoformat() if row.period_start else None,
		"period_end": row.period_end.isoformat() if row.period_end else None,
		"status": row.status,
		"convention": row.convention,
		"total_amount": str(row.total_amount or 0),
		"document_id": row.document_id,
		"description": row.description,
		"created_at": row.created_at,
		"posted_at": row.posted_at,
	}
	if include_lines:
		data["lines"] = [
			{
				"id": ln.id,
				"asset_id": ln.asset_id,
				"amount": str(ln.amount),
				"tax_preview_amount": str(ln.tax_preview_amount or 0),
				"book_value_before": str(ln.book_value_before),
				"book_value_after": str(ln.book_value_after),
				"method": ln.method,
				"expense_account_id": ln.expense_account_id,
				"accum_account_id": ln.accum_account_id,
			}
			for ln in (row.lines or [])
		]
	return data


def _bind_class_account_ids(db: Session, cls: FixedAssetClass) -> None:
	pairs = (
		("cost_account_id", "cost_account_code"),
		("accum_dep_account_id", "accum_dep_account_code"),
		("dep_expense_account_id", "dep_expense_account_code"),
	)
	for id_attr, code_attr in pairs:
		if getattr(cls, id_attr) is not None:
			continue
		code = getattr(cls, code_attr)
		if not code:
			continue
		acc = (
			db.query(Account)
			.filter(Account.code == str(code), Account.business_id.is_(None))  # noqa: E711
			.first()
		)
		if acc:
			setattr(cls, id_attr, acc.id)


def _seed_system_classes(db: Session, business_id: int) -> None:
	existing = {
		row.code: row
		for row in db.query(FixedAssetClass).filter(FixedAssetClass.business_id == business_id).all()
	}
	for spec in SYSTEM_CLASSES:
		row = existing.get(spec["code"])
		if row is None:
			row = FixedAssetClass(
				business_id=business_id,
				code=spec["code"],
				name=spec["name"],
				depreciable=bool(spec["depreciable"]),
				cost_account_code=spec["cost_account_code"],
				accum_dep_account_code=spec["accum_dep_account_code"],
				dep_expense_account_code=spec["dep_expense_account_code"],
				default_method=spec["default_method"],
				is_system=True,
				is_active=True,
				sort_order=int(spec["sort_order"]),
			)
			db.add(row)
			db.flush()
		_bind_class_account_ids(db, row)


def _get_or_create_settings(db: Session, business_id: int) -> FixedAssetSettings:
	row = db.query(FixedAssetSettings).filter(FixedAssetSettings.business_id == business_id).first()
	if row:
		_seed_system_classes(db, business_id)
		return row
	business = db.query(Business).filter(Business.id == business_id).first()
	if not business:
		raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد.", http_status=404)
	row = FixedAssetSettings(
		business_id=business_id,
		enabled=True,
		default_currency_id=business.default_currency_id,
		accounting_convention=CONVENTION_FROM_READY,
		plaque_prefix="FA",
	)
	db.add(row)
	db.flush()
	_seed_system_classes(db, business_id)
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
	user_id: Optional[int] = None,  # noqa: ARG001
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = _get_or_create_settings(db, business_id)
	if "enabled" in payload:
		row.enabled = bool(payload["enabled"])
	if "default_currency_id" in payload:
		val = payload["default_currency_id"]
		row.default_currency_id = int(val) if val is not None else None
	if "vat_account_id" in payload:
		row.vat_account_id = _optional_int(payload["vat_account_id"])
	if "vat_output_account_id" in payload:
		row.vat_output_account_id = _optional_int(payload["vat_output_account_id"])
	if "opening_equity_account_id" in payload:
		row.opening_equity_account_id = _optional_int(payload["opening_equity_account_id"])
	if "disposal_gain_account_id" in payload:
		row.disposal_gain_account_id = _optional_int(payload["disposal_gain_account_id"])
	if "disposal_loss_account_id" in payload:
		row.disposal_loss_account_id = _optional_int(payload["disposal_loss_account_id"])
	if "repair_expense_account_id" in payload:
		row.repair_expense_account_id = _optional_int(payload["repair_expense_account_id"])
	if "accounting_convention" in payload:
		conv = str(payload["accounting_convention"] or "").strip()
		if conv not in SUPPORTED_CONVENTIONS:
			raise ApiError(
				"INVALID_CONVENTION",
				"قرارداد استهلاک باید from_ready_date یا next_month باشد.",
				http_status=400,
			)
		row.accounting_convention = conv
	if "tax_idle_months" in payload:
		try:
			months = int(payload["tax_idle_months"])
		except (TypeError, ValueError) as exc:
			raise ApiError("INVALID_IDLE_MONTHS", "آستانه ماه رکود مالیاتی نامعتبر است.", http_status=400) from exc
		if months < 0 or months > 600:
			raise ApiError("INVALID_IDLE_MONTHS", "آستانه ماه رکود مالیاتی باید بین ۰ و ۶۰۰ باشد.", http_status=400)
		row.tax_idle_months = months
	if "tax_idle_factor" in payload:
		factor = _decimal(payload["tax_idle_factor"])
		if factor < 0 or factor > 1:
			raise ApiError(
				"INVALID_TAX_IDLE_FACTOR",
				"عامل استهلاک مالیاتی رکود باید بین ۰ و ۱ باشد (۰٫۷ یعنی ۳۰٪ کاهش).",
				http_status=400,
			)
		row.tax_idle_factor = factor
	if "accounting_idle_factor" in payload:
		factor = _decimal(payload["accounting_idle_factor"])
		if factor < 0 or factor > 1:
			raise ApiError(
				"INVALID_ACCOUNTING_IDLE_FACTOR",
				"عامل استهلاک حسابداری هنگام رکود باید بین ۰ و ۱ باشد (۱ یعنی بدون کاهش).",
				http_status=400,
			)
		row.accounting_idle_factor = factor
	if "extra_settings" in payload:
		raw_extra = payload["extra_settings"]
		if raw_extra is None:
			row.extra_settings = None
		elif isinstance(raw_extra, dict):
			row.extra_settings = raw_extra
		else:
			raise ApiError("INVALID_EXTRA_SETTINGS", "extra_settings باید شیء JSON باشد.", http_status=400)
	if "require_custodian" in payload:
		row.require_custodian = bool(payload["require_custodian"])
	if "plaque_prefix" in payload:
		prefix = str(payload["plaque_prefix"] or "FA").strip() or "FA"
		if len(prefix) > 16:
			raise ApiError("INVALID_PREFIX", "پیشوند پلاک حداکثر ۱۶ نویسه است.", http_status=400)
		row.plaque_prefix = prefix
	db.commit()
	db.refresh(row)
	return _settings_to_dict(row)


def list_classes(db: Session, business_id: int, include_inactive: bool = False) -> List[Dict[str, Any]]:
	_ensure_plugin(db, business_id)
	_get_or_create_settings(db, business_id)
	q = db.query(FixedAssetClass).filter(FixedAssetClass.business_id == business_id)
	if not include_inactive:
		q = q.filter(FixedAssetClass.is_active == True)  # noqa: E712
	rows = q.order_by(FixedAssetClass.sort_order.asc(), FixedAssetClass.id.asc()).all()
	db.commit()
	return [_class_to_dict(r) for r in rows]


def update_class(
	db: Session,
	business_id: int,
	class_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,  # noqa: ARG001
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = (
		db.query(FixedAssetClass)
		.filter(FixedAssetClass.id == class_id, FixedAssetClass.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("CLASS_NOT_FOUND", "طبقه دارایی یافت نشد.", http_status=404)
	if "name" in payload and payload["name"]:
		row.name = str(payload["name"]).strip()
	if "cost_account_id" in payload:
		row.cost_account_id = _optional_int(payload["cost_account_id"])
	if "accum_dep_account_id" in payload:
		row.accum_dep_account_id = _optional_int(payload["accum_dep_account_id"])
	if "dep_expense_account_id" in payload:
		row.dep_expense_account_id = _optional_int(payload["dep_expense_account_id"])
	if "cost_account_code" in payload:
		row.cost_account_code = (str(payload["cost_account_code"]).strip() or None) if payload["cost_account_code"] else None
	if "accum_dep_account_code" in payload:
		row.accum_dep_account_code = (
			(str(payload["accum_dep_account_code"]).strip() or None) if payload["accum_dep_account_code"] else None
		)
	if "dep_expense_account_code" in payload:
		row.dep_expense_account_code = (
			(str(payload["dep_expense_account_code"]).strip() or None) if payload["dep_expense_account_code"] else None
		)
	if "default_method" in payload:
		method = str(payload["default_method"] or "").strip()
		if method == METHOD_UNITS or method not in SUPPORTED_METHODS:
			raise ApiError("INVALID_METHOD", "روش استهلاک این فاز فقط خط مستقیم یا مانده نزولی است.", http_status=400)
		row.default_method = method
	if "default_useful_life_months" in payload:
		val = payload["default_useful_life_months"]
		row.default_useful_life_months = int(val) if val not in (None, "") else None
	if "default_declining_rate" in payload:
		val = payload["default_declining_rate"]
		row.default_declining_rate = _decimal(val) if val not in (None, "") else None
	if "is_active" in payload and not row.is_system:
		row.is_active = bool(payload["is_active"])
	if "depreciable" in payload and not row.is_system:
		row.depreciable = bool(payload["depreciable"])
	db.commit()
	db.refresh(row)
	return _class_to_dict(row)


def list_locations(db: Session, business_id: int, include_inactive: bool = False) -> List[Dict[str, Any]]:
	_ensure_plugin(db, business_id)
	q = db.query(FixedAssetLocation).filter(FixedAssetLocation.business_id == business_id)
	if not include_inactive:
		q = q.filter(FixedAssetLocation.is_active == True)  # noqa: E712
	rows = q.order_by(FixedAssetLocation.code.asc()).all()
	return [_location_to_dict(r) for r in rows]


def create_location(
	db: Session,
	business_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,  # noqa: ARG001
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	code = str(payload.get("code") or "").strip()
	name = str(payload.get("name") or "").strip()
	if not code or not name:
		raise ApiError("LOCATION_REQUIRED", "کد و نام محل استقرار الزامی است.", http_status=400)
	row = FixedAssetLocation(
		business_id=business_id,
		code=code,
		name=name,
		parent_id=_optional_int(payload.get("parent_id")),
		is_active=True,
	)
	db.add(row)
	try:
		db.commit()
	except IntegrityError as exc:
		db.rollback()
		raise ApiError("LOCATION_CODE_EXISTS", "کد محل استقرار تکراری است.", http_status=409) from exc
	db.refresh(row)
	return _location_to_dict(row)


def update_location(
	db: Session,
	business_id: int,
	location_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,  # noqa: ARG001
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = (
		db.query(FixedAssetLocation)
		.filter(FixedAssetLocation.id == location_id, FixedAssetLocation.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("LOCATION_NOT_FOUND", "محل استقرار یافت نشد.", http_status=404)
	if "code" in payload and payload["code"]:
		row.code = str(payload["code"]).strip()
	if "name" in payload and payload["name"]:
		row.name = str(payload["name"]).strip()
	if "parent_id" in payload:
		pid = _optional_int(payload["parent_id"])
		if pid == row.id:
			raise ApiError("INVALID_PARENT", "محل نمی‌تواند والد خودش باشد.", http_status=400)
		row.parent_id = pid
	if "is_active" in payload:
		row.is_active = bool(payload["is_active"])
	db.commit()
	db.refresh(row)
	return _location_to_dict(row)


def _get_class(db: Session, business_id: int, class_id: int) -> FixedAssetClass:
	row = (
		db.query(FixedAssetClass)
		.filter(FixedAssetClass.id == class_id, FixedAssetClass.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("CLASS_NOT_FOUND", "طبقه دارایی یافت نشد.", http_status=404)
	if not row.is_active:
		raise ApiError("CLASS_INACTIVE", "این طبقه غیرفعال است.", http_status=400)
	return row


def _next_asset_code(db: Session, business_id: int, settings: FixedAssetSettings, cls: FixedAssetClass) -> str:
	prefix = (settings.plaque_prefix or "FA").strip() or "FA"
	class_part = (cls.code or "gen").upper()[:8]
	stem = f"{prefix}-{class_part}-"
	last = (
		db.query(FixedAsset.code)
		.filter(FixedAsset.business_id == business_id, FixedAsset.code.like(f"{stem}%"))
		.order_by(FixedAsset.code.desc())
		.first()
	)
	seq = 1
	if last and last[0]:
		tail = str(last[0])[len(stem) :]
		try:
			seq = int(tail) + 1
		except ValueError:
			seq = (
				db.query(func.count(FixedAsset.id))
				.filter(FixedAsset.business_id == business_id, FixedAsset.class_id == cls.id)
				.scalar()
				or 0
			) + 1
	return f"{stem}{seq:04d}"


def _validate_method_fields(*, method: str, depreciable: bool, life: Optional[int], rate: Optional[Decimal]) -> None:
	if method == METHOD_UNITS or method not in SUPPORTED_METHODS:
		raise ApiError(
			"INVALID_METHOD",
			"روش استهلاک این فاز فقط خط مستقیم یا مانده نزولی است.",
			http_status=400,
		)
	if not depreciable:
		return
	if method == METHOD_STRAIGHT_LINE and (life is None or int(life) < 1):
		raise ApiError(
			"USEFUL_LIFE_REQUIRED",
			"برای روش خط مستقیم، عمر مفید به ماه الزامی است.",
			http_status=400,
		)
	if method == METHOD_DECLINING:
		if rate is None or rate <= 0 or rate >= 1:
			raise ApiError(
				"DECLINING_RATE_REQUIRED",
				"نرخ مانده نزولی باید کسری بین ۰ و ۱ باشد (مثلاً ۰٫۲۵).",
				http_status=400,
			)


def create_asset(
	db: Session,
	business_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	if not settings.enabled:
		raise ApiError("FIXED_ASSETS_DISABLED", "ماژول اموال در تنظیمات این کسب‌وکار غیرفعال است.", http_status=400)
	cls = _get_class(db, business_id, int(payload.get("class_id") or 0))
	name = str(payload.get("name") or "").strip()
	if not name:
		raise ApiError("NAME_REQUIRED", "نام دارایی الزامی است.", http_status=400)
	acquisition_date = _parse_date(payload.get("acquisition_date"), "acquisition_date")
	commission_raw = payload.get("commission_date") or payload.get("acquisition_date")
	commission_date = _parse_date(commission_raw, "commission_date")
	if commission_date < acquisition_date:
		raise ApiError(
			"INVALID_COMMISSION_DATE",
			"تاریخ بهره‌برداری نمی‌تواند قبل از تاریخ تحصیل باشد.",
			http_status=400,
		)
	kind = str(payload.get("acquisition_kind") or "purchase").strip()
	if kind not in _ACQUISITION_KINDS:
		raise ApiError("INVALID_ACQUISITION_KIND", "نوع تحصیل باید purchase یا opening باشد.", http_status=400)
	quant = _quant_for_settings(db, settings)
	cost = q_amount(_decimal(payload.get("cost")), quant)
	if cost <= 0:
		raise ApiError("INVALID_COST", "بهای تمام‌شده باید بزرگ‌تر از صفر باشد.", http_status=400)
	salvage = q_amount(_decimal(payload.get("salvage")), quant)
	vat = q_amount(_decimal(payload.get("vat_amount")), quant)
	opening_accum = q_amount(_decimal(payload.get("opening_accum_depreciation")), quant)
	if salvage < 0 or vat < 0 or opening_accum < 0:
		raise ApiError("INVALID_AMOUNT", "مبالغ نمی‌توانند منفی باشند.", http_status=400)
	if salvage > cost:
		raise ApiError("INVALID_SALVAGE", "ارزش اسقاط نمی‌تواند از بها بیشتر باشد.", http_status=400)
	if kind != "opening" and opening_accum > 0:
		raise ApiError(
			"OPENING_ACCUM_NOT_ALLOWED",
			"استهلاک انباشته افتتاحیه فقط برای تحصیل opening مجاز است.",
			http_status=400,
		)
	if opening_accum >= cost:
		raise ApiError("INVALID_OPENING_ACCUM", "استهلاک انباشته افتتاحیه باید از بها کمتر باشد.", http_status=400)
	method = str(payload.get("method") or cls.default_method or METHOD_STRAIGHT_LINE).strip()
	life = payload.get("useful_life_months")
	if life in (None, "") and cls.default_useful_life_months is not None:
		life = cls.default_useful_life_months
	life_i = int(life) if life not in (None, "") else None
	rate = payload.get("declining_annual_rate")
	if rate in (None, "") and cls.default_declining_rate is not None:
		rate = cls.default_declining_rate
	rate_d = _decimal(rate) if rate not in (None, "") else None
	custodian_id = _optional_int(payload.get("custodian_person_id"))
	if custodian_id:
		person = (
			db.query(Person)
			.filter(Person.id == custodian_id, Person.business_id == business_id)
			.first()
		)
		if not person:
			raise ApiError("PERSON_NOT_FOUND", "تحویل‌گیرنده یافت نشد.", http_status=404)
	code = str(payload.get("code") or "").strip() or _next_asset_code(db, business_id, settings, cls)
	row = FixedAsset(
		business_id=business_id,
		class_id=cls.id,
		code=code,
		name=name,
		description=(str(payload.get("description")).strip() or None) if payload.get("description") else None,
		serial_number=(str(payload.get("serial_number")).strip() or None) if payload.get("serial_number") else None,
		status="draft",
		acquisition_kind=kind,
		acquisition_date=acquisition_date,
		commission_date=commission_date,
		cost=cost,
		salvage=salvage,
		vat_amount=vat,
		accum_depreciation=opening_accum,
		opening_accum_depreciation=opening_accum,
		method=method,
		useful_life_months=life_i,
		declining_annual_rate=rate_d,
		location_id=_optional_int(payload.get("location_id")),
		custodian_person_id=custodian_id,
		project_id=_optional_int(payload.get("project_id")),
		created_by_user_id=user_id,
	)
	db.add(row)
	try:
		db.commit()
	except IntegrityError as exc:
		db.rollback()
		raise ApiError("ASSET_CODE_EXISTS", "کد دارایی تکراری است.", http_status=409) from exc
	db.refresh(row)
	return _asset_to_dict(row, cls)


def list_assets(
	db: Session,
	business_id: int,
	*,
	status: Optional[str] = None,
	class_id: Optional[int] = None,
	search: Optional[str] = None,
	invoice_id: Optional[int] = None,
	limit: int = 100,
	skip: int = 0,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	q = db.query(FixedAsset).filter(FixedAsset.business_id == business_id)
	if status:
		if status not in _ASSET_STATUSES:
			raise ApiError("INVALID_STATUS", "وضعیت دارایی نامعتبر است.", http_status=400)
		q = q.filter(FixedAsset.status == status)
	if class_id:
		q = q.filter(FixedAsset.class_id == int(class_id))
	if invoice_id:
		q = q.filter(FixedAsset.invoice_id == int(invoice_id))
	if search:
		term = f"%{search.strip()}%"
		q = q.filter(
			or_(
				FixedAsset.code.ilike(term),
				FixedAsset.name.ilike(term),
				FixedAsset.serial_number.ilike(term),
			)
		)
	total = q.count()
	rows = q.order_by(FixedAsset.id.desc()).offset(max(0, skip)).limit(min(500, max(1, limit))).all()
	class_ids = {r.class_id for r in rows}
	classes = {
		c.id: c
		for c in db.query(FixedAssetClass).filter(FixedAssetClass.id.in_(class_ids)).all()
	} if class_ids else {}
	return {
		"total": total,
		"items": [_asset_to_dict(r, classes.get(r.class_id), settings) for r in rows],
	}


def get_asset(db: Session, business_id: int, asset_id: int) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	row = (
		db.query(FixedAsset)
		.filter(FixedAsset.id == asset_id, FixedAsset.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("ASSET_NOT_FOUND", "دارایی یافت نشد.", http_status=404)
	cls = db.query(FixedAssetClass).filter(FixedAssetClass.id == row.class_id).first()
	return _asset_to_dict(row, cls, settings)


def update_asset(
	db: Session,
	business_id: int,
	asset_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,  # noqa: ARG001
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = (
		db.query(FixedAsset)
		.filter(FixedAsset.id == asset_id, FixedAsset.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("ASSET_NOT_FOUND", "دارایی یافت نشد.", http_status=404)
	if row.status == "disposed":
		raise ApiError("ASSET_DISPOSED", "دارایی خارج‌شده قابل ویرایش نیست.", http_status=409)
	cls = _get_class(db, business_id, row.class_id)
	locked = row.status in ("capitalized", "idle")
	if locked:
		unknown = set(payload.keys()) - _EDITABLE_WHEN_CAPITALIZED
		if unknown:
			raise ApiError(
				"ASSET_LOCKED",
				"پس از سرمایه‌گذاری فقط نام، محل، تحویل‌گیرنده و وضعیت راکد قابل تغییر است.",
				http_status=409,
			)
	settings = _get_or_create_settings(db, business_id)
	quant = _quant_for_settings(db, settings)
	if "name" in payload and payload["name"]:
		row.name = str(payload["name"]).strip()
	if "description" in payload:
		row.description = (str(payload["description"]).strip() or None) if payload["description"] else None
	if "serial_number" in payload:
		row.serial_number = (str(payload["serial_number"]).strip() or None) if payload["serial_number"] else None
	if "location_id" in payload:
		row.location_id = _optional_int(payload["location_id"])
	if "custodian_person_id" in payload:
		row.custodian_person_id = _optional_int(payload["custodian_person_id"])
	if "project_id" in payload:
		row.project_id = _optional_int(payload["project_id"])
	if "status" in payload and locked:
		new_status = str(payload["status"]).strip()
		if new_status not in ("capitalized", "idle"):
			raise ApiError("INVALID_STATUS", "پس از سرمایه، وضعیت فقط capitalized یا idle است.", http_status=400)
		row.status = new_status
		if new_status == "idle":
			if payload.get("idle_from"):
				row.idle_from = _parse_date(payload.get("idle_from"), "idle_from")
			elif row.idle_from is None:
				row.idle_from = date.today()
		else:
			row.idle_from = None
	if not locked:
		if "class_id" in payload and payload["class_id"]:
			cls = _get_class(db, business_id, int(payload["class_id"]))
			row.class_id = cls.id
		if "acquisition_kind" in payload:
			kind = str(payload["acquisition_kind"]).strip()
			if kind not in _ACQUISITION_KINDS:
				raise ApiError("INVALID_ACQUISITION_KIND", "نوع تحصیل نامعتبر است.", http_status=400)
			row.acquisition_kind = kind
		if "acquisition_date" in payload:
			row.acquisition_date = _parse_date(payload["acquisition_date"], "acquisition_date")
		if "commission_date" in payload:
			row.commission_date = _parse_date(payload["commission_date"], "commission_date")
		if row.commission_date < row.acquisition_date:
			raise ApiError("INVALID_COMMISSION_DATE", "تاریخ بهره‌برداری قبل از تحصیل است.", http_status=400)
		if "cost" in payload:
			row.cost = q_amount(_decimal(payload["cost"]), quant)
		if "salvage" in payload:
			row.salvage = q_amount(_decimal(payload["salvage"]), quant)
		if "vat_amount" in payload:
			row.vat_amount = q_amount(_decimal(payload["vat_amount"]), quant)
		if "opening_accum_depreciation" in payload:
			row.opening_accum_depreciation = q_amount(_decimal(payload["opening_accum_depreciation"]), quant)
			row.accum_depreciation = row.opening_accum_depreciation
		if "method" in payload and payload["method"]:
			row.method = str(payload["method"]).strip()
		if "useful_life_months" in payload:
			val = payload["useful_life_months"]
			row.useful_life_months = int(val) if val not in (None, "") else None
		if "declining_annual_rate" in payload:
			val = payload["declining_annual_rate"]
			row.declining_annual_rate = _decimal(val) if val not in (None, "") else None
	db.commit()
	db.refresh(row)
	return _asset_to_dict(row, cls)


def delete_asset(db: Session, business_id: int, asset_id: int) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = (
		db.query(FixedAsset)
		.filter(FixedAsset.id == asset_id, FixedAsset.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("ASSET_NOT_FOUND", "دارایی یافت نشد.", http_status=404)
	if row.status != "draft" or row.acquisition_document_id or row.invoice_id:
		raise ApiError("ASSET_NOT_DRAFT", "فقط دارایی پیش‌نویسِ سرمایه‌نشده قابل حذف است.", http_status=409)
	db.delete(row)
	db.commit()
	return {"deleted": True, "id": asset_id}


def capitalize_asset(
	db: Session,
	business_id: int,
	asset_id: int,
	payload: Dict[str, Any],
	user_id: int,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	row = (
		db.query(FixedAsset)
		.filter(FixedAsset.id == asset_id, FixedAsset.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("ASSET_NOT_FOUND", "دارایی یافت نشد.", http_status=404)
	if row.status != "draft":
		raise ApiError("ASSET_NOT_DRAFT", "فقط دارایی پیش‌نویس قابل سرمایه‌گذاری است.", http_status=409)
	if row.invoice_id or row.invoice_item_line_id:
		raise ApiError(
			"ASSET_CAPITALIZED_VIA_INVOICE",
			"این دارایی از فاکتور خرید سرمایه‌ای ثبت شده است؛ سند تحصیل جدا صادر نمی‌شود.",
			http_status=409,
		)
	cls = _get_class(db, business_id, row.class_id)
	if settings.require_custodian and not row.custodian_person_id:
		raise ApiError("CUSTODIAN_REQUIRED", "تحویل‌گیرنده برای سرمایه‌گذاری الزامی است.", http_status=400)
	rate = Decimal(str(row.declining_annual_rate)) if row.declining_annual_rate is not None else None
	_validate_method_fields(
		method=row.method,
		depreciable=bool(cls.depreciable),
		life=row.useful_life_months,
		rate=rate,
	)
	class_cost_account(db, business_id, cls)
	if cls.depreciable:
		class_accum_account(db, business_id, cls)
		class_expense_account(db, business_id, cls)
	counterparty = resolve_counterparty(db, business_id, settings, payload)
	quant = _quant_for_settings(db, settings)
	document = post_acquisition_document(
		db,
		business_id=business_id,
		user_id=user_id,
		asset=row,
		cls=cls,
		settings=settings,
		counterparty=counterparty,
		quant=quant,
	)
	row.acquisition_document_id = document.id
	row.status = "capitalized"
	row.accum_depreciation = Decimal(str(row.opening_accum_depreciation or 0))
	db.commit()
	db.refresh(row)
	data = _asset_to_dict(row, cls)
	data["acquisition_document_code"] = document.code
	return data


def prepare_invoice_capital_lines(
	db: Session,
	business_id: int,
	invoice_type: str,
	lines: List[Dict[str, Any]],
	*,
	existing_invoice_id: Optional[int] = None,
) -> bool:
	"""اعتبارسنجی سطر سرمایه‌ای. موجودی را برای این سطرها خاموش می‌کند. False اگر سطر سرمایه‌ای نباشد."""
	from app.services.fixed_asset_capital_purchase import (
		EXTRA_FLAG,
		INVOICE_PURCHASE_RETURN_TYPE,
		INVOICE_PURCHASE_TYPE,
		capital_class_id,
		capital_optional_decimal,
		capital_optional_int,
		is_capital_invoice_line,
	)

	has_capital = any(is_capital_invoice_line(ln.get("extra_info")) for ln in lines)
	existing_fa = False
	if existing_invoice_id:
		existing_fa = (
			db.query(FixedAsset.id)
			.filter(
				FixedAsset.business_id == business_id,
				FixedAsset.invoice_id == int(existing_invoice_id),
			)
			.first()
			is not None
		)
	if not has_capital and not existing_fa:
		return False
	if invoice_type == INVOICE_PURCHASE_RETURN_TYPE and has_capital:
		raise ApiError(
			"CAPITAL_PURCHASE_RETURN_FORBIDDEN",
			"برگشت کالای سرمایه‌ای از فاکتور برگشت خرید مجاز نیست. دارایی را از ماژول اموال خارج کنید.",
			http_status=409,
		)
	if invoice_type != INVOICE_PURCHASE_TYPE:
		if has_capital:
			raise ApiError(
				"CAPITAL_LINE_ONLY_ON_PURCHASE",
				"سطر سرمایه‌ای فقط در فاکتور خرید مجاز است.",
				http_status=400,
			)
		if existing_fa:
			raise ApiError(
				"CAPITAL_INVOICE_TYPE_LOCKED",
				"این فاکتور به کارت دارایی پیوند دارد و نوع آن قابل تغییر نیست.",
				http_status=409,
			)
		return False
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	if not settings.enabled:
		raise ApiError("FIXED_ASSETS_DISABLED", "ماژول اموال در تنظیمات این کسب‌وکار غیرفعال است.", http_status=400)
	if not has_capital:
		return True
	for idx, ln in enumerate(lines, start=1):
		info = dict(ln.get("extra_info") or {})
		if not is_capital_invoice_line(info):
			continue
		cls_id = capital_class_id(info)
		if not cls_id:
			raise ApiError(
				"FIXED_ASSET_CLASS_REQUIRED",
				f"سطر {idx}: طبقه دارایی برای سطر سرمایه‌ای الزامی است.",
				http_status=400,
			)
		cls = _get_class(db, business_id, cls_id)
		class_cost_account(db, business_id, cls)
		if cls.depreciable:
			class_accum_account(db, business_id, cls)
			class_expense_account(db, business_id, cls)
		life = capital_optional_int(info, "fixed_asset_useful_life_months", "useful_life_months")
		if life is None and cls.default_useful_life_months is not None:
			life = int(cls.default_useful_life_months)
		rate = capital_optional_decimal(info, "fixed_asset_declining_annual_rate", "declining_annual_rate")
		if rate is None and cls.default_declining_rate is not None:
			rate = Decimal(str(cls.default_declining_rate))
		method = str(cls.default_method or METHOD_STRAIGHT_LINE)
		_validate_method_fields(method=method, depreciable=bool(cls.depreciable), life=life, rate=rate)
		info[EXTRA_FLAG] = True
		info["inventory_tracked"] = False
		info["inventory_posted"] = False
		ln["extra_info"] = info
	return True


def add_capital_cost_document_lines(
	db: Session,
	business_id: int,
	document_id: int,
	capital_net_by_class: Dict[int, Decimal],
) -> None:
	if not capital_net_by_class:
		return
	settings = _get_or_create_settings(db, business_id)
	quant = _quant_for_settings(db, settings)
	for class_id, net in capital_net_by_class.items():
		amount = q_amount(Decimal(str(net or 0)), quant)
		if amount <= 0:
			continue
		if not class_id:
			raise ApiError(
				"FIXED_ASSET_CLASS_REQUIRED",
				"طبقه دارایی برای سطر سرمایه‌ای الزامی است.",
				http_status=400,
			)
		cls = _get_class(db, business_id, int(class_id))
		acc = class_cost_account(db, business_id, cls)
		db.add(
			DocumentLine(
				document_id=document_id,
				account_id=acc.id,
				debit=amount,
				credit=Decimal(0),
				description=f"تحصیل دارایی ثابت — {cls.name}",
				extra_info={"source": "fixed_asset_capital_purchase", "class_id": cls.id},
			)
		)


def _invoice_linked_assets(db: Session, business_id: int, invoice_id: int) -> List[FixedAsset]:
	return (
		db.query(FixedAsset)
		.filter(FixedAsset.business_id == business_id, FixedAsset.invoice_id == int(invoice_id))
		.order_by(FixedAsset.id.asc())
		.all()
	)


def _asset_is_invoice_reversible(db: Session, asset: FixedAsset) -> bool:
	if asset.invoice_id is None:
		return False
	if asset.status not in ("draft", "capitalized"):
		return False
	if Decimal(str(asset.accum_depreciation or 0)) != Decimal(str(asset.opening_accum_depreciation or 0)):
		return False
	if asset.disposal_document_id or asset.disposed_at:
		return False
	if (
		db.query(FixedAssetSubsequentExpenditure.id)
		.filter(FixedAssetSubsequentExpenditure.asset_id == asset.id)
		.first()
	):
		return False
	if (
		db.query(FixedAssetEstimateChange.id)
		.filter(FixedAssetEstimateChange.asset_id == asset.id)
		.first()
	):
		return False
	if (
		db.query(FixedAssetDepreciationRunLine.id)
		.filter(FixedAssetDepreciationRunLine.asset_id == asset.id)
		.first()
	):
		return False
	return True


def assert_invoice_capital_assets_rebuildable(db: Session, business_id: int, invoice_id: int) -> None:
	assets = _invoice_linked_assets(db, business_id, invoice_id)
	blocked = [a.code for a in assets if not _asset_is_invoice_reversible(db, a)]
	if blocked:
		raise ApiError(
			"CAPITAL_INVOICE_LOCKED",
			"فاکتور خرید سرمایه‌ای پس از استهلاک، تعمیر، تغییر برآورد یا خروج دارایی قابل ویرایش یا حذف نیست.",
			http_status=409,
			details={"asset_codes": blocked},
		)


def _delete_reversible_invoice_asset(db: Session, asset: FixedAsset) -> None:
	if not _asset_is_invoice_reversible(db, asset):
		raise ApiError(
			"CAPITAL_INVOICE_LOCKED",
			"این دارایی از فاکتور خرید دیگر قابل برگشت نیست.",
			http_status=409,
		)
	db.delete(asset)


def delete_invoice_capital_assets(db: Session, business_id: int, invoice_id: int) -> int:
	assert_invoice_capital_assets_rebuildable(db, business_id, invoice_id)
	assets = _invoice_linked_assets(db, business_id, invoice_id)
	count = 0
	for asset in assets:
		_delete_reversible_invoice_asset(db, asset)
		count += 1
	if count:
		db.flush()
	return count


def _match_key(class_id: int, cost: Decimal, vat: Decimal, product_id: Optional[int]) -> Tuple[int, str, str, int]:
	return (int(class_id), str(cost), str(vat), int(product_id or 0))


def sync_capital_assets_from_purchase_invoice(
	db: Session,
	business_id: int,
	document: Any,
	user_id: Optional[int],
) -> List[int]:
	"""کارت دارایی سرمایه‌شده از سطرهای فاکتور؛ بدون سند FAA جدا (بها روی خود فاکتور است)."""
	from app.services.fixed_asset_capital_purchase import (
		EXTRA_ASSET_ID,
		capital_asset_name,
		capital_class_id,
		capital_custodian_id,
		capital_location_id,
		capital_optional_decimal,
		capital_optional_int,
		is_capital_invoice_line,
		line_purchase_amounts,
	)

	if bool(getattr(document, "is_proforma", False)):
		return []
	assert_invoice_capital_assets_rebuildable(db, business_id, int(document.id))
	settings = _get_or_create_settings(db, business_id)
	quant = _quant_for_settings(db, settings)
	item_lines = (
		db.query(InvoiceItemLine)
		.filter(InvoiceItemLine.document_id == int(document.id))
		.order_by(InvoiceItemLine.id.asc())
		.all()
	)
	specs: List[Dict[str, Any]] = []
	for row in item_lines:
		info = dict(row.extra_info or {})
		if not is_capital_invoice_line(info):
			continue
		_gross, _disc, net, tax = line_purchase_amounts(
			{"quantity": row.quantity, "extra_info": info}
		)
		cls_id = capital_class_id(info)
		if not cls_id:
			raise ApiError("FIXED_ASSET_CLASS_REQUIRED", "طبقه دارایی برای سطر سرمایه‌ای الزامی است.", http_status=400)
		product = db.query(Product).filter(Product.id == int(row.product_id)).first()
		fallback_name = (row.description or "").strip() or (product.name if product else None) or f"دارایی سطر {row.id}"
		salvage = capital_optional_decimal(info, "fixed_asset_salvage", "salvage") or Decimal("0")
		specs.append(
			{
				"line": row,
				"info": info,
				"class_id": int(cls_id),
				"cost": q_amount(net, quant),
				"vat": q_amount(tax, quant),
				"salvage": q_amount(salvage, quant),
				"product_id": int(row.product_id) if row.product_id else None,
				"name": capital_asset_name(info, fallback_name),
				"location_id": capital_location_id(info),
				"custodian_person_id": capital_custodian_id(info),
				"life": capital_optional_int(info, "fixed_asset_useful_life_months", "useful_life_months"),
				"rate": capital_optional_decimal(info, "fixed_asset_declining_annual_rate", "declining_annual_rate"),
			}
		)

	old_assets = _invoice_linked_assets(db, business_id, int(document.id))
	unused: List[FixedAsset] = list(old_assets)
	created_or_kept: List[int] = []
	acq_date = document.document_date
	if not isinstance(acq_date, date):
		acq_date = date.fromisoformat(str(acq_date)[:10])

	for spec in specs:
		key = _match_key(spec["class_id"], spec["cost"], spec["vat"], spec["product_id"])
		matched: Optional[FixedAsset] = None
		for asset in unused:
			asset_key = _match_key(
				int(asset.class_id),
				q_amount(Decimal(str(asset.cost or 0)), quant),
				q_amount(Decimal(str(asset.vat_amount or 0)), quant),
				int((asset.extra_info or {}).get("product_id") or 0) or None,
			)
			if asset_key == key:
				matched = asset
				break
		if matched is not None:
			unused.remove(matched)
			matched.invoice_item_line_id = int(spec["line"].id)
			matched.acquisition_document_id = int(document.id)
			matched.name = spec["name"]
			matched.location_id = spec["location_id"]
			matched.custodian_person_id = spec["custodian_person_id"]
			ex = dict(matched.extra_info or {})
			ex["source"] = "purchase_invoice"
			ex["product_id"] = spec["product_id"]
			matched.extra_info = ex
			created_or_kept.append(int(matched.id))
			info = spec["info"]
			info[EXTRA_ASSET_ID] = int(matched.id)
			spec["line"].extra_info = info
			flag_modified(spec["line"], "extra_info")
			continue
		cls = _get_class(db, business_id, spec["class_id"])
		life = spec["life"]
		if life is None and cls.default_useful_life_months is not None:
			life = int(cls.default_useful_life_months)
		rate = spec["rate"]
		if rate is None and cls.default_declining_rate is not None:
			rate = Decimal(str(cls.default_declining_rate))
		method = str(cls.default_method or METHOD_STRAIGHT_LINE)
		_validate_method_fields(method=method, depreciable=bool(cls.depreciable), life=life, rate=rate)
		if spec["salvage"] > spec["cost"]:
			raise ApiError("INVALID_SALVAGE", "ارزش اسقاط نمی‌تواند از بها بیشتر باشد.", http_status=400)
		row = FixedAsset(
			business_id=business_id,
			class_id=cls.id,
			code=_next_asset_code(db, business_id, settings, cls),
			name=spec["name"],
			description=(str(spec["line"].description).strip() or None) if spec["line"].description else None,
			status="capitalized",
			acquisition_kind="purchase",
			acquisition_date=acq_date,
			commission_date=acq_date,
			cost=spec["cost"],
			salvage=spec["salvage"],
			vat_amount=spec["vat"],
			accum_depreciation=Decimal("0"),
			opening_accum_depreciation=Decimal("0"),
			method=method,
			useful_life_months=life,
			declining_annual_rate=rate,
			location_id=spec["location_id"],
			custodian_person_id=spec["custodian_person_id"],
			acquisition_document_id=int(document.id),
			invoice_id=int(document.id),
			invoice_item_line_id=int(spec["line"].id),
			created_by_user_id=user_id,
			extra_info={"source": "purchase_invoice", "product_id": spec["product_id"]},
		)
		db.add(row)
		db.flush()
		created_or_kept.append(int(row.id))
		info = spec["info"]
		info[EXTRA_ASSET_ID] = int(row.id)
		spec["line"].extra_info = info
		flag_modified(spec["line"], "extra_info")

	for leftover in unused:
		_delete_reversible_invoice_asset(db, leftover)
	db.flush()
	return created_or_kept


def list_depreciation_runs(
	db: Session,
	business_id: int,
	*,
	limit: int = 50,
	skip: int = 0,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	q = db.query(FixedAssetDepreciationRun).filter(FixedAssetDepreciationRun.business_id == business_id)
	total = q.count()
	rows = (
		q.order_by(FixedAssetDepreciationRun.period_year.desc(), FixedAssetDepreciationRun.period_month.desc())
		.offset(max(0, skip))
		.limit(min(200, max(1, limit)))
		.all()
	)
	return {"total": total, "items": [_run_to_dict(r) for r in rows]}


def get_depreciation_run(db: Session, business_id: int, run_id: int) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = (
		db.query(FixedAssetDepreciationRun)
		.filter(FixedAssetDepreciationRun.id == run_id, FixedAssetDepreciationRun.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("RUN_NOT_FOUND", "اجرای استهلاک یافت نشد.", http_status=404)
	return _run_to_dict(row, include_lines=True)


def create_depreciation_run(
	db: Session,
	business_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	if payload.get("period_start"):
		period_start = month_start(_parse_date(payload.get("period_start"), "period_start"))
		year = period_start.year
		month = period_start.month
	else:
		year = int(payload.get("period_year") or 0)
		month = int(payload.get("period_month") or 0)
		if year < 1900 or year > 2100 or month < 1 or month > 12:
			raise ApiError(
				"INVALID_PERIOD",
				"سال و ماه دوره استهلاک باید میلادی معتبر باشد (یا period_start را بفرستید).",
				http_status=400,
			)
		period_start = date(year, month, 1)
	period_end = month_end(period_start)
	convention = str(payload.get("convention") or settings.accounting_convention or CONVENTION_FROM_READY)
	if convention not in SUPPORTED_CONVENTIONS:
		raise ApiError("INVALID_CONVENTION", "قرارداد استهلاک نامعتبر است.", http_status=400)
	quant = _quant_for_settings(db, settings)

	assets = (
		db.query(FixedAsset)
		.filter(
			FixedAsset.business_id == business_id,
			FixedAsset.status.in_(("capitalized", "idle")),
		)
		.all()
	)
	class_map = {
		c.id: c
		for c in db.query(FixedAssetClass)
		.filter(FixedAssetClass.business_id == business_id)
		.all()
	}
	run = FixedAssetDepreciationRun(
		business_id=business_id,
		period_year=year,
		period_month=month,
		period_start=period_start,
		period_end=period_end,
		status="draft",
		convention=convention,
		total_amount=Decimal("0"),
		created_by_user_id=user_id,
		description=str(payload.get("description") or "").strip() or None,
	)
	db.add(run)
	try:
		db.flush()
	except IntegrityError as exc:
		db.rollback()
		raise ApiError(
			"PERIOD_ALREADY_OPEN",
			"برای این ماه یک اجرای پیش‌نویس یا ثبت‌شده وجود دارد.",
			http_status=409,
		) from exc

	total = Decimal("0")
	for asset in assets:
		cls = class_map.get(asset.class_id)
		if cls is None:
			continue
		try:
			engine_kwargs = dict(
				cost=Decimal(str(asset.cost)),
				salvage=Decimal(str(asset.salvage or 0)),
				useful_life_months=asset.useful_life_months,
				method=asset.method,
				declining_annual_rate=asset.declining_annual_rate,
				commission_date=asset.commission_date,
				convention=convention,
				depreciable=bool(cls.depreciable),
				already_depreciated=Decimal(str(asset.accum_depreciation or 0)),
				period_start=period_start,
				period_end=period_end,
				quant=quant,
				sl_monthly_override=asset.sl_monthly_override,
			)
			amount = compute_period_depreciation(
				DepreciationPeriodInput(
					**engine_kwargs,
					idle_factor=_settings_accounting_idle_factor(
						settings, idle=asset.status == "idle"
					),
				)
			)
			tax_factor = (
				tax_idle_factor(
					asset.idle_from,
					period_end,
					idle_months=_settings_tax_idle_months(settings),
					factor_after=_settings_tax_idle_factor(settings),
				)
				if asset.status == "idle"
				else Decimal("1")
			)
			tax_preview = compute_period_depreciation(
				DepreciationPeriodInput(
					**engine_kwargs,
					idle_factor=tax_factor,
				)
			)
		except DepreciationEngineError as exc:
			raise ApiError("DEPRECIATION_ENGINE_ERROR", str(exc), http_status=400) from exc
		if amount <= 0:
			continue
		if not cls.depreciable:
			continue
		expense_acc = class_expense_account(db, business_id, cls)
		accum_acc = class_accum_account(db, business_id, cls)
		nbv_before = Decimal(str(asset.cost)) - Decimal(str(asset.accum_depreciation or 0))
		nbv_after = nbv_before - amount
		db.add(
			FixedAssetDepreciationRunLine(
				run_id=run.id,
				asset_id=asset.id,
				amount=amount,
				tax_preview_amount=tax_preview,
				book_value_before=nbv_before,
				book_value_after=nbv_after,
				method=asset.method,
				expense_account_id=expense_acc.id,
				accum_account_id=accum_acc.id,
			)
		)
		total += amount
	run.total_amount = total
	db.commit()
	db.refresh(run)
	return _run_to_dict(run, include_lines=True)


def post_depreciation_run(
	db: Session,
	business_id: int,
	run_id: int,
	user_id: int,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	run = (
		db.query(FixedAssetDepreciationRun)
		.filter(FixedAssetDepreciationRun.id == run_id, FixedAssetDepreciationRun.business_id == business_id)
		.first()
	)
	if not run:
		raise ApiError("RUN_NOT_FOUND", "اجرای استهلاک یافت نشد.", http_status=404)
	document = post_depreciation_run_document(
		db,
		business_id=business_id,
		user_id=user_id,
		run=run,
		settings=settings,
	)
	for ln in run.lines or []:
		asset = db.query(FixedAsset).filter(FixedAsset.id == ln.asset_id).first()
		if not asset:
			raise ApiError("ASSET_NOT_FOUND", f"دارایی #{ln.asset_id} یافت نشد.", http_status=404)
		asset.accum_depreciation = Decimal(str(asset.accum_depreciation or 0)) + Decimal(str(ln.amount))
	run.document_id = document.id
	run.status = "posted"
	run.posted_by_user_id = user_id
	run.posted_at = datetime.utcnow()
	db.commit()
	db.refresh(run)
	data = _run_to_dict(run, include_lines=True)
	data["document_code"] = document.code
	return data


def delete_depreciation_run(db: Session, business_id: int, run_id: int) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	run = (
		db.query(FixedAssetDepreciationRun)
		.filter(FixedAssetDepreciationRun.id == run_id, FixedAssetDepreciationRun.business_id == business_id)
		.first()
	)
	if not run:
		raise ApiError("RUN_NOT_FOUND", "اجرای استهلاک یافت نشد.", http_status=404)
	if run.status != "draft" or run.document_id:
		raise ApiError(
			"RUN_NOT_DRAFT",
			"فقط اجرای پیش‌نویس قابل حذف است. سند ثبت‌شده در فاز ۱ برگشت ندارد.",
			http_status=409,
		)
	db.delete(run)
	db.commit()
	return {"deleted": True, "id": run_id}


def _get_live_asset(db: Session, business_id: int, asset_id: int) -> FixedAsset:
	row = (
		db.query(FixedAsset)
		.filter(FixedAsset.id == asset_id, FixedAsset.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("ASSET_NOT_FOUND", "دارایی یافت نشد.", http_status=404)
	return row


def _assert_capitalized_or_idle(row: FixedAsset) -> None:
	if row.status not in ("capitalized", "idle"):
		raise ApiError(
			"ASSET_NOT_CAPITALIZED",
			"این عملیات فقط برای دارایی سرمایه‌شده یا راکد مجاز است.",
			http_status=409,
		)


def _assert_no_draft_run(db: Session, business_id: int) -> None:
	open_draft = (
		db.query(FixedAssetDepreciationRun.id)
		.filter(
			FixedAssetDepreciationRun.business_id == business_id,
			FixedAssetDepreciationRun.status == "draft",
		)
		.first()
	)
	if open_draft:
		raise ApiError(
			"DRAFT_RUN_OPEN",
			"پیش‌نویس استهلاک باز است؛ ابتدا آن را حذف یا ثبت کنید.",
			http_status=409,
		)


def _last_posted_period_end(db: Session, business_id: int, asset_id: int) -> Optional[date]:
	row = (
		db.query(FixedAssetDepreciationRun.period_end)
		.join(
			FixedAssetDepreciationRunLine,
			FixedAssetDepreciationRunLine.run_id == FixedAssetDepreciationRun.id,
		)
		.filter(
			FixedAssetDepreciationRun.business_id == business_id,
			FixedAssetDepreciationRun.status == "posted",
			FixedAssetDepreciationRunLine.asset_id == asset_id,
		)
		.order_by(FixedAssetDepreciationRun.period_end.desc())
		.first()
	)
	return row[0] if row else None


def _catch_up_depreciation(
	db: Session,
	*,
	asset: FixedAsset,
	cls: FixedAssetClass,
	settings: FixedAssetSettings,
	through: date,
	quant: Decimal,
) -> Decimal:
	if not cls.depreciable:
		return Decimal("0")
	last_end = _last_posted_period_end(db, asset.business_id, asset.id)
	if last_end is not None and last_end > through:
		raise ApiError(
			"DISPOSAL_BEFORE_DEPRECIATION",
			"تاریخ خروج قبل از آخرین استهلاک ثبت‌شده است.",
			http_status=400,
		)
	convention = str(settings.accounting_convention or CONVENTION_FROM_READY)
	start = depreciation_start_date(asset.commission_date, convention)
	period_start = (last_end + timedelta(days=1)) if last_end is not None else start
	if period_start > through:
		return Decimal("0")
	try:
		return compute_period_depreciation(
			DepreciationPeriodInput(
				cost=Decimal(str(asset.cost)),
				salvage=Decimal(str(asset.salvage or 0)),
				useful_life_months=asset.useful_life_months,
				method=asset.method,
				declining_annual_rate=asset.declining_annual_rate,
				commission_date=asset.commission_date,
				convention=convention,
				depreciable=True,
				already_depreciated=Decimal(str(asset.accum_depreciation or 0)),
				period_start=period_start,
				period_end=through,
				quant=quant,
				idle_factor=_settings_accounting_idle_factor(
					settings, idle=asset.status == "idle"
				),
				sl_monthly_override=asset.sl_monthly_override,
			)
		)
	except DepreciationEngineError as exc:
		raise ApiError("DEPRECIATION_ENGINE_ERROR", str(exc), http_status=400) from exc


def set_asset_idle(
	db: Session,
	business_id: int,
	asset_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,  # noqa: ARG001
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = _get_live_asset(db, business_id, asset_id)
	_assert_capitalized_or_idle(row)
	idle_from = _parse_date(payload.get("idle_from") or date.today(), "idle_from")
	if idle_from < row.commission_date:
		raise ApiError("INVALID_IDLE_FROM", "شروع رکود نمی‌تواند قبل از بهره‌برداری باشد.", http_status=400)
	row.status = "idle"
	row.idle_from = idle_from
	db.commit()
	db.refresh(row)
	cls = db.query(FixedAssetClass).filter(FixedAssetClass.id == row.class_id).first()
	return _asset_to_dict(row, cls)


def resume_asset(
	db: Session,
	business_id: int,
	asset_id: int,
	user_id: Optional[int] = None,  # noqa: ARG001
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = _get_live_asset(db, business_id, asset_id)
	_assert_capitalized_or_idle(row)
	row.status = "capitalized"
	row.idle_from = None
	db.commit()
	db.refresh(row)
	cls = db.query(FixedAssetClass).filter(FixedAssetClass.id == row.class_id).first()
	return _asset_to_dict(row, cls)


def dispose_asset(
	db: Session,
	business_id: int,
	asset_id: int,
	payload: Dict[str, Any],
	user_id: int,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	_assert_no_draft_run(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	row = _get_live_asset(db, business_id, asset_id)
	_assert_capitalized_or_idle(row)
	cls = _get_class(db, business_id, row.class_id)
	kind = str(payload.get("kind") or KIND_SALE).strip()
	if kind not in SUPPORTED_DISPOSAL_KINDS:
		raise ApiError("INVALID_DISPOSAL_KIND", "نوع خروج باید sale یا scrap باشد.", http_status=400)
	disposal_date = _parse_date(payload.get("disposal_date") or date.today(), "disposal_date")
	if disposal_date < row.acquisition_date:
		raise ApiError("INVALID_DISPOSAL_DATE", "تاریخ خروج نمی‌تواند قبل از تحصیل باشد.", http_status=400)
	quant = _quant_for_settings(db, settings)
	proceeds = q_amount(_decimal(payload.get("proceeds")), quant)
	vat_output = q_amount(_decimal(payload.get("vat_output") or payload.get("vat_amount")), quant)
	if kind == KIND_SCRAP or (proceeds + vat_output == 0):
		counterparty = {
			"type": "none",
			"account": class_cost_account(db, business_id, cls),
		}
	else:
		counterparty = resolve_counterparty(db, business_id, settings, payload)

	catch_up = _catch_up_depreciation(
		db, asset=row, cls=cls, settings=settings, through=disposal_date, quant=quant
	)
	document = post_disposal_document(
		db,
		business_id=business_id,
		user_id=user_id,
		asset=row,
		cls=cls,
		settings=settings,
		counterparty=counterparty,
		kind=kind,
		proceeds=proceeds,
		vat_output=vat_output,
		catch_up_amount=catch_up,
		quant=quant,
		document_date=disposal_date,
	)
	row.accum_depreciation = Decimal(str(row.accum_depreciation or 0)) + catch_up
	row.status = "disposed"
	row.disposed_at = disposal_date
	row.disposal_kind = kind
	row.disposal_proceeds = proceeds
	row.disposal_document_id = document.id
	row.idle_from = None
	db.commit()
	db.refresh(row)
	data = _asset_to_dict(row, cls)
	data["disposal_document_code"] = document.code
	data["catch_up_amount"] = str(catch_up)
	return data


def post_subsequent_expenditure(
	db: Session,
	business_id: int,
	asset_id: int,
	payload: Dict[str, Any],
	user_id: int,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	_assert_no_draft_run(db, business_id)
	settings = _get_or_create_settings(db, business_id)
	row = _get_live_asset(db, business_id, asset_id)
	_assert_capitalized_or_idle(row)
	cls = _get_class(db, business_id, row.class_id)
	kind = str(payload.get("kind") or EXP_ROUTINE).strip()
	if kind not in SUPPORTED_EXPENDITURE_KINDS:
		raise ApiError("INVALID_EXPENDITURE_KIND", "نوع مخارج باید routine یا major باشد.", http_status=400)
	exp_date = _parse_date(payload.get("expenditure_date") or date.today(), "expenditure_date")
	if exp_date < row.acquisition_date:
		raise ApiError("INVALID_DATE", "تاریخ مخارج نمی‌تواند قبل از تحصیل باشد.", http_status=400)
	quant = _quant_for_settings(db, settings)
	amount = q_amount(_decimal(payload.get("amount")), quant)
	vat = q_amount(_decimal(payload.get("vat_amount")), quant)
	counterparty = resolve_counterparty(db, business_id, settings, payload)
	note = str(payload.get("description") or "").strip() or None
	document = post_subsequent_expenditure_document(
		db,
		business_id=business_id,
		user_id=user_id,
		asset=row,
		cls=cls,
		settings=settings,
		counterparty=counterparty,
		kind=kind,
		amount=amount,
		vat=vat,
		quant=quant,
		document_date=exp_date,
		description=note,
	)
	if kind == EXP_MAJOR:
		row.cost = q_amount(Decimal(str(row.cost)) + amount, quant)
		if cls.depreciable and row.method == METHOD_STRAIGHT_LINE:
			life_raw = payload.get("remaining_useful_life_months")
			if life_raw in (None, ""):
				raise ApiError(
					"REMAINING_LIFE_REQUIRED",
					"پس از تعمیر اساسی خط مستقیم، عمر باقیمانده به ماه الزامی است تا ماهانه از تاریخ مؤثر محاسبه شود.",
					http_status=400,
				)
			remaining_months = int(life_raw)
			try:
				override = prospective_straight_line_monthly(
					cost=Decimal(str(row.cost)),
					salvage=Decimal(str(row.salvage or 0)),
					already=Decimal(str(row.accum_depreciation or 0)),
					remaining_months=remaining_months,
				)
			except DepreciationEngineError as exc:
				raise ApiError("DEPRECIATION_ENGINE_ERROR", str(exc), http_status=400) from exc
			row.sl_monthly_override = override
			row.useful_life_months = remaining_months
			row.estimate_effective_date = exp_date
	db.add(
		FixedAssetSubsequentExpenditure(
			business_id=business_id,
			asset_id=row.id,
			kind=kind,
			amount=amount,
			vat_amount=vat,
			expenditure_date=exp_date,
			document_id=document.id,
			description=note,
			created_by_user_id=user_id,
		)
	)
	db.commit()
	db.refresh(row)
	data = _asset_to_dict(row, cls)
	data["subsequent_document_code"] = document.code
	return data


def change_asset_estimate(
	db: Session,
	business_id: int,
	asset_id: int,
	payload: Dict[str, Any],
	user_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	_assert_no_draft_run(db, business_id)
	row = _get_live_asset(db, business_id, asset_id)
	_assert_capitalized_or_idle(row)
	cls = _get_class(db, business_id, row.class_id)
	if not cls.depreciable:
		raise ApiError("CLASS_NOT_DEPRECIABLE", "تغییر برآورد برای طبقه غیراستهلاک‌پذیر معنی ندارد.", http_status=400)
	effective = _parse_date(payload.get("effective_date") or date.today(), "effective_date")
	if effective < row.commission_date:
		raise ApiError("INVALID_DATE", "تاریخ مؤثر نمی‌تواند قبل از بهره‌برداری باشد.", http_status=400)
	new_method = str(payload.get("method") or row.method).strip()
	new_salvage = Decimal(str(row.salvage or 0))
	if "salvage" in payload and payload["salvage"] not in (None, ""):
		settings = _get_or_create_settings(db, business_id)
		quant = _quant_for_settings(db, settings)
		new_salvage = q_amount(_decimal(payload["salvage"]), quant)
		if new_salvage > Decimal(str(row.cost)):
			raise ApiError("INVALID_SALVAGE", "ارزش اسقاط نمی‌تواند از بها بیشتر باشد.", http_status=400)
	life_raw = payload.get("remaining_useful_life_months")
	rate_raw = payload.get("declining_annual_rate")
	new_life = int(life_raw) if life_raw not in (None, "") else None
	if rate_raw not in (None, ""):
		new_rate = _decimal(rate_raw)
	elif row.declining_annual_rate is not None:
		new_rate = Decimal(str(row.declining_annual_rate))
	else:
		new_rate = None
	_validate_method_fields(
		method=new_method,
		depreciable=True,
		life=new_life if new_method == METHOD_STRAIGHT_LINE else row.useful_life_months,
		rate=new_rate if new_method == METHOD_DECLINING else None,
	)
	already = Decimal(str(row.accum_depreciation or 0))
	remaining = remaining_depreciable(Decimal(str(row.cost)), new_salvage, already)
	old_method = row.method
	old_life = row.useful_life_months
	old_rate = row.declining_annual_rate
	old_salvage = Decimal(str(row.salvage or 0))
	override = None
	if new_method == METHOD_STRAIGHT_LINE:
		if new_life is None or new_life < 1:
			raise ApiError(
				"REMAINING_LIFE_REQUIRED",
				"برای تغییر برآورد خط مستقیم، عمر باقیمانده به ماه از تاریخ مؤثر الزامی است.",
				http_status=400,
			)
		try:
			override = prospective_straight_line_monthly(
				cost=Decimal(str(row.cost)),
				salvage=new_salvage,
				already=already,
				remaining_months=new_life,
			)
		except DepreciationEngineError as exc:
			raise ApiError("DEPRECIATION_ENGINE_ERROR", str(exc), http_status=400) from exc
		row.sl_monthly_override = override
		row.useful_life_months = new_life
		row.declining_annual_rate = None
	else:
		row.sl_monthly_override = None
		row.declining_annual_rate = new_rate
	row.method = new_method
	row.salvage = new_salvage
	row.estimate_effective_date = effective
	db.add(
		FixedAssetEstimateChange(
			business_id=business_id,
			asset_id=row.id,
			effective_date=effective,
			old_method=old_method,
			new_method=new_method,
			old_useful_life_months=old_life,
			remaining_useful_life_months=new_life,
			old_declining_rate=old_rate,
			new_declining_rate=new_rate,
			old_salvage=old_salvage,
			new_salvage=new_salvage,
			sl_monthly_override=override,
			remaining_depreciable=remaining,
			created_by_user_id=user_id,
		)
	)
	db.commit()
	db.refresh(row)
	return _asset_to_dict(row, cls)


def get_dashboard(db: Session, business_id: int) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	_get_or_create_settings(db, business_id)
	db.commit()
	counts = dict(
		db.query(FixedAsset.status, func.count(FixedAsset.id))
		.filter(FixedAsset.business_id == business_id)
		.group_by(FixedAsset.status)
		.all()
	)
	cost_total = (
		db.query(func.coalesce(func.sum(FixedAsset.cost), 0))
		.filter(FixedAsset.business_id == business_id, FixedAsset.status.in_(("capitalized", "idle")))
		.scalar()
	)
	accum_total = (
		db.query(func.coalesce(func.sum(FixedAsset.accum_depreciation), 0))
		.filter(FixedAsset.business_id == business_id, FixedAsset.status.in_(("capitalized", "idle")))
		.scalar()
	)
	return {
		"counts": {
			"draft": int(counts.get("draft") or 0),
			"capitalized": int(counts.get("capitalized") or 0),
			"idle": int(counts.get("idle") or 0),
			"disposed": int(counts.get("disposed") or 0),
		},
		"cost_total": str(cost_total or 0),
		"accum_total": str(accum_total or 0),
		"net_book_value": str(Decimal(str(cost_total or 0)) - Decimal(str(accum_total or 0))),
	}
