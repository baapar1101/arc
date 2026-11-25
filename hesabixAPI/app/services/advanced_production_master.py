"""مراکز، خط، دستگاه، شیفت، توقف، خروجی خط و کنترل کیفیت."""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from adapters.db.models.advanced_production import (
	AdvancedProductionDowntime,
	AdvancedProductionInspection,
	AdvancedProductionLabor,
	AdvancedProductionLine,
	AdvancedProductionLineReturn,
	AdvancedProductionMaintenance,
	AdvancedProductionMachine,
	AdvancedProductionOrderHold,
	AdvancedProductionOrderLine,
	AdvancedProductionRework,
	AdvancedProductionWipCount,
	AdvancedProductionOutputLog,
	AdvancedProductionScrapEvent,
	AdvancedProductionScrapReason,
	AdvancedProductionShift,
	AdvancedProductionStageTransfer,
	AdvancedProductionWorkCenter,
)
from adapters.db.models.product import Product
from app.core.advanced_production_plugin_dependency import check_advanced_production_plugin_active
from app.core.responses import ApiError
from app.services.advanced_production_calc import D, mean_gap_days, mean_minutes, oee_factors

MASTER_KINDS = (
	"work_centers",
	"lines",
	"machines",
	"shifts",
	"downtime",
	"outputs",
	"inspections",
	"maintenance",
	"scrap_reasons",
	"scrap_events",
	"order_holds",
	"order_lines",
	"wip_counts",
	"reworks",
	"line_returns",
	"stage_transfers",
	"labor",
)
_QC_STAGES = ("incoming", "in_process", "final")
_QC_RESULTS = ("pass", "fail")


def _ensure(db: Session, business_id: int) -> None:
	if not check_advanced_production_plugin_active(db, business_id):
		raise ApiError(
			"ADVANCED_PRODUCTION_PLUGIN_NOT_ACTIVE",
			"ADVANCED_PRODUCTION_PLUGIN_NOT_ACTIVE",
			http_status=403,
			details={"plugin_code": "advanced_production"},
		)


def _parse_date(value: Any, code: str = "INVALID_DATE") -> date:
	if isinstance(value, datetime):
		return value.date()
	if isinstance(value, date):
		return value
	try:
		return date.fromisoformat(str(value)[:10])
	except ValueError as exc:
		raise ApiError(code, code, http_status=400) from exc


def _required_int(value: Any, code: str) -> int:
	if value in (None, ""):
		raise ApiError(code, code, http_status=400)
	try:
		return int(value)
	except (TypeError, ValueError) as exc:
		raise ApiError(code, code, http_status=400) from exc


def _safe_decimal(value: Any, code: str) -> Decimal:
	if value in (None, ""):
		return Decimal("0")
	try:
		return Decimal(str(value))
	except (InvalidOperation, ValueError, TypeError) as exc:
		raise ApiError(code, code, http_status=400) from exc


def _required_minutes(value: Any) -> int:
	try:
		minutes = int(value or 0)
	except (TypeError, ValueError) as exc:
		raise ApiError("AP_MINUTES_REQUIRED", "AP_MINUTES_REQUIRED", http_status=400) from exc
	if minutes <= 0:
		raise ApiError("AP_MINUTES_REQUIRED", "AP_MINUTES_REQUIRED", http_status=400)
	return minutes


def _optional_minutes(value: Any) -> int:
	if value in (None, ""):
		return 0
	try:
		minutes = int(value)
	except (TypeError, ValueError) as exc:
		raise ApiError("AP_MINUTES_REQUIRED", "AP_MINUTES_REQUIRED", http_status=400) from exc
	if minutes < 0:
		raise ApiError("AP_MINUTES_REQUIRED", "AP_MINUTES_REQUIRED", http_status=400)
	return minutes


def _require_line(db: Session, business_id: int, line_id: int) -> AdvancedProductionLine:
	row = db.query(AdvancedProductionLine).filter(
		AdvancedProductionLine.id == int(line_id),
		AdvancedProductionLine.business_id == int(business_id),
	).first()
	if row is None:
		raise ApiError("AP_LINE_NOT_FOUND", "AP_LINE_NOT_FOUND", http_status=404)
	return row


def _require_product(db: Session, business_id: int, product_id: int) -> Product:
	row = db.query(Product).filter(Product.id == int(product_id), Product.business_id == int(business_id)).first()
	if row is None:
		raise ApiError("AP_PRODUCT_NOT_FOUND", "AP_PRODUCT_NOT_FOUND", http_status=404)
	return row


def list_master(db: Session, business_id: int, kind: str) -> Dict[str, Any]:
	_ensure(db, business_id)
	if kind not in MASTER_KINDS:
		raise ApiError("AP_MASTER_UNKNOWN", "AP_MASTER_UNKNOWN", http_status=404)
	model = {
		"work_centers": AdvancedProductionWorkCenter,
		"lines": AdvancedProductionLine,
		"machines": AdvancedProductionMachine,
		"shifts": AdvancedProductionShift,
		"downtime": AdvancedProductionDowntime,
		"outputs": AdvancedProductionOutputLog,
		"inspections": AdvancedProductionInspection,
		"maintenance": AdvancedProductionMaintenance,
		"scrap_reasons": AdvancedProductionScrapReason,
		"scrap_events": AdvancedProductionScrapEvent,
		"order_holds": AdvancedProductionOrderHold,
		"order_lines": AdvancedProductionOrderLine,
		"wip_counts": AdvancedProductionWipCount,
		"reworks": AdvancedProductionRework,
		"line_returns": AdvancedProductionLineReturn,
		"stage_transfers": AdvancedProductionStageTransfer,
		"labor": AdvancedProductionLabor,
	}[kind]
	rows = db.query(model).filter(model.business_id == int(business_id)).order_by(model.id.desc()).limit(500).all()
	return {"kind": kind, "items": [_public(row) for row in rows]}


