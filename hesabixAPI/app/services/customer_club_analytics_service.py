from __future__ import annotations

import logging
from calendar import monthrange
from collections import defaultdict
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional, Sequence, Tuple

from sqlalchemy import String, and_, cast, desc, func, or_
from sqlalchemy.orm import Session

from adapters.db.models.customer_club import CustomerClubBalance, CustomerClubRfmSnapshot, CustomerClubSettings
from adapters.db.models.document import Document
from adapters.db.models.person import Person
from app.core.responses import ApiError
from app.services.customer_club_service import (
	_basis_net_and_total_from_document,
	_person_is_customer,
)
from app.services.invoice_service import INVOICE_SALES, INVOICE_SALES_RETURN

logger = logging.getLogger(__name__)


def subtract_months(d: date, months: int) -> date:
	y, mth = d.year, d.month
	mth -= months
	while mth <= 0:
		mth += 12
		y -= 1
	last_day = monthrange(y, mth)[1]
	return date(y, mth, min(d.day, last_day))


def _monetary_amount(db: Session, doc: Document, monetary_basis: str) -> Decimal:
	net_b, total_b = _basis_net_and_total_from_document(db, doc)
	return total_b if monetary_basis == "total_with_tax" else net_b


def _quintile_scores(values: Sequence[float], *, higher_is_better: bool) -> List[int]:
	n = len(values)
	if n == 0:
		return []
	if n == 1:
		return [5]
	order = sorted(range(n), key=lambda i: values[i], reverse=higher_is_better)
	scores = [1] * n
	for q in range(5):
		start = q * n // 5
		end = (q + 1) * n // 5 if q < 4 else n
		score_val = 5 - q
		for j in range(start, end):
			scores[order[j]] = score_val
	return scores


def _normalize_weights(wr: Optional[Decimal], wf: Optional[Decimal], wm: Optional[Decimal]) -> Tuple[Decimal, Decimal, Decimal]:
	if wr is not None and wf is not None and wm is not None:
		s = wr + wf + wm
		if s > 0:
			return wr / s, wf / s, wm / s
	return Decimal("0.34"), Decimal("0.33"), Decimal("0.33")


def _min_max_norm(xs: Sequence[float], *, invert: bool) -> List[float]:
	if not xs:
		return []
	mn = min(xs)
	mx = max(xs)
	span = float(mx - mn) if mx != mn else 1.0
	out: List[float] = []
	for x in xs:
		v = float((Decimal(str(x)) - Decimal(str(mn))) / Decimal(str(span)))
		if invert:
			v = 1.0 - v
		out.append(max(0.0, min(1.0, v)))
	return out


def default_segment_label(r: int, f: int, m: int) -> str:
	if r >= 5 and f >= 5 and m >= 5:
		return "قهرمانان"
	if r >= 4 and f >= 4 and m >= 4:
		return "وفاداران ارزشمند"
	if r >= 5 and f <= 2 and m >= 4:
		return "تازه‌واردهای پرارزش"
	if r >= 5 and f <= 2:
		return "تازه‌وارد"
	if r <= 2 and f >= 4:
		return "در معرض ریزش"
	if r <= 2 and f <= 2 and m <= 2:
		return "غیرفعال / از دست‌رفته"
	if r <= 2:
		return "خرید قدیمی"
	if f >= 4 and m <= 2:
		return "پرتکرار کم‌ارزش"
	if m >= 5 and f <= 2:
		return "خریدهای احجام بالا (گاه‌به‌گاه)"
	return "سگمنت ترکیبی"


def _resolve_segment_label(
	r: int,
	f: int,
	m: int,
	custom_map: Optional[Dict[str, Any]],
) -> str:
	key = f"{r}-{f}-{m}"
	if isinstance(custom_map, dict) and custom_map.get(key):
		return str(custom_map[key])[:160]
	return default_segment_label(r, f, m)


