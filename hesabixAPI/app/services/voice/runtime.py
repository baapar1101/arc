"""Resolve STT/TTS engines from catalog, policy, and env fallback."""

from __future__ import annotations

import json
from typing import Any, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_voice_model import AIVoiceModel
from adapters.db.repositories.ai_config_repository import AIConfigRepository
from adapters.db.repositories.ai_voice_model_repository import (
	AIVoiceModelRepository,
	AIVoicePolicyRepository,
	BusinessAIVoiceSettingsRepository,
)
from app.core.responses import ApiError
from app.core.settings import get_settings
from app.services.ai.ai_provider_service import resolve_provider_connection
from app.services.voice.contracts import ResolvedVoiceStack, VoiceResolveRequest, provider_is_cloud
from app.services.voice.local_adapters import LocalWhisperSTT
from app.services.voice.openai_audio import OpenAITTSEngine, OpenAITranscriptionSTT
from app.services.voice.stt import STTConfig
from app.services.voice.tts import DummyTTSEngine, PiperTTSEngine, TTSConfig, TTSFactory
from app.services.voice.voice_catalog import cloud_audio_allowed


def _extra(model: AIVoiceModel | None) -> dict[str, Any]:
	if not model or not model.extra_json:
		return {}
	try:
		data = json.loads(model.extra_json)
	except Exception:
		return {}
	return data if isinstance(data, dict) else {}


def _require_cloud_or_raise(allow_cloud: bool, model: AIVoiceModel) -> None:
	if provider_is_cloud(model.provider) and not allow_cloud:
		raise ApiError(
			"CLOUD_AUDIO_DISABLED",
			"ارسال صوت به ابر برای این کسب‌وکار مجاز نیست. از موتور محلی استفاده کنید یا در تنظیمات اجازه دهید.",
			http_status=403,
		)


def _pick_model(
	db: Session,
	*,
	kind: str,
	requested: Optional[str],
	business_id: int,
	allow_cloud: bool,
) -> Optional[AIVoiceModel]:
	repo = AIVoiceModelRepository(db)
	policy = AIVoicePolicyRepository(db).get_or_create()
	biz = BusinessAIVoiceSettingsRepository(db).get_by_business(business_id)
	candidates: list[str] = []
	if requested and str(requested).strip():
		candidates.append(str(requested).strip())
	if biz:
		pref = biz.preferred_stt_code if kind == "stt" else biz.preferred_tts_code
		if pref:
			candidates.append(pref)
	pol = policy.default_stt_code if kind == "stt" else policy.default_tts_code
	if pol:
		candidates.append(pol)
	seen: set[str] = set()
	for code in candidates:
		if code in seen:
			continue
		seen.add(code)
		row = repo.get_by_code(code)
		if not row or not row.is_active or row.kind != kind:
			continue
		if provider_is_cloud(row.provider) and not allow_cloud:
			if requested and code == requested.strip():
				_require_cloud_or_raise(False, row)
			continue
		return row
	defaults = [m for m in repo.get_active(kind=kind) if not provider_is_cloud(m.provider) or allow_cloud]
	if defaults:
		marked = [m for m in defaults if m.is_default]
		return (marked or defaults)[0]
	return None


def _credential(db: Session, provider: str) -> tuple[str, Optional[str]]:
	legacy = AIConfigRepository(db).get_active_config()
	_ptype, api_key, api_base, _fce = resolve_provider_connection(
		db, provider, legacy_config=legacy
	)
	return api_key, api_base


def _cloud_connection(db: Session, model: AIVoiceModel) -> tuple[str, Optional[str], str]:
	extra = _extra(model)
	provider = (model.provider or "custom").strip().lower()
	cred_provider = str(extra.get("credential_provider") or provider).strip().lower()
	if cred_provider in ("", "local", "dummy", "piper", "whisper"):
		cred_provider = "custom" if provider == "custom" else provider
	api_key, api_base = _credential(db, cred_provider)
	override = str(extra.get("api_base_url") or "").strip() or None
	return api_key, override or api_base, str(extra.get("audio_endpoint") or "auto")


def _build_local_stt(model: Optional[AIVoiceModel], language: str) -> LocalWhisperSTT:
	settings = get_settings()
	extra = _extra(model)
	cfg = STTConfig(
		language=language or settings.voice_stt_language,
		model_size_or_path=(model.model_id if model else None) or settings.voice_stt_model_size_or_path,
		device=str(extra.get("device") or settings.voice_stt_device),
		compute_type=str(extra.get("compute_type") or settings.voice_stt_compute_type),
	)
	return LocalWhisperSTT.from_config(cfg)