def create_master(db: Session, business_id: int, kind: str, payload: Dict[str, Any]) -> Dict[str, Any]:
	_ensure(db, business_id)
	payload = payload or {}
	if kind == "work_centers":
		row = AdvancedProductionWorkCenter(business_id=business_id, code=_code(payload), name=_name(payload))
	elif kind == "lines":
		center_id = payload.get("work_center_id")
		if center_id:
			center = db.query(AdvancedProductionWorkCenter).filter(
				AdvancedProductionWorkCenter.id == int(center_id),
				AdvancedProductionWorkCenter.business_id == int(business_id),
			).first()
			if center is None:
				raise ApiError("AP_WORK_CENTER_NOT_FOUND", "AP_WORK_CENTER_NOT_FOUND", http_status=404)
		nominal = Decimal(str(payload.get("nominal_units_per_hour") or 0))
		if nominal < 0:
			raise ApiError("AP_NOMINAL_RATE_INVALID", "AP_NOMINAL_RATE_INVALID", http_status=400)
		row = AdvancedProductionLine(
			business_id=business_id,
			work_center_id=int(center_id) if center_id else None,
			code=_code(payload),
			name=_name(payload),
			nominal_units_per_hour=nominal,
		)
	elif kind == "machines":
		line_id = payload.get("line_id")
		if line_id:
			_require_line(db, business_id, int(line_id))
		asset_id = payload.get("fixed_asset_id")
		if asset_id:
			from adapters.db.models.fixed_asset import FixedAsset
			asset = db.query(FixedAsset).filter(
				FixedAsset.id == int(asset_id),
				FixedAsset.business_id == int(business_id),
			).first()
			if asset is None:
				raise ApiError("AP_ASSET_NOT_FOUND", "AP_ASSET_NOT_FOUND", http_status=404)
		row = AdvancedProductionMachine(
			business_id=business_id,
			line_id=int(line_id) if line_id else None,
			fixed_asset_id=int(asset_id) if asset_id else None,
			code=_code(payload),
			name=_name(payload),
		)
	elif kind == "shifts":
		row = AdvancedProductionShift(
			business_id=business_id,
			code=_code(payload),
			name=_name(payload),
			start_time=_clock(payload.get("start_time")),
			end_time=_clock(payload.get("end_time")),
		)
	elif kind == "downtime":
		started = _parse_date(payload.get("started_on"))
		ended = _parse_date(payload.get("ended_on")) if payload.get("ended_on") else None
		if ended and ended < started:
			raise ApiError("INVALID_DATE_RANGE", "INVALID_DATE_RANGE", http_status=400)
		minutes = _required_minutes(payload.get("minutes"))
		line_id = _required_int(payload.get("line_id"), "AP_LINE_NOT_FOUND")
		_require_line(db, business_id, line_id)
		machine_id = None
		if payload.get("machine_id"):
			machine_id = _required_int(payload.get("machine_id"), "AP_MACHINE_NOT_FOUND")
			_require_machine(db, business_id, machine_id)
		row = AdvancedProductionDowntime(
			business_id=business_id,
			line_id=line_id,
			machine_id=machine_id,
			started_on=started,
			ended_on=ended,
			minutes=minutes,
			reason_code=str(payload.get("reason_code") or "").strip() or "unspecified",
			cost_amount=_non_negative_money(payload.get("cost_amount")),
			notes=payload.get("notes"),
		)
	elif kind == "outputs":
		line_id = _required_int(payload.get("line_id"), "AP_LINE_NOT_FOUND")
		product_id = _required_int(payload.get("product_id"), "AP_PRODUCT_NOT_FOUND")
		_require_line(db, business_id, line_id)
		_require_product(db, business_id, product_id)
		good = _safe_decimal(payload.get("quantity_good"), "AP_OUTPUT_QUANTITY_REQUIRED")
		scrap = _safe_decimal(payload.get("quantity_scrap"), "AP_OUTPUT_QUANTITY_REQUIRED")
		if good < 0 or scrap < 0 or good + scrap <= 0:
			raise ApiError("AP_OUTPUT_QUANTITY_REQUIRED", "AP_OUTPUT_QUANTITY_REQUIRED", http_status=400)
		operator_id = payload.get("operator_person_id")
		if operator_id:
			from adapters.db.models.person import Person
			operator_id = _required_int(operator_id, "AP_OPERATOR_NOT_FOUND")
			person = db.query(Person).filter(Person.id == operator_id, Person.business_id == int(business_id)).first()
			if person is None:
				raise ApiError("AP_OPERATOR_NOT_FOUND", "AP_OPERATOR_NOT_FOUND", http_status=404)
		shift_id = payload.get("shift_id")
		if shift_id:
			shift_id = _required_int(shift_id, "AP_SHIFT_NOT_FOUND")
			shift = db.query(AdvancedProductionShift).filter(
				AdvancedProductionShift.id == shift_id,
				AdvancedProductionShift.business_id == int(business_id),
			).first()
			if shift is None:
				raise ApiError("AP_SHIFT_NOT_FOUND", "AP_SHIFT_NOT_FOUND", http_status=404)
		machine_id = payload.get("machine_id")
		if machine_id:
			machine_id = _required_int(machine_id, "AP_MACHINE_NOT_FOUND")
			machine = _require_machine(db, business_id, machine_id)
			if machine.line_id is not None and int(machine.line_id) != line_id:
				raise ApiError("AP_MACHINE_LINE_MISMATCH", "AP_MACHINE_LINE_MISMATCH", http_status=400)
		row = AdvancedProductionOutputLog(
			business_id=business_id,
			line_id=line_id,
			shift_id=int(shift_id) if shift_id else None,
			operator_person_id=int(operator_id) if operator_id else None,
			machine_id=int(machine_id) if machine_id else None,
			product_id=product_id,
			produced_on=_parse_date(payload.get("produced_on")),
			run_minutes=_required_minutes(payload.get("run_minutes")),
			quantity_good=good,
			quantity_scrap=scrap,
		)
	elif kind == "maintenance":
		machine = db.query(AdvancedProductionMachine).filter(
			AdvancedProductionMachine.id == _required_int(payload.get("machine_id"), "AP_MACHINE_NOT_FOUND"),
			AdvancedProductionMachine.business_id == int(business_id),
		).first()
		if machine is None:
			raise ApiError("AP_MACHINE_NOT_FOUND", "AP_MACHINE_NOT_FOUND", http_status=404)
		kind_value = str(payload.get("maintenance_kind") or payload.get("kind") or "")
		if kind_value not in ("breakdown", "preventive"):
			raise ApiError("AP_MAINTENANCE_KIND_INVALID", "AP_MAINTENANCE_KIND_INVALID", http_status=400)
		opened = _parse_date(payload.get("opened_on"))
		closed = _parse_date(payload.get("closed_on")) if payload.get("closed_on") else None
		if closed and closed < opened:
			raise ApiError("INVALID_DATE_RANGE", "INVALID_DATE_RANGE", http_status=400)
		spare_product_id = payload.get("spare_product_id")
		if spare_product_id not in (None, ""):
			spare_product_id = _required_int(spare_product_id, "AP_PRODUCT_NOT_FOUND")
		else:
			spare_product_id = None
		spare_quantity = _safe_decimal(payload.get("spare_quantity"), "AP_SCRAP_QUANTITY_REQUIRED")
		if spare_quantity < 0:
			raise ApiError("AP_SCRAP_QUANTITY_REQUIRED", "AP_SCRAP_QUANTITY_REQUIRED", http_status=400)
		row = AdvancedProductionMaintenance(
			business_id=business_id,
			machine_id=machine.id,
			line_id=machine.line_id,
			kind=kind_value,
			opened_on=opened,
			closed_on=closed,
			repair_minutes=_optional_minutes(payload.get("repair_minutes")),
			cost_amount=_non_negative_money(payload.get("cost_amount")),
			spare_product_id=spare_product_id,
			spare_quantity=spare_quantity,
			notes=payload.get("notes"),
		)
	elif kind == "inspections":
		_require_product(db, business_id, _required_int(payload.get("product_id"), "AP_PRODUCT_NOT_FOUND"))
		stage = str(payload.get("stage") or "")
		result = str(payload.get("result") or "")
		if stage not in _QC_STAGES or result not in _QC_RESULTS:
			raise ApiError("AP_QC_VALUE_INVALID", "AP_QC_VALUE_INVALID", http_status=400)
		checked = _safe_decimal(payload.get("quantity_checked"), "AP_QC_QUANTITY_INVALID")
		rejected = _safe_decimal(payload.get("quantity_rejected"), "AP_QC_QUANTITY_INVALID")
		if checked <= 0 or rejected < 0 or rejected > checked:
			raise ApiError("AP_QC_QUANTITY_INVALID", "AP_QC_QUANTITY_INVALID", http_status=400)
		row = AdvancedProductionInspection(
			business_id=business_id,
			product_id=_required_int(payload.get("product_id"), "AP_PRODUCT_NOT_FOUND"),
			stage=stage,
			inspected_on=_parse_date(payload.get("inspected_on")),
			quantity_checked=checked,
			quantity_rejected=rejected,
			result=result,
			reason_code=(str(payload.get("reason_code") or "").strip() or None),
			notes=payload.get("notes"),
		)
	elif kind == "order_holds":
		row = _save_order_hold(db, business_id, payload)
	elif kind == "order_lines":
		row = _save_order_line(db, business_id, payload)
	elif kind == "wip_counts":
		row = _save_wip_count(db, business_id, payload)
	elif kind == "reworks":
		row = _save_quantity_event(db, business_id, payload, AdvancedProductionRework, with_order=True)
	elif kind == "line_returns":
		row = _save_quantity_event(db, business_id, payload, AdvancedProductionLineReturn, with_line=True)
	elif kind == "stage_transfers":
		row = _save_stage_transfer(db, business_id, payload)
	elif kind == "labor":
		row = _save_labor(db, business_id, payload)
	elif kind == "scrap_reasons":
		if "recyclable" not in payload:
			raise ApiError("AP_SCRAP_RECYCLABLE_REQUIRED", "AP_SCRAP_RECYCLABLE_REQUIRED", http_status=400)
		row = AdvancedProductionScrapReason(
			business_id=business_id,
			code=_code(payload),
			name=_name(payload),
			recyclable=_flag(payload.get("recyclable")),
		)
	elif kind == "scrap_events":
		reason_id = _required_int(payload.get("reason_id"), "AP_SCRAP_REASON_NOT_FOUND")
		reason = db.query(AdvancedProductionScrapReason).filter(
			AdvancedProductionScrapReason.id == reason_id,
			AdvancedProductionScrapReason.business_id == int(business_id),
		).first()
		if reason is None:
			raise ApiError("AP_SCRAP_REASON_NOT_FOUND", "AP_SCRAP_REASON_NOT_FOUND", http_status=404)
		product_id = _required_int(payload.get("product_id"), "AP_PRODUCT_NOT_FOUND")
		_require_product(db, business_id, product_id)
		line_id = None
		if payload.get("line_id") not in (None, ""):
			line_id = _require_line(db, business_id, _required_int(payload.get("line_id"), "AP_LINE_NOT_FOUND")).id
		quantity = _positive_quantity(payload.get("quantity"))
		row = AdvancedProductionScrapEvent(
			business_id=business_id,
			reason_id=reason.id,
			product_id=product_id,
			line_id=line_id,
			occurred_on=_parse_date(payload.get("occurred_on") or payload.get("produced_on")),
			quantity=quantity,
		)
	else:
		raise ApiError("AP_MASTER_UNKNOWN", "AP_MASTER_UNKNOWN", http_status=404)
	db.add(row)
	db.flush()
	return _public(row)


