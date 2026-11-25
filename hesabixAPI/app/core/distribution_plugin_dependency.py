"""بررسی فعال بودن افزونه پخش مویرگی."""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.plugin_license import is_plugin_active


PLUGIN_CODE = "distribution"


def check_distribution_plugin_active(db: Session, business_id: int) -> bool:
	return is_plugin_active(db, business_id, PLUGIN_CODE)
