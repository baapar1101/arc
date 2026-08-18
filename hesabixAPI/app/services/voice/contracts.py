"""قرارداد STT/TTS جدا از WebSocket تماس."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import AsyncGenerator, Optional, Protocol


CLOUD_VOICE_PROVIDERS = frozenset(
	{"openai", "azure", "google", "groq", "elevenlabs", "custom"}
)
LOCAL_VOICE_PROVIDERS = frozenset({"local", "dummy", "piper", "whisper"})

VOICE_KIND_STT = "stt"
VOICE_KIND_TTS = "tts"
VOICE_KIND_REALTIME = "realtime"
VOICE_KINDS = (VOICE_KIND_STT, VOICE_KIND_TTS, VOICE_KIND_REALTIME)


def provider_is_cloud(provider: str | None) -> bool:
	p = (provider or "").strip().lower()
	if not p or p in LOCAL_VOICE_PROVIDERS:
		return False
	return p in CLOUD_VOICE_PROVIDERS or p not in LOCAL_VOICE_PROVIDERS


@dataclass(frozen=True)
class TranscriptResult:
	text: str
	language: str | None = None
	engine: str = ""
	model_id: str = ""
	duration_ms: int = 0
	extra: dict = field(default_factory=dict)


class STTProvider(Protocol):
	engine_name: str
	model_id: str
	is_cloud: bool

	async def transcribe_pcm16(
		self,
		pcm16: bytes,
		sample_rate_hz: int,
		*,
		language: str | None = None,
	) -> TranscriptResult: ...


class TTSEngine(Protocol):
	engine_name: str
	model_id: str
	is_cloud: bool
	dummy: bool

	async def synthesize_pcm16_async(self, text: str) -> tuple[bytes, int]: ...


@dataclass
class ResolvedVoiceStack:
	stt: STTProvider
	tts_engine: object
	stt_code: str
	tts_code: str
	stt_provider: str
	tts_provider: str
	stt_model_id: str
	tts_model_id: str
	tts_voice_id: str | None
	language: str
	dummy_tts: bool
	cloud_stt: bool
	cloud_tts: bool
	allow_cloud_audio: bool


@dataclass(frozen=True)
class VoiceResolveRequest:
	business_id: int
	stt_code: Optional[str] = None
	tts_code: Optional[str] = None
	language: Optional[str] = None
	force_allow_cloud: bool = False
