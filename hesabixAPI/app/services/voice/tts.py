from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import AsyncGenerator, Optional
import asyncio
import audioop
import re


@dataclass(frozen=True)
class TTSConfig:
	"""
	TTS engine config.
	- engine: "piper" | "coqui" | "dummy"
	- model_name: شناسه مدل Piper (مثلاً fa_IR-ganji-medium) یا نام مدل Coqui
	- model_path: مسیر فایل .onnx (Piper) یا دایرکتوری مدل Coqui
	"""
	engine: str = "piper"
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


class PiperTTSEngine(TTSEngineBase):
	"""TTS محلی با Piper (ONNX) — سازگار با Python 3.12، بدون torch."""

	def __init__(self, cfg: TTSConfig) -> None:
		self.cfg = cfg
		self._voice = None
		self._lock = asyncio.Lock()

	def _resolve_voice_id(self) -> str:
		if self.cfg.model_name:
			return self.cfg.model_name.strip()
		from app.core.settings import get_settings

		settings = get_settings()
		if (self.cfg.language or "").startswith("fa"):
			voice_id = (settings.voice_tts_piper_voice_fa or "").strip()
			if voice_id:
				return voice_id
		raise RuntimeError(
			"شناسه مدل Piper تنظیم نشده است. "
			"VOICE_TTS_MODEL_NAME یا VOICE_TTS_PIPER_VOICE_FA را در env تنظیم کنید."
		)

	def _resolve_model_path(self) -> Path:
		if self.cfg.model_path:
			p = Path(self.cfg.model_path)
			if p.is_dir():
				onnx = p / f"{p.name}.onnx"
				if onnx.is_file():
					return onnx
				candidates = sorted(p.glob("*.onnx"))
				if candidates:
					return candidates[0]
			if p.suffix == ".onnx" or p.with_suffix(".onnx").is_file():
				return p if p.suffix == ".onnx" else p.with_suffix(".onnx")
			raise RuntimeError(f"فایل مدل Piper یافت نشد: {p}")

		from app.core.settings import get_settings

		settings = get_settings()
		models_dir = Path(settings.voice_tts_piper_models_dir)
		voice_id = self._resolve_voice_id()
		onnx = models_dir / f"{voice_id}.onnx"
		if onnx.is_file():
			return onnx
		self._download_voice(voice_id, models_dir)
		if not onnx.is_file():
			raise RuntimeError(f"مدل Piper پس از دانلود یافت نشد: {onnx}")
		return onnx

	@staticmethod
	def _download_voice(voice_id: str, models_dir: Path) -> None:
		try:
			from piper.download_voices import download_voice  # type: ignore
		except Exception as exc:
			raise RuntimeError(
				"ماژول piper-tts نصب نیست. pip install -e \".[voice]\" را اجرا کنید."
			) from exc
		models_dir.mkdir(parents=True, exist_ok=True)
		download_voice(voice_id, models_dir)

	async def _ensure_loaded(self):
		async with self._lock:
			if self._voice is not None:
				return self._voice
			try:
				from piper import PiperVoice  # type: ignore
			except Exception as exc:
				raise RuntimeError(
					"پکیج piper-tts نصب نیست. برای TTS محلی، optional-deps صوت را نصب کنید."
				) from exc

			model_path = self._resolve_model_path()
			self._voice = PiperVoice.load(model_path)
			return self._voice

	async def synthesize_pcm16_async(self, text: str) -> tuple[bytes, int]:
		voice = await self._ensure_loaded()
		loop = asyncio.get_event_loop()
		return await loop.run_in_executor(None, lambda: self._synth_sync(voice, text))

	def _synth_sync(self, voice, text: str) -> tuple[bytes, int]:
		chunks = list(voice.synthesize(text))
		if not chunks:
			return (b"", self.cfg.output_sample_rate_hz)
		pcm_parts: list[bytes] = []
		sr = int(chunks[0].sample_rate)
		for chunk in chunks:
			pcm_parts.append(chunk.audio_int16_bytes)
			sr = int(chunk.sample_rate)
		return (b"".join(pcm_parts), sr)

	def synthesize_pcm16(self, text: str) -> tuple[bytes, int]:
		raise RuntimeError("Use synthesize_pcm16_async for PiperTTSEngine")


class CoquiTTSEngine(TTSEngineBase):
	"""Coqui TTS — فقط Python <3.12؛ برای سازگاری قدیمی نگه داشته شده."""

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
					"پکیج Coqui TTS نصب نیست (روی Python 3.12+ از engine=piper استفاده کنید)."
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
						"برای فارسی VOICE_TTS_COQUI_MODEL_FA یا engine=piper را تنظیم کنید."
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
		wav = tts.tts(text=text)
		sr = getattr(getattr(tts, "synthesizer", None), "output_sample_rate", None) or getattr(
			tts, "output_sample_rate", None
		)
		sr = int(sr) if sr else 22050
		return self._float_to_pcm16(wav, sr)

	def synthesize_pcm16(self, text: str) -> tuple[bytes, int]:
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

		if isinstance(self.engine, (CoquiTTSEngine, PiperTTSEngine)):
			pcm, sr = await self.engine.synthesize_pcm16_async(text)
		else:
			pcm, sr = self.engine.synthesize_pcm16(text)

		if sr != self.cfg.output_sample_rate_hz:
			pcm = _resample_pcm16_mono(pcm, sr, self.cfg.output_sample_rate_hz)

		for i in range(0, len(pcm), self._frame_bytes):
			if cancel_event.is_set():
				break
			yield pcm[i : i + self._frame_bytes]


class TTSFactory:
	@staticmethod
	def create(cfg: TTSConfig) -> StreamingTTS:
		engine_name = (cfg.engine or "piper").strip().lower()
		if engine_name == "dummy":
			engine: TTSEngineBase = DummyTTSEngine(cfg.output_sample_rate_hz)
		elif engine_name == "piper":
			engine = PiperTTSEngine(cfg)
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
	if len(buf) >= max_chars:
		ws = buf.rfind(" ", 0, max_chars)
		return ws if ws > 30 else max_chars
	m = _END_RE.search(buf)
	if m:
		return m.end()
	return None
