"""PCM16LE mono ↔ WAV helpers for STT/TTS HTTP and cloud adapters."""

from __future__ import annotations

import io
import struct
import wave


def pcm16_to_wav(pcm: bytes, sample_rate_hz: int, *, channels: int = 1) -> bytes:
	if sample_rate_hz <= 0:
		raise ValueError("sample_rate_hz must be positive")
	buf = io.BytesIO()
	with wave.open(buf, "wb") as wf:
		wf.setnchannels(channels)
		wf.setsampwidth(2)
		wf.setframerate(int(sample_rate_hz))
		wf.writeframes(pcm)
	return buf.getvalue()


def wav_to_pcm16(wav_bytes: bytes) -> tuple[bytes, int, int]:
	"""Return (pcm16, sample_rate_hz, channels)."""
	with wave.open(io.BytesIO(wav_bytes), "rb") as wf:
		channels = wf.getnchannels()
		sampwidth = wf.getsampwidth()
		rate = wf.getframerate()
		frames = wf.readframes(wf.getnframes())
	if sampwidth != 2:
		raise RuntimeError("فقط WAV با نمونهٔ ۱۶ بیتی پشتیبانی می‌شود")
	return frames, int(rate), int(channels)


def looks_like_wav(data: bytes) -> bool:
	return len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WAVE"


def pcm_duration_seconds(pcm: bytes, sample_rate_hz: int, *, channels: int = 1) -> float:
	if sample_rate_hz <= 0 or channels <= 0:
		return 0.0
	bytes_per_sec = sample_rate_hz * channels * 2
	if bytes_per_sec <= 0:
		return 0.0
	return len(pcm) / float(bytes_per_sec)


def max_pcm_bytes_for_seconds(max_seconds: int, sample_rate_hz: int, *, channels: int = 1) -> int:
	return int(max(1, max_seconds) * sample_rate_hz * channels * 2)


def wav_header_pcm16(data_len: int, sample_rate_hz: int, *, channels: int = 1) -> bytes:
	byte_rate = sample_rate_hz * channels * 2
	block_align = channels * 2
	return struct.pack(
		"<4sI4s4sIHHIIHH4sI",
		b"RIFF",
		36 + data_len,
		b"WAVE",
		b"fmt ",
		16,
		1,
		channels,
		sample_rate_hz,
		byte_rate,
		block_align,
		16,
		b"data",
		data_len,
	)
