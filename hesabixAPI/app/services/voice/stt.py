from __future__ import annotations

from dataclasses import dataclass
from typing import Optional
import asyncio


@dataclass(frozen=True)
class STTConfig:
	language: str = "fa"
	model_size_or_path: str = "small"  # قابل تنظیم (small/medium/large-v3 یا مسیر لوکال)
	device: str = "auto"  # auto/cpu/cuda
	compute_type: str = "int8"  # برای CPU مناسب است


class WhisperSTT:
	"""
	STT بر پایه Whisper (ترجیحاً faster-whisper).
	- ورودی: PCM16 mono bytes
	- خروجی: متن
	"""

	def __init__(self, cfg: STTConfig) -> None:
		self.cfg = cfg
		self._model = None  # lazy load
		self._lock = asyncio.Lock()

	def _load_model(self):
		try:
			from faster_whisper import WhisperModel  # type: ignore
		except Exception as exc:
			raise RuntimeError(
				"faster-whisper نصب نیست. برای STT رایگان با کیفیت فارسی، optional-deps صوت را نصب کنید."
			) from exc

		device = self.cfg.device
		if device == "auto":
			device = "cuda" if _has_cuda() else "cpu"

		self._model = WhisperModel(
			self.cfg.model_size_or_path,
			device=device,
			compute_type=self.cfg.compute_type,
		)
		return self._model

	async def transcribe_pcm16(self, pcm16: bytes, sample_rate_hz: int) -> str:
		"""
		تبدیل PCM16 به متن.
		نکته: مدل Whisper عموماً روی 16kHz بهترین عملکرد را دارد.
		"""
		# Lazy load model (یکبار)
		async with self._lock:
			if self._model is None:
				self._load_model()
			model = self._model

		# تبدیل به float32 numpy و resample در صورت نیاز (فعلاً فرض 16kHz)
		try:
			import numpy as np  # type: ignore
		except Exception as exc:
			raise RuntimeError("numpy نصب نیست (برای STT لازم است).") from exc

		audio_i16 = np.frombuffer(pcm16, dtype=np.int16)
		audio = (audio_i16.astype(np.float32)) / 32768.0

		# اگر sample_rate غیر 16k باشد، فعلاً خطا می‌دهیم (فاز بعد: resample)
		if sample_rate_hz != 16000:
			raise RuntimeError("در فاز اول فقط sample_rate=16000 پشتیبانی می‌شود.")

		# اجرای transcribe در thread جدا چون CPU-bound است
		loop = asyncio.get_event_loop()
		text = await loop.run_in_executor(
			None,
			lambda: _transcribe_sync(model, audio, self.cfg.language),
		)
		return text or ""


def _transcribe_sync(model, audio, language: str) -> str:
	segments, _info = model.transcribe(
		audio,
		language=language,
		beam_size=5,
		vad_filter=False,  # ما VAD خودمان را داریم
	)
	return "".join([seg.text for seg in segments]).strip()


def _has_cuda() -> bool:
	try:
		import torch  # type: ignore
		return bool(torch.cuda.is_available())
	except Exception:
		return False


