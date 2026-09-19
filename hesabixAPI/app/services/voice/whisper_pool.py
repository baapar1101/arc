"""Process-wide Whisper STT so each WS connection does not reload the model."""

from __future__ import annotations

import threading

from app.services.voice.stt import STTConfig, WhisperSTT

_lock = threading.Lock()
_instances: dict[tuple[str, str, str, str], WhisperSTT] = {}


def get_shared_whisper(cfg: STTConfig) -> WhisperSTT:
	key = (
		str(cfg.model_size_or_path),
		str(cfg.device),
		str(cfg.compute_type),
		str(cfg.language),
	)
	with _lock:
		existing = _instances.get(key)
		if existing is not None:
			return existing
		inst = WhisperSTT(cfg)
		_instances[key] = inst
		return inst


def reset_shared_whisper_for_tests() -> None:
	with _lock:
		_instances.clear()