def oee_report(db: Session, business_id: int, *, date_from: Optional[str] = None, date_to: Optional[str] = None) -> Dict[str, Any]:
	_ensure(db, business_id)
	start = _parse_date(date_from) if date_from else None
	end = _parse_date(date_to) if date_to else None
	if start and end and start > end:
		raise ApiError("INVALID_DATE_RANGE", "INVALID_DATE_RANGE", http_status=400)
	lines = db.query(AdvancedProductionLine).filter(AdvancedProductionLine.business_id == int(business_id)).all()
	items = []
	for line in lines:
		outputs = db.query(AdvancedProductionOutputLog).filter(
			AdvancedProductionOutputLog.business_id == int(business_id),
			AdvancedProductionOutputLog.line_id == line.id,
		)
		downtime = db.query(AdvancedProductionDowntime).filter(
			AdvancedProductionDowntime.business_id == int(business_id),
			AdvancedProductionDowntime.line_id == line.id,
		)
		if start:
			outputs = outputs.filter(AdvancedProductionOutputLog.produced_on >= start)
			downtime = downtime.filter(AdvancedProductionDowntime.started_on >= start)
		if end:
			outputs = outputs.filter(AdvancedProductionOutputLog.produced_on <= end)
			downtime = downtime.filter(AdvancedProductionDowntime.started_on <= end)
		output_rows = outputs.all()
		down_rows = downtime.all()
		run_minutes = sum(int(row.run_minutes or 0) for row in output_rows)
		down_minutes = sum(int(row.minutes or 0) for row in down_rows)
		good = sum((D(row.quantity_good) for row in output_rows), Decimal("0"))
		scrap = sum((D(row.quantity_scrap) for row in output_rows), Decimal("0"))
		ideal = D(line.nominal_units_per_hour) * Decimal(run_minutes) / Decimal(60) if run_minutes else Decimal("0")
		factors = oee_factors(run_minutes, down_minutes, ideal, good, scrap)
		items.append({
			"line_id": line.id,
			"line_code": line.code,
			"line_name": line.name,
			"run_minutes": run_minutes,
			"downtime_minutes": down_minutes,
			"quantity_good": float(good),
			"quantity_scrap": float(scrap),
			"ideal_quantity": float(ideal),
			**{key: (None if value is None else float(value)) for key, value in factors.items()},
		})
	return {
		"items": items,
		"summary": {"count": len(items)},
		"pagination": {"total": len(items), "page": 1, "per_page": len(items) or 1},
		"meta": {
			"oee_definition": "availability_x_performance_x_quality",
			"requires_output_log": True,
		},
	}


