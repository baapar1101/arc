"""تست نقش Media Edge و جلوگیری از عملیات روی worker عمومی."""
from __future__ import annotations

import os

import pytest

from app.core.responses import ApiError
from app.core.settings import get_settings


@pytest.fixture(autouse=True)
def _clear_settings_cache():
	get_settings.cache_clear()
	yield
	get_settings.cache_clear()
	# پاکسازی envهای تست
	for k in ("HESABIX_PROCESS_ROLE", "HESABIX_MEDIA_EDGE_URL", "HESABIX_MEDIA_EDGE_TOKEN"):
		os.environ.pop(k, None)
	get_settings.cache_clear()


def test_auto_role_allows_media_ops(monkeypatch):
	monkeypatch.delenv("HESABIX_PROCESS_ROLE", raising=False)
	get_settings.cache_clear()
	from app.services.telephony import media_edge as me

	assert me.process_role() == "auto"
	assert me.is_media_edge_process() is True
	me.require_media_edge_process()  # no raise


def test_api_role_blocks_media_ops(monkeypatch):
	monkeypatch.setenv("HESABIX_PROCESS_ROLE", "api")
	get_settings.cache_clear()
	from app.services.telephony import media_edge as me

	assert me.is_media_edge_process() is False
	with pytest.raises(ApiError) as ei:
		me.require_media_edge_process()
	detail = ei.value.detail
	assert isinstance(detail, dict)
	assert detail.get("error", {}).get("code") == "SOFTPHONE_MEDIA_EDGE_REQUIRED"


def test_media_edge_role_allows(monkeypatch):
	monkeypatch.setenv("HESABIX_PROCESS_ROLE", "media_edge")
	get_settings.cache_clear()
	from app.services.telephony import media_edge as me

	assert me.is_media_edge_process() is True
	me.require_media_edge_process()
