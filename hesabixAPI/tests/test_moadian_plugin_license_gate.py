"""Gate افزونه مودیان."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from app.core.moadian_plugin_dependency import (
	PLUGIN_CODE,
	check_moadian_plugin_active,
	ensure_moadian_plugin_active,
)
from app.core.responses import ApiError


def test_ensure_moadian_plugin_raises_when_inactive() -> None:
	db = MagicMock()
	with patch(
		"app.core.moadian_plugin_dependency.check_moadian_plugin_active",
		return_value=False,
	):
		with pytest.raises(ApiError) as ei:
			ensure_moadian_plugin_active(db, 1)
	err = ei.value.detail.get("error") or {}
	assert err.get("code") == "MOADIAN_PLUGIN_NOT_ACTIVE"
	assert err.get("details", {}).get("plugin_code") == PLUGIN_CODE


def test_ensure_moadian_plugin_passes_when_active() -> None:
	db = MagicMock()
	with patch(
		"app.core.moadian_plugin_dependency.check_moadian_plugin_active",
		return_value=True,
	):
		ensure_moadian_plugin_active(db, 1)


def test_check_moadian_plugin_active_false_without_catalog() -> None:
	db = MagicMock()
	db.query.return_value.filter.return_value.first.return_value = None
	assert check_moadian_plugin_active(db, 99) is False
