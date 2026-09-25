"""گزارش آماری صورتحساب و اشتراک پشتیبانی."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Set

from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from adapters.db.models.support.billing import (
	SupportInvoice,
	SupportPlan,
	SupportSubscription,
	SupportUsageCounter,
)
from adapters.db.models.support.ticket import Ticket
from app.services.support.support_billing_settings import (
	get_support_billing_mode,
	get_support_free_quota_per_month,
)
from app.services.support.support_entitlement_service import current_period_key


def get_support_billing_stats(
	db: Session,
	*,
	date_from: Optional[datetime] = None,
	date_to: Optional[datetime] = None,
) -> Dict[str, Any]:
	now = datetime.utcnow()
	if date_to is None:
		date_to = now
	if date_from is None:
		date_from = date_to - timedelta(days=30)

	paid_q = db.query(SupportInvoice).options(joinedload(SupportInvoice.plan)).filter(
		SupportInvoice.status == "paid",
		SupportInvoice.paid_at.isnot(None),
		SupportInvoice.paid_at >= date_from,
		SupportInvoice.paid_at <= date_to,
	)
	paid_invoices = paid_q.all()
	revenue = sum(float(i.amount or 0) for i in paid_invoices)
	paid_count = len(paid_invoices)
	failed_count = (
		db.query(SupportInvoice)
		.filter(
			SupportInvoice.status == "failed",
			SupportInvoice.issued_at >= date_from,
			SupportInvoice.issued_at <= date_to,
		)
		.count()
	)
	awaiting_payment_count = (
		db.query(SupportInvoice)
		.filter(
			SupportInvoice.status == "awaiting_payment",
			SupportInvoice.issued_at >= date_from,
			SupportInvoice.issued_at <= date_to,
		)
		.count()
	)

	# شمارش وضعیت صورت‌حساب‌ها در بازه (بر اساس issued_at)
	invoices_by_status: Dict[str, int] = {}
	status_rows = (
		db.query(SupportInvoice.status, func.count(SupportInvoice.id))
		.filter(
			SupportInvoice.issued_at >= date_from,
			SupportInvoice.issued_at <= date_to,
		)
		.group_by(SupportInvoice.status)
		.all()
	)
	for st, cnt in status_rows:
		invoices_by_status[str(st)] = int(cnt)

	# درآمد بر اساس پلن
	revenue_by_plan: List[Dict[str, Any]] = []
	plan_rev: Dict[str, Dict[str, Any]] = {}
	for inv in paid_invoices:
		name = inv.plan.name if inv.plan else f"plan#{inv.plan_id}"
		key = str(inv.plan_id)
		row = plan_rev.setdefault(
			key,
			{"plan_id": inv.plan_id, "plan_name": name, "revenue": 0.0, "paid_count": 0},
		)
		row["revenue"] += float(inv.amount or 0)
		row["paid_count"] += 1
	revenue_by_plan = sorted(plan_rev.values(), key=lambda x: x["revenue"], reverse=True)

	# درآمد بر اساس درگاه
	revenue_by_gateway: List[Dict[str, Any]] = []
	gw_rev: Dict[str, Dict[str, Any]] = {}
	for inv in paid_invoices:
		gw = (inv.gateway_provider or "نامشخص").strip() or "نامشخص"
		row = gw_rev.setdefault(gw, {"gateway": gw, "revenue": 0.0, "paid_count": 0})
		row["revenue"] += float(inv.amount or 0)
		row["paid_count"] += 1
	revenue_by_gateway = sorted(gw_rev.values(), key=lambda x: x["revenue"], reverse=True)

	active_subs = (
		db.query(SupportSubscription)
		.filter(SupportSubscription.status == "active")
		.count()
	)
	grace_subs = (
		db.query(SupportSubscription)
		.filter(SupportSubscription.status == "grace")
		.count()
	)
	active_or_grace = active_subs + grace_subs

	expiring_filter = (
		SupportSubscription.status == "active",
		SupportSubscription.ends_at.isnot(None),
		SupportSubscription.ends_at >= now,
		SupportSubscription.ends_at <= now + timedelta(days=7),
	)
	expiring_7d = db.query(SupportSubscription).filter(*expiring_filter).count()
	expiring_rows = (
		db.query(SupportSubscription)
		.options(joinedload(SupportSubscription.plan))
		.filter(*expiring_filter)
		.order_by(SupportSubscription.ends_at.asc())
		.limit(20)
		.all()
	)
	expiring_soon = [
		{
			"subscription_id": s.id,
			"user_id": s.user_id,
			"plan_id": s.plan_id,
			"plan_name": s.plan.name if s.plan else None,
			"status": s.status,
			"ends_at": s.ends_at.isoformat() if s.ends_at else None,
		}
		for s in expiring_rows
	]

	expired_in_period = (
		db.query(SupportSubscription)
		.filter(
			SupportSubscription.status == "expired",
			SupportSubscription.updated_at >= date_from,
			SupportSubscription.updated_at <= date_to,
		)
		.count()
	)

	# تفکیک بر اساس مدت پلن
	by_period: Dict[str, Any] = {}
	rows = (
		db.query(SupportPlan.period_months, func.count(SupportSubscription.id))
		.join(SupportSubscription, SupportSubscription.plan_id == SupportPlan.id)
		.filter(SupportSubscription.status.in_(("active", "grace")))
		.group_by(SupportPlan.period_months)
		.all()
	)
	for months, cnt in rows:
		by_period[str(months)] = int(cnt)

	# تفکیک اشتراک فعال بر اساس نام پلن
	subscriptions_by_plan: List[Dict[str, Any]] = []
	plan_sub_rows = (
		db.query(
			SupportPlan.id,
			SupportPlan.name,
			SupportPlan.period_months,
			func.count(SupportSubscription.id),
		)
		.join(SupportSubscription, SupportSubscription.plan_id == SupportPlan.id)
		.filter(SupportSubscription.status.in_(("active", "grace")))
		.group_by(SupportPlan.id, SupportPlan.name, SupportPlan.period_months)
		.order_by(func.count(SupportSubscription.id).desc())
		.all()
	)
	for pid, pname, months, cnt in plan_sub_rows:
		subscriptions_by_plan.append(
			{
				"plan_id": int(pid),
				"plan_name": pname,
				"period_months": int(months),
				"count": int(cnt),
			}
		)

	# MRR تقریبی
	mrr = 0.0
	for inv in paid_invoices:
		months = int(inv.period_months or 1) or 1
		mrr += float(inv.amount or 0) / months

	# سری روزانه درآمد
	timeseries: Dict[str, float] = {}
	for inv in paid_invoices:
		if not inv.paid_at:
			continue
		key = inv.paid_at.strftime("%Y-%m-%d")
		timeseries[key] = timeseries.get(key, 0.0) + float(inv.amount or 0)
	series = [{"date": k, "revenue": v} for k, v in sorted(timeseries.items())]

	payment_attempts = paid_count + failed_count
	success_rate = round((paid_count / payment_attempts) * 100, 1) if payment_attempts else None

	# کاربرهای دارای اشتراک فعال/مهلت
	subscriber_ids: Set[int] = {
		int(uid)
		for (uid,) in db.query(SupportSubscription.user_id)
		.filter(SupportSubscription.status.in_(("active", "grace")))
		.distinct()
		.all()
	}

	# CSAT: میانگین امتیاز تیکت‌های دارای csat در بازه (بر اساس csat_submitted_at یا updated_at)
	csat_q = db.query(Ticket.user_id, Ticket.csat_rating).filter(
		Ticket.csat_rating.isnot(None),
		Ticket.csat_submitted_at.isnot(None),
		Ticket.csat_submitted_at >= date_from,
		Ticket.csat_submitted_at <= date_to,
	)
	csat_rows = csat_q.all()
	sub_ratings = [int(r) for uid, r in csat_rows if int(uid) in subscriber_ids and r is not None]
	non_ratings = [int(r) for uid, r in csat_rows if int(uid) not in subscriber_ids and r is not None]

	def _avg(vals: List[int]) -> Optional[float]:
		if not vals:
			return None
		return round(sum(vals) / len(vals), 2)

	# تیکت به‌ازای مشترک در بازه
	tickets_by_subscribers = 0
	if subscriber_ids:
		tickets_by_subscribers = (
			db.query(Ticket)
			.filter(
				Ticket.user_id.in_(subscriber_ids),
				Ticket.created_at >= date_from,
				Ticket.created_at <= date_to,
			)
			.count()
		)
	tickets_per_subscriber = (
		round(tickets_by_subscribers / len(subscriber_ids), 2) if subscriber_ids else 0.0
	)

	# سهمیه hybrid
	billing_mode = get_support_billing_mode(db)
	free_quota = get_support_free_quota_per_month(db)
	period_key = current_period_key(now)
	usage_rows = (
		db.query(SupportUsageCounter.tickets_created)
		.filter(SupportUsageCounter.period_key == period_key)
		.all()
	)
	usage_vals = [int(r[0] or 0) for r in usage_rows]
	hybrid_usage = {
		"billing_mode": billing_mode,
		"period_key": period_key,
		"free_quota_per_month": free_quota,
		"users_with_usage": len(usage_vals),
		"avg_tickets_created": round(sum(usage_vals) / len(usage_vals), 2) if usage_vals else 0.0,
		"max_tickets_created": max(usage_vals) if usage_vals else 0,
		"quota_utilization_pct": (
			round((sum(usage_vals) / (len(usage_vals) * free_quota)) * 100, 1)
			if usage_vals and free_quota > 0
			else None
		),
	}

	return {
		"date_from": date_from.isoformat(),
		"date_to": date_to.isoformat(),
		"revenue": revenue,
		"paid_count": paid_count,
		"failed_count": failed_count,
		"awaiting_payment_count": awaiting_payment_count,
		"success_rate_pct": success_rate,
		"active_subscriptions": active_or_grace,
		"active_only": active_subs,
		"grace_subscriptions": grace_subs,
		"expiring_in_7_days": expiring_7d,
		"expiring_soon": expiring_soon,
		"expired_in_period": expired_in_period,
		"subscriptions_by_period_months": by_period,
		"subscriptions_by_plan": subscriptions_by_plan,
		"revenue_by_plan": revenue_by_plan,
		"revenue_by_gateway": revenue_by_gateway,
		"invoices_by_status": invoices_by_status,
		"approximate_mrr": mrr,
		"timeseries": series,
		"csat": {
			"subscribers_avg": _avg(sub_ratings),
			"subscribers_count": len(sub_ratings),
			"non_subscribers_avg": _avg(non_ratings),
			"non_subscribers_count": len(non_ratings),
		},
		"tickets_per_subscriber": tickets_per_subscriber,
		"tickets_by_subscribers_in_period": tickets_by_subscribers,
		"subscriber_user_count": len(subscriber_ids),
		"hybrid_usage": hybrid_usage,
	}
