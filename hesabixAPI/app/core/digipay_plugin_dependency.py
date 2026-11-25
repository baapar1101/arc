"""بررسی فعال بودن افزونه پرداخت اعتباری دیجی‌پی."""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.i18n import get_translator
from app.core.plugin_license import is_plugin_active
from app.core.responses import ApiError

PLUGIN_CODE = "digipay_credit"


def check_digipay_plugin_active(db: Session, business_id: int) -> bool:
	return is_plugin_active(db, business_id, PLUGIN_CODE)


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
