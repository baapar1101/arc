"""بررسی فعال بودن افزونه پخش مویرگی."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy.orm import Session

from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin


PLUGIN_CODE = "distribution"


def check_distribution_plugin_active(db: Session, business_id: int) -> bool:
	plugin = (
		db.query(MarketplacePlugin)
		.filter(
			MarketplacePlugin.code == PLUGIN_CODE,
			MarketplacePlugin.is_active == True,  # noqa: E712
		)
		.first()
	)
	if not plugin:
		return False
	license_row = (
		db.query(BusinessPlugin)
		.filter(
			BusinessPlugin.business_id == business_id,
			BusinessPlugin.plugin_id == plugin.id,
			BusinessPlugin.status == "active",
		)
		.first()
	)
	if not license_row:
		return False
	if license_row.ends_at:
		ea = license_row.ends_at
		ends_at_val = ea.date() if isinstance(ea, datetime) else ea
		now_val = datetime.utcnow().date()
		if ends_at_val < now_val:
			return False
	return True
