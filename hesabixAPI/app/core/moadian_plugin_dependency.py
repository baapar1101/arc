"""بررسی فعال بودن افزونه اتصال به سامانه مودیان."""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.plugin_license import is_plugin_active
from app.core.responses import ApiError


PLUGIN_CODE = "moadian_tax_integration"


def check_moadian_plugin_active(db: Session, business_id: int) -> bool:
	return is_plugin_active(db, business_id, PLUGIN_CODE)


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
