"""Plugin activation checks for Basalam integration."""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.plugin_license import is_plugin_active


PLUGIN_CODE = "basalam_connector"


def check_basalam_plugin_active(db: Session, business_id: int) -> bool:
    return is_plugin_active(db, business_id, PLUGIN_CODE)