def output_group_report(db: Session, business_id: int, report_key: str, *, date_from: Optional[str] = None, date_to: Optional[str] = None) -> Dict[str, Any]:
	_ensure(db, business_id)
	start = _parse_date(date_from) if date_from else None
	end = _parse_date(date_to) if date_to else None
	if start and end and start > end:
		raise ApiError("INVALID_DATE_RANGE", "INVALID_DATE_RANGE", http_status=400)
	query = db.query(AdvancedProductionOutputLog).filter(AdvancedProductionOutputLog.business_id == int(business_id))
	if start:
		query = query.filter(AdvancedProductionOutputLog.produced_on >= start)
	if end:
		query = query.filter(AdvancedProductionOutputLog.produced_on <= end)
	lines = {row.id: row for row in db.query(AdvancedProductionLine).filter(AdvancedProductionLine.business_id == int(business_id)).all()}
	centers = {row.id: row for row in db.query(AdvancedProductionWorkCenter).filter(AdvancedProductionWorkCenter.business_id == int(business_id)).all()}
	grouped: Dict[int, Dict[str, Any]] = {}
	for row in query.all():
		line_row = lines.get(row.line_id)
		if report_key == "work_center_output":
			key = int(line_row.work_center_id or 0) if line_row else 0
		elif report_key in ("line_output", "capacity_usage"):
			key = int(row.line_id)
		elif report_key == "operator_output":
			key = int(row.operator_person_id or 0)
		else:
			key = int(row.shift_id or 0)
		item = grouped.setdefault(key, {
			"line_id": row.line_id,
			"work_center_id": line_row.work_center_id if line_row else None,
			"shift_id": row.shift_id,
			"operator_person_id": row.operator_person_id,
			"quantity_good": Decimal("0"),
			"quantity_scrap": Decimal("0"),
			"run_minutes": 0,
		})
		item["quantity_good"] += D(row.quantity_good)
		item["quantity_scrap"] += D(row.quantity_scrap)
		item["run_minutes"] += int(row.run_minutes or 0)
	shifts = {row.id: row for row in db.query(AdvancedProductionShift).filter(AdvancedProductionShift.business_id == int(business_id)).all()}
	from adapters.db.models.person import Person
	operator_ids = [item["operator_person_id"] for item in grouped.values() if item.get("operator_person_id")]
	people = {}
	if operator_ids:
		people = {row.id: row for row in db.query(Person).filter(Person.business_id == int(business_id), Person.id.in_(operator_ids)).all()}
	items = []
	for item in grouped.values():
		line = lines.get(item["line_id"])
		shift = shifts.get(item["shift_id"]) if item["shift_id"] else None
		total = item["quantity_good"] + item["quantity_scrap"]
		nominal = D(line.nominal_units_per_hour) if line else Decimal("0")
		from app.services.advanced_production_calc import capacity_gap
		gap = capacity_gap(nominal, item["run_minutes"], total)
		items.append({
			"line_id": item["line_id"],
			"line_code": line.code if line else None,
			"line_name": line.name if line else None,
			"work_center_id": item.get("work_center_id"),
			"work_center_name": centers.get(item.get("work_center_id")).name if centers.get(item.get("work_center_id")) else None,
			"shift_id": item["shift_id"],
			"shift_code": shift.code if shift else None,
			"shift_name": shift.name if shift else None,
			"operator_person_id": item.get("operator_person_id"),
			"operator_name": people.get(item.get("operator_person_id")).alias_name if people.get(item.get("operator_person_id")) else None,
			"quantity_good": float(item["quantity_good"]),
			"quantity_scrap": float(item["quantity_scrap"]),
			"run_minutes": item["run_minutes"],
			"good_percent": None if total <= 0 else float(((item["quantity_good"] / total) * Decimal("100")).quantize(Decimal("0.01"))),
			"ideal_quantity": None if gap is None else float(gap["ideal_quantity"]),
			"utilization_percent": None if gap is None else float(gap["utilization_percent"]),
		})
	return {
		"report_key": report_key,
		"items": items,
		"summary": {"count": len(items)},
		"pagination": {"total": len(items), "page": 1, "per_page": max(len(items), 1)},
		"meta": {"source": "line_output_logs"},
	}


def setup_time_report(db: Session, business_id: int, *, date_from: Optional[str] = None, date_to: Optional[str] = None) -> Dict[str, Any]:
	"""فقط توقف‌هایی که reason_code آن‌ها setup است. علت دیگر در این گزارش نمی‌آید."""
	_ensure(db, business_id)
	start = _parse_date(date_from) if date_from else None
	end = _parse_date(date_to) if date_to else None
	query = db.query(AdvancedProductionDowntime).filter(
		AdvancedProductionDowntime.business_id == int(business_id),
		AdvancedProductionDowntime.reason_code.ilike("setup"),
	)
	if start:
		query = query.filter(AdvancedProductionDowntime.started_on >= start)
	if end:
		query = query.filter(AdvancedProductionDowntime.started_on <= end)
	items = [_public(row) for row in query.order_by(AdvancedProductionDowntime.started_on.desc()).all()]
	minutes = sum(int(row.get("minutes") or 0) for row in items)
	return {
		"report_key": "setup_time",
		"items": items,
		"summary": {"count": len(items), "minutes": minutes},
		"pagination": {"total": len(items), "page": 1, "per_page": max(len(items), 1)},
		"meta": {"reason_code": "setup"},
	}


def reliability_report(db: Session, business_id: int) -> Dict[str, Any]:
	_ensure(db, business_id)
	rows = db.query(AdvancedProductionMaintenance, AdvancedProductionMachine).join(
		AdvancedProductionMachine, AdvancedProductionMachine.id == AdvancedProductionMaintenance.machine_id
	).filter(AdvancedProductionMaintenance.business_id == int(business_id)).all()
	grouped: Dict[int, Dict[str, Any]] = {}
	for order, machine in rows:
		item = grouped.setdefault(machine.id, {
			"machine_id": machine.id,
			"machine_code": machine.code,
			"machine_name": machine.name,
			"line_id": machine.line_id,
			"breakdown_count": 0,
			"preventive_count": 0,
			"repair_minutes": [],
			"opened_on": [],
			"cost_amount": Decimal("0"),
			"spare_quantity": Decimal("0"),
		})
		if order.kind == "breakdown":
			item["breakdown_count"] += 1
			item["opened_on"].append(order.opened_on)
			if order.closed_on is not None:
				item["repair_minutes"].append(int(order.repair_minutes or 0))
		else:
			item["preventive_count"] += 1
		item["cost_amount"] += D(order.cost_amount)
		item["spare_quantity"] += D(order.spare_quantity)
	items = []
	for item in grouped.values():
		mtbf = mean_gap_days(item["opened_on"])
		mttr = mean_minutes(item["repair_minutes"])
		items.append({
			"machine_id": item["machine_id"],
			"machine_code": item["machine_code"],
			"machine_name": item["machine_name"],
			"line_id": item["line_id"],
			"breakdown_count": item["breakdown_count"],
			"preventive_count": item["preventive_count"],
			"mtbf_days": None if mtbf is None else float(mtbf),
			"mttr_minutes": None if mttr is None else float(mttr),
			"cost_amount": float(item["cost_amount"]),
			"spare_quantity": float(item["spare_quantity"]),
		})
	return {
		"items": items,
		"summary": {"count": len(items)},
		"pagination": {"total": len(items), "page": 1, "per_page": max(len(items), 1)},
		"meta": {
			"mtbf": "mean_days_between_breakdown_open_dates",
			"mttr": "mean_repair_minutes_of_closed_breakdowns",
			"general_ledger_posting": "not_posted",
		},
	}


def _require_machine(db: Session, business_id: int, machine_id: int) -> AdvancedProductionMachine:
	row = db.query(AdvancedProductionMachine).filter(
		AdvancedProductionMachine.id == int(machine_id),
		AdvancedProductionMachine.business_id == int(business_id),
	).first()
	if row is None:
		raise ApiError("AP_MACHINE_NOT_FOUND", "AP_MACHINE_NOT_FOUND", http_status=404)
	return row


