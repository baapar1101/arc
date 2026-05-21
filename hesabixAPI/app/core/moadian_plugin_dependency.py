"""بررسی فعال بودن افزونه اتصال به سامانه مودیان."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy.orm import Session

from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin
from app.core.responses import ApiError


PLUGIN_CODE = "moadian_tax_integration"


def check_moadian_plugin_active(db: Session, business_id: int) -> bool:
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
		ends_at_val = (
			license_row.ends_at.date()
			if isinstance(license_row.ends_at, datetime)
			else license_row.ends_at
		)
		if ends_at_val < datetime.utcnow().date():
			return False
	return True


def ensure_moadian_plugin_active(db: Session, business_id: int) -> None:
	"""در صورت غیرفعال بودن افزونه، خطای 403 برمی‌گرداند."""
	if check_moadian_plugin_active(db, business_id):
		return
	raise ApiError(
		"MOADIAN_PLUGIN_NOT_ACTIVE",
		"افزونه اتصال به سامانه مودیان برای این کسب‌وکار فعال نیست.",
		http_status=403,
		details={
			"plugin_code": PLUGIN_CODE,
			"required_action": "activate_plugin",
			"marketplace_url": "/marketplace",
		},
	)
