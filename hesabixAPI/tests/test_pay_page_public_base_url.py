from unittest.mock import MagicMock, patch

import pytest

from app.core.responses import ApiError
from app.services.business_pay_page_service import public_pay_page_path
from app.services.system_settings_service import (
	_normalize_pay_page_public_origin,
	get_pay_page_public_base_url,
	resolve_pay_page_public_base_url,
	set_pay_page_system_settings,
)


def test_public_pay_page_path_omits_u_on_vanity_domain():
	assert public_pay_page_path("shop-ali", vanity=True) == "/shop-ali"
	assert public_pay_page_path("shop-ali", vanity=False) == "/u/shop-ali"
	assert public_pay_page_path("", vanity=True) is None


def test_normalize_pay_page_origin_empty_and_full_url():
	assert _normalize_pay_page_public_origin("") == ""
	assert _normalize_pay_page_public_origin("   ") == ""
	assert _normalize_pay_page_public_origin("https://hesabix.ir/") == "https://hesabix.ir"
	assert _normalize_pay_page_public_origin("https://hesabix.ir/u/shop-ali") == "https://hesabix.ir"
	assert _normalize_pay_page_public_origin("https://hesabix.ir/public") == "https://hesabix.ir"
	assert _normalize_pay_page_public_origin("http://localhost:8080/u/x") == "http://localhost:8080"


def test_normalize_pay_page_origin_rejects_invalid():
	with pytest.raises(ApiError) as exc:
		_normalize_pay_page_public_origin("hesabix.ir")
	assert exc.value.code == "INVALID_PAY_PAGE_PUBLIC_BASE_URL"
	with pytest.raises(ApiError):
		_normalize_pay_page_public_origin("ftp://hesabix.ir")


def test_resolve_pay_page_public_base_url_falls_back_when_unset():
	db = MagicMock()
	with patch(
		"app.services.system_settings_service.get_pay_page_public_base_url",
		return_value="",
	), patch(
		"app.services.system_settings_service.resolve_public_app_base_url_for_public_links",
		return_value="https://app.hesabix.com",
	):
		assert resolve_pay_page_public_base_url(db) == "https://app.hesabix.com"


def test_resolve_pay_page_public_base_url_uses_custom_domain():
	db = MagicMock()
	with patch(
		"app.services.system_settings_service.get_pay_page_public_base_url",
		return_value="https://hesabix.ir",
	):
		assert resolve_pay_page_public_base_url(db) == "https://hesabix.ir"


def test_get_pay_page_public_base_url_ignores_corrupt_stored_value():
	db = MagicMock()
	row = MagicMock()
	row.value_string = "not-a-url"
	with patch("app.services.system_settings_service._get_setting", return_value=row):
		assert get_pay_page_public_base_url(db) == ""


def test_set_pay_page_system_settings_stores_origin_or_clears():
	db = MagicMock()
	with patch("app.services.system_settings_service._upsert_setting_string") as upsert, patch(
		"app.services.system_settings_service.get_pay_page_system_settings",
		return_value={"public_base_url": "https://hesabix.ir", "effective_public_base_url": "https://hesabix.ir"},
	):
		set_pay_page_system_settings(db, public_base_url="https://hesabix.ir/u/demo")
	upsert.assert_called_once()
	assert upsert.call_args.args[1] == "pay_page_public_base_url"
	assert upsert.call_args.args[2] == "https://hesabix.ir"
	db.commit.assert_called_once()

	db.reset_mock()
	with patch("app.services.system_settings_service._upsert_setting_string") as upsert, patch(
		"app.services.system_settings_service.get_pay_page_system_settings",
		return_value={"public_base_url": "", "effective_public_base_url": "https://app.example"},
	):
		set_pay_page_system_settings(db, public_base_url="  ")
	assert upsert.call_args.args[2] == ""