def _build_stt(db: Session, model: Optional[AIVoiceModel], language: str, allow_cloud: bool):
	if model is None:
		return _build_local_stt(None, language)
	provider = (model.provider or "local").strip().lower()
	if provider in ("local", "whisper", "piper"):
		return _build_local_stt(model, language)
	if provider == "dummy":
		from app.services.voice.local_adapters import DummySTT

		return DummySTT()
	_require_cloud_or_raise(allow_cloud, model)
	if provider in ("openai", "groq", "custom"):
		api_key, api_base, audio_endpoint = _cloud_connection(db, model)
		return OpenAITranscriptionSTT(
			api_key=api_key,
			api_base_url=api_base,
			model_id=model.model_id,
			language=language or model.language or "fa",
			audio_endpoint=audio_endpoint,
		)
	raise ApiError("VOICE_PROVIDER_UNSUPPORTED", f"ارائه‌دهنده STT «{provider}» پشتیبانی نمی‌شود", http_status=400)


def _build_tts_engine(db: Session, model: Optional[AIVoiceModel], language: str, allow_cloud: bool):
	settings = get_settings()
	if model is None:
		cfg = TTSConfig(
			engine=settings.voice_tts_engine,
			language=language or settings.voice_tts_language,
			model_name=settings.voice_tts_model_name,
			model_path=settings.voice_tts_model_path,
			output_sample_rate_hz=int(settings.voice_tts_output_sample_rate_hz),
			frame_ms=int(settings.voice_tts_frame_ms),
		)
		return TTSFactory.create(cfg).engine
	provider = (model.provider or "local").strip().lower()
	if provider == "dummy":
		return DummyTTSEngine(int(settings.voice_tts_output_sample_rate_hz))
	if provider in ("local", "piper"):
		cfg = TTSConfig(
			engine="piper",
			language=language or model.language or "fa",
			model_name=model.voice_id or model.model_id or settings.voice_tts_piper_voice_fa,
			model_path=settings.voice_tts_model_path,
			output_sample_rate_hz=int(settings.voice_tts_output_sample_rate_hz),
			frame_ms=int(settings.voice_tts_frame_ms),
		)
		return PiperTTSEngine(cfg)
	_require_cloud_or_raise(allow_cloud, model)
	if provider in ("openai", "groq", "custom"):
		api_key, api_base, _endpoint = _cloud_connection(db, model)
		return OpenAITTSEngine(
			api_key=api_key,
			api_base_url=api_base,
			model_id=model.model_id,
			voice_id=model.voice_id,
		)
	raise ApiError("VOICE_PROVIDER_UNSUPPORTED", f"ارائه‌دهنده TTS «{provider}» پشتیبانی نمی‌شود", http_status=400)


def resolve_voice_stack(db: Session, request: VoiceResolveRequest) -> ResolvedVoiceStack:
	settings = get_settings()
	allow_cloud = bool(request.force_allow_cloud) or cloud_audio_allowed(db, request.business_id)
	language = (request.language or settings.voice_stt_language or "fa").strip() or "fa"
	stt_model = _pick_model(
		db,
		kind="stt",
		requested=request.stt_code,
		business_id=request.business_id,
		allow_cloud=allow_cloud,
	)
	tts_model = _pick_model(
		db,
		kind="tts",
		requested=request.tts_code,
		business_id=request.business_id,
		allow_cloud=allow_cloud,
	)
	stt = _build_stt(db, stt_model, language, allow_cloud)
	tts_engine = _build_tts_engine(db, tts_model, language, allow_cloud)
	dummy = bool(getattr(tts_engine, "dummy", False)) or isinstance(tts_engine, DummyTTSEngine)
	return ResolvedVoiceStack(
		stt=stt,
		tts_engine=tts_engine,
		stt_code=(stt_model.code if stt_model else "stt-env-whisper"),
		tts_code=(tts_model.code if tts_model else "tts-env-default"),
		stt_provider=(stt_model.provider if stt_model else "local"),
		tts_provider=(tts_model.provider if tts_model else settings.voice_tts_engine),
		stt_model_id=(stt_model.model_id if stt_model else settings.voice_stt_model_size_or_path),
		tts_model_id=(tts_model.model_id if tts_model else (settings.voice_tts_model_name or settings.voice_tts_engine)),
		tts_voice_id=(tts_model.voice_id if tts_model else settings.voice_tts_piper_voice_fa),
		language=language,
		dummy_tts=dummy,
		cloud_stt=bool(getattr(stt, "is_cloud", False)),
		cloud_tts=bool(getattr(tts_engine, "is_cloud", False)),
		allow_cloud_audio=allow_cloud,
	)
