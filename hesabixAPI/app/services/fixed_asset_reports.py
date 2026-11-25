"""گزارش‌های افزونه اموال: دفتر، گردش طبقات، استهلاک، تحصیل، خروج، راکد، استقرار، مخارج."""
from __future__ import annotations

from collections import defaultdict
from datetime import date, datetime
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import func
from sqlalchemy.orm import Session

from adapters.db.models.fixed_asset import (
	FixedAsset,
	FixedAssetClass,
	FixedAssetDepreciationRun,
	FixedAssetDepreciationRunLine,
	FixedAssetLocation,
	FixedAssetSettings,
	FixedAssetSubsequentExpenditure,
)
from adapters.db.models.person import Person
from app.core.fixed_assets_plugin_dependency import check_fixed_assets_plugin_active
from app.core.responses import ApiError
from app.services.fixed_asset_depreciation_engine import tax_idle_factor
from app.services.fixed_asset_service import (
	_settings_tax_idle_factor,
	_settings_tax_idle_months,
)

Q2 = Decimal("0.01")
_MAX_ROWS = 2000
REPORT_KINDS = frozenset(
	{
		"register",
		"class_summary",
		"depreciation",
		"acquisitions",
		"disposals",
		"idle",
		"locations",
		"expenditures",
	}
)
_LIVE = ("capitalized", "idle")


def _ensure_plugin(db: Session, business_id: int) -> None:
	if not check_fixed_assets_plugin_active(db, business_id):
		raise ApiError(
			"FIXED_ASSETS_PLUGIN_NOT_ACTIVE",
			"افزونه کنترل اموال و دارایی ثابت برای این کسب‌وکار فعال نیست.",
			http_status=403,
			details={"plugin_code": "fixed_assets"},
		)


def _money(value: Any) -> str:
	return str(Decimal(str(value or 0)).quantize(Q2, rounding=ROUND_HALF_UP))


def _d(value: Any) -> Decimal:
	return Decimal(str(value or 0)).quantize(Q2, rounding=ROUND_HALF_UP)


def _iso(value: Optional[date]) -> Optional[str]:
	return value.isoformat() if value else None


def _optional_date(value: Any, field: str) -> Optional[date]:
	if value in (None, ""):
		return None
	if isinstance(value, datetime):
		return value.date()
	if isinstance(value, date):
		return value
	try:
		return date.fromisoformat(str(value).strip().split("T")[0])
	except ValueError as exc:
		raise ApiError("INVALID_DATE", f"تاریخ {field} نامعتبر است.", http_status=400) from exc


def _period(from_date: Optional[date], to_date: Optional[date]) -> Tuple[date, date]:
	start = from_date or date(date.today().year, 1, 1)
	end = to_date or date.today()
	if end < start:
		raise ApiError("INVALID_DATE_RANGE", "تاریخ پایان نمی‌تواند قبل از تاریخ شروع باشد.", http_status=400)
	return start, end


def class_rollforward_amounts(
	*,
	closing_cost: Decimal,
	closing_accum: Decimal,
	additions: Decimal,
	major_repairs: Decimal,
	depreciation: Decimal,
	disposals_cost: Decimal,
	disposals_accum: Decimal,
) -> Dict[str, Decimal]:
	"""گردش طبقه از ماندهٔ جاری و رویدادهای دوره. هویت: ابتدا + تحصیل + تعمیر − NBV خروج − استهلاک = انتها."""
	opening_cost = closing_cost - additions - major_repairs + disposals_cost
	opening_accum = closing_accum - depreciation + disposals_accum
	return {
		"opening_cost": opening_cost,
		"opening_accum": opening_accum,
		"opening_nbv": opening_cost - opening_accum,
		"additions": additions,
		"major_repairs": major_repairs,
		"depreciation": depreciation,
		"disposals_cost": disposals_cost,
		"disposals_accum": disposals_accum,
		"disposals_nbv": disposals_cost - disposals_accum,
		"closing_cost": closing_cost,
		"closing_accum": closing_accum,
		"closing_nbv": closing_cost - closing_accum,
	}