def _non_negative_money(value: Any) -> Decimal:
	amount = _safe_decimal(value, "AP_COST_INVALID")
	if amount < 0:
		raise ApiError("AP_COST_INVALID", "AP_COST_INVALID", http_status=400)
	return amount


def _require_order(db: Session, business_id: int, order_id: int):
	from adapters.db.models.production_order import ProductionOrder

	order = db.query(ProductionOrder).filter(
		ProductionOrder.id == int(order_id),
		ProductionOrder.business_id == int(business_id),
	).first()
	if order is None:
		raise ApiError("AP_ORDER_NOT_FOUND", "AP_ORDER_NOT_FOUND", http_status=404)
	return order


def _positive_quantity(value: Any) -> Decimal:
	quantity = _safe_decimal(value, "AP_SCRAP_QUANTITY_REQUIRED")
	if quantity <= 0:
		raise ApiError("AP_SCRAP_QUANTITY_REQUIRED", "AP_SCRAP_QUANTITY_REQUIRED", http_status=400)
	return quantity


def _save_order_line(db: Session, business_id: int, payload: Dict[str, Any]) -> AdvancedProductionOrderLine:
	order = _require_order(db, business_id, _required_int(payload.get("production_order_id"), "AP_ORDER_NOT_FOUND"))
	line = _require_line(db, business_id, _required_int(payload.get("line_id"), "AP_LINE_NOT_FOUND"))
	existing = db.query(AdvancedProductionOrderLine).filter(
		AdvancedProductionOrderLine.business_id == int(business_id),
		AdvancedProductionOrderLine.production_order_id == order.id,
	).first()
	if existing is not None:
		existing.line_id = line.id
		return existing
	return AdvancedProductionOrderLine(business_id=business_id, production_order_id=order.id, line_id=line.id)


def _save_wip_count(db: Session, business_id: int, payload: Dict[str, Any]) -> AdvancedProductionWipCount:
	order = _require_order(db, business_id, _required_int(payload.get("production_order_id"), "AP_ORDER_NOT_FOUND"))
	raw_quantity = payload.get("counted_quantity") if payload.get("counted_quantity") is not None else payload.get("quantity")
	quantity = _safe_decimal(raw_quantity, "AP_COUNT_INVALID")
	if quantity < 0:
		raise ApiError("AP_COUNT_INVALID", "AP_COUNT_INVALID", http_status=400)
	return AdvancedProductionWipCount(
		business_id=business_id,
		production_order_id=order.id,
		counted_on=_parse_date(payload.get("counted_on") or payload.get("produced_on") or payload.get("started_on")),
		counted_quantity=quantity,
	)


def _save_quantity_event(db: Session, business_id: int, payload: Dict[str, Any], model, *, with_order: bool = False, with_line: bool = False):
	product_id = _required_int(payload.get("product_id"), "AP_PRODUCT_NOT_FOUND")
	_require_product(db, business_id, product_id)
	order_id = None
	if with_order and payload.get("production_order_id") not in (None, ""):
		order_id = _require_order(db, business_id, _required_int(payload.get("production_order_id"), "AP_ORDER_NOT_FOUND")).id
	line_id = None
	if with_line and payload.get("line_id") not in (None, ""):
		line_id = _require_line(db, business_id, _required_int(payload.get("line_id"), "AP_LINE_NOT_FOUND")).id
	values = dict(
		business_id=business_id,
		product_id=product_id,
		occurred_on=_parse_date(payload.get("occurred_on") or payload.get("produced_on") or payload.get("started_on")),
		quantity=_positive_quantity(payload.get("quantity") or payload.get("quantity_scrap")),
	)
	if with_order:
		values["production_order_id"] = order_id
	if with_line:
		values["line_id"] = line_id
	return model(**values)


def _optional_non_negative(value: Any, code: str) -> Optional[Decimal]:
	if value in (None, ""):
		return None
	amount = _safe_decimal(value, code)
	if amount < 0:
		raise ApiError(code, code, http_status=400)
	return amount


def _save_labor(db: Session, business_id: int, payload: Dict[str, Any]) -> AdvancedProductionLabor:
	hours = _safe_decimal(payload.get("actual_hours"), "AP_LABOR_HOURS_REQUIRED")
	if hours <= 0:
		raise ApiError("AP_LABOR_HOURS_REQUIRED", "AP_LABOR_HOURS_REQUIRED", http_status=400)
	order_id = None
	if payload.get("production_order_id") not in (None, ""):
		order_id = _require_order(db, business_id, _required_int(payload.get("production_order_id"), "AP_ORDER_NOT_FOUND")).id
	person_id = payload.get("person_id") or payload.get("operator_person_id")
	if person_id not in (None, ""):
		from adapters.db.models.person import Person
		person_id = _required_int(person_id, "AP_OPERATOR_NOT_FOUND")
		person = db.query(Person).filter(Person.id == person_id, Person.business_id == int(business_id)).first()
		if person is None:
			raise ApiError("AP_OPERATOR_NOT_FOUND", "AP_OPERATOR_NOT_FOUND", http_status=404)
		person_id = person.id
	return AdvancedProductionLabor(
		business_id=business_id,
		production_order_id=order_id,
		person_id=person_id if person_id else None,
		worked_on=_parse_date(payload.get("worked_on") or payload.get("produced_on") or payload.get("started_on")),
		actual_hours=hours,
		standard_hours=_optional_non_negative(payload.get("standard_hours"), "AP_LABOR_HOURS_REQUIRED"),
		standard_hourly_rate=_optional_non_negative(payload.get("standard_hourly_rate"), "AP_LABOR_RATE_INVALID"),
		actual_hourly_rate=_optional_non_negative(payload.get("actual_hourly_rate"), "AP_LABOR_RATE_INVALID"),
	)


def _save_stage_transfer(db: Session, business_id: int, payload: Dict[str, Any]) -> AdvancedProductionStageTransfer:
	source = _require_line(db, business_id, _required_int(payload.get("from_line_id") or payload.get("line_id"), "AP_LINE_NOT_FOUND"))
	target = _require_line(db, business_id, _required_int(payload.get("to_line_id"), "AP_LINE_NOT_FOUND"))
	if source.id == target.id:
		raise ApiError("AP_TRANSFER_LINES_SAME", "AP_TRANSFER_LINES_SAME", http_status=400)
	product_id = _required_int(payload.get("product_id"), "AP_PRODUCT_NOT_FOUND")
	_require_product(db, business_id, product_id)
	return AdvancedProductionStageTransfer(
		business_id=business_id,
		from_line_id=source.id,
		to_line_id=target.id,
		product_id=product_id,
		transferred_on=_parse_date(payload.get("transferred_on") or payload.get("produced_on") or payload.get("started_on")),
		quantity=_positive_quantity(payload.get("quantity") or payload.get("quantity_scrap")),
	)


