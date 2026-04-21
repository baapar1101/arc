from __future__ import annotations

import json
import logging
import math
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, List, Optional, Tuple

from datetime import datetime

from sqlalchemy import and_, desc
from sqlalchemy.orm import Session

from adapters.db.models.customer_club import (
	CustomerClubBalance,
	CustomerClubInvoiceSnapshot,
	CustomerClubLedger,
	CustomerClubSettings,
	CustomerClubTier,
)
from adapters.db.models.business import Business
from adapters.db.models.document import Document
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.person import Person, PersonType
from app.core.customer_club_plugin_dependency import check_customer_club_plugin_active
from app.core.responses import ApiError
from app.services.invoice_service import INVOICE_SALES, INVOICE_SALES_RETURN

logger = logging.getLogger(__name__)


def _settings_to_dict(row: CustomerClubSettings) -> Dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"enabled": bool(row.enabled),
		"earn_mode": row.earn_mode,
		"amount_basis": row.amount_basis,
		"percent_of_basis": float(row.percent_of_basis) if row.percent_of_basis is not None else None,
		"step_currency_amount": float(row.step_currency_amount) if row.step_currency_amount is not None else None,
		"points_per_step": float(row.points_per_step) if row.points_per_step is not None else None,
		"rounding_mode": row.rounding_mode,
		"max_points_per_invoice": float(row.max_points_per_invoice) if row.max_points_per_invoice is not None else None,
		"min_basis_amount": float(row.min_basis_amount),
		"require_customer_person_type": bool(row.require_customer_person_type),
		"currency_value_per_point": float(row.currency_value_per_point) if getattr(row, "currency_value_per_point", None) is not None else None,
		"max_redeem_points_per_invoice": float(row.max_redeem_points_per_invoice)
		if getattr(row, "max_redeem_points_per_invoice", None) is not None
		else None,
		"points_expire_after_days": int(row.points_expire_after_days)
		if getattr(row, "points_expire_after_days", None) is not None
		else None,
		"rfm_analytics_enabled": bool(getattr(row, "rfm_analytics_enabled", False)),
		"clv_analytics_enabled": bool(getattr(row, "clv_analytics_enabled", False)),
		"rfm_analysis_window_months": int(getattr(row, "rfm_analysis_window_months", 12) or 12),
		"rfm_monetary_basis": getattr(row, "rfm_monetary_basis", None) or "net",
		"rfm_scoring_method": getattr(row, "rfm_scoring_method", None) or "quintiles",
		"rfm_weight_recency": float(row.rfm_weight_recency) if getattr(row, "rfm_weight_recency", None) is not None else None,
		"rfm_weight_frequency": float(row.rfm_weight_frequency)
		if getattr(row, "rfm_weight_frequency", None) is not None
		else None,
		"rfm_weight_monetary": float(row.rfm_weight_monetary)
		if getattr(row, "rfm_weight_monetary", None) is not None
		else None,
		"clv_formula": getattr(row, "clv_formula", None) or "historical_total",
		"clv_avg_lifespan_years": float(row.clv_avg_lifespan_years)
		if getattr(row, "clv_avg_lifespan_years", None) is not None
		else None,
		"rfm_segment_labels_json": getattr(row, "rfm_segment_labels_json", None),
	}


def _default_settings_row(db: Session, business_id: int) -> CustomerClubSettings:
	row = CustomerClubSettings(
		business_id=business_id,
		enabled=True,
		earn_mode="percent_basis",
		amount_basis="net",
		percent_of_basis=Decimal("1"),
		step_currency_amount=None,
		points_per_step=None,
		rounding_mode="floor",
		max_points_per_invoice=None,
		min_basis_amount=Decimal("0"),
		require_customer_person_type=True,
		rfm_analytics_enabled=False,
		clv_analytics_enabled=False,
		rfm_analysis_window_months=12,
		rfm_monetary_basis="net",
		rfm_scoring_method="quintiles",
		clv_formula="historical_total",
		clv_avg_lifespan_years=Decimal("3"),
	)
	db.add(row)
	db.flush()
	return row


