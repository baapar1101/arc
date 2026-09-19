from __future__ import annotations

import io
import logging
from typing import Optional

logger = logging.getLogger(__name__)


class WebmOpusStreamDecoder:
	"""
	تبدیل chunkهای WebM/Opus (خروجی MediaRecorder مرورگر) به PCM16 mono.
	فقط با PyAV (libav محلی) — بدون API ابری.
	"""

	def __init__(self, target_sample_rate_hz: int = 16000) -> None:
		self.target_sample_rate_hz = target_sample_rate_hz
		self._buffer = bytearray()
		self._av = None
		self._resampler = None
		self._emitted_bytes = 0

	def _ensure_av(self):
		if self._av is not None:
			return
		try:
			import av  # type: ignore
		except ImportError as exc:
			raise RuntimeError(
				"PyAV نصب نیست. برای WebM/Opus محلی: pip install -e \".[voice]\" (شامل av)"
			) from exc
		self._av = av

	def reset(self) -> None:
		self._buffer.clear()
		self._resampler = None
		self._emitted_bytes = 0

	def feed(self, chunk: bytes) -> bytes:
		"""chunk جدید را می‌خورد؛ فقط PCM تازه‌decode‌شده را برمی‌گرداند."""
		if not chunk:
			return b""
		self._ensure_av()
		self._buffer.extend(chunk)
		if len(self._buffer) < 32:
			return b""
		if len(self._buffer) > 2 * 1024 * 1024:
			logger.warning("webm buffer overflow, reset")
			self.reset()
			return b""

		try:
			pcm = self._decode_buffer(bytes(self._buffer))
		except Exception as exc:
			logger.debug("webm decode not ready: %s", exc)
			return b""
		if len(pcm) <= self._emitted_bytes:
			return b""
		new_pcm = pcm[self._emitted_bytes :]
		self._emitted_bytes = len(pcm)
		return new_pcm

	def _decode_buffer(self, data: bytes) -> bytes:
		av = self._av
		import numpy as np  # type: ignore

		out_pcm = bytearray()
		resampler = None
		with av.open(io.BytesIO(data), format="webm") as container:
			audio_stream = next((s for s in container.streams if s.type == "audio"), None)
			if audio_stream is None:
				return b""

			for frame in container.decode(audio=0):
				if resampler is None:
					resampler = av.audio.resampler.AudioResampler(
						format="s16",
						layout="mono",
						rate=self.target_sample_rate_hz,
					)
				for resampled in resampler.resample(frame):
					arr = resampled.to_ndarray()
					if arr.size == 0:
						continue
					if arr.ndim > 1:
						arr = arr[0]
					out_pcm.extend(arr.astype(np.int16).tobytes())

		return bytes(out_pcm)


def webm_opus_available() -> bool:
	try:
		import av  # noqa: F401
		return True
	except ImportError:
		return False