def _save_order_hold(db: Session, business_id: int, payload: Dict[str, Any]) -> AdvancedProductionOrderHold:
	from adapters.db.models.production_order import ProductionOrder

	if payload.get("hold_id") not in (None, ""):
		hold = db.query(AdvancedProductionOrderHold).filter(
			AdvancedProductionOrderHold.id == _required_int(payload.get("hold_id"), "AP_HOLD_NOT_FOUND"),
			AdvancedProductionOrderHold.business_id == int(business_id),
		).first()
		if hold is None:
			raise ApiError("AP_HOLD_NOT_FOUND", "AP_HOLD_NOT_FOUND", http_status=404)
		released = _parse_date(payload.get("released_on") or payload.get("produced_on"))
		if released < hold.held_on:
			raise ApiError("INVALID_DATE_RANGE", "INVALID_DATE_RANGE", http_status=400)
		hold.released_on = released
		return hold
	order = db.query(ProductionOrder).filter(
		ProductionOrder.id == _required_int(payload.get("production_order_id"), "AP_ORDER_NOT_FOUND"),
		ProductionOrder.business_id == int(business_id),
	).first()
	if order is None:
		raise ApiError("AP_ORDER_NOT_FOUND", "AP_ORDER_NOT_FOUND", http_status=404)
	reason = str(payload.get("reason") or payload.get("name") or "").strip()
	if not reason:
		raise ApiError("AP_HOLD_REASON_REQUIRED", "AP_HOLD_REASON_REQUIRED", http_status=400)
	held = _parse_date(payload.get("held_on") or payload.get("produced_on") or payload.get("started_on"))
	released = _parse_date(payload.get("released_on")) if payload.get("released_on") else None
	if released and released < held:
		raise ApiError("INVALID_DATE_RANGE", "INVALID_DATE_RANGE", http_status=400)
	return AdvancedProductionOrderHold(
		business_id=business_id,
		production_order_id=order.id,
		held_on=held,
		released_on=released,
		reason=reason[:255],
	)


def _flag(value: Any) -> bool:
	if value is True or str(value).strip().lower() in {"1", "true", "yes"}:
		return True
	if value is False or str(value).strip().lower() in {"0", "false", "no"}:
		return False
	raise ApiError("AP_SCRAP_RECYCLABLE_REQUIRED", "AP_SCRAP_RECYCLABLE_REQUIRED", http_status=400)


def _code(payload: Dict[str, Any]) -> str:
	code = str(payload.get("code") or "").strip()
	if not code:
		raise ApiError("AP_CODE_REQUIRED", "AP_CODE_REQUIRED", http_status=400)
	return code[:64]


def _name(payload: Dict[str, Any]) -> str:
	name = str(payload.get("name") or "").strip()
	if not name:
		raise ApiError("AP_NAME_REQUIRED", "AP_NAME_REQUIRED", http_status=400)
	return name[:255]


def _clock(value: Any) -> Optional[str]:
	if value in (None, ""):
		return None
	text = str(value).strip()
	if len(text) != 5 or text[2] != ":":
		raise ApiError("AP_TIME_INVALID", "AP_TIME_INVALID", http_status=400)
	return text


def machine_output_report(db: Session, business_id: int, *, date_from: Optional[str] = None, date_to: Optional[str] = None) -> Dict[str, Any]:
	"""فقط خروجی‌هایی که دستگاه دارند. نرخ خط بین ماشین‌ها تقسیم نمی‌شود."""
	from app.services.advanced_production_calc import units_per_hour, yield_percent

	_ensure(db, business_id)
	start = _parse_date(date_from) if date_from else None
	end = _parse_date(date_to) if date_to else None
	query = db.query(AdvancedProductionOutputLog, AdvancedProductionMachine).join(
		AdvancedProductionMachine, AdvancedProductionMachine.id == AdvancedProductionOutputLog.machine_id
	).filter(
		AdvancedProductionOutputLog.business_id == int(business_id),
		AdvancedProductionOutputLog.machine_id.isnot(None),
	)
	if start:
		query = query.filter(AdvancedProductionOutputLog.produced_on >= start)
	if end:
		query = query.filter(AdvancedProductionOutputLog.produced_on <= end)
	grouped: Dict[int, Dict[str, Any]] = {}
	for log, machine in query.all():
		item = grouped.setdefault(machine.id, {
			"machine_code": machine.code,
			"machine_name": machine.name,
			"quantity_good": Decimal("0"),
			"quantity_scrap": Decimal("0"),
			"run_minutes": 0,
		})
		item["quantity_good"] += D(log.quantity_good)
		item["quantity_scrap"] += D(log.quantity_scrap)
		item["run_minutes"] += int(log.run_minutes or 0)
	items = []
	for item in grouped.values():
		rate = units_per_hour(item["quantity_good"], item["run_minutes"])
		yld = yield_percent(item["quantity_good"], item["quantity_scrap"])
		items.append({
			"machine_code": item["machine_code"],
			"machine_name": item["machine_name"],
			"quantity_good": float(item["quantity_good"]),
			"quantity_scrap": float(item["quantity_scrap"]),
			"run_minutes": item["run_minutes"],
			"good_per_hour": None if rate is None else float(rate),
			"yield_percent": None if yld is None else float(yld),
		})
	return {
		"report_key": "machine_output",
		"items": items,
		"summary": {"count": len(items)},
		"pagination": {"total": len(items), "page": 1, "per_page": max(len(items), 1)},
		"meta": {"logs_without_machine_excluded": True, "line_rate_not_split_across_machines": True},
	}


def downtime_cost_report(db: Session, business_id: int, *, date_from: Optional[str] = None, date_to: Optional[str] = None) -> Dict[str, Any]:
	_ensure(db, business_id)
	start = _parse_date(date_from) if date_from else None
	end = _parse_date(date_to) if date_to else None
	query = db.query(AdvancedProductionDowntime, AdvancedProductionLine).join(
		AdvancedProductionLine, AdvancedProductionLine.id == AdvancedProductionDowntime.line_id
	).filter(AdvancedProductionDowntime.business_id == int(business_id))
	if start:
		query = query.filter(AdvancedProductionDowntime.started_on >= start)
	if end:
		query = query.filter(AdvancedProductionDowntime.started_on <= end)
	grouped: Dict[int, Dict[str, Any]] = {}
	for row, line in query.all():
		item = grouped.setdefault(line.id, {
			"line_code": line.code,
			"line_name": line.name,
			"minutes": 0,
			"cost_amount": Decimal("0"),
		})
		item["minutes"] += int(row.minutes or 0)
		item["cost_amount"] += D(row.cost_amount)
	items = [{**item, "cost_amount": float(item["cost_amount"])} for item in grouped.values()]
	return {
		"report_key": "downtime_cost",
		"items": items,
		"summary": {"count": len(items)},
		"pagination": {"total": len(items), "page": 1, "per_page": max(len(items), 1)},
		"meta": {"general_ledger_posting": "not_this_report", "zero_cost_means_no_amount_was_entered": True},
	}