def _compute_clv(
	settings: CustomerClubSettings,
	monetary: Decimal,
	frequency: int,
	window_months: int,
) -> Optional[Decimal]:
	if not getattr(settings, "clv_analytics_enabled", False):
		return None
	formula = getattr(settings, "clv_formula", None) or "historical_total"
	if formula == "historical_total":
		return monetary.quantize(Decimal("0.0001"))
	if formula == "avg_order_projection":
		life = getattr(settings, "clv_avg_lifespan_years", None) or Decimal("3")
		if frequency <= 0 or window_months <= 0:
			return Decimal("0")
		years = Decimal(str(window_months)) / Decimal("12")
		if years <= 0:
			return Decimal("0")
		aov = monetary / Decimal(str(frequency))
		purchases_per_year = Decimal(str(frequency)) / years
		out = aov * purchases_per_year * life
		return out.quantize(Decimal("0.0001"))
	return monetary.quantize(Decimal("0.0001"))


def recalculate_rfm_snapshots(db: Session, business_id: int) -> Dict[str, Any]:
	settings = db.query(CustomerClubSettings).filter(CustomerClubSettings.business_id == business_id).first()
	if not settings:
		raise ApiError(
			"CUSTOMER_CLUB_SETTINGS_MISSING",
			"Customer club settings not found.",
			http_status=404,
		)

	if not getattr(settings, "rfm_analytics_enabled", False) and not getattr(settings, "clv_analytics_enabled", False):
		raise ApiError(
			"CUSTOMER_CLUB_ANALYTICS_DISABLED",
			"Enable RFM or CLV analytics in customer club settings first.",
			http_status=400,
		)

	window_months = max(1, int(getattr(settings, "rfm_analysis_window_months", 12) or 12))
	end_d = date.today()
	start_d = subtract_months(end_d, window_months)
	monetary_basis = getattr(settings, "rfm_monetary_basis", None) or "net"
	scoring_method = getattr(settings, "rfm_scoring_method", None) or "quintiles"
	custom_labels = getattr(settings, "rfm_segment_labels_json", None)

	wr, wf, wm = _normalize_weights(
		getattr(settings, "rfm_weight_recency", None),
		getattr(settings, "rfm_weight_frequency", None),
		getattr(settings, "rfm_weight_monetary", None),
	)

	docs = (
		db.query(Document)
		.filter(
			and_(
				Document.business_id == business_id,
				Document.is_proforma.is_(False),
				Document.document_type.in_((INVOICE_SALES, INVOICE_SALES_RETURN)),
				Document.document_date >= start_d,
				Document.document_date <= end_d,
			)
		)
		.all()
	)

	sales_dates: Dict[int, List[date]] = defaultdict(list)
	sales_count: Dict[int, int] = defaultdict(int)
	monetary_sum: Dict[int, Decimal] = defaultdict(lambda: Decimal("0"))

	for doc in docs:
		ex = doc.extra_info or {}
		if not isinstance(ex, dict):
			continue
		pid = ex.get("person_id")
		try:
			person_id = int(pid) if pid is not None else None
		except (TypeError, ValueError):
			continue
		if not person_id:
			continue

		person = db.query(Person).filter(and_(Person.id == person_id, Person.business_id == business_id)).first()
		if not person:
			continue
		if settings.require_customer_person_type and not _person_is_customer(person):
			continue

		amt = _monetary_amount(db, doc, monetary_basis)
		if doc.document_type == INVOICE_SALES:
			sales_dates[person_id].append(doc.document_date)
			sales_count[person_id] += 1
			monetary_sum[person_id] += amt
		else:
			monetary_sum[person_id] -= amt

	eligible_pids = [pid for pid in sales_count.keys() if sales_count[pid] > 0]
	if not eligible_pids:
		db.query(CustomerClubRfmSnapshot).filter(CustomerClubRfmSnapshot.business_id == business_id).delete(
			synchronize_session=False
		)
		db.commit()
		return {
			"persons_computed": 0,
			"window_start": start_d.isoformat(),
			"window_end": end_d.isoformat(),
			"computed_at": datetime.utcnow().isoformat(),
		}

	recency_days: Dict[int, int] = {}
	for pid in eligible_pids:
		last_dt = max(sales_dates[pid])
		recency_days[pid] = max(0, (end_d - last_dt).days)

	index_order = eligible_pids
	n = len(index_order)
	R_raw = [float(recency_days[pid]) for pid in index_order]
	F_raw = [float(sales_count[pid]) for pid in index_order]
	M_raw = [float(monetary_sum[pid]) for pid in index_order]

	r_scores = _quintile_scores(R_raw, higher_is_better=False)
	f_scores = _quintile_scores(F_raw, higher_is_better=True)
	m_scores = _quintile_scores(M_raw, higher_is_better=True)

	composite: Optional[List[float]] = None
	if scoring_method == "weighted":
		norm_r = _min_max_norm(R_raw, invert=True)
		norm_f = _min_max_norm(F_raw, invert=False)
		norm_m = _min_max_norm(M_raw, invert=False)
		composite = [
			float(wr * Decimal(str(norm_r[i])) + wf * Decimal(str(norm_f[i])) + wm * Decimal(str(norm_m[i])))
			for i in range(n)
		]

	computed_at = datetime.utcnow()
	db.query(CustomerClubRfmSnapshot).filter(CustomerClubRfmSnapshot.business_id == business_id).delete(
		synchronize_session=False
	)

	for i, pid in enumerate(index_order):
		r = int(r_scores[i])
		f = int(f_scores[i])
		m = int(m_scores[i])
		cell = f"{r}-{f}-{m}"
		label = _resolve_segment_label(r, f, m, custom_labels if isinstance(custom_labels, dict) else None)
		money = monetary_sum[pid].quantize(Decimal("0.0001"))
		comp_dec: Decimal | None = None
		if composite is not None:
			comp_dec = Decimal(str(composite[i])).quantize(Decimal("0.00000001"))
		clv = _compute_clv(settings, monetary_sum[pid], int(sales_count[pid]), window_months)

		row = CustomerClubRfmSnapshot(
			business_id=business_id,
			person_id=pid,
			recency_days=int(recency_days[pid]),
			frequency_count=int(sales_count[pid]),
			monetary_total=money,
			r_score=r if getattr(settings, "rfm_analytics_enabled", False) else None,
			f_score=f if getattr(settings, "rfm_analytics_enabled", False) else None,
			m_score=m if getattr(settings, "rfm_analytics_enabled", False) else None,
			rfm_cell=cell if getattr(settings, "rfm_analytics_enabled", False) else None,
			segment_label=label if getattr(settings, "rfm_analytics_enabled", False) else None,
			composite_score=comp_dec if getattr(settings, "rfm_analytics_enabled", False) else None,
			clv_estimate=clv,
			computed_at=computed_at,
		)
		db.add(row)

	db.commit()
	return {
		"persons_computed": n,
		"window_start": start_d.isoformat(),
		"window_end": end_d.isoformat(),
		"computed_at": computed_at.isoformat(),
	}


