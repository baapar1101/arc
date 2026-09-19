"""Adapters for OpenAI-compatible /v1/audio/transcriptions and /v1/audio/speech."""

from __future__ import annotations

import json
import time
from typing import Any, Optional

import httpx

from app.services.voice.audio_wav import looks_like_wav, pcm16_to_wav, wav_to_pcm16
from app.services.voice.contracts import TranscriptResult
from app.services.voice.tts import _resample_pcm16_mono

_DEFAULT_TIMEOUT = 45.0
_OPENAI_TTS_PCM_RATE = 24000
_STT_FALLBACK_STATUS = {400, 404, 405, 415, 422, 500, 502, 503}
_HTTPX_TRANSIENT = (
	httpx.RemoteProtocolError,
	httpx.ReadError,
	httpx.ConnectError,
	httpx.TimeoutException,
	httpx.DecodingError,
)


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
		base = (self.api_base_url or "").lower()
		# درگاه پارس‌پک transcriptions را با ۵۰۰ ناقص می‌بندد؛ نمونهٔ رسمی‌شان translations است.
		if "parspack" in base:
			return ["audio/translations", "audio/transcriptions"]
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
		async with httpx.AsyncClient(timeout=self.timeout, http2=False) as client:
			for path in self._audio_paths():
				url = _join_url(self.api_base_url, path)
				data: dict[str, Any] = {"model": self.model_id}
				if path.endswith("transcriptions") and lang and lang != "auto":
					data["language"] = lang
				status = 0
				raw = b""
				try:
					async with client.stream(
						"POST",
						url,
						headers=headers,
						data=data,
						files={"file": ("utterance.wav", wav, "audio/wav")},
					) as response:
						status = response.status_code
						try:
							async for chunk in response.aiter_bytes():
								raw += chunk
								if status >= 400 and len(raw) >= 800:
									break
						except _HTTPX_TRANSIENT as exc:
							if status < 400 and raw:
								pass
							else:
								last_error = f"STT ابری قطع شد ({path}): {type(exc).__name__}"
								continue
				except _HTTPX_TRANSIENT as exc:
					last_error = f"STT ابری قطع شد ({path}): {type(exc).__name__}"
					continue
				if status >= 400:
					snippet = raw[:400].decode("utf-8", errors="replace")
					last_error = f"STT ابری ناموفق ({status}): {snippet}"
					if status in _STT_FALLBACK_STATUS:
						continue
					break
				try:
					payload: Any = json.loads(raw.decode("utf-8")) if raw else {}
				except Exception:
					last_error = f"پاسخ STT ابری نامعتبر است ({path})"
					continue
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
		response_format: str = "pcm",
	) -> None:
		self.api_key = api_key
		self.api_base_url = api_base_url
		self.model_id = model_id
		self.voice_id = (voice_id or "alloy").strip() or "alloy"
		self.timeout = timeout
		fmt = (response_format or "pcm").strip().lower() or "pcm"
		self.response_format = "wav" if fmt in ("wav", "wave") else "pcm"

	def _format_order(self) -> list[str]:
		if self.response_format == "wav":
			return ["wav", "pcm"]
		return ["pcm", "wav"]

	async def synthesize_pcm16_async(self, text: str) -> tuple[bytes, int]:
		url = _join_url(self.api_base_url, "audio/speech")
		headers = {
			"Authorization": f"Bearer {self.api_key}",
			"Content-Type": "application/json",
		}
		last_error = "TTS ابری ناموفق"
		async with httpx.AsyncClient(timeout=self.timeout) as client:
			for fmt in self._format_order():
				body = {
					"model": self.model_id,
					"voice": self.voice_id,
					"input": text,
					"response_format": fmt,
				}
				response = await client.post(url, headers=headers, json=body)
				if response.status_code < 400:
					raw = response.content or b""
					if looks_like_wav(raw):
						pcm, rate, channels = wav_to_pcm16(raw)
						if channels != 1:
							raise RuntimeError("خروجی TTS ابری باید مونو باشد")
						return pcm, rate
					return raw, _OPENAI_TTS_PCM_RATE
				last_error = f"TTS ابری ناموفق ({response.status_code}): {response.text[:400]}"
				if response.status_code not in (400, 404, 405, 415, 422):
					break
		raise RuntimeError(last_error)


def resample_to_output(pcm: bytes, src_rate: int, dst_rate: int) -> bytes:
	if src_rate == dst_rate:
		return pcm
	return _resample_pcm16_mono(pcm, src_rate, dst_rate)