def get_settings(db: Session, business_id: int) -> Dict[str, Any]:
	row = db.query(CustomerClubSettings).filter(CustomerClubSettings.business_id == business_id).first()
	if not row:
		row = _default_settings_row(db, business_id)
		db.commit()
		db.refresh(row)
	return _settings_to_dict(row)


def update_settings(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	row = db.query(CustomerClubSettings).filter(CustomerClubSettings.business_id == business_id).first()
	if not row:
		row = _default_settings_row(db, business_id)

	if "enabled" in payload:
		row.enabled = bool(payload["enabled"])
	if "earn_mode" in payload:
		em = str(payload["earn_mode"]).strip()
		if em not in ("percent_basis", "points_per_currency"):
			raise ApiError(
				"CUSTOMER_CLUB_INVALID_EARN_MODE",
				"earn_mode must be percent_basis or points_per_currency.",
				http_status=400,
			)
		row.earn_mode = em
	if "amount_basis" in payload:
		ab = str(payload["amount_basis"]).strip()
		if ab not in ("net", "total_with_tax"):
			raise ApiError(
				"CUSTOMER_CLUB_INVALID_AMOUNT_BASIS",
				"amount_basis must be net or total_with_tax.",
				http_status=400,
			)
		row.amount_basis = ab
	if "percent_of_basis" in payload:
		v = payload["percent_of_basis"]
		row.percent_of_basis = Decimal(str(v)) if v is not None else None
	if "step_currency_amount" in payload:
		v = payload["step_currency_amount"]
		row.step_currency_amount = Decimal(str(v)) if v is not None else None
	if "points_per_step" in payload:
		v = payload["points_per_step"]
		row.points_per_step = Decimal(str(v)) if v is not None else None
	if "rounding_mode" in payload:
		rm = str(payload["rounding_mode"]).strip()
		if rm not in ("floor", "ceil", "round"):
			raise ApiError(
				"CUSTOMER_CLUB_INVALID_ROUNDING_MODE",
				"rounding_mode must be floor, ceil, or round.",
				http_status=400,
			)
		row.rounding_mode = rm
	if "max_points_per_invoice" in payload:
		v = payload["max_points_per_invoice"]
		row.max_points_per_invoice = Decimal(str(v)) if v is not None else None
	if "min_basis_amount" in payload:
		row.min_basis_amount = Decimal(str(payload["min_basis_amount"]))
	if "require_customer_person_type" in payload:
		row.require_customer_person_type = bool(payload["require_customer_person_type"])
	if "currency_value_per_point" in payload:
		v = payload["currency_value_per_point"]
		row.currency_value_per_point = Decimal(str(v)) if v is not None else None
	if "max_redeem_points_per_invoice" in payload:
		v = payload["max_redeem_points_per_invoice"]
		row.max_redeem_points_per_invoice = Decimal(str(v)) if v is not None else None
	if "points_expire_after_days" in payload:
		v = payload["points_expire_after_days"]
		row.points_expire_after_days = int(v) if v is not None else None

	if "rfm_analytics_enabled" in payload:
		row.rfm_analytics_enabled = bool(payload["rfm_analytics_enabled"])
	if "clv_analytics_enabled" in payload:
		row.clv_analytics_enabled = bool(payload["clv_analytics_enabled"])
	if "rfm_analysis_window_months" in payload:
		wm = int(payload["rfm_analysis_window_months"])
		if wm < 1 or wm > 120:
			raise ApiError(
				"CUSTOMER_CLUB_RFM_WINDOW_INVALID",
				"rfm_analysis_window_months must be between 1 and 120.",
				http_status=400,
			)
		row.rfm_analysis_window_months = wm
	if "rfm_monetary_basis" in payload:
		mb = str(payload["rfm_monetary_basis"]).strip()
		if mb not in ("net", "total_with_tax"):
			raise ApiError(
				"CUSTOMER_CLUB_RFM_MONETARY_BASIS_INVALID",
				"rfm_monetary_basis must be net or total_with_tax.",
				http_status=400,
			)
		row.rfm_monetary_basis = mb
	if "rfm_scoring_method" in payload:
		sm = str(payload["rfm_scoring_method"]).strip()
		if sm not in ("quintiles", "weighted"):
			raise ApiError(
				"CUSTOMER_CLUB_RFM_SCORING_INVALID",
				"rfm_scoring_method must be quintiles or weighted.",
				http_status=400,
			)
		row.rfm_scoring_method = sm
	if "rfm_weight_recency" in payload:
		v = payload["rfm_weight_recency"]
		row.rfm_weight_recency = Decimal(str(v)) if v is not None else None
	if "rfm_weight_frequency" in payload:
		v = payload["rfm_weight_frequency"]
		row.rfm_weight_frequency = Decimal(str(v)) if v is not None else None
	if "rfm_weight_monetary" in payload:
		v = payload["rfm_weight_monetary"]
		row.rfm_weight_monetary = Decimal(str(v)) if v is not None else None
	if "clv_formula" in payload:
		cf = str(payload["clv_formula"]).strip()
		if cf not in ("historical_total", "avg_order_projection"):
			raise ApiError(
				"CUSTOMER_CLUB_CLV_FORMULA_INVALID",
				"clv_formula must be historical_total or avg_order_projection.",
				http_status=400,
			)
		row.clv_formula = cf
	if "clv_avg_lifespan_years" in payload:
		v = payload["clv_avg_lifespan_years"]
		row.clv_avg_lifespan_years = Decimal(str(v)) if v is not None else None
	if "rfm_segment_labels_json" in payload:
		row.rfm_segment_labels_json = payload["rfm_segment_labels_json"]

	db.commit()
	db.refresh(row)
	return _settings_to_dict(row)


def _person_is_customer(person: Person) -> bool:
	try:
		types_list = json.loads(person.person_types) if person.person_types else []
	except json.JSONDecodeError:
		types_list = []
	return PersonType.CUSTOMER.value in types_list


def _basis_net_and_total_from_document(db: Session, doc: Document) -> Tuple[Decimal, Decimal]:
	"""خواندن خالص و جمع با مالیات از totals؛ در صورت غیبت، تقریب از خطوط اقلام."""
	extra = doc.extra_info or {}
	totals = extra.get("totals") if isinstance(extra, dict) else None
	line_sum_netish = Decimal("0")
	item_lines = db.query(InvoiceItemLine).filter(InvoiceItemLine.document_id == doc.id).all()
	for item_line in item_lines:
		ex = item_line.extra_info or {}
		line_total = ex.get("line_total")
		try:
			if line_total is not None:
				line_sum_netish += abs(Decimal(str(line_total)))
				continue
			qty = Decimal(str(item_line.quantity or 0))
			unit_price = Decimal(str(ex.get("unit_price", 0)))
			line_discount = Decimal(str(ex.get("line_discount", 0)))
			tax_amount = Decimal(str(ex.get("tax_amount", 0)))
			line_sum_netish += abs((qty * unit_price) - line_discount + tax_amount)
		except (InvalidOperation, ValueError):
			continue

	if isinstance(totals, dict):
		try:
			net_dec = Decimal(str(totals.get("net") if totals.get("net") is not None else "0"))
		except (InvalidOperation, ValueError):
			net_dec = Decimal("0")
		try:
			tax_dec = Decimal(str(totals.get("tax") if totals.get("tax") is not None else "0"))
		except (InvalidOperation, ValueError):
			tax_dec = Decimal("0")
		net_abs = abs(net_dec)
		total_abs = abs(net_dec + tax_dec)
		return net_abs, total_abs

	return line_sum_netish, line_sum_netish


def _resolved_basis_amount(settings: CustomerClubSettings, db: Session, doc: Document) -> Decimal:
	net_b, total_b = _basis_net_and_total_from_document(db, doc)
	return total_b if settings.amount_basis == "total_with_tax" else net_b


def _apply_round(mode: str, value: Decimal) -> Decimal:
	if mode == "ceil":
		return Decimal(math.ceil(float(value)))
	if mode == "round":
		return Decimal(round(float(value)))
	return Decimal(math.floor(float(value)))


def _compute_points_for_amount(
	settings: CustomerClubSettings,
	basis_amount: Decimal,
	direction_sign: int,
) -> Decimal:
	if basis_amount < Decimal(str(settings.min_basis_amount)):
		return Decimal("0")

	if settings.earn_mode == "percent_basis":
		pct = settings.percent_of_basis or Decimal("0")
		raw = basis_amount * (pct / Decimal("100"))
	elif settings.earn_mode == "points_per_currency":
		step = settings.step_currency_amount or Decimal("1")
		pps = settings.points_per_step or Decimal("0")
		if step <= 0:
			raw = Decimal("0")
		else:
			raw = (basis_amount / step) * pps
	else:
		raw = Decimal("0")

	pts = _apply_round(settings.rounding_mode, raw)
	if direction_sign < 0:
		pts = -pts
	mx = settings.max_points_per_invoice
	if mx is not None and mx >= 0:
		cap = abs(mx)
		if pts > cap:
			pts = cap if pts > 0 else -cap
	return pts


def _locked_balance_row(db: Session, business_id: int, person_id: int) -> CustomerClubBalance:
	q = (
		db.query(CustomerClubBalance)
		.filter(
			and_(
				CustomerClubBalance.business_id == business_id,
				CustomerClubBalance.person_id == person_id,
			)
		)
		.with_for_update()
	)
	row = q.first()
	if row is None:
		row = CustomerClubBalance(
			business_id=business_id,
			person_id=person_id,
			balance_points=Decimal("0"),
		)
		db.add(row)
		db.flush()
		row = (
			db.query(CustomerClubBalance)
			.filter(
				and_(
					CustomerClubBalance.business_id == business_id,
					CustomerClubBalance.person_id == person_id,
				)
			)
			.with_for_update()
			.first()
		)
	return row


def _append_ledger(
	db: Session,
	*,
	business_id: int,
	person_id: Optional[int],
	delta_points: Decimal,
	balance_after: Decimal,
	transaction_type: str,
	reference_document_id: Optional[int] = None,
	description: Optional[str] = None,
	created_by_user_id: Optional[int] = None,
) -> CustomerClubLedger:
	entry = CustomerClubLedger(
		business_id=business_id,
		person_id=person_id,
		delta_points=delta_points,
		balance_after=balance_after,
		transaction_type=transaction_type,
		reference_document_id=reference_document_id,
		description=description,
		created_by_user_id=created_by_user_id,
	)
	db.add(entry)
	return entry


def user_can_redeem_loyalty_points(db: Session, user_id: int, business_id: int) -> bool:
	"""مالک کسب‌وکار یا customer_club.redeem در JSON دسترسی."""
	biz = db.query(Business).filter(Business.id == business_id).first()
	if biz and int(biz.owner_id) == int(user_id):
		return True
	from adapters.db.models.business_permission import BusinessPermission

	row = (
		db.query(BusinessPermission)
		.filter(
			and_(
				BusinessPermission.user_id == int(user_id),
				BusinessPermission.business_id == int(business_id),
			)
		)
		.first()
	)
	if not row or not row.business_permissions:
		return False
	cc = (row.business_permissions or {}).get("customer_club") or {}
	return bool(cc.get("redeem") is True)


def _earn_tier_multiplier(db: Session, business_id: int, person_id: int) -> Decimal:
	rows = (
		db.query(CustomerClubTier)
		.filter(CustomerClubTier.business_id == int(business_id))
		.order_by(CustomerClubTier.sort_order.asc(), CustomerClubTier.min_balance_points.asc(), CustomerClubTier.id.asc())
		.all()
	)
	if not rows:
		return Decimal("1")
	bal_row = (
		db.query(CustomerClubBalance)
		.filter(
			and_(
				CustomerClubBalance.business_id == int(business_id),
				CustomerClubBalance.person_id == int(person_id),
			)
		)
		.first()
	)
	bal = bal_row.balance_points if bal_row else Decimal("0")
	best = Decimal("1")
	for t in rows:
		if bal >= (t.min_balance_points or Decimal("0")):
			m = t.earn_multiplier or Decimal("1")
			if m > 0:
				best = m
	return best


def maybe_apply_loyalty_redemption_to_invoice_payload(
	db: Session,
	business_id: int,
	invoice_type: str,
	is_proforma: bool,
	person_id: Optional[int],
	totals: Dict[str, Any],
	header_extra: Dict[str, Any],
	data: Dict[str, Any],
	user_id: int,
) -> None:
	"""قبل از ذخیره فاکتور: افزایش تخفیف و کاهش مالیات به نسبت مبنای جدید. extra_info.customer_club پر می‌شود."""
	raw_pts = data.get("loyalty_redemption_points")
	if raw_pts is None:
		return
	try:
		redeem_pts = Decimal(str(raw_pts))
	except Exception:
		raise ApiError(
			"INVALID_LOYALTY_POINTS",
			"loyalty_redemption_points is invalid.",
			http_status=400,
		)
	if redeem_pts <= 0:
		if raw_pts is not None:
			ccz = dict(header_extra.get("customer_club") or {})
			ccz.pop("redeem_points_requested", None)
			ccz.pop("redeem_discount_amount", None)
			if ccz:
				header_extra["customer_club"] = ccz
			else:
				header_extra.pop("customer_club", None)
		return
	if invoice_type != INVOICE_SALES or is_proforma:
		raise ApiError(
			"LOYALTY_REDEEM_NOT_ALLOWED",
			"Loyalty redemption is only allowed on finalized sales invoices.",
			http_status=400,
		)
	if not person_id:
		raise ApiError(
			"LOYALTY_REDEEM_NO_PERSON",
			"Invoice must have a person to redeem loyalty points.",
			http_status=400,
		)
	if not check_customer_club_plugin_active(db, business_id):
		raise ApiError(
			"CUSTOMER_CLUB_PLUGIN_NOT_ACTIVE",
			"Customer club add-on is not active for this business.",
			http_status=403,
		)
	if not user_can_redeem_loyalty_points(db, user_id, business_id):
		raise ApiError(
			"LOYALTY_REDEEM_PERMISSION",
			"You do not have permission to redeem loyalty points (customer_club.redeem).",
			http_status=403,
		)

	settings_row = db.query(CustomerClubSettings).filter(CustomerClubSettings.business_id == business_id).first()
	if not settings_row:
		settings_row = _default_settings_row(db, business_id)
		db.flush()
	if not settings_row.enabled:
		raise ApiError(
			"CUSTOMER_CLUB_DISABLED",
			"Customer club is disabled for this business.",
			http_status=400,
		)
	cv = getattr(settings_row, "currency_value_per_point", None) or Decimal("0")
	if cv <= 0:
		raise ApiError(
			"LOYALTY_RATE_MISSING",
			"currency_value_per_point is not set in customer club settings.",
			http_status=400,
		)

	mx = getattr(settings_row, "max_redeem_points_per_invoice", None)
	if mx is not None and redeem_pts > mx:
		raise ApiError(
			"LOYALTY_REDEEM_CAP",
			f"Maximum redeemable points per invoice is {mx}.",
			http_status=400,
		)

	bal_row = (
		db.query(CustomerClubBalance)
		.filter(
			and_(
				CustomerClubBalance.business_id == business_id,
				CustomerClubBalance.person_id == int(person_id),
			)
		)
		.with_for_update()
		.first()
	)
	cur_bal = bal_row.balance_points if bal_row else Decimal("0")
	if redeem_pts > cur_bal:
		raise ApiError(
			"LOYALTY_INSUFFICIENT_BALANCE",
			"Customer does not have enough loyalty points.",
			http_status=400,
		)

	discount_add = (redeem_pts * cv).quantize(Decimal("0.01"))
	gross = Decimal(str(totals.get("gross", 0)))
	old_disc = Decimal(str(totals.get("discount", 0)))
	old_tax = Decimal(str(totals.get("tax", 0)))
	old_net = gross - old_disc
	new_disc = old_disc + discount_add
	new_net = gross - new_disc
	if new_net < 0:
		raise ApiError(
			"LOYALTY_DISCOUNT_TOO_HIGH",
			"Loyalty discount exceeds the invoice net amount.",
			http_status=400,
		)
	new_tax = old_tax
	if old_net > 0 and new_net >= 0:
		new_tax = (old_tax * (new_net / old_net)).quantize(Decimal("0.01"))

	totals["discount"] = float(new_disc)
	totals["net"] = float(new_net)
	totals["tax"] = float(new_tax)
	header_extra["totals"] = totals
	cc = dict(header_extra.get("customer_club") or {})
	cc["redeem_points_requested"] = float(redeem_pts)
	cc["redeem_discount_amount"] = float(discount_add)
	header_extra["customer_club"] = cc


def commit_loyalty_redemption_for_sales_invoice(db: Session, document: Document, user_id: int) -> None:
	"""پس از ایجاد/به‌روزرسانی سند و پیش از commit نهایی: اعمال تفاضل امتیاز مصرف‌شده نسبت به snapshot قبلی."""
	if document.is_proforma or document.document_type != INVOICE_SALES:
		return
	if not check_customer_club_plugin_active(db, int(document.business_id)):
		return
	extra = dict(document.extra_info or {})
	cc = extra.get("customer_club") or {}
	try:
		new_pts = Decimal(str(cc.get("redeem_points_requested") or 0))
	except Exception:
		new_pts = Decimal("0")

	pid = extra.get("person_id")
	try:
		person_id = int(pid) if pid is not None else None
	except (TypeError, ValueError):
		person_id = None

	snap_existing = (
		db.query(CustomerClubInvoiceSnapshot).filter(CustomerClubInvoiceSnapshot.document_id == document.id).first()
	)
	old_redeemed = snap_existing.redeemed_points if snap_existing else Decimal("0")

	if new_pts <= 0 and old_redeemed <= 0:
		return

	if new_pts <= 0 < old_redeemed:
		rpid = person_id or (snap_existing.person_id if snap_existing else None)
		if not rpid:
			return
		bal = _locked_balance_row(db, int(document.business_id), int(rpid))
		cur = bal.balance_points + old_redeemed
		bal.balance_points = cur
		bal.updated_at = datetime.utcnow()
		_append_ledger(
			db,
			business_id=int(document.business_id),
			person_id=int(rpid),
			delta_points=old_redeemed,
			balance_after=cur,
			transaction_type="redeem_void",
			reference_document_id=int(document.id),
			description=f"لغو مصرف امتیاز در فاکتور {document.code}",
			created_by_user_id=user_id,
		)
		if snap_existing:
			snap_existing.redeemed_points = Decimal("0")
			snap_existing.person_id = int(rpid)
		db.flush()
		return

	if not person_id:
		return

	delta = new_pts - old_redeemed
	if delta == 0:
		if snap_existing:
			snap_existing.person_id = person_id
		db.flush()
		return

	bal = _locked_balance_row(db, int(document.business_id), person_id)
	if delta > 0 and bal.balance_points < delta:
		raise ApiError(
			"LOYALTY_INSUFFICIENT_BALANCE_AT_COMMIT",
			"Insufficient loyalty points at save time.",
			http_status=409,
		)
	new_bal = bal.balance_points - delta
	bal.balance_points = new_bal
	bal.updated_at = datetime.utcnow()
	_append_ledger(
		db,
		business_id=int(document.business_id),
		person_id=person_id,
		delta_points=-delta,
		balance_after=new_bal,
		transaction_type="redeem",
		reference_document_id=int(document.id),
		description=f"مصرف امتیاز در فاکتور {document.code}",
		created_by_user_id=user_id,
	)
	if snap_existing:
		snap_existing.redeemed_points = new_pts
		snap_existing.person_id = person_id
	else:
		db.add(
			CustomerClubInvoiceSnapshot(
				document_id=document.id,
				business_id=document.business_id,
				person_id=person_id,
				accrued_points=Decimal("0"),
				redeemed_points=new_pts,
			)
		)
	db.flush()


def sync_customer_club_for_invoice(db: Session, document_id: int) -> None:
	"""همگام‌سازی امتیاز با یک سند فاکتور قطعی (فروش یا برگشت از فروش)."""
	doc = db.query(Document).filter(Document.id == document_id).first()
	if not doc:
		return
	if doc.is_proforma:
		return
	if doc.document_type not in (INVOICE_SALES, INVOICE_SALES_RETURN):
		return
	if not check_customer_club_plugin_active(db, int(doc.business_id)):
		return

	fy = db.query(FiscalYear).filter(FiscalYear.id == doc.fiscal_year_id).first()
	if fy is not None and getattr(fy, "is_last", False) is not True:
		return

	settings_row = db.query(CustomerClubSettings).filter(CustomerClubSettings.business_id == doc.business_id).first()
	if not settings_row:
		settings_row = _default_settings_row(db, doc.business_id)
		db.flush()
		db.refresh(settings_row)
	if not settings_row.enabled:
		return

	extra = doc.extra_info or {}
	pid = extra.get("person_id") if isinstance(extra, dict) else None
	try:
		person_id = int(pid) if pid is not None else None
	except (TypeError, ValueError):
		person_id = None
	if not person_id:
		return

	person = db.query(Person).filter(and_(Person.id == person_id, Person.business_id == doc.business_id)).first()
	if not person:
		return
	if settings_row.require_customer_person_type and not _person_is_customer(person):
		return

	basis = _resolved_basis_amount(settings_row, db, doc)

	direction = 1 if doc.document_type == INVOICE_SALES else -1
	target_pts = _compute_points_for_amount(settings_row, basis, direction)
	if doc.document_type == INVOICE_SALES and direction > 0:
		tm = _earn_tier_multiplier(db, int(doc.business_id), int(person_id))
		target_pts = (target_pts * tm).quantize(Decimal("0.000001"))

	snap = db.query(CustomerClubInvoiceSnapshot).filter(CustomerClubInvoiceSnapshot.document_id == doc.id).first()
	old_pts = snap.accrued_points if snap else Decimal("0")
	delta = target_pts - old_pts
	if delta == Decimal("0"):
		if snap:
			snap.person_id = person_id
			snap.accrued_points = target_pts
		else:
			db.add(
				CustomerClubInvoiceSnapshot(
					document_id=doc.id,
					business_id=doc.business_id,
					person_id=person_id,
					accrued_points=target_pts,
				)
			)
		db.flush()
		return

	bal = _locked_balance_row(db, doc.business_id, person_id)
	new_bal = bal.balance_points + delta
	bal.balance_points = new_bal
	bal.updated_at = datetime.utcnow()

	desc = (
		f"همگام امتیاز با فاکتور {doc.code}"
		if doc.document_type == INVOICE_SALES
		else f"همگام امتیاز با برگشت از فروش {doc.code}"
	)
	_append_ledger(
		db,
		business_id=doc.business_id,
		person_id=person_id,
		delta_points=delta,
		balance_after=new_bal,
		transaction_type="invoice_sync",
		reference_document_id=doc.id,
		description=desc,
	)

	if snap:
		snap.accrued_points = target_pts
		snap.person_id = person_id
	else:
		db.add(
			CustomerClubInvoiceSnapshot(
				document_id=doc.id,
				business_id=doc.business_id,
				person_id=person_id,
				accrued_points=target_pts,
			)
		)
	db.flush()


def reverse_customer_club_on_invoice_delete(db: Session, document_id: int, business_id: int) -> None:
	if not check_customer_club_plugin_active(db, business_id):
		return
	snap = (
		db.query(CustomerClubInvoiceSnapshot)
		.filter(
			and_(
				CustomerClubInvoiceSnapshot.document_id == document_id,
				CustomerClubInvoiceSnapshot.business_id == business_id,
			)
		)
		.first()
	)
	if not snap:
		return
	pid = snap.person_id
	if not pid:
		return

	redeemed = getattr(snap, "redeemed_points", None) or Decimal("0")
	accrued = snap.accrued_points or Decimal("0")
	if redeemed <= 0 and accrued == Decimal("0"):
		return

	bal = _locked_balance_row(db, business_id, pid)
	cur = bal.balance_points

	if redeemed > 0:
		cur = cur + redeemed
		bal.balance_points = cur
		bal.updated_at = datetime.utcnow()
		_append_ledger(
			db,
			business_id=business_id,
			person_id=pid,
			delta_points=redeemed,
			balance_after=cur,
			transaction_type="invoice_delete_reversal_redeem",
			reference_document_id=document_id,
			description="برگشت امتیاز مصرف‌شده به دلیل حذف فاکتور",
		)

	if accrued != Decimal("0"):
		delta = -accrued
		cur = cur + delta
		bal.balance_points = cur
		bal.updated_at = datetime.utcnow()
		_append_ledger(
			db,
			business_id=business_id,
			person_id=pid,
			delta_points=delta,
			balance_after=cur,
			transaction_type="invoice_delete_reversal",
			reference_document_id=document_id,
			description="برگشت امتیاز به دلیل حذف فاکتور",
		)
	db.flush()


def get_person_balance(db: Session, business_id: int, person_id: int) -> Dict[str, Any]:
	row = (
		db.query(CustomerClubBalance)
		.filter(
			and_(CustomerClubBalance.business_id == business_id, CustomerClubBalance.person_id == person_id)
		)
		.first()
	)
	bal = row.balance_points if row else Decimal("0")
	return {"person_id": person_id, "balance_points": float(bal)}


def list_ledger(
	db: Session,
	business_id: int,
	*,
	person_id: Optional[int] = None,
	limit: int = 50,
	skip: int = 0,
) -> Tuple[List[Dict[str, Any]], int]:
	q = db.query(CustomerClubLedger).filter(CustomerClubLedger.business_id == business_id)
	if person_id is not None:
		q = q.filter(CustomerClubLedger.person_id == person_id)
	total = q.count()
	rows = (
		q.order_by(desc(CustomerClubLedger.created_at), desc(CustomerClubLedger.id))
		.offset(skip)
		.limit(limit)
		.all()
	)
	out: List[Dict[str, Any]] = []
	for r in rows:
		out.append(
			{
				"id": r.id,
				"person_id": r.person_id,
				"delta_points": float(r.delta_points),
				"balance_after": float(r.balance_after),
				"transaction_type": r.transaction_type,
				"reference_document_id": r.reference_document_id,
				"description": r.description,
				"created_by_user_id": r.created_by_user_id,
				"created_at": r.created_at.isoformat() if r.created_at else None,
			}
		)
	return out, total


def list_tiers(db: Session, business_id: int) -> List[Dict[str, Any]]:
	rows = (
		db.query(CustomerClubTier)
		.filter(CustomerClubTier.business_id == int(business_id))
		.order_by(CustomerClubTier.sort_order.asc(), CustomerClubTier.min_balance_points.asc(), CustomerClubTier.id.asc())
		.all()
	)
	return [
		{
			"id": r.id,
			"sort_order": r.sort_order,
			"name": r.name,
			"min_balance_points": float(r.min_balance_points),
			"earn_multiplier": float(r.earn_multiplier),
		}
		for r in rows
	]


def replace_tiers(db: Session, business_id: int, items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
	db.query(CustomerClubTier).filter(CustomerClubTier.business_id == int(business_id)).delete(synchronize_session=False)
	for i, it in enumerate(items or []):
		name = str(it.get("name") or "").strip()
		if not name:
			raise ApiError(
				"CUSTOMER_CLUB_TIER_NAME_REQUIRED",
				"Tier name is required.",
				http_status=400,
			)
		sort_order = int(it.get("sort_order", i))
		min_b = Decimal(str(it.get("min_balance_points", 0)))
		mult = Decimal(str(it.get("earn_multiplier", 1)))
		if mult <= 0:
			raise ApiError(
				"CUSTOMER_CLUB_TIER_MULTIPLIER_INVALID",
				"earn_multiplier must be positive.",
				http_status=400,
			)
		db.add(
			CustomerClubTier(
				business_id=int(business_id),
				sort_order=sort_order,
				name=name[:120],
				min_balance_points=min_b,
				earn_multiplier=mult,
			)
		)
	db.commit()
	return list_tiers(db, business_id)


def manual_adjustment(
	db: Session,
	business_id: int,
	user_id: int,
	person_id: int,
	delta_points: Decimal,
	description: str,
) -> Dict[str, Any]:
	person = db.query(Person).filter(and_(Person.id == person_id, Person.business_id == business_id)).first()
	if not person:
		raise ApiError(
			"CUSTOMER_CLUB_PERSON_NOT_FOUND",
			"Person not found.",
			http_status=404,
		)

	bal = _locked_balance_row(db, business_id, person_id)
	new_bal = bal.balance_points + delta_points
	bal.balance_points = new_bal
	_append_ledger(
		db,
		business_id=business_id,
		person_id=person_id,
		delta_points=delta_points,
		balance_after=new_bal,
		transaction_type="adjustment",
		reference_document_id=None,
		description=description[:2000] if description else "",
		created_by_user_id=user_id,
	)
	db.commit()
	return get_person_balance(db, business_id, person_id)