def get_rfm_summary(db: Session, business_id: int) -> Dict[str, Any]:
	settings = db.query(CustomerClubSettings).filter(CustomerClubSettings.business_id == business_id).first()
	window_months = int(getattr(settings, "rfm_analysis_window_months", 12) or 12) if settings else 12
	end_d = date.today()
	start_d = subtract_months(end_d, window_months)

	subq = (
		db.query(func.max(CustomerClubRfmSnapshot.computed_at))
		.filter(CustomerClubRfmSnapshot.business_id == business_id)
		.scalar()
	)

	total = db.query(func.count(CustomerClubRfmSnapshot.id)).filter(
		CustomerClubRfmSnapshot.business_id == business_id
	).scalar() or 0

	segments_rows = (
		db.query(CustomerClubRfmSnapshot.segment_label, func.count(CustomerClubRfmSnapshot.id))
		.filter(CustomerClubRfmSnapshot.business_id == business_id)
		.group_by(CustomerClubRfmSnapshot.segment_label)
		.all()
	)
	segments = [{"label": str(lab or ""), "count": int(cnt)} for lab, cnt in segments_rows]
	segments.sort(key=lambda x: (-x["count"], x["label"]))

	return {
		"total_persons": int(total),
		"computed_at": subq.isoformat() if subq else None,
		"window": {
			"start": start_d.isoformat(),
			"end": end_d.isoformat(),
			"months": window_months,
		},
		"segments": segments,
		"rfm_enabled": bool(getattr(settings, "rfm_analytics_enabled", False)) if settings else False,
		"clv_enabled": bool(getattr(settings, "clv_analytics_enabled", False)) if settings else False,
	}


