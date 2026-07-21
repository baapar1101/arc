"""گزارش آماری صورتحساب و اشتراک پشتیبانی."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Dict, Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from adapters.db.models.support.billing import SupportInvoice, SupportPlan, SupportSubscription


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

	paid_q = db.query(SupportInvoice).filter(
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

	active_subs = (
		db.query(SupportSubscription)
		.filter(SupportSubscription.status.in_(("active", "grace")))
		.count()
	)
	expiring_7d = (
		db.query(SupportSubscription)
		.filter(
			SupportSubscription.status == "active",
			SupportSubscription.ends_at.isnot(None),
			SupportSubscription.ends_at >= now,
			SupportSubscription.ends_at <= now + timedelta(days=7),
		)
		.count()
	)
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

	return {
		"date_from": date_from.isoformat(),
		"date_to": date_to.isoformat(),
		"revenue": revenue,
		"paid_count": paid_count,
		"failed_count": failed_count,
		"active_subscriptions": active_subs,
		"expiring_in_7_days": expiring_7d,
		"expired_in_period": expired_in_period,
		"subscriptions_by_period_months": by_period,
		"approximate_mrr": mrr,
		"timeseries": series,
	}
