"""Local STT/TTS adapters wrapping existing Whisper and Piper/dummy engines."""

from __future__ import annotations

import time

from app.services.voice.contracts import TranscriptResult
from app.services.voice.stt import STTConfig, WhisperSTT
from app.services.voice.whisper_pool import get_shared_whisper


class LocalWhisperSTT:
	engine_name = "faster-whisper"
	is_cloud = False

	def __init__(self, stt: WhisperSTT) -> None:
		self._stt = stt
		self.model_id = stt.cfg.model_size_or_path
		self.language = stt.cfg.language

	@classmethod
	def from_config(cls, cfg: STTConfig) -> "LocalWhisperSTT":
		return cls(get_shared_whisper(cfg))

	async def transcribe_pcm16(
		self,
		pcm16: bytes,
		sample_rate_hz: int,
		*,
		language: str | None = None,
	) -> TranscriptResult:
		started = time.perf_counter()
		text = await self._stt.transcribe_pcm16(pcm16, sample_rate_hz=sample_rate_hz)
		elapsed = int((time.perf_counter() - started) * 1000)
		return TranscriptResult(
			text=(text or "").strip(),
			language=language or self.language,
			engine=self.engine_name,
			model_id=self.model_id,
			duration_ms=elapsed,
		)


class DummySTT:
	engine_name = "dummy"
	model_id = "dummy"
	is_cloud = False
	language = "fa"

	async def transcribe_pcm16(
		self,
		pcm16: bytes,
		sample_rate_hz: int,
		*,
		language: str | None = None,
	) -> TranscriptResult:
		return TranscriptResult(
			text="",
			language=language or self.language,
			engine=self.engine_name,
			model_id=self.model_id,
			duration_ms=0,
		)