def list_rfm_persons(
	db: Session,
	business_id: int,
	*,
	skip: int = 0,
	limit: int = 50,
	segment_label: Optional[str] = None,
	search: Optional[str] = None,
	sort: str = "monetary_total",
	sort_dir: str = "desc",
) -> Tuple[List[Dict[str, Any]], int]:
	q = (
		db.query(CustomerClubRfmSnapshot, Person)
		.join(Person, Person.id == CustomerClubRfmSnapshot.person_id)
		.filter(CustomerClubRfmSnapshot.business_id == business_id)
	)
	if segment_label and segment_label.strip():
		q = q.filter(CustomerClubRfmSnapshot.segment_label == segment_label.strip())
	if search and search.strip():
		term = f"%{search.strip()}%"
		q = q.filter(
			or_(
				Person.alias_name.ilike(term),
				Person.company_name.ilike(term),
				cast(Person.code, String).ilike(term),
			)
		)

	total = q.count()

	sort_col = CustomerClubRfmSnapshot.monetary_total
	if sort == "recency_days":
		sort_col = CustomerClubRfmSnapshot.recency_days
	elif sort == "frequency_count":
		sort_col = CustomerClubRfmSnapshot.frequency_count
	elif sort == "clv_estimate":
		sort_col = CustomerClubRfmSnapshot.clv_estimate
	elif sort == "segment_label":
		sort_col = CustomerClubRfmSnapshot.segment_label
	elif sort == "composite_score":
		sort_col = CustomerClubRfmSnapshot.composite_score

	if sort_dir.lower() == "asc":
		q = q.order_by(sort_col.asc().nulls_last(), CustomerClubRfmSnapshot.person_id.asc())
	else:
		q = q.order_by(sort_col.desc().nulls_last(), CustomerClubRfmSnapshot.person_id.asc())

	rows = q.offset(skip).limit(limit).all()

	balances = {}
	pids = [int(s.person_id) for s, _p in rows if s.person_id]
	if pids:
		brs = (
			db.query(CustomerClubBalance)
			.filter(
				and_(CustomerClubBalance.business_id == business_id, CustomerClubBalance.person_id.in_(pids))
			)
			.all()
		)
		for b in brs:
			balances[int(b.person_id)] = float(b.balance_points)

	items: List[Dict[str, Any]] = []
	for snap, person in rows:
		pid = int(snap.person_id)
		items.append(
			{
				"person_id": pid,
				"person_name": person.alias_name,
				"person_code": person.code,
				"company_name": person.company_name,
				"recency_days": snap.recency_days,
				"frequency_count": snap.frequency_count,
				"monetary_total": float(snap.monetary_total),
				"r_score": snap.r_score,
				"f_score": snap.f_score,
				"m_score": snap.m_score,
				"rfm_cell": snap.rfm_cell,
				"segment_label": snap.segment_label,
				"composite_score": float(snap.composite_score) if snap.composite_score is not None else None,
				"clv_estimate": float(snap.clv_estimate) if snap.clv_estimate is not None else None,
				"loyalty_balance_points": balances.get(pid),
				"computed_at": snap.computed_at.isoformat() if snap.computed_at else None,
			}
		)

	return items, int(total)
