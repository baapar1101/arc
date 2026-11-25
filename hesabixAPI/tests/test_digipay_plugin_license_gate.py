"""گیت لایسنس افزونه پرداخت اعتباری دیجی‌پی."""

from __future__ import annotations

from datetime import datetime, timedelta
from unittest.mock import MagicMock

from app.core.digipay_plugin_dependency import PLUGIN_CODE, check_digipay_plugin_active


def _mock_db_with_license(*, plugin_active: bool = True, business_active: bool = True, expired: bool = False):
	db = MagicMock()
	plugin = MagicMock()
	plugin.id = 42
	plugin.is_active = plugin_active

	license_row = None
	if business_active:
		license_row = MagicMock()
		license_row.status = "active"
		if expired:
			license_row.ends_at = datetime.utcnow() - timedelta(days=1)
		else:
			license_row.ends_at = datetime.utcnow() + timedelta(days=30)

	def query_side_effect(model):
		q = MagicMock()
		if model.__name__ == "MarketplacePlugin":
			q.filter.return_value.first.return_value = plugin if plugin_active else None
		elif model.__name__ == "BusinessPlugin":
			q.filter.return_value.first.return_value = license_row
		return q

	db.query.side_effect = query_side_effect
	return db


def test_plugin_active_when_licensed():
	assert check_digipay_plugin_active(_mock_db_with_license(), 1) is True


def test_plugin_inactive_when_no_marketplace_plugin():
	assert check_digipay_plugin_active(_mock_db_with_license(plugin_active=False), 1) is False


def test_plugin_inactive_when_no_business_license():
	assert check_digipay_plugin_active(_mock_db_with_license(business_active=False), 1) is False


def test_plugin_inactive_when_expired():
	assert check_digipay_plugin_active(_mock_db_with_license(expired=True), 1) is False


def test_plugin_code_constant():
	assert PLUGIN_CODE == "digipay_credit"
