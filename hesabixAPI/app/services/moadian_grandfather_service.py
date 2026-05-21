"""اعطای لایسنس رایگان به کسب‌وکارهایی که قبل از افزونه‌سازی از مودیان استفاده می‌کردند."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Set

from sqlalchemy import cast, Boolean
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin, MarketplacePluginPlan
from adapters.db.models.tax_setting import TaxSetting
from app.core.moadian_plugin_dependency import PLUGIN_CODE
from app.services.invoice_service import SUPPORTED_INVOICE_TYPES


def grant_moadian_grandfather_licenses(db: Session) -> Dict[str, Any]:
	"""
	کسب‌وکارهای دارای تنظیمات مودیان یا فاکتور در کارپوشه → لایسنس lifetime (یک‌بار، idempotent).
	"""
	plugin = (
		db.query(MarketplacePlugin)
		.filter(MarketplacePlugin.code == PLUGIN_CODE)
		.first()
	)
	if not plugin:
		return {"ok": False, "error": "PLUGIN_NOT_IN_CATALOG", "granted": 0}

	lifetime_plan = (
		db.query(MarketplacePluginPlan)
		.filter(
			MarketplacePluginPlan.plugin_id == plugin.id,
			MarketplacePluginPlan.period == "lifetime",
			MarketplacePluginPlan.is_active == True,  # noqa: E712
		)
		.first()
	)
	if not lifetime_plan:
		lifetime_plan = (
			db.query(MarketplacePluginPlan)
			.filter(MarketplacePluginPlan.plugin_id == plugin.id)
			.order_by(MarketplacePluginPlan.id.asc())
			.first()
		)
	if not lifetime_plan:
		return {"ok": False, "error": "NO_PLAN", "granted": 0}

	business_ids: Set[int] = set()

	for row in db.query(TaxSetting.business_id).distinct().all():
		if row[0] is not None:
			business_ids.add(int(row[0]))

	_extra = cast(Document.extra_info, JSONB)
	workspace_rows = (
		db.query(Document.business_id)
		.filter(
			Document.document_type.in_(list(SUPPORTED_INVOICE_TYPES)),
			cast(_extra["tax_workspace"], Boolean) == True,  # noqa: E712
		)
		.distinct()
		.all()
	)
	for row in workspace_rows:
		if row[0] is not None:
			business_ids.add(int(row[0]))

	granted = 0
	now = datetime.utcnow()
	grandfathered: List[int] = []

	for bid in sorted(business_ids):
		existing = (
			db.query(BusinessPlugin)
			.filter(
				BusinessPlugin.business_id == bid,
				BusinessPlugin.plugin_id == plugin.id,
			)
			.first()
		)
		if existing:
			if existing.status != "active":
				existing.status = "active"
				existing.ends_at = None
				existing.is_trial = False
				existing.updated_at = now
				granted += 1
				grandfathered.append(bid)
			continue

		db.add(
			BusinessPlugin(
				business_id=bid,
				plugin_id=plugin.id,
				plan_id=lifetime_plan.id,
				status="active",
				starts_at=now,
				ends_at=None,
				auto_renew=False,
				is_trial=False,
				extra_info='{"source":"grandfather"}',
			)
		)
		granted += 1
		grandfathered.append(bid)

	if granted:
		db.flush()

	return {
		"ok": True,
		"eligible_businesses": len(business_ids),
		"granted_or_reactivated": granted,
		"business_ids": grandfathered,
	}
