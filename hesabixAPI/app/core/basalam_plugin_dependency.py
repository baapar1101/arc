"""Plugin activation checks for Basalam integration."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy.orm import Session

from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin


PLUGIN_CODE = "basalam_connector"


def check_basalam_plugin_active(db: Session, business_id: int) -> bool:
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
        ends_at_val = license_row.ends_at.date() if isinstance(license_row.ends_at, datetime) else license_row.ends_at
        if ends_at_val < datetime.utcnow().date():
            return False
    return True
