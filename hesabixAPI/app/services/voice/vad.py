from __future__ import annotations

from dataclasses import dataclass
from collections import deque
from typing import Optional


@dataclass(frozen=True)
class VadConfig:
	# Audio format: PCM16 mono
	sample_rate_hz: int = 16000
	frame_ms: int = 20  # must be 10/20/30 for webrtcvad
	mode: int = 2  # 0..3 (more aggressive => more speech detection)

	# Endpointing
	silence_ms: int = 650
	min_speech_ms: int = 250
	pre_roll_ms: int = 200
	max_utterance_ms: int = 30_000


@dataclass
class VadEvent:
	speech_started: bool = False
	utterance_completed: bool = False
	utterance_pcm: Optional[bytes] = None


class VadEndpointing:
	"""
	VAD + endpointing برای PCM16 mono.
	- ورودی: bytes به شکل فریم‌های 10/20/30ms
	- خروجی: رویداد شروع صحبت + وقتی سکوت کافی شد، utterance کامل
	"""

	def __init__(self, cfg: VadConfig) -> None:
		self.cfg = cfg
		self._vad = None  # lazy import
		self._frame_bytes = int(cfg.sample_rate_hz * (cfg.frame_ms / 1000.0) * 2)
		self._ring: deque[bytes] = deque(maxlen=max(1, int(cfg.pre_roll_ms / cfg.frame_ms)))
		self._buf = bytearray()
		self._in_speech = False
		self._speech_frames = 0
		self._silence_frames = 0
		self._utterance_frames: list[bytes] = []

		self._silence_thresh_frames = max(1, int(cfg.silence_ms / cfg.frame_ms))
		self._min_speech_frames = max(1, int(cfg.min_speech_ms / cfg.frame_ms))
		self._max_utterance_frames = max(1, int(cfg.max_utterance_ms / cfg.frame_ms))

	def reset(self) -> None:
		self._buf.clear()
		self._ring.clear()
		self._in_speech = False
		self._speech_frames = 0
		self._silence_frames = 0
		self._utterance_frames = []

	def _ensure_vad(self):
		if self._vad is None:
			try:
				import webrtcvad  # type: ignore
			except Exception as exc:
				raise RuntimeError(
					"webrtcvad نصب نیست. برای voice chat، optional-deps مربوط به صوت را نصب کنید."
				) from exc
			self._vad = webrtcvad.Vad()
			self._vad.set_mode(int(self.cfg.mode))
		return self._vad

	def process_bytes(self, data: bytes) -> VadEvent:
		self._buf.extend(data)
		event = VadEvent()

		while len(self._buf) >= self._frame_bytes:
			frame = bytes(self._buf[: self._frame_bytes])
			del self._buf[: self._frame_bytes]

			vad = self._ensure_vad()
			is_speech = bool(vad.is_speech(frame, self.cfg.sample_rate_hz))

			if not self._in_speech:
				# pre-roll always filled
				self._ring.append(frame)
				if is_speech:
					self._in_speech = True
					self._speech_frames = 1
					self._silence_frames = 0
					self._utterance_frames = list(self._ring)
					self._utterance_frames.append(frame)
					self._ring.clear()
					event.speech_started = True
				continue

			# in speech
			self._utterance_frames.append(frame)
			if is_speech:
				self._speech_frames += 1
				self._silence_frames = 0
			else:
				self._silence_frames += 1

			# hard cap
			if len(self._utterance_frames) >= self._max_utterance_frames:
				return self._finalize_event(event)

			# endpointing
			if self._speech_frames >= self._min_speech_frames and self._silence_frames >= self._silence_thresh_frames:
				return self._finalize_event(event)

		return event

	def _finalize_event(self, event: VadEvent) -> VadEvent:
		event.utterance_completed = True
		event.utterance_pcm = b"".join(self._utterance_frames)
		self._in_speech = False
		self._speech_frames = 0
		self._silence_frames = 0
		self._utterance_frames = []
		self._ring.clear()
		return event


