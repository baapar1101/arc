"""
گزارش‌های پیشرفته حقوق و دستمزد (فاز ۴).
"""
from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, List, Optional

from sqlalchemy import desc, func, distinct
from sqlalchemy.orm import Session

from adapters.db.models.payroll import (
	PayrollEmployee,
	PayrollItemDefinition,
	PayrollPeriod,
	PayrollRun,
	PayrollRunLine,
	PayrollRunLineItem,
)
from adapters.db.models.person import Person
from app.core.payroll_plugin_dependency import check_payroll_plugin_active
from app.core.responses import ApiError


def _ensure_plugin(db: Session, business_id: int) -> None:
	if not check_payroll_plugin_active(db, business_id):
		raise ApiError(
			"PAYROLL_PLUGIN_NOT_ACTIVE",
			"افزونه حقوق و دستمزد برای این کسب‌وکار فعال نیست.",
			http_status=403,
			details={"plugin_code": "payroll"},
		)


def _runs_filter_query(db: Session, business_id: int, *, period_id: Optional[int], run_id: Optional[int]):
	q = db.query(PayrollRun).filter(
		PayrollRun.business_id == business_id,
		PayrollRun.status.notin_(["draft", "cancelled"]),
	)
	if run_id is not None:
		q = q.filter(PayrollRun.id == int(run_id))
	if period_id is not None:
		q = q.filter(PayrollRun.period_id == int(period_id))
	return q


