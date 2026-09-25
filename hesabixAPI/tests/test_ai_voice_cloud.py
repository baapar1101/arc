from __future__ import annotations

import json
from types import SimpleNamespace
from unittest.mock import patch

import httpx
import pytest

from app.core.responses import ApiError
from app.services.voice.contracts import VoiceResolveRequest, provider_is_cloud
from app.services.voice.openai_audio import OpenAITTSEngine, OpenAITranscriptionSTT
from app.services.voice.voice_catalog import cloud_audio_allowed


class _StreamResp:
	def __init__(self, status_code: int, body: bytes):
		self.status_code = status_code
		self._body = body
		self._raise = None

	@classmethod
	def json_ok(cls, payload: dict, status_code: int = 200):
		return cls(status_code, json.dumps(payload).encode("utf-8"))

	@classmethod
	def fail(cls, status_code: int, text: str = "err"):
		return cls(status_code, text.encode("utf-8"))

	@classmethod
	def protocol_error(cls, status_code: int = 500):
		obj = cls(status_code, b"")
		obj._raise = httpx.RemoteProtocolError("incomplete chunked read")
		return obj

	async def aiter_bytes(self):
		if self._raise:
			raise self._raise
		yield self._body


class _StreamCM:
	def __init__(self, resp):
		self._resp = resp

	async def __aenter__(self):
		return self._resp

	async def __aexit__(self, *args):
		return False


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

	class _Client:
		async def __aenter__(self):
			return self

		async def __aexit__(self, *args):
			return False

		def stream(self, method, url, headers=None, data=None, files=None, json=None):
			assert method == "POST"
			assert "transcriptions" in url
			assert files and "file" in files
			assert data["model"] == "whisper-1"
			return _StreamCM(_StreamResp.json_ok({"text": "فروش امروز"}))

	with patch("app.services.voice.openai_audio.httpx.AsyncClient", return_value=_Client()):
		result = await stt.transcribe_pcm16(b"\x00\x00" * 32, 16000)
	assert result.text == "فروش امروز"
	assert result.engine == "openai_transcription"


@pytest.mark.asyncio
async def test_openai_stt_parspack_uses_translations_first():
	stt = OpenAITranscriptionSTT(
		api_key="sk-test",
		api_base_url="https://ai.parspack.com/v1",
		model_id="openai/whisper-1",
		language="fa",
		audio_endpoint="auto",
	)
	urls: list[str] = []

	class _Client:
		async def __aenter__(self):
			return self

		async def __aexit__(self, *args):
			return False

		def stream(self, method, url, headers=None, data=None, files=None, json=None):
			urls.append(url)
			assert data["model"] == "openai/whisper-1"
			assert "language" not in data
			assert "translations" in url
			return _StreamCM(_StreamResp.json_ok({"text": "hello"}))

	with patch("app.services.voice.openai_audio.httpx.AsyncClient", return_value=_Client()):
		result = await stt.transcribe_pcm16(b"\x00\x00" * 32, 16000)
	assert result.text == "hello"
	assert urls and "translations" in urls[0]


@pytest.mark.asyncio
async def test_openai_stt_falls_back_after_protocol_error():
	stt = OpenAITranscriptionSTT(
		api_key="sk-test",
		api_base_url="https://api.openai.com/v1",
		model_id="whisper-1",
		language="fa",
		audio_endpoint="auto",
	)
	urls: list[str] = []

	class _Client:
		async def __aenter__(self):
			return self

		async def __aexit__(self, *args):
			return False

		def stream(self, method, url, headers=None, data=None, files=None, json=None):
			urls.append(url)
			if "transcriptions" in url:
				return _StreamCM(_StreamResp.protocol_error(500))
			return _StreamCM(_StreamResp.json_ok({"text": "ok"}))

	with patch("app.services.voice.openai_audio.httpx.AsyncClient", return_value=_Client()):
		result = await stt.transcribe_pcm16(b"\x00\x00" * 32, 16000)
	assert result.text == "ok"
	assert any("transcriptions" in u for u in urls)
	assert any("translations" in u for u in urls)


@pytest.mark.asyncio
async def test_openai_tts_prefers_wav_then_pcm():
	engine = OpenAITTSEngine(
		api_key="sk-test",
		api_base_url="https://ai.parspack.com/v1",
		model_id="openai/gpt-4o-mini-tts",
		voice_id="alloy",
		response_format="wav",
	)
	wav = b"RIFF\x24\x00\x00\x00WAVEfmt "
	# Minimal valid-looking payload is decoded by looks_like_wav; use a tiny real wav.
	from app.services.voice.audio_wav import pcm16_to_wav

	wav = pcm16_to_wav(b"\x00\x01" * 32, 24000)
	ok = SimpleNamespace(status_code=200, content=wav, text="")
	formats: list[str] = []

	class _Client:
		async def __aenter__(self):
			return self

		async def __aexit__(self, *args):
			return False

		async def post(self, url, headers=None, data=None, files=None, json=None):
			assert url.endswith("/audio/speech")
			assert json["model"] == "openai/gpt-4o-mini-tts"
			formats.append(json["response_format"])
			return ok

	with patch("app.services.voice.openai_audio.httpx.AsyncClient", return_value=_Client()):
		pcm, rate = await engine.synthesize_pcm16_async("سلام")
	assert formats == ["wav"]
	assert rate == 24000
	assert len(pcm) == 64


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