def held_orders_report(db: Session, business_id: int) -> Dict[str, Any]:
	from adapters.db.models.product import Product
	from adapters.db.models.production_order import ProductionOrder

	_ensure(db, business_id)
	rows = db.query(AdvancedProductionOrderHold, ProductionOrder, Product).join(
		ProductionOrder, ProductionOrder.id == AdvancedProductionOrderHold.production_order_id
	).join(Product, Product.id == ProductionOrder.product_id).filter(
		AdvancedProductionOrderHold.business_id == int(business_id),
		AdvancedProductionOrderHold.released_on.is_(None),
	).all()
	items = [
		{
			"hold_id": hold.id,
			"production_order_id": order.id,
			"code": order.code,
			"product_name": product.name,
			"status": order.status,
			"held_on": hold.held_on.isoformat(),
			"reason": hold.reason,
		}
		for hold, order, product in rows
	]
	return {
		"report_key": "held_orders",
		"items": items,
		"summary": {"count": len(items)},
		"pagination": {"total": len(items), "page": 1, "per_page": max(len(items), 1)},
		"meta": {"core_order_status_unchanged": True, "open_holds_only": True},
	}


def capacity_report(db: Session, business_id: int) -> Dict[str, Any]:
	from adapters.db.models.production_order import ProductionOrder
	from app.services.advanced_production_calc import required_hours

	_ensure(db, business_id)
	rows = db.query(AdvancedProductionOrderLine, ProductionOrder, AdvancedProductionLine, Product).join(
		ProductionOrder, ProductionOrder.id == AdvancedProductionOrderLine.production_order_id
	).join(AdvancedProductionLine, AdvancedProductionLine.id == AdvancedProductionOrderLine.line_id).join(
		Product, Product.id == ProductionOrder.product_id
	).filter(AdvancedProductionOrderLine.business_id == int(business_id)).all()
	items = []
	for _link, order, line, product in rows:
		remaining = max(D(order.planned_quantity) - D(order.produced_quantity), Decimal("0"))
		hours = required_hours(remaining, line.nominal_units_per_hour)
		items.append({
			"code": order.code,
			"product_name": product.name,
			"line_name": line.name,
			"remaining_quantity": float(remaining),
			"nominal_units_per_hour": float(D(line.nominal_units_per_hour)),
			"required_hours": None if hours is None else float(hours),
		})
	return {
		"report_key": "capacity_required",
		"items": items,
		"summary": {"count": len(items)},
		"pagination": {"total": len(items), "page": 1, "per_page": max(len(items), 1)},
		"meta": {"hours_blank_when_nominal_rate_is_zero": True, "unassigned_orders_excluded": True},
	}


def wip_count_report(db: Session, business_id: int) -> Dict[str, Any]:
	from adapters.db.models.production_order import ProductionOrder

	_ensure(db, business_id)
	rows = db.query(AdvancedProductionWipCount, ProductionOrder, Product).join(
		ProductionOrder, ProductionOrder.id == AdvancedProductionWipCount.production_order_id
	).join(Product, Product.id == ProductionOrder.product_id).filter(
		AdvancedProductionWipCount.business_id == int(business_id),
	).order_by(AdvancedProductionWipCount.counted_on.desc()).all()
	items = []
	for count, order, product in rows:
		book = max(D(order.planned_quantity) - D(order.produced_quantity), Decimal("0"))
		items.append({
			"code": order.code,
			"product_name": product.name,
			"counted_on": count.counted_on.isoformat(),
			"counted_quantity": float(D(count.counted_quantity)),
			"book_remaining": float(book),
			"quantity_variance": float(D(count.counted_quantity) - book),
		})
	return {
		"report_key": "wip_count",
		"items": items,
		"summary": {"count": len(items)},
		"pagination": {"total": len(items), "page": 1, "per_page": max(len(items), 1)},
		"meta": {
			"book_remaining": "current_order_planned_minus_produced",
			"general_ledger_posting": "not_this_report",
			"positive_variance": "physical_above_order_remaining",
		},
	}


def wage_variance_report(db: Session, business_id: int, *, date_from: Optional[str] = None, date_to: Optional[str] = None) -> Dict[str, Any]:
	from app.services.advanced_production_calc import wage_variances

	_ensure(db, business_id)
	start = _parse_date(date_from) if date_from else None
	end = _parse_date(date_to) if date_to else None
	query = db.query(AdvancedProductionLabor).filter(AdvancedProductionLabor.business_id == int(business_id))
	if start:
		query = query.filter(AdvancedProductionLabor.worked_on >= start)
	if end:
		query = query.filter(AdvancedProductionLabor.worked_on <= end)
	items = []
	for row in query.order_by(AdvancedProductionLabor.worked_on.desc()).all():
		split = wage_variances(row.actual_hours, row.standard_hours, row.standard_hourly_rate, row.actual_hourly_rate)
		items.append({
			"worked_on": row.worked_on.isoformat(),
			"production_order_id": row.production_order_id,
			"person_id": row.person_id,
			"actual_hours": float(D(row.actual_hours)),
			"standard_hours": None if row.standard_hours is None else float(D(row.standard_hours)),
			"standard_hourly_rate": None if row.standard_hourly_rate is None else float(D(row.standard_hourly_rate)),
			"actual_hourly_rate": None if row.actual_hourly_rate is None else float(D(row.actual_hourly_rate)),
			"rate_variance": None if split is None or split["rate_variance"] is None else float(split["rate_variance"]),
			"efficiency_variance": None if split is None or split["efficiency_variance"] is None else float(split["efficiency_variance"]),
		})
	return {
		"report_key": "wage_variance",
		"items": items,
		"summary": {"count": len(items)},
		"pagination": {"total": len(items), "page": 1, "per_page": max(len(items), 1)},
		"meta": {
			"source": "production_labor_records_not_payroll",
			"general_ledger_posting": "not_this_report",
			"positive_variance": "unfavorable",
		},
	}


def stage_transfer_report(db: Session, business_id: int, *, date_from: Optional[str] = None, date_to: Optional[str] = None) -> Dict[str, Any]:
	_ensure(db, business_id)
	start = _parse_date(date_from) if date_from else None
	end = _parse_date(date_to) if date_to else None
	source = aliased_line()
	query = db.query(AdvancedProductionStageTransfer, Product).join(
		Product, Product.id == AdvancedProductionStageTransfer.product_id
	).filter(AdvancedProductionStageTransfer.business_id == int(business_id))
	if start:
		query = query.filter(AdvancedProductionStageTransfer.transferred_on >= start)
	if end:
		query = query.filter(AdvancedProductionStageTransfer.transferred_on <= end)
	lines = {row.id: row for row in db.query(AdvancedProductionLine).filter(AdvancedProductionLine.business_id == int(business_id)).all()}
	items = []
	for event, product in query.order_by(AdvancedProductionStageTransfer.transferred_on.desc()).all():
		origin = lines.get(event.from_line_id)
		dest = lines.get(event.to_line_id)
		items.append({
			"transferred_on": event.transferred_on.isoformat(),
			"from_line_name": origin.name if origin else None,
			"to_line_name": dest.name if dest else None,
			"product_name": product.name,
			"quantity": float(D(event.quantity)),
		})
	return {
		"report_key": "stage_transfers",
		"items": items,
		"summary": {"count": len(items)},
		"pagination": {"total": len(items), "page": 1, "per_page": max(len(items), 1)},
		"meta": {"routing": "recorded_transfer_not_a_standard_route", "inventory_document": "not_created"},
	}