def get_item_summary_report(
	db: Session,
	business_id: int,
	*,
	period_id: Optional[int] = None,
	run_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	if period_id is None and run_id is None:
		raise ApiError("FILTER_REQUIRED", "period_id یا run_id الزامی است.", http_status=400)

	run_ids = [r.id for r in _runs_filter_query(db, business_id, period_id=period_id, run_id=run_id).all()]
	if not run_ids:
		return {"period_id": period_id, "run_id": run_id, "items": [], "totals": {}}

	rows = (
		db.query(
			PayrollItemDefinition.id,
			PayrollItemDefinition.code,
			PayrollItemDefinition.name,
			PayrollItemDefinition.item_kind,
			func.coalesce(func.sum(PayrollRunLineItem.amount), 0),
			func.count(PayrollRunLineItem.id),
		)
		.join(PayrollRunLineItem, PayrollRunLineItem.item_definition_id == PayrollItemDefinition.id)
		.join(PayrollRunLine, PayrollRunLine.id == PayrollRunLineItem.run_line_id)
		.filter(PayrollRunLine.run_id.in_(run_ids))
		.group_by(
			PayrollItemDefinition.id,
			PayrollItemDefinition.code,
			PayrollItemDefinition.name,
			PayrollItemDefinition.item_kind,
		)
		.order_by(PayrollItemDefinition.sort_order, PayrollItemDefinition.id)
		.all()
	)

	items = []
	total_amount = Decimal("0")
	for iid, code, name, kind, total, cnt in rows:
		amt = Decimal(str(total or 0))
		total_amount += amt
		items.append(
			{
				"item_id": iid,
				"item_code": code,
				"item_name": name,
				"item_kind": kind,
				"line_item_count": int(cnt),
				"total_amount": float(amt),
			}
		)

	return {
		"period_id": period_id,
		"run_id": run_id,
		"items": items,
		"totals": {"total_amount": float(total_amount)},
	}


def get_employee_summary_report(
	db: Session,
	business_id: int,
	*,
	period_id: Optional[int] = None,
	run_id: Optional[int] = None,
	limit: int = 500,
	skip: int = 0,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	if period_id is None and run_id is None:
		raise ApiError("FILTER_REQUIRED", "period_id یا run_id الزامی است.", http_status=400)

	q = (
		db.query(
			PayrollEmployee.id,
			PayrollEmployee.employee_code,
			Person.name,
			func.coalesce(func.sum(PayrollRunLine.gross_amount), 0),
			func.coalesce(func.sum(PayrollRunLine.deduction_amount), 0),
			func.coalesce(func.sum(PayrollRunLine.net_amount), 0),
			func.coalesce(func.sum(PayrollRunLine.employer_cost_amount), 0),
			func.count(PayrollRunLine.id),
		)
		.select_from(PayrollRunLine)
		.join(PayrollRun, PayrollRun.id == PayrollRunLine.run_id)
		.join(PayrollEmployee, PayrollEmployee.id == PayrollRunLine.employee_id)
		.join(Person, Person.id == PayrollRunLine.person_id)
		.filter(PayrollRun.business_id == business_id, PayrollRun.status.notin_(["draft", "cancelled"]))
	)
	if run_id is not None:
		q = q.filter(PayrollRun.id == int(run_id))
	if period_id is not None:
		q = q.filter(PayrollRun.period_id == int(period_id))

	q = q.group_by(PayrollEmployee.id, PayrollEmployee.employee_code, Person.name)
	total = (
		db.query(func.count(distinct(PayrollEmployee.id)))
		.select_from(PayrollRunLine)
		.join(PayrollRun, PayrollRun.id == PayrollRunLine.run_id)
		.join(PayrollEmployee, PayrollEmployee.id == PayrollRunLine.employee_id)
		.filter(PayrollRun.business_id == business_id, PayrollRun.status.notin_(["draft", "cancelled"]))
	)
	if run_id is not None:
		total = total.filter(PayrollRun.id == int(run_id))
	if period_id is not None:
		total = total.filter(PayrollRun.period_id == int(period_id))
	total_count = int(total.scalar() or 0)
	rows = q.order_by(PayrollEmployee.employee_code).offset(skip).limit(limit).all()

	items = [
		{
			"employee_id": eid,
			"employee_code": code,
			"person_name": pname,
			"gross_total": float(gross or 0),
			"deduction_total": float(ded or 0),
			"net_total": float(net or 0),
			"employer_cost_total": float(emp or 0),
			"line_count": int(cnt),
		}
		for eid, code, pname, gross, ded, net, emp, cnt in rows
	]

	return {
		"period_id": period_id,
		"run_id": run_id,
		"items": items,
		"total": total_count,
		"skip": skip,
		"limit": limit,
	}


def get_statutory_summary_report(
	db: Session,
	business_id: int,
	*,
	period_id: Optional[int] = None,
	run_id: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	item_report = get_item_summary_report(db, business_id, period_id=period_id, run_id=run_id)
	by_code = {row["item_code"]: row for row in item_report.get("items") or []}

	ins_emp = by_code.get("insurance_employee", {}).get("total_amount", 0)
	ins_er = by_code.get("insurance_employer", {}).get("total_amount", 0)
	tax = by_code.get("tax", {}).get("total_amount", 0)
	gross = sum(
		row.get("total_amount", 0)
		for row in item_report.get("items") or []
		if row.get("item_kind") == "earning"
	)

	return {
		"period_id": period_id,
		"run_id": run_id,
		"gross_earnings_total": gross,
		"insurance_employee_total": ins_emp,
		"insurance_employer_total": ins_er,
		"tax_total": tax,
		"net_employer_statutory_cost": float(ins_er),
	}


def get_period_overview_report(
	db: Session,
	business_id: int,
	*,
	year: Optional[int] = None,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	periods_q = db.query(PayrollPeriod).filter(PayrollPeriod.business_id == business_id)
	if year is not None:
		periods_q = periods_q.filter(PayrollPeriod.year == int(year))
	periods = periods_q.order_by(PayrollPeriod.year, PayrollPeriod.month).all()

	items: List[Dict[str, Any]] = []
	for period in periods:
		agg = (
			db.query(
				func.count(PayrollRun.id),
				func.coalesce(func.sum(PayrollRun.gross_total), 0),
				func.coalesce(func.sum(PayrollRun.deduction_total), 0),
				func.coalesce(func.sum(PayrollRun.net_total), 0),
				func.coalesce(func.sum(PayrollRun.employer_cost_total), 0),
			)
			.filter(
				PayrollRun.business_id == business_id,
				PayrollRun.period_id == period.id,
				PayrollRun.status.notin_(["draft", "cancelled"]),
			)
			.one()
		)
		run_count, gross, ded, net, employer = agg
		items.append(
			{
				"period_id": period.id,
				"year": period.year,
				"month": period.month,
				"title": period.title,
				"status": period.status,
				"run_count": int(run_count or 0),
				"gross_total": float(gross or 0),
				"deduction_total": float(ded or 0),
				"net_total": float(net or 0),
				"employer_cost_total": float(employer or 0),
			}
		)

	totals = {
		"gross_total": sum(i["gross_total"] for i in items),
		"deduction_total": sum(i["deduction_total"] for i in items),
		"net_total": sum(i["net_total"] for i in items),
		"employer_cost_total": sum(i["employer_cost_total"] for i in items),
		"run_count": sum(i["run_count"] for i in items),
	}

	return {"year": year, "periods": items, "totals": totals}
