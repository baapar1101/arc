"""تست سرویس برچسب فاکتور."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from app.core.responses import ApiError
from app.services.invoice_tag_service import update_invoice_tag


def _api_error_code(exc: ApiError) -> str:
	detail = exc.detail
	if isinstance(detail, dict):
		err = detail.get("error")
		if isinstance(err, dict):
			return str(err.get("code") or "")
	return ""


def _tag(*, is_system: bool = False, name: str = "سفارشی", tag_id: int = 1) -> MagicMock:
	tag = MagicMock()
	tag.id = tag_id
	tag.is_system = is_system
	tag.name = name
	tag.is_active = True
	tag.color = None
	tag.sort_order = 0
	return tag


def _db_with_tag(tag: MagicMock) -> MagicMock:
	db = MagicMock()
	db.query.return_value.filter.return_value.first.return_value = tag
	return db


def test_update_system_tag_rename_blocked() -> None:
	tag = _tag(is_system=True, name="فروش سایت")
	db = _db_with_tag(tag)
	with pytest.raises(ApiError) as exc:
		update_invoice_tag(db, 1, 1, {"name": "نام جدید"})
	assert _api_error_code(exc.value) == "SYSTEM_TAG_PROTECTED"


def test_update_system_tag_deactivate_blocked() -> None:
	tag = _tag(is_system=True, name="فروش سایت")
	db = _db_with_tag(tag)
	with pytest.raises(ApiError) as exc:
		update_invoice_tag(db, 1, 1, {"is_active": False})
	assert _api_error_code(exc.value) == "SYSTEM_TAG_PROTECTED"


def test_update_system_tag_same_name_allowed() -> None:
	tag = _tag(is_system=True, name="فروش سایت")
	db = _db_with_tag(tag)
	result = update_invoice_tag(db, 1, 1, {"name": "فروش سایت"})
	assert result["name"] == "فروش سایت"
	db.commit.assert_called_once()


def test_update_custom_tag_rename_allowed() -> None:
	tag = _tag(is_system=False, name="VIP")
	db = _db_with_tag(tag)
	db.query.return_value.filter.return_value.first.side_effect = [tag, None]
	result = update_invoice_tag(db, 1, 1, {"name": "VIP طلایی"})
	assert tag.name == "VIP طلایی"
	assert result["name"] == "VIP طلایی"
	db.commit.assert_called_once()
