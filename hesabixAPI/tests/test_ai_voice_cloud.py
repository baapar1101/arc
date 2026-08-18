from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest

from app.core.responses import ApiError
from app.services.voice.contracts import VoiceResolveRequest, provider_is_cloud
from app.services.voice.openai_audio import OpenAITranscriptionSTT
from app.services.voice.voice_catalog import cloud_audio_allowed


class _FakePolicy:
	allow_cloud_audio = False


class _FakeBiz:
	allow_cloud_audio = True


def test_cloud_audio_requires_global_and_business(monkeypatch):
	class RepoPolicy:
		def __init__(self, db):
			pass

		def get_or_create(self):
			return _FakePolicy()

	class RepoBiz:
		def __init__(self, db):
			pass

		def get_by_business(self, business_id):
			return _FakeBiz()

	monkeypatch.setattr(
		"app.services.voice.voice_catalog.AIVoicePolicyRepository",
		RepoPolicy,
	)
	monkeypatch.setattr(
		"app.services.voice.voice_catalog.BusinessAIVoiceSettingsRepository",
		RepoBiz,
	)
	assert cloud_audio_allowed(SimpleNamespace(), 1) is False
	_FakePolicy.allow_cloud_audio = True
	assert cloud_audio_allowed(SimpleNamespace(), 1) is True
	assert cloud_audio_allowed(SimpleNamespace(), None) is False


@pytest.mark.asyncio
async def test_openai_stt_posts_wav():
	stt = OpenAITranscriptionSTT(
		api_key="sk-test",
		api_base_url="https://api.openai.com/v1",
		model_id="whisper-1",
		language="fa",
	)
	mock_response = SimpleNamespace(status_code=200, json=lambda: {"text": "فروش امروز"}, text="")

	class _Client:
		async def __aenter__(self):
			return self

		async def __aexit__(self, *args):
			return False

		async def post(self, url, headers=None, data=None, files=None, json=None):
			assert "transcriptions" in url
			assert files and "file" in files
			assert data["model"] == "whisper-1"
			return mock_response

	with patch("app.services.voice.openai_audio.httpx.AsyncClient", return_value=_Client()):
		result = await stt.transcribe_pcm16(b"\x00\x00" * 32, 16000)
	assert result.text == "فروش امروز"
	assert result.engine == "openai_transcription"


def test_cloud_disabled_error_code():
	from app.services.voice.runtime import _require_cloud_or_raise
	from adapters.db.models.ai_voice_model import AIVoiceModel

	model = AIVoiceModel(
		code="stt-openai-whisper-1",
		kind="stt",
		display_name="x",
		provider="openai",
		model_id="whisper-1",
	)
	with pytest.raises(ApiError) as exc:
		_require_cloud_or_raise(False, model)
	assert exc.value.error_code == "CLOUD_AUDIO_DISABLED"
	assert provider_is_cloud("openai")