def rework_report(db: Session, business_id: int, *, date_from: Optional[str] = None, date_to: Optional[str] = None) -> Dict[str, Any]:
	return _quantity_event_report(db, business_id, AdvancedProductionRework, "rework", date_from=date_from, date_to=date_to)


def line_return_report(db: Session, business_id: int, *, date_from: Optional[str] = None, date_to: Optional[str] = None) -> Dict[str, Any]:
	result = _quantity_event_report(db, business_id, AdvancedProductionLineReturn, "line_returns", date_from=date_from, date_to=date_to)
	result["meta"]["inventory_document"] = "not_created"
	return result


def _quantity_event_report(db: Session, business_id: int, model, report_key: str, *, date_from: Optional[str] = None, date_to: Optional[str] = None) -> Dict[str, Any]:
	_ensure(db, business_id)
	start = _parse_date(date_from) if date_from else None
	end = _parse_date(date_to) if date_to else None
	query = db.query(model, Product).join(Product, Product.id == model.product_id).filter(model.business_id == int(business_id))
	if start:
		query = query.filter(model.occurred_on >= start)
	if end:
		query = query.filter(model.occurred_on <= end)
	items = [
		{
			"product_code": product.code,
			"product_name": product.name,
			"occurred_on": event.occurred_on.isoformat(),
			"quantity": float(D(event.quantity)),
			"production_order_id": getattr(event, "production_order_id", None),
			"line_id": getattr(event, "line_id", None),
		}
		for event, product in query.order_by(model.occurred_on.desc()).all()
	]
	return {
		"report_key": report_key,
		"items": items,
		"summary": {"count": len(items)},
		"pagination": {"total": len(items), "page": 1, "per_page": max(len(items), 1)},
		"meta": {"general_ledger_posting": "not_this_report"},
	}


def scrap_classified_report(db: Session, business_id: int, mode: str, *, date_from: Optional[str] = None, date_to: Optional[str] = None) -> Dict[str, Any]:
	"""ضایعاتی که با علت ثبت شده‌اند. فاکتور ضایعات هسته در این گزارش نیست."""
	_ensure(db, business_id)
	start = _parse_date(date_from) if date_from else None
	end = _parse_date(date_to) if date_to else None
	query = db.query(AdvancedProductionScrapEvent, AdvancedProductionScrapReason, Product).join(
		AdvancedProductionScrapReason, AdvancedProductionScrapReason.id == AdvancedProductionScrapEvent.reason_id
	).join(Product, Product.id == AdvancedProductionScrapEvent.product_id).filter(
		AdvancedProductionScrapEvent.business_id == int(business_id),
	)
	if mode == "recyclable":
		query = query.filter(AdvancedProductionScrapReason.recyclable.is_(True))
	elif mode == "nonrecyclable":
		query = query.filter(AdvancedProductionScrapReason.recyclable.is_(False))
	if start:
		query = query.filter(AdvancedProductionScrapEvent.occurred_on >= start)
	if end:
		query = query.filter(AdvancedProductionScrapEvent.occurred_on <= end)
	grouped: Dict[tuple, Dict[str, Any]] = {}
	for event, reason, product in query.all():
		key = (reason.id, product.id)
		item = grouped.setdefault(key, {
			"reason_code": reason.code,
			"reason_name": reason.name,
			"recyclable": bool(reason.recyclable),
			"product_code": product.code,
			"product_name": product.name,
			"quantity": Decimal("0"),
		})
		item["quantity"] += D(event.quantity)
	items = [{**item, "quantity": float(item["quantity"])} for item in grouped.values()]
	return {
		"report_key": "scrap_by_reason" if mode == "all" else f"{mode}_scrap",
		"items": items,
		"summary": {"count": len(items)},
		"pagination": {"total": len(items), "page": 1, "per_page": max(len(items), 1)},
		"meta": {"source": "recorded_scrap_events_not_waste_invoices", "general_ledger_posting": "not_this_report"},
	}


def qc_cause_report(db: Session, business_id: int, *, date_from: Optional[str] = None, date_to: Optional[str] = None) -> Dict[str, Any]:
	_ensure(db, business_id)
	start = _parse_date(date_from) if date_from else None
	end = _parse_date(date_to) if date_to else None
	query = db.query(AdvancedProductionInspection).filter(
		AdvancedProductionInspection.business_id == int(business_id),
		AdvancedProductionInspection.reason_code.isnot(None),
		AdvancedProductionInspection.reason_code != "",
	)
	if start:
		query = query.filter(AdvancedProductionInspection.inspected_on >= start)
	if end:
		query = query.filter(AdvancedProductionInspection.inspected_on <= end)
	grouped: Dict[str, Dict[str, Any]] = {}
	for row in query.all():
		if row.result != "fail" and D(row.quantity_rejected) <= 0:
			continue
		item = grouped.setdefault(row.reason_code, {
			"reason_code": row.reason_code,
			"quantity_rejected": Decimal("0"),
			"inspection_count": 0,
		})
		item["quantity_rejected"] += D(row.quantity_rejected)
		item["inspection_count"] += 1
	items = [{**item, "quantity_rejected": float(item["quantity_rejected"])} for item in grouped.values()]
	return {
		"report_key": "qc_causes",
		"items": items,
		"summary": {"count": len(items)},
		"pagination": {"total": len(items), "page": 1, "per_page": max(len(items), 1)},
		"meta": {"blank_reason_excluded": True},
	}


def _public(row: Any) -> Dict[str, Any]:
	data = {}
	for key in (
		"id", "code", "name", "is_active", "kind", "work_center_id", "line_id", "machine_id", "shift_id", "operator_person_id",
		"fixed_asset_id", "nominal_units_per_hour", "start_time", "end_time", "started_on", "ended_on",
		"minutes", "reason_code", "notes", "product_id", "produced_on", "run_minutes", "quantity_good",
		"quantity_scrap", "stage", "inspected_on", "quantity_checked", "quantity_rejected", "result", "reason_code",
		"maintenance_kind", "opened_on", "closed_on", "repair_minutes", "cost_amount",
		"recyclable", "reason_id", "occurred_on", "quantity",
		"production_order_id", "held_on", "released_on", "reason",
		"counted_on", "counted_quantity",
		"from_line_id", "to_line_id", "transferred_on",
		"person_id", "worked_on", "actual_hours", "standard_hours", "standard_hourly_rate", "actual_hourly_rate",
		"spare_product_id", "spare_quantity",
	):
		if not hasattr(row, key):
			continue
		value = getattr(row, key)
		if isinstance(value, Decimal):
			value = float(value)
		elif isinstance(value, date):
			value = value.isoformat()
		data[key] = value
	return data
