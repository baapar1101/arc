"""بررسی فعال بودن افزونه پرداخت اعتباری دیجی‌پی."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy.orm import Session

from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin
from app.core.i18n import get_translator
from app.core.responses import ApiError

PLUGIN_CODE = "digipay_credit"


def check_digipay_plugin_active(db: Session, business_id: int) -> bool:
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


def ensure_digipay_plugin_active(db: Session, business_id: int, locale: str = "fa") -> None:
	if check_digipay_plugin_active(db, business_id):
		return
	tr = get_translator(locale)
	raise ApiError(
		"DIGIPAY_PLUGIN_NOT_ACTIVE",
		tr.t(
			"DIGIPAY_PLUGIN_NOT_ACTIVE",
			"افزونه پرداخت اعتباری دیجی‌پی برای این کسب‌وکار فعال نیست."
			if locale == "fa"
			else "The DigiPay credit payment plugin is not active for this business.",
		),
		http_status=403,
		details={
			"plugin_code": PLUGIN_CODE,
			"required_action": "activate_plugin",
			"marketplace_url": "/marketplace",
		},
	)