def get_fixed_asset_report(
	db: Session,
	business_id: int,
	kind: str,
	*,
	from_date: Optional[str] = None,
	to_date: Optional[str] = None,
	class_id: Optional[int] = None,
	status: Optional[str] = None,
	location_id: Optional[int] = None,
	limit: int = 500,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	report = str(kind or "").strip()
	if report not in REPORT_KINDS:
		raise ApiError("INVALID_REPORT", "نوع گزارش اموال نامعتبر است.", http_status=400)
	start = _optional_date(from_date, "from_date")
	end = _optional_date(to_date, "to_date")
	cid = int(class_id) if class_id else None
	lid = int(location_id) if location_id else None
	row_limit = min(_MAX_ROWS, max(1, int(limit or 500)))
	settings = db.query(FixedAssetSettings).filter(FixedAssetSettings.business_id == business_id).first()
	if report == "register":
		return _register(db, business_id, class_id=cid, status=status, location_id=lid, limit=row_limit)
	if report == "class_summary":
		period = _period(start, end)
		return _class_summary(db, business_id, period[0], period[1], class_id=cid)
	if report == "depreciation":
		period = _period(start, end)
		return _depreciation(db, business_id, period[0], period[1], class_id=cid, limit=row_limit)
	if report == "acquisitions":
		period = _period(start, end)
		return _acquisitions(db, business_id, period[0], period[1], class_id=cid, limit=row_limit)
	if report == "disposals":
		period = _period(start, end)
		return _disposals(db, business_id, period[0], period[1], class_id=cid, limit=row_limit)
	if report == "idle":
		return _idle(db, business_id, settings, class_id=cid, limit=row_limit)
	if report == "locations":
		return _locations(db, business_id, class_id=cid, location_id=lid, limit=row_limit)
	period = _period(start, end)
	return _expenditures(db, business_id, period[0], period[1], class_id=cid, limit=row_limit)


def _base_assets(db: Session, business_id: int, *, class_id: Optional[int] = None, location_id: Optional[int] = None):
	q = db.query(FixedAsset).filter(FixedAsset.business_id == business_id)
	if class_id:
		q = q.filter(FixedAsset.class_id == class_id)
	if location_id:
		q = q.filter(FixedAsset.location_id == location_id)
	return q


def _class_map(db: Session, business_id: int) -> Dict[int, FixedAssetClass]:
	return {c.id: c for c in db.query(FixedAssetClass).filter(FixedAssetClass.business_id == business_id).all()}


def _location_map(db: Session, ids: set[int]) -> Dict[int, FixedAssetLocation]:
	if not ids:
		return {}
	return {r.id: r for r in db.query(FixedAssetLocation).filter(FixedAssetLocation.id.in_(ids)).all()}


def _person_map(db: Session, ids: set[int]) -> Dict[int, Person]:
	if not ids:
		return {}
	return {r.id: r for r in db.query(Person).filter(Person.id.in_(ids)).all()}


def _totals(items: List[Dict[str, Any]], keys: Tuple[str, ...]) -> Dict[str, str]:
	acc: Dict[str, Decimal] = {k: Decimal("0.00") for k in keys}
	for row in items:
		for k in keys:
			acc[k] += _d(row.get(k))
	return {k: _money(v) for k, v in acc.items()}


def _register(
	db: Session,
	business_id: int,
	*,
	class_id: Optional[int],
	status: Optional[str],
	location_id: Optional[int],
	limit: int,
) -> Dict[str, Any]:
	q = _base_assets(db, business_id, class_id=class_id, location_id=location_id)
	if status:
		q = q.filter(FixedAsset.status == status)
	rows = q.order_by(FixedAsset.code.asc()).limit(limit).all()
	classes = _class_map(db, business_id)
	locations = _location_map(db, {r.location_id for r in rows if r.location_id})
	persons = _person_map(db, {r.custodian_person_id for r in rows if r.custodian_person_id})
	items = []
	for row in rows:
		cost = _d(row.cost)
		accum = _d(row.accum_depreciation)
		cls = classes.get(row.class_id)
		loc = locations.get(row.location_id) if row.location_id else None
		person = persons.get(row.custodian_person_id) if row.custodian_person_id else None
		items.append(
			{
				"id": row.id,
				"code": row.code,
				"name": row.name,
				"serial_number": row.serial_number,
				"status": row.status,
				"class_id": row.class_id,
				"class_name": cls.name if cls else None,
				"class_code": cls.code if cls else None,
				"location_name": loc.name if loc else None,
				"custodian_name": person.alias_name if person else None,
				"acquisition_kind": row.acquisition_kind,
				"acquisition_date": _iso(row.acquisition_date),
				"commission_date": _iso(row.commission_date),
				"method": row.method,
				"useful_life_months": row.useful_life_months,
				"cost": _money(cost),
				"salvage": _money(row.salvage),
				"accum_depreciation": _money(accum),
				"net_book_value": _money(cost - accum),
				"invoice_id": row.invoice_id,
			}
		)
	return {
		"kind": "register",
		"items": items,
		"totals": _totals(items, ("cost", "salvage", "accum_depreciation", "net_book_value")),
	}


def _class_summary(
	db: Session,
	business_id: int,
	start: date,
	end: date,
	*,
	class_id: Optional[int],
) -> Dict[str, Any]:
	assets = _base_assets(db, business_id, class_id=class_id).filter(FixedAsset.status != "draft").all()
	classes = _class_map(db, business_id)
	live_cost: Dict[int, Decimal] = defaultdict(lambda: Decimal("0.00"))
	live_accum: Dict[int, Decimal] = defaultdict(lambda: Decimal("0.00"))
	live_count: Dict[int, int] = defaultdict(int)
	idle_count: Dict[int, int] = defaultdict(int)
	additions: Dict[int, Decimal] = defaultdict(lambda: Decimal("0.00"))
	disposals_cost: Dict[int, Decimal] = defaultdict(lambda: Decimal("0.00"))
	disposals_accum: Dict[int, Decimal] = defaultdict(lambda: Decimal("0.00"))
	disposals_proceeds: Dict[int, Decimal] = defaultdict(lambda: Decimal("0.00"))
	for row in assets:
		cid = row.class_id
		if row.status in _LIVE:
			live_cost[cid] += _d(row.cost)
			live_accum[cid] += _d(row.accum_depreciation)
			live_count[cid] += 1
			if row.status == "idle":
				idle_count[cid] += 1
		if start <= row.acquisition_date <= end:
			additions[cid] += _d(row.cost)
		if row.status == "disposed" and row.disposed_at and start <= row.disposed_at <= end:
			disposals_cost[cid] += _d(row.cost)
			disposals_accum[cid] += _d(row.accum_depreciation)
			disposals_proceeds[cid] += _d(row.disposal_proceeds)

	major: Dict[int, Decimal] = defaultdict(lambda: Decimal("0.00"))
	exp_rows = (
		db.query(FixedAssetSubsequentExpenditure, FixedAsset.class_id)
		.join(FixedAsset, FixedAsset.id == FixedAssetSubsequentExpenditure.asset_id)
		.filter(
			FixedAssetSubsequentExpenditure.business_id == business_id,
			FixedAssetSubsequentExpenditure.kind == "major",
			FixedAssetSubsequentExpenditure.expenditure_date >= start,
			FixedAssetSubsequentExpenditure.expenditure_date <= end,
		)
	)
	if class_id:
		exp_rows = exp_rows.filter(FixedAsset.class_id == class_id)
	for exp, cid in exp_rows.all():
		major[int(cid)] += _d(exp.amount)

	dep: Dict[int, Decimal] = defaultdict(lambda: Decimal("0.00"))
	dep_rows = (
		db.query(FixedAsset.class_id, func.coalesce(func.sum(FixedAssetDepreciationRunLine.amount), 0))
		.join(FixedAssetDepreciationRunLine, FixedAssetDepreciationRunLine.asset_id == FixedAsset.id)
		.join(FixedAssetDepreciationRun, FixedAssetDepreciationRun.id == FixedAssetDepreciationRunLine.run_id)
		.filter(
			FixedAsset.business_id == business_id,
			FixedAssetDepreciationRun.status == "posted",
			FixedAssetDepreciationRun.period_end >= start,
			FixedAssetDepreciationRun.period_end <= end,
		)
	)
	if class_id:
		dep_rows = dep_rows.filter(FixedAsset.class_id == class_id)
	for cid, amount in dep_rows.group_by(FixedAsset.class_id).all():
		dep[int(cid)] += _d(amount)

	class_ids = sorted(set(classes) | set(live_cost) | set(additions) | set(disposals_cost) | set(major) | set(dep))
	if class_id:
		class_ids = [class_id]
	items = []
	for cid in class_ids:
		cls = classes.get(cid)
		if cls is None:
			continue
		rf = class_rollforward_amounts(
			closing_cost=live_cost[cid],
			closing_accum=live_accum[cid],
			additions=additions[cid],
			major_repairs=major[cid],
			depreciation=dep[cid],
			disposals_cost=disposals_cost[cid],
			disposals_accum=disposals_accum[cid],
		)
		items.append(
			{
				"class_id": cid,
				"class_code": cls.code,
				"class_name": cls.name,
				"depreciable": cls.depreciable,
				"live_count": live_count[cid],
				"idle_count": idle_count[cid],
				"proceeds": _money(disposals_proceeds[cid]),
				**{k: _money(v) for k, v in rf.items()},
			}
		)
	money_keys = (
		"opening_cost",
		"opening_accum",
		"opening_nbv",
		"additions",
		"major_repairs",
		"depreciation",
		"disposals_cost",
		"disposals_nbv",
		"closing_cost",
		"closing_accum",
		"closing_nbv",
		"proceeds",
	)
	return {
		"kind": "class_summary",
		"from_date": _iso(start),
		"to_date": _iso(end),
		"items": items,
		"totals": _totals(items, money_keys),
	}


def _depreciation(
	db: Session,
	business_id: int,
	start: date,
	end: date,
	*,
	class_id: Optional[int],
	limit: int,
) -> Dict[str, Any]:
	q = (
		db.query(FixedAssetDepreciationRunLine, FixedAssetDepreciationRun, FixedAsset, FixedAssetClass)
		.join(FixedAssetDepreciationRun, FixedAssetDepreciationRun.id == FixedAssetDepreciationRunLine.run_id)
		.join(FixedAsset, FixedAsset.id == FixedAssetDepreciationRunLine.asset_id)
		.join(FixedAssetClass, FixedAssetClass.id == FixedAsset.class_id)
		.filter(
			FixedAsset.business_id == business_id,
			FixedAssetDepreciationRun.status == "posted",
			FixedAssetDepreciationRun.period_end >= start,
			FixedAssetDepreciationRun.period_end <= end,
		)
	)
	if class_id:
		q = q.filter(FixedAsset.class_id == class_id)
	rows = q.order_by(FixedAssetDepreciationRun.period_end.asc(), FixedAsset.code.asc()).limit(limit).all()
	items = []
	for line, run, asset, cls in rows:
		items.append(
			{
				"run_id": run.id,
				"period_year": run.period_year,
				"period_month": run.period_month,
				"period_end": _iso(run.period_end),
				"asset_id": asset.id,
				"code": asset.code,
				"name": asset.name,
				"class_name": cls.name,
				"method": line.method,
				"amount": _money(line.amount),
				"tax_preview_amount": _money(line.tax_preview_amount),
				"book_value_before": _money(line.book_value_before),
				"book_value_after": _money(line.book_value_after),
			}
		)
	return {
		"kind": "depreciation",
		"from_date": _iso(start),
		"to_date": _iso(end),
		"items": items,
		"totals": _totals(items, ("amount", "tax_preview_amount")),
	}


def _acquisitions(
	db: Session,
	business_id: int,
	start: date,
	end: date,
	*,
	class_id: Optional[int],
	limit: int,
) -> Dict[str, Any]:
	q = _base_assets(db, business_id, class_id=class_id).filter(
		FixedAsset.acquisition_date >= start,
		FixedAsset.acquisition_date <= end,
		FixedAsset.status != "draft",
	)
	rows = q.order_by(FixedAsset.acquisition_date.asc(), FixedAsset.code.asc()).limit(limit).all()
	classes = _class_map(db, business_id)
	items = []
	for row in rows:
		cls = classes.get(row.class_id)
		items.append(
			{
				"id": row.id,
				"code": row.code,
				"name": row.name,
				"class_name": cls.name if cls else None,
				"status": row.status,
				"acquisition_kind": row.acquisition_kind,
				"acquisition_date": _iso(row.acquisition_date),
				"commission_date": _iso(row.commission_date),
				"cost": _money(row.cost),
				"vat_amount": _money(row.vat_amount),
				"invoice_id": row.invoice_id,
			}
		)
	return {
		"kind": "acquisitions",
		"from_date": _iso(start),
		"to_date": _iso(end),
		"items": items,
		"totals": _totals(items, ("cost", "vat_amount")),
	}


def _disposals(
	db: Session,
	business_id: int,
	start: date,
	end: date,
	*,
	class_id: Optional[int],
	limit: int,
) -> Dict[str, Any]:
	q = _base_assets(db, business_id, class_id=class_id).filter(
		FixedAsset.status == "disposed",
		FixedAsset.disposed_at.isnot(None),
		FixedAsset.disposed_at >= start,
		FixedAsset.disposed_at <= end,
	)
	rows = q.order_by(FixedAsset.disposed_at.asc(), FixedAsset.code.asc()).limit(limit).all()
	classes = _class_map(db, business_id)
	items = []
	for row in rows:
		cost = _d(row.cost)
		accum = _d(row.accum_depreciation)
		nbv = cost - accum
		proceeds = _d(row.disposal_proceeds)
		cls = classes.get(row.class_id)
		items.append(
			{
				"id": row.id,
				"code": row.code,
				"name": row.name,
				"class_name": cls.name if cls else None,
				"disposal_kind": row.disposal_kind,
				"disposal_date": _iso(row.disposed_at),
				"cost": _money(cost),
				"accum_depreciation": _money(accum),
				"net_book_value": _money(nbv),
				"proceeds": _money(proceeds),
				"gain_loss": _money(proceeds - nbv),
			}
		)
	return {
		"kind": "disposals",
		"from_date": _iso(start),
		"to_date": _iso(end),
		"items": items,
		"totals": _totals(items, ("cost", "accum_depreciation", "net_book_value", "proceeds", "gain_loss")),
	}


def _idle(
	db: Session,
	business_id: int,
	settings: Optional[FixedAssetSettings],
	*,
	class_id: Optional[int],
	limit: int,
) -> Dict[str, Any]:
	q = _base_assets(db, business_id, class_id=class_id).filter(FixedAsset.status == "idle")
	rows = q.order_by(FixedAsset.idle_from.asc(), FixedAsset.code.asc()).limit(limit).all()
	classes = _class_map(db, business_id)
	today = date.today()
	items = []
	for row in rows:
		cost = _d(row.cost)
		accum = _d(row.accum_depreciation)
		cls = classes.get(row.class_id)
		factor = tax_idle_factor(
			row.idle_from,
			today,
			idle_months=_settings_tax_idle_months(settings),
			factor_after=_settings_tax_idle_factor(settings),
		)
		items.append(
			{
				"id": row.id,
				"code": row.code,
				"name": row.name,
				"class_name": cls.name if cls else None,
				"idle_from": _iso(row.idle_from),
				"cost": _money(cost),
				"accum_depreciation": _money(accum),
				"net_book_value": _money(cost - accum),
				"tax_idle_factor": str(factor),
			}
		)
	return {
		"kind": "idle",
		"items": items,
		"totals": _totals(items, ("cost", "accum_depreciation", "net_book_value")),
	}


def _locations(
	db: Session,
	business_id: int,
	*,
	class_id: Optional[int],
	location_id: Optional[int],
	limit: int,
) -> Dict[str, Any]:
	q = _base_assets(db, business_id, class_id=class_id, location_id=location_id).filter(
		FixedAsset.status.in_(_LIVE)
	)
	rows = q.order_by(FixedAsset.code.asc()).limit(limit).all()
	classes = _class_map(db, business_id)
	locations = _location_map(db, {r.location_id for r in rows if r.location_id})
	persons = _person_map(db, {r.custodian_person_id for r in rows if r.custodian_person_id})
	items = []
	for row in rows:
		cost = _d(row.cost)
		accum = _d(row.accum_depreciation)
		cls = classes.get(row.class_id)
		loc = locations.get(row.location_id) if row.location_id else None
		person = persons.get(row.custodian_person_id) if row.custodian_person_id else None
		items.append(
			{
				"id": row.id,
				"code": row.code,
				"name": row.name,
				"serial_number": row.serial_number,
				"status": row.status,
				"class_name": cls.name if cls else None,
				"location_name": loc.name if loc else None,
				"custodian_name": person.alias_name if person else None,
				"cost": _money(cost),
				"net_book_value": _money(cost - accum),
			}
		)
	return {
		"kind": "locations",
		"items": items,
		"totals": _totals(items, ("cost", "net_book_value")),
	}


def _expenditures(
	db: Session,
	business_id: int,
	start: date,
	end: date,
	*,
	class_id: Optional[int],
	limit: int,
) -> Dict[str, Any]:
	q = (
		db.query(FixedAssetSubsequentExpenditure, FixedAsset, FixedAssetClass)
		.join(FixedAsset, FixedAsset.id == FixedAssetSubsequentExpenditure.asset_id)
		.join(FixedAssetClass, FixedAssetClass.id == FixedAsset.class_id)
		.filter(
			FixedAssetSubsequentExpenditure.business_id == business_id,
			FixedAssetSubsequentExpenditure.expenditure_date >= start,
			FixedAssetSubsequentExpenditure.expenditure_date <= end,
		)
	)
	if class_id:
		q = q.filter(FixedAsset.class_id == class_id)
	rows = q.order_by(FixedAssetSubsequentExpenditure.expenditure_date.asc()).limit(limit).all()
	items = []
	for exp, asset, cls in rows:
		items.append(
			{
				"id": exp.id,
				"asset_id": asset.id,
				"code": asset.code,
				"name": asset.name,
				"class_name": cls.name,
				"kind": exp.kind,
				"expenditure_date": _iso(exp.expenditure_date),
				"amount": _money(exp.amount),
				"vat_amount": _money(exp.vat_amount),
				"description": exp.description,
				"document_id": exp.document_id,
			}
		)
	return {
		"kind": "expenditures",
		"from_date": _iso(start),
		"to_date": _iso(end),
		"items": items,
		"totals": _totals(items, ("amount", "vat_amount")),
	}
