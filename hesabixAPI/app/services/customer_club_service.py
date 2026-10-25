from __future__ import annotations

import json
import logging
from decimal import Decimal, InvalidOperation, ROUND_CEILING, ROUND_FLOOR, ROUND_HALF_UP
from typing import Any, Dict, List, Optional, Tuple

from datetime import datetime, timedelta

from sqlalchemy import and_, case, desc, or_
from sqlalchemy.orm import Session

from adapters.db.models.customer_club import (
	CustomerClubBalance,
	CustomerClubInvoiceSnapshot,
	CustomerClubLedger,
	CustomerClubCampaignMember,
	CustomerClubPointLot,
	CustomerClubRfmSnapshot,
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


def _setting_decimal(value: Any, field: str, *, allow_negative: bool = False) -> Decimal:
	try:
		parsed = Decimal(str(value))
	except (InvalidOperation, TypeError, ValueError):
		raise ApiError("CUSTOMER_CLUB_SETTING_INVALID", f"{field} must be a valid number.", http_status=400)
	if not parsed.is_finite() or (not allow_negative and parsed < 0):
		raise ApiError("CUSTOMER_CLUB_SETTING_INVALID", f"{field} is outside its allowed range.", http_status=400)
	return parsed


def _setting_bool(value: Any, field: str) -> bool:
	if not isinstance(value, bool):
		raise ApiError("CUSTOMER_CLUB_SETTING_INVALID", f"{field} must be true or false.", http_status=400)
	return value


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
		"referral_points": float(getattr(row, "referral_points", 0) or 0),
		"survey_points": float(getattr(row, "survey_points", 0) or 0),
		"loyalty_rfm_integration_mode": getattr(row, "loyalty_rfm_integration_mode", None) or "decoupled",
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
		referral_points=Decimal("0"),
		survey_points=Decimal("0"),
		loyalty_rfm_integration_mode="decoupled",
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
		row.enabled = _setting_bool(payload["enabled"], "enabled")
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
		row.percent_of_basis = _setting_decimal(v, "percent_of_basis") if v is not None else None
		if row.percent_of_basis is not None and row.percent_of_basis > 100:
			raise ApiError("CUSTOMER_CLUB_SETTING_INVALID", "percent_of_basis cannot exceed 100.", http_status=400)
	if "step_currency_amount" in payload:
		v = payload["step_currency_amount"]
		row.step_currency_amount = _setting_decimal(v, "step_currency_amount") if v is not None else None
	if "points_per_step" in payload:
		v = payload["points_per_step"]
		row.points_per_step = _setting_decimal(v, "points_per_step") if v is not None else None
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
		row.max_points_per_invoice = _setting_decimal(v, "max_points_per_invoice") if v is not None else None
	if "min_basis_amount" in payload:
		row.min_basis_amount = _setting_decimal(payload["min_basis_amount"], "min_basis_amount")
	if "require_customer_person_type" in payload:
		row.require_customer_person_type = _setting_bool(payload["require_customer_person_type"], "require_customer_person_type")
	if "currency_value_per_point" in payload:
		v = payload["currency_value_per_point"]
		row.currency_value_per_point = _setting_decimal(v, "currency_value_per_point") if v is not None else None
	if "max_redeem_points_per_invoice" in payload:
		v = payload["max_redeem_points_per_invoice"]
		row.max_redeem_points_per_invoice = _setting_decimal(v, "max_redeem_points_per_invoice") if v is not None else None
	if "points_expire_after_days" in payload:
		v = payload["points_expire_after_days"]
		if v is None or str(v).strip() == "":
			row.points_expire_after_days = None
		else:
			days = int(v)
			if days < 0 or days > 3650:
				raise ApiError("CUSTOMER_CLUB_EXPIRY_DAYS_INVALID", "points_expire_after_days must be between 1 and 3650, or 0 to disable expiry.", http_status=400)
			row.points_expire_after_days = days or None
	for key in ("referral_points", "survey_points"):
		if key in payload:
			value = _setting_decimal(payload[key], key)
			setattr(row, key, value)

	if "rfm_analytics_enabled" in payload:
		row.rfm_analytics_enabled = _setting_bool(payload["rfm_analytics_enabled"], "rfm_analytics_enabled")
	if "clv_analytics_enabled" in payload:
		row.clv_analytics_enabled = _setting_bool(payload["clv_analytics_enabled"], "clv_analytics_enabled")
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
		row.rfm_weight_recency = _setting_decimal(v, "rfm_weight_recency") if v is not None else None
	if "rfm_weight_frequency" in payload:
		v = payload["rfm_weight_frequency"]
		row.rfm_weight_frequency = _setting_decimal(v, "rfm_weight_frequency") if v is not None else None
	if "rfm_weight_monetary" in payload:
		v = payload["rfm_weight_monetary"]
		row.rfm_weight_monetary = _setting_decimal(v, "rfm_weight_monetary") if v is not None else None
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
		row.clv_avg_lifespan_years = _setting_decimal(v, "clv_avg_lifespan_years") if v is not None else None
	if "rfm_segment_labels_json" in payload:
		row.rfm_segment_labels_json = payload["rfm_segment_labels_json"]
	if "loyalty_rfm_integration_mode" in payload:
		lm = str(payload["loyalty_rfm_integration_mode"]).strip()
		if lm not in ("decoupled", "rfm_based_tiers"):
			raise ApiError(
				"CUSTOMER_CLUB_LOYALTY_RFM_MODE_INVALID",
				"loyalty_rfm_integration_mode must be decoupled or rfm_based_tiers.",
				http_status=400,
			)
		row.loyalty_rfm_integration_mode = lm

	if (getattr(row, "loyalty_rfm_integration_mode", None) or "decoupled") == "rfm_based_tiers" and not getattr(
		row, "rfm_analytics_enabled", False
	):
		raise ApiError(
			"CUSTOMER_CLUB_RFM_REQUIRED_FOR_TIERS",
			"Enable RFM analytics before using RFM-based tier multipliers.",
			http_status=400,
		)

	db.commit()
	db.refresh(row)
	return _settings_to_dict(row)


def rfm_normalized_from_snapshot(snap: Optional[CustomerClubRfmSnapshot]) -> Optional[Decimal]:
	"""نمرهٔ ۰ تا ۱ برای مقایسه با آستانهٔ سطوح در حالت rfm_based_tiers."""
	if snap is None:
		return None
	cs = getattr(snap, "composite_score", None)
	if cs is not None:
		v = Decimal(str(cs))
		return max(Decimal("0"), min(Decimal("1"), v))
	r = getattr(snap, "r_score", None)
	f = getattr(snap, "f_score", None)
	m = getattr(snap, "m_score", None)
	if r is not None and f is not None and m is not None:
		v = (Decimal(int(r)) + Decimal(int(f)) + Decimal(int(m))) / Decimal("15")
		return max(Decimal("0"), min(Decimal("1"), v))
	return None


def _person_rfm_normalized_for_tiers(db: Session, business_id: int, person_id: int) -> Optional[Decimal]:
	snap = (
		db.query(CustomerClubRfmSnapshot)
		.filter(
			and_(
				CustomerClubRfmSnapshot.business_id == int(business_id),
				CustomerClubRfmSnapshot.person_id == int(person_id),
			)
		)
		.first()
	)
	return rfm_normalized_from_snapshot(snap)


def _tier_min_rfm_threshold(tier: CustomerClubTier) -> Decimal:
	if getattr(tier, "min_rfm_normalized", None) is not None:
		v = Decimal(str(tier.min_rfm_normalized))
		return max(Decimal("0"), min(Decimal("1"), v))
	mb = tier.min_balance_points or Decimal("0")
	v = mb / Decimal("10000")
	return max(Decimal("0"), min(Decimal("1"), v))


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
		return value.to_integral_value(rounding=ROUND_CEILING)
	if mode == "round":
		return value.to_integral_value(rounding=ROUND_HALF_UP)
	return value.to_integral_value(rounding=ROUND_FLOOR)


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
		if abs(pts) > cap:
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


def usable_points_balance(db: Session, business_id: int, person_id: int, balance_points: Decimal | None = None) -> Decimal:
	"""Current points that are not past their lot expiry, including untracked legacy points."""
	if balance_points is None:
		balance = db.query(CustomerClubBalance).filter_by(business_id=business_id, person_id=person_id).first()
		balance_points = balance.balance_points if balance else Decimal("0")
	lots = db.query(CustomerClubPointLot).filter_by(business_id=business_id, person_id=person_id).all()
	tracked = sum((lot.remaining_points for lot in lots), Decimal("0"))
	legacy = max(balance_points - tracked, Decimal("0"))
	valid = sum((lot.remaining_points for lot in lots if lot.expires_at is None or lot.expires_at > datetime.utcnow()), Decimal("0"))
	return max(legacy + valid, Decimal("0"))


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
	db.flush()
	if person_id is not None and delta_points > 0 and transaction_type != "point_expiry":
		settings = db.query(CustomerClubSettings).filter(CustomerClubSettings.business_id == business_id).first()
		expirable_types = {"invoice_sync", "adjustment", "campaign_reward", "referral_reward", "survey_reward"}
		days = int(settings.points_expire_after_days) if settings and settings.points_expire_after_days and transaction_type in expirable_types else None
		expires_at = datetime.utcnow() + timedelta(days=days) if days and days > 0 else None
		db.add(
			CustomerClubPointLot(
				business_id=business_id,
				person_id=person_id,
				ledger_id=entry.id,
				original_points=delta_points,
				remaining_points=delta_points,
				expires_at=expires_at,
			)
		)
	elif person_id is not None and delta_points < 0 and transaction_type != "point_expiry":
		# Migrate old aggregate balances on first debit as a non-expiring legacy lot.
		# This preserves points earned before lot tracking was introduced.
		lots = (
			db.query(CustomerClubPointLot)
			.filter(
				CustomerClubPointLot.business_id == business_id,
				CustomerClubPointLot.person_id == person_id,
			)
			.with_for_update()
			.order_by(CustomerClubPointLot.created_at.asc(), CustomerClubPointLot.id.asc())
			.all()
		)
		old_balance = balance_after - delta_points
		tracked = sum((lot.remaining_points for lot in lots), Decimal("0"))
		legacy = old_balance - tracked
		if legacy > 0:
			db.add(
				CustomerClubPointLot(
					business_id=business_id,
					person_id=person_id,
					original_points=legacy,
					remaining_points=legacy,
					expires_at=None,
				)
			)
			db.flush()
		lot_query = db.query(CustomerClubPointLot).filter(
			CustomerClubPointLot.business_id == business_id,
			CustomerClubPointLot.person_id == person_id,
			CustomerClubPointLot.remaining_points > 0,
		)
		# A real redemption may consume only unexpired points. Corrections and
		# reversals must still reconcile expired lots or the aggregate diverges.
		if transaction_type in {"redeem", "reward_redeem"}:
			lot_query = lot_query.filter(
				or_(CustomerClubPointLot.expires_at.is_(None), CustomerClubPointLot.expires_at > datetime.utcnow())
			)
		lots = (
			lot_query.with_for_update()
			.order_by(
				case((CustomerClubPointLot.expires_at.is_(None), 1), else_=0),
				CustomerClubPointLot.expires_at.asc(),
				CustomerClubPointLot.created_at.asc(),
				CustomerClubPointLot.id.asc(),
			)
			.all()
		)
		remaining = -delta_points
		for lot in lots:
			if remaining <= 0:
				break
			used = min(lot.remaining_points, remaining)
			lot.remaining_points -= used
			remaining -= used
	return entry


def expire_due_points(db: Session, *, business_id: int | None = None, now: datetime | None = None) -> Dict[str, Any]:
	"""Expire due point lots atomically while keeping the aggregate balance and ledger aligned."""
	now = now or datetime.utcnow()
	query = db.query(CustomerClubPointLot).filter(
		CustomerClubPointLot.expires_at.is_not(None),
		CustomerClubPointLot.expires_at <= now,
		CustomerClubPointLot.remaining_points > 0,
	)
	if business_id is not None:
		query = query.filter(CustomerClubPointLot.business_id == int(business_id))
	lots = query.with_for_update().order_by(CustomerClubPointLot.business_id, CustomerClubPointLot.person_id, CustomerClubPointLot.expires_at, CustomerClubPointLot.id).limit(1000).all()
	processed = 0
	expired = Decimal("0")
	for lot in lots:
		amount = lot.remaining_points
		lot.remaining_points = Decimal("0")
		balance = _locked_balance_row(db, lot.business_id, lot.person_id)
		amount = min(amount, max(balance.balance_points, Decimal("0")))
		if amount <= 0:
			continue
		balance.balance_points -= amount
		balance.updated_at = now
		_append_ledger(
			db,
			business_id=lot.business_id,
			person_id=lot.person_id,
			delta_points=-amount,
			balance_after=balance.balance_points,
			transaction_type="point_expiry",
			description=f"انقضای {amount} امتیاز در {lot.expires_at:%Y-%m-%d}",
		)
		processed += 1
		expired += amount
	db.commit()
	return {"lots_expired": processed, "points_expired": float(expired)}


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
	settings_row = db.query(CustomerClubSettings).filter(CustomerClubSettings.business_id == int(business_id)).first()
	mode = getattr(settings_row, "loyalty_rfm_integration_mode", None) or "decoupled" if settings_row else "decoupled"
	rows = (
		db.query(CustomerClubTier)
		.filter(CustomerClubTier.business_id == int(business_id))
		.order_by(CustomerClubTier.sort_order.asc(), CustomerClubTier.min_balance_points.asc(), CustomerClubTier.id.asc())
		.all()
	)
	if not rows:
		return Decimal("1")
	if mode == "rfm_based_tiers":
		rfm_val = _person_rfm_normalized_for_tiers(db, business_id, person_id)
		if rfm_val is None:
			return Decimal("1")
		best = Decimal("1")
		for t in rows:
			if rfm_val >= _tier_min_rfm_threshold(t):
				m = t.earn_multiplier or Decimal("1")
				if m > 0:
					best = m
		return best
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
	invoice_lines: Optional[List[Dict[str, Any]]] = None,
	document_id: int | None = None,
) -> None:
	"""قبل از ذخیره فاکتور: افزایش تخفیف و کاهش مالیات به نسبت مبنای جدید. extra_info.customer_club پر می‌شود."""
	cc = dict(header_extra.get("customer_club") or {})
	voucher_code = str(data.get("customer_club_voucher_code") or cc.get("voucher_code") or "").strip().upper()
	if voucher_code:
		if invoice_type != INVOICE_SALES or is_proforma or not person_id:
			raise ApiError("CUSTOMER_CLUB_VOUCHER_NOT_ALLOWED", "Vouchers require a finalized sales invoice with a customer.", http_status=400)
		if not check_customer_club_plugin_active(db, business_id):
			raise ApiError("CUSTOMER_CLUB_PLUGIN_NOT_ACTIVE", "Customer club add-on is not active for this business.", http_status=403)
		if not user_can_redeem_loyalty_points(db, user_id, business_id):
			raise ApiError("LOYALTY_REDEEM_PERMISSION", "You do not have permission to redeem rewards.", http_status=403)
		from adapters.db.models.customer_club import CustomerClubVoucher
		voucher = db.query(CustomerClubVoucher).filter_by(business_id=business_id, code=voucher_code).with_for_update().first()
		if not voucher or voucher.person_id != int(person_id):
			raise ApiError("CUSTOMER_CLUB_VOUCHER_INVALID", "Voucher is not valid for this customer.", http_status=400)
		if voucher.status != "issued" and voucher.status != "redeemed":
			raise ApiError("CUSTOMER_CLUB_VOUCHER_UNAVAILABLE", "Voucher is no longer available.", http_status=409)
		if voucher.expires_at and voucher.expires_at <= datetime.utcnow():
			voucher.status = "expired"
			raise ApiError("CUSTOMER_CLUB_VOUCHER_EXPIRED", "Voucher has expired.", http_status=400)
		if voucher.status == "redeemed":
			snap = db.query(CustomerClubInvoiceSnapshot).filter_by(document_id=document_id or data.get("id") or 0).first()
			if not snap or snap.voucher_id != voucher.id:
				raise ApiError("CUSTOMER_CLUB_VOUCHER_UNAVAILABLE", "Voucher has already been used.", http_status=409)
		if voucher.reward_type == "free_product":
			if not voucher.product_id or not any(int(line.get("product_id") or 0) == int(voucher.product_id) for line in (invoice_lines or [])):
				raise ApiError("CUSTOMER_CLUB_VOUCHER_PRODUCT_REQUIRED", "This voucher requires its assigned product on the invoice.", http_status=400)
		gross = Decimal(str(totals.get("gross", 0)))
		old_discount = Decimal(str(totals.get("discount", 0)))
		available = max(gross - old_discount, Decimal("0"))
		value = Decimal(str(voucher.value))
		if voucher.reward_type == "discount_percent":
			if value < 0 or value > 100:
				raise ApiError("CUSTOMER_CLUB_VOUCHER_VALUE_INVALID", "Voucher percentage is invalid.", http_status=409)
			voucher_discount = (available * value / Decimal("100")).quantize(Decimal("0.01"))
		elif voucher.reward_type == "free_product":
			voucher_discount = min(max(value, Decimal("0")), available)
		else:
			voucher_discount = min(max(value, Decimal("0")), available)
		new_discount = old_discount + voucher_discount
		old_tax = Decimal(str(totals.get("tax", 0)))
		new_net = gross - new_discount
		new_tax = (old_tax * new_net / (gross - old_discount)).quantize(Decimal("0.01")) if gross > old_discount else old_tax
		totals.update({"discount": float(new_discount), "net": float(new_net), "tax": float(new_tax)})
		header_extra["totals"] = totals
		cc["voucher_code"] = voucher.code
		cc["voucher_id"] = voucher.id
		cc["voucher_discount_amount"] = float(voucher_discount)
		header_extra["customer_club"] = cc
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
	if not redeem_pts.is_finite():
		raise ApiError("INVALID_LOYALTY_POINTS", "loyalty_redemption_points must be finite.", http_status=400)
	if redeem_pts <= 0:
		if raw_pts is not None:
			cc.pop("redeem_points_requested", None)
			cc.pop("redeem_discount_amount", None)
			if cc:
				header_extra["customer_club"] = cc
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
	usable_points = usable_points_balance(db, business_id, int(person_id), cur_bal)
	if redeem_pts > usable_points:
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
	person_changed = bool(snap_existing and snap_existing.person_id and person_id and int(snap_existing.person_id) != int(person_id))
	if person_changed and old_redeemed > 0:
		# A customer change must refund the original member before points are
		# charged to the new member; otherwise an edit transfers redemption debt.
		previous_person_id = int(snap_existing.person_id)
		previous_balance = _locked_balance_row(db, int(document.business_id), previous_person_id)
		previous_balance.balance_points += old_redeemed
		previous_balance.updated_at = datetime.utcnow()
		_append_ledger(db, business_id=int(document.business_id), person_id=previous_person_id,
			delta_points=old_redeemed, balance_after=previous_balance.balance_points,
			transaction_type="redeem_void", reference_document_id=int(document.id),
			description=f"بازگردانی امتیاز مصرف‌شده پس از تغییر مشتری فاکتور {document.code}",
			created_by_user_id=user_id)
		old_redeemed = Decimal("0")
	old_voucher_id = snap_existing.voucher_id if snap_existing else None
	try:
		new_voucher_id = int(cc.get("voucher_id")) if cc.get("voucher_id") is not None else None
	except (TypeError, ValueError):
		new_voucher_id = None
	if old_voucher_id and old_voucher_id != new_voucher_id:
		from adapters.db.models.customer_club import CustomerClubVoucher
		old_voucher = db.query(CustomerClubVoucher).filter_by(id=old_voucher_id, business_id=document.business_id).with_for_update().first()
		if old_voucher and old_voucher.status == "redeemed" and old_voucher.redeemed_document_id == document.id:
			old_voucher.status = "issued"
			old_voucher.redeemed_at = None
			old_voucher.redeemed_document_id = None
	if new_voucher_id:
		from adapters.db.models.customer_club import CustomerClubVoucher
		voucher = db.query(CustomerClubVoucher).filter_by(id=new_voucher_id, business_id=document.business_id).with_for_update().first()
		if not voucher or voucher.person_id != person_id:
			raise ApiError("CUSTOMER_CLUB_VOUCHER_INVALID", "Voucher no longer belongs to this customer.", http_status=409)
		if voucher.expires_at and voucher.expires_at <= datetime.utcnow():
			raise ApiError("CUSTOMER_CLUB_VOUCHER_EXPIRED", "Voucher expired before invoice save.", http_status=409)
		if voucher.status == "issued":
			voucher.status = "redeemed"
			voucher.redeemed_at = datetime.utcnow()
			voucher.redeemed_document_id = document.id
		elif not (voucher.status == "redeemed" and voucher.redeemed_document_id == document.id):
			raise ApiError("CUSTOMER_CLUB_VOUCHER_UNAVAILABLE", "Voucher was used by another invoice.", http_status=409)

	if new_pts <= 0 and old_redeemed <= 0:
		if snap_existing:
			if not (person_changed and snap_existing.accrued_points != 0):
				snap_existing.person_id = person_id or snap_existing.person_id
			snap_existing.voucher_id = new_voucher_id
		elif new_voucher_id:
			db.add(CustomerClubInvoiceSnapshot(document_id=document.id, business_id=document.business_id,
				person_id=person_id, accrued_points=Decimal("0"), redeemed_points=Decimal("0"), voucher_id=new_voucher_id))
		db.flush()
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
			if not (person_changed and snap_existing.accrued_points != 0):
				snap_existing.person_id = int(rpid)
			snap_existing.voucher_id = new_voucher_id
		db.flush()
		return

	if not person_id:
		return

	delta = new_pts - old_redeemed
	if delta == 0:
		if snap_existing:
			if not (person_changed and snap_existing.accrued_points != 0):
				snap_existing.person_id = person_id
			snap_existing.voucher_id = new_voucher_id
		db.flush()
		return

	bal = _locked_balance_row(db, int(document.business_id), person_id)
	if delta > 0 and usable_points_balance(db, int(document.business_id), person_id, bal.balance_points) < delta:
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
		if not (person_changed and snap_existing.accrued_points != 0):
			snap_existing.person_id = person_id
		snap_existing.voucher_id = new_voucher_id
	else:
		db.add(
			CustomerClubInvoiceSnapshot(
				document_id=document.id,
				business_id=document.business_id,
				person_id=person_id,
				accrued_points=Decimal("0"),
				redeemed_points=new_pts,
				voucher_id=new_voucher_id,
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
	snap = db.query(CustomerClubInvoiceSnapshot).filter(CustomerClubInvoiceSnapshot.document_id == doc.id).first()
	if not person_id:
		if snap and snap.person_id and snap.accrued_points != 0:
			old_balance = _locked_balance_row(db, int(doc.business_id), int(snap.person_id))
			old_balance.balance_points -= snap.accrued_points
			old_balance.updated_at = datetime.utcnow()
			_append_ledger(db, business_id=int(doc.business_id), person_id=int(snap.person_id),
				delta_points=-snap.accrued_points, balance_after=old_balance.balance_points,
				transaction_type="invoice_sync_reassignment", reference_document_id=int(doc.id),
				description=f"برگشت امتیاز فاکتور {doc.code} پس از حذف مشتری")
			snap.accrued_points = Decimal("0")
			snap.person_id = None
		db.flush()
		return

	person = db.query(Person).filter(and_(Person.id == person_id, Person.business_id == doc.business_id)).first()
	if not person:
		if snap and snap.person_id and snap.accrued_points != 0:
			old_balance = _locked_balance_row(db, int(doc.business_id), int(snap.person_id))
			old_balance.balance_points -= snap.accrued_points
			old_balance.updated_at = datetime.utcnow()
			_append_ledger(db, business_id=int(doc.business_id), person_id=int(snap.person_id),
				delta_points=-snap.accrued_points, balance_after=old_balance.balance_points,
				transaction_type="invoice_sync_reassignment", reference_document_id=int(doc.id),
				description=f"برگشت امتیاز فاکتور {doc.code} به‌دلیل نامعتبرشدن مشتری")
			snap.accrued_points = Decimal("0")
			snap.person_id = None
		db.flush()
		return
	if settings_row.require_customer_person_type and not _person_is_customer(person):
		if snap and snap.person_id and snap.accrued_points != 0:
			old_balance = _locked_balance_row(db, int(doc.business_id), int(snap.person_id))
			old_balance.balance_points -= snap.accrued_points
			old_balance.updated_at = datetime.utcnow()
			_append_ledger(db, business_id=int(doc.business_id), person_id=int(snap.person_id),
				delta_points=-snap.accrued_points, balance_after=old_balance.balance_points,
				transaction_type="invoice_sync_reassignment", reference_document_id=int(doc.id),
				description=f"برگشت امتیاز فاکتور {doc.code} به‌دلیل تغییر نوع شخص")
			snap.accrued_points = Decimal("0")
			snap.person_id = None
		db.flush()
		return

	if doc.document_type == INVOICE_SALES:
		_award_referral_for_first_purchase(db, int(doc.business_id), int(person_id))

	basis = _resolved_basis_amount(settings_row, db, doc)

	direction = 1 if doc.document_type == INVOICE_SALES else -1
	target_pts = _compute_points_for_amount(settings_row, basis, direction)
	if doc.document_type == INVOICE_SALES and direction > 0:
		tm = _earn_tier_multiplier(db, int(doc.business_id), int(person_id))
		target_pts = (target_pts * tm).quantize(Decimal("0.000001"))

	old_pts = snap.accrued_points if snap else Decimal("0")
	if snap and snap.person_id is not None and int(snap.person_id) != int(person_id):
		old_person_id = int(snap.person_id)
		if old_pts != 0:
			old_balance = _locked_balance_row(db, doc.business_id, old_person_id)
			old_balance.balance_points -= old_pts
			old_balance.updated_at = datetime.utcnow()
			_append_ledger(
				db,
				business_id=doc.business_id,
				person_id=old_person_id,
				delta_points=-old_pts,
				balance_after=old_balance.balance_points,
				transaction_type="invoice_sync_reassignment",
				reference_document_id=doc.id,
				description=f"برگشت امتیاز فاکتور {doc.code} از مشتری قبلی",
			)
		old_pts = Decimal("0")
	delta = target_pts - old_pts
	if delta != 0:
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
	if doc.document_type == INVOICE_SALES:
		from app.services.customer_club_program_service import apply_purchase_campaigns
		apply_purchase_campaigns(db, int(doc.business_id), int(person_id), basis)
		_attribute_campaign_conversion(db, int(doc.business_id), int(person_id), int(doc.id), basis)


def _attribute_campaign_conversion(db: Session, business_id: int, person_id: int, document_id: int, amount: Decimal) -> None:
	"""Attribute the first sales invoice within 30 days to the member's latest campaign."""
	cutoff = datetime.utcnow() - timedelta(days=30)
	row = (
		db.query(CustomerClubCampaignMember)
		.filter(
			CustomerClubCampaignMember.business_id == business_id,
			CustomerClubCampaignMember.person_id == person_id,
			CustomerClubCampaignMember.created_at >= cutoff,
			CustomerClubCampaignMember.conversion_document_id.is_(None),
			CustomerClubCampaignMember.status.in_(("rewarded", "sent")),
		)
		.order_by(CustomerClubCampaignMember.created_at.desc(), CustomerClubCampaignMember.id.desc())
		.with_for_update()
		.first()
	)
	if row:
		row.conversion_document_id = document_id
		row.conversion_amount = amount
		row.converted_at = datetime.utcnow()


def _award_referral_for_first_purchase(db: Session, business_id: int, person_id: int) -> None:
	"""Award inviter and invitee once, after the referred member's first finalized sale."""
	from adapters.db.models.customer_club import CustomerClubMember

	settings = db.query(CustomerClubSettings).filter_by(business_id=business_id).first()
	points = getattr(settings, "referral_points", Decimal("0")) if settings else Decimal("0")
	member = (
		db.query(CustomerClubMember)
		.filter_by(business_id=business_id, person_id=person_id)
		.with_for_update()
		.first()
	)
	if not member or not member.referrer_person_id or member.referral_rewarded_at:
		return
	referrer_id = int(member.referrer_person_id)
	if referrer_id == person_id:
		return
	if points > 0:
		for recipient_id, note in ((referrer_id, "معرفی مشتری جدید"), (person_id, "عضویت با کد معرفی")):
			balance = _locked_balance_row(db, business_id, recipient_id)
			balance.balance_points += points
			balance.updated_at = datetime.utcnow()
			_append_ledger(
				db,
				business_id=business_id,
				person_id=recipient_id,
				delta_points=points,
				balance_after=balance.balance_points,
				transaction_type="referral_reward",
				description=f"پاداش {note}",
			)
	from app.services.customer_club_program_service import apply_event_campaigns
	apply_event_campaigns(db, business_id, referrer_id, "referral")
	member.referral_rewarded_at = datetime.utcnow()
	db.flush()


def reverse_customer_club_on_invoice_delete(db: Session, document_id: int, business_id: int) -> None:
	# A saved snapshot must always be reversed, even after the add-on is disabled
	# or its license lapses; otherwise deleted invoices leave orphaned balances.
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
	if snap.voucher_id:
		from adapters.db.models.customer_club import CustomerClubVoucher
		voucher = db.query(CustomerClubVoucher).filter_by(id=snap.voucher_id, business_id=business_id).with_for_update().first()
		if voucher and voucher.status == "redeemed" and voucher.redeemed_document_id == document_id:
			voucher.status = "issued"
			voucher.redeemed_at = None
			voucher.redeemed_document_id = None
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
	settings_row = db.query(CustomerClubSettings).filter(CustomerClubSettings.business_id == business_id).first()
	mode = getattr(settings_row, "loyalty_rfm_integration_mode", None) or "decoupled" if settings_row else "decoupled"
	snap = (
		db.query(CustomerClubRfmSnapshot)
		.filter(
			and_(CustomerClubRfmSnapshot.business_id == business_id, CustomerClubRfmSnapshot.person_id == person_id)
		)
		.first()
	)
	rfm_n = rfm_normalized_from_snapshot(snap)
	out: Dict[str, Any] = {
		"person_id": person_id,
		"balance_points": float(bal),
		"loyalty_rfm_integration_mode": mode,
	}
	if rfm_n is not None:
		out["rfm_normalized_score"] = float(rfm_n)
	tiers = list_tiers(db, business_id)
	current = None
	for tier in tiers:
		if mode == "rfm_based_tiers":
			threshold = tier.get("min_rfm_normalized")
			if threshold is None:
				threshold = min(1.0, max(0.0, float(tier.get("min_balance_points") or 0) / 10000.0))
			eligible = rfm_n is not None and float(rfm_n) >= float(threshold)
		else:
			eligible = float(bal) >= float(tier.get("min_balance_points") or 0)
		if eligible:
			current = tier
	if current:
		out["tier"] = {"id": current["id"], "name": current["name"], "benefits": current.get("benefits") or [], "earn_multiplier": current["earn_multiplier"]}
	return out


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
			"min_rfm_normalized": float(r.min_rfm_normalized) if getattr(r, "min_rfm_normalized", None) is not None else None,
			"earn_multiplier": float(r.earn_multiplier),
			"benefits": r.benefits_json or [],
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
		min_rfm_raw = it.get("min_rfm_normalized")
		min_rfm: Decimal | None = Decimal(str(min_rfm_raw)) if min_rfm_raw is not None else None
		benefits = it.get("benefits", [])
		if not isinstance(benefits, list) or len(benefits) > 30 or any(not isinstance(x, str) or len(x.strip()) > 240 for x in benefits):
			raise ApiError("CUSTOMER_CLUB_TIER_BENEFITS_INVALID", "benefits must be a list of at most 30 short text items.", http_status=400)
		if min_rfm is not None and (min_rfm < Decimal("0") or min_rfm > Decimal("1")):
			raise ApiError(
				"CUSTOMER_CLUB_TIER_RFM_THRESHOLD_INVALID",
				"min_rfm_normalized must be between 0 and 1.",
				http_status=400,
			)
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
				min_rfm_normalized=min_rfm,
				earn_multiplier=mult,
				benefits_json=[x.strip() for x in benefits if x.strip()],
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
	if new_bal < 0:
		raise ApiError("CUSTOMER_CLUB_INSUFFICIENT_POINTS", "Customer balance cannot become negative.", http_status=409)
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
