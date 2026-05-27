from __future__ import annotations

from dataclasses import dataclass
from typing import AsyncGenerator, Optional
import asyncio
import audioop
import re


@dataclass(frozen=True)
class TTSConfig:
	"""
	TTS engine config.
	- engine: "coqui" | "dummy"
	- model_name / model_path: برای Coqui
	"""
	engine: str = "coqui"
	language: str = "fa"
	model_name: str | None = None
	model_path: str | None = None
	output_sample_rate_hz: int = 16000
	frame_ms: int = 20


class TTSEngineBase:
	def synthesize_pcm16(self, text: str) -> tuple[bytes, int]:
		"""Return (pcm16_bytes, sample_rate_hz)."""
		raise NotImplementedError


class DummyTTSEngine(TTSEngineBase):
	"""برای تست: خروجی سکوت تولید می‌کند."""

	def __init__(self, sample_rate_hz: int = 16000) -> None:
		self.sample_rate_hz = sample_rate_hz

	def synthesize_pcm16(self, text: str) -> tuple[bytes, int]:
		# 300ms سکوت برای هر chunk
		samples = int(self.sample_rate_hz * 0.3)
		return (b"\x00\x00" * samples, self.sample_rate_hz)


class CoquiTTSEngine(TTSEngineBase):
	def __init__(self, cfg: TTSConfig) -> None:
		self.cfg = cfg
		self._tts = None  # lazy
		self._lock = asyncio.Lock()

	async def _ensure_loaded(self):
		async with self._lock:
			if self._tts is not None:
				return self._tts
			try:
				from TTS.api import TTS  # type: ignore
			except Exception as exc:
				raise RuntimeError(
					"پکیج Coqui TTS نصب نیست. برای TTS رایگان، optional-deps صوت را نصب کنید."
				) from exc

			if self.cfg.model_path:
				self._tts = TTS(model_path=self.cfg.model_path)
			elif self.cfg.model_name:
				self._tts = TTS(self.cfg.model_name)
			else:
				from app.core.settings import get_settings

				settings = get_settings()
				default_fa = (settings.voice_tts_coqui_model_fa or "").strip()
				if (self.cfg.language or "").startswith("fa") and default_fa:
					self._tts = TTS(default_fa)
				else:
					raise RuntimeError(
						"TTS model_name/model_path تنظیم نشده است. "
						"برای فارسی می‌توانید VOICE_TTS_COQUI_MODEL_FA را در env تنظیم کنید."
					)
			return self._tts

	def _float_to_pcm16(self, wav_float, sample_rate_hz: int) -> tuple[bytes, int]:
		try:
			import numpy as np  # type: ignore
		except Exception as exc:
			raise RuntimeError("numpy برای Coqui TTS لازم است.") from exc

		w = np.asarray(wav_float, dtype=np.float32)
		w = np.clip(w, -1.0, 1.0)
		i16 = (w * 32767.0).astype(np.int16)
		return (i16.tobytes(), sample_rate_hz)

	async def synthesize_pcm16_async(self, text: str) -> tuple[bytes, int]:
		tts = await self._ensure_loaded()
		loop = asyncio.get_event_loop()
		return await loop.run_in_executor(None, lambda: self._synth_sync(tts, text))

	def _synth_sync(self, tts, text: str) -> tuple[bytes, int]:
		# Coqui API: tts.tts returns waveform float32 array
		wav = tts.tts(text=text)
		# output sample rate
		sr = getattr(getattr(tts, "synthesizer", None), "output_sample_rate", None) or getattr(
			tts, "output_sample_rate", None
		)
		sr = int(sr) if sr else 22050
		return self._float_to_pcm16(wav, sr)

	def synthesize_pcm16(self, text: str) -> tuple[bytes, int]:
		# sync wrapper (برای interface) - ولی بهتر است از async استفاده شود
		raise RuntimeError("Use synthesize_pcm16_async for CoquiTTSEngine")


class StreamingTTS:
	def __init__(self, cfg: TTSConfig, engine: TTSEngineBase) -> None:
		self.cfg = cfg
		self.engine = engine
		self._frame_bytes = int(cfg.output_sample_rate_hz * (cfg.frame_ms / 1000.0) * 2)

	async def synthesize_stream_pcm16(
		self, text: str, cancel_event: Optional[asyncio.Event] = None
	) -> AsyncGenerator[bytes, None]:
		cancel_event = cancel_event or asyncio.Event()
		text = (text or "").strip()
		if not text:
			return

		# Coqui async
		if isinstance(self.engine, CoquiTTSEngine):
			pcm, sr = await self.engine.synthesize_pcm16_async(text)
		else:
			pcm, sr = self.engine.synthesize_pcm16(text)

		# resample to target output sample rate (PCM16 mono)
		if sr != self.cfg.output_sample_rate_hz:
			pcm = _resample_pcm16_mono(pcm, sr, self.cfg.output_sample_rate_hz)

		# chunk to frames
		for i in range(0, len(pcm), self._frame_bytes):
			if cancel_event.is_set():
				break
			yield pcm[i : i + self._frame_bytes]


class TTSFactory:
	@staticmethod
	def create(cfg: TTSConfig) -> StreamingTTS:
		engine_name = (cfg.engine or "coqui").strip().lower()
		if engine_name == "dummy":
			engine: TTSEngineBase = DummyTTSEngine(cfg.output_sample_rate_hz)
		elif engine_name == "coqui":
			engine = CoquiTTSEngine(cfg)
		else:
			raise RuntimeError(f"Unknown TTS engine: {engine_name}")
		return StreamingTTS(cfg, engine)


def _resample_pcm16_mono(pcm: bytes, src_rate: int, dst_rate: int) -> bytes:
	"""
	Resample PCM16 mono using stdlib audioop (fast, no extra deps).
	"""
	if src_rate == dst_rate:
		return pcm
	# audioop.ratecv returns (converted, state)
	converted, _state = audioop.ratecv(pcm, 2, 1, src_rate, dst_rate, None)
	return converted


class TextChunker:
	"""
	Chunker ساده برای تبدیل stream متن به تکه‌هایی مناسب TTS.
	قواعد:
	- اگر به پایان جمله رسیدیم یا طول از حدی گذشت، خروجی بده.
	"""

	def __init__(self, max_chars: int = 140) -> None:
		self.max_chars = max_chars
		self._buf = ""

	def reset(self) -> None:
		self._buf = ""

	def push(self, delta: str) -> list[str]:
		out: list[str] = []
		if not delta:
			return out
		self._buf += delta

		# تکه‌بندی بر اساس انتهای جمله
		while True:
			cut = _find_chunk_cut(self._buf, self.max_chars)
			if cut is None:
				break
			chunk = self._buf[:cut].strip()
			self._buf = self._buf[cut:]
			if chunk:
				out.append(chunk)
		return out

	def flush(self) -> str:
		rest = self._buf.strip()
		self._buf = ""
		return rest


_END_RE = re.compile(r"([.!؟\n])")


def _find_chunk_cut(buf: str, max_chars: int) -> int | None:
	if not buf:
		return None
	# اگر طول خیلی زیاد شد، قطع در نزدیک‌ترین فاصله
	if len(buf) >= max_chars:
		# cut at last whitespace before max_chars, otherwise hard cut
		ws = buf.rfind(" ", 0, max_chars)
		return ws if ws > 30 else max_chars
	# اگر پایان جمله داریم
	m = _END_RE.search(buf)
	if m:
		return m.end()
	return None


