"""Adapters for OpenAI-compatible /v1/audio/transcriptions and /v1/audio/speech."""

from __future__ import annotations

import time
from typing import Any, Optional

import httpx

from app.services.voice.audio_wav import looks_like_wav, pcm16_to_wav, wav_to_pcm16
from app.services.voice.contracts import TranscriptResult
from app.services.voice.tts import _resample_pcm16_mono

_DEFAULT_TIMEOUT = 45.0
_OPENAI_TTS_PCM_RATE = 24000


def _join_url(base: str | None, path: str) -> str:
	root = (base or "https://api.openai.com/v1").rstrip("/")
	if root.endswith("/v1"):
		return f"{root}/{path.lstrip('/')}"
	return f"{root}/v1/{path.lstrip('/')}"


class OpenAITranscriptionSTT:
	engine_name = "openai_transcription"
	is_cloud = True

	def __init__(
		self,
		*,
		api_key: str,
		api_base_url: str | None,
		model_id: str,
		language: str = "fa",
		timeout: float = _DEFAULT_TIMEOUT,
		audio_endpoint: str = "auto",
	) -> None:
		self.api_key = api_key
		self.api_base_url = api_base_url
		self.model_id = model_id
		self.language = language
		self.timeout = timeout
		self.audio_endpoint = (audio_endpoint or "auto").strip().lower() or "auto"

	def _audio_paths(self) -> list[str]:
		if self.audio_endpoint in ("translations", "translation"):
			return ["audio/translations"]
		if self.audio_endpoint in ("transcriptions", "transcription"):
			return ["audio/transcriptions"]
		return ["audio/transcriptions", "audio/translations"]

	async def transcribe_pcm16(
		self,
		pcm16: bytes,
		sample_rate_hz: int,
		*,
		language: str | None = None,
	) -> TranscriptResult:
		started = time.perf_counter()
		wav = pcm16_to_wav(pcm16, sample_rate_hz)
		lang = (language or self.language or "fa").strip() or "fa"
		headers = {"Authorization": f"Bearer {self.api_key}"}
		last_error = ""
		async with httpx.AsyncClient(timeout=self.timeout) as client:
			for path in self._audio_paths():
				url = _join_url(self.api_base_url, path)
				data: dict[str, Any] = {"model": self.model_id}
				if path.endswith("transcriptions") and lang and lang != "auto":
					data["language"] = lang
				response = await client.post(
					url,
					headers=headers,
					data=data,
					files={"file": ("utterance.wav", wav, "audio/wav")},
				)
				if response.status_code < 400:
					payload = response.json()
					text = ""
					if isinstance(payload, dict):
						text = str(payload.get("text") or "").strip()
					elif isinstance(payload, str):
						text = payload.strip()
					elapsed = int((time.perf_counter() - started) * 1000)
					return TranscriptResult(
						text=text,
						language=lang,
						engine=self.engine_name,
						model_id=self.model_id,
						duration_ms=elapsed,
					)
				last_error = f"STT ابری ناموفق ({response.status_code}): {response.text[:400]}"
				if response.status_code not in (400, 404, 405, 422):
					break
		raise RuntimeError(last_error or "STT ابری ناموفق")


class OpenAITTSEngine:
	engine_name = "openai_tts"
	is_cloud = True
	dummy = False

	def __init__(
		self,
		*,
		api_key: str,
		api_base_url: str | None,
		model_id: str,
		voice_id: str | None = None,
		timeout: float = _DEFAULT_TIMEOUT,
	) -> None:
		self.api_key = api_key
		self.api_base_url = api_base_url
		self.model_id = model_id
		self.voice_id = (voice_id or "alloy").strip() or "alloy"
		self.timeout = timeout

	async def synthesize_pcm16_async(self, text: str) -> tuple[bytes, int]:
		url = _join_url(self.api_base_url, "audio/speech")
		headers = {
			"Authorization": f"Bearer {self.api_key}",
			"Content-Type": "application/json",
		}
		body = {
			"model": self.model_id,
			"voice": self.voice_id,
			"input": text,
			"response_format": "pcm",
		}
		async with httpx.AsyncClient(timeout=self.timeout) as client:
			response = await client.post(url, headers=headers, json=body)
			if response.status_code >= 400 and "pcm" in (response.text or "").lower():
				body["response_format"] = "wav"
				response = await client.post(url, headers=headers, json=body)
		if response.status_code >= 400:
			raise RuntimeError(
				f"TTS ابری ناموفق ({response.status_code}): {response.text[:400]}"
			)
		raw = response.content or b""
		if looks_like_wav(raw):
			pcm, rate, channels = wav_to_pcm16(raw)
			if channels != 1:
				raise RuntimeError("خروجی TTS ابری باید مونو باشد")
			return pcm, rate
		return raw, _OPENAI_TTS_PCM_RATE


def resample_to_output(pcm: bytes, src_rate: int, dst_rate: int) -> bytes:
	if src_rate == dst_rate:
		return pcm
	return _resample_pcm16_mono(pcm, src_rate, dst_rate)
