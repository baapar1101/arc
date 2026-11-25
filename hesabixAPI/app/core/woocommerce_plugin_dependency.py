"""بررسی فعال بودن افزونهٔ بازار «ووکامرس / ArcWOC» برای کسب‌وکار."""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.plugin_license import is_plugin_active

PLUGIN_CODE = "woocommerce_hesabix"


def check_woocommerce_plugin_active(db: Session, business_id: int) -> bool:
	return is_plugin_active(db, business_id, PLUGIN_CODE)
