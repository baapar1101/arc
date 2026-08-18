from __future__ import annotations

import json
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_voice_model import AIVoiceModel, AIVoicePolicy, BusinessAIVoiceSettings
from adapters.db.repositories.ai_voice_model_repository import (
	AIVoiceModelRepository,
	AIVoicePolicyRepository,
	BusinessAIVoiceSettingsRepository,
)
from app.core.responses import ApiError
from app.core.settings import get_settings
from app.services.voice.contracts import (
	VOICE_KIND_STT,
	VOICE_KIND_TTS,
	VOICE_KINDS,
	provider_is_cloud,
)

_CODE_MAX = 80


def serialize_voice_model(model: AIVoiceModel) -> Dict[str, Any]:
	extra = _parse_extra(model.extra_json)
	return {
		"id": model.id,
		"code": model.code,
		"kind": model.kind,
		"display_name": model.display_name,
		"description": model.description,
		"provider": model.provider,
		"model_id": model.model_id,
		"language": model.language,
		"voice_id": model.voice_id,
		"tier": model.tier,
		"reference_cost_per_minute": float(model.reference_cost_per_minute)
		if model.reference_cost_per_minute is not None
		else None,
		"reference_cost_per_1k_chars": float(model.reference_cost_per_1k_chars)
		if model.reference_cost_per_1k_chars is not None
		else None,
		"is_default": bool(model.is_default),
		"is_active": bool(model.is_active),
		"is_cloud": provider_is_cloud(model.provider),
		"sort_order": model.sort_order,
		"extra": extra,
		"created_at": model.created_at.isoformat() if model.created_at else None,
		"updated_at": model.updated_at.isoformat() if model.updated_at else None,
	}


def serialize_policy(policy: AIVoicePolicy) -> Dict[str, Any]:
	return {
		"allow_cloud_audio": bool(policy.allow_cloud_audio),
		"default_stt_code": policy.default_stt_code,
		"default_tts_code": policy.default_tts_code,
		"updated_at": policy.updated_at.isoformat() if policy.updated_at else None,
	}


def serialize_business_voice_settings(row: BusinessAIVoiceSettings) -> Dict[str, Any]:
	return {
		"business_id": row.business_id,
		"allow_cloud_audio": bool(row.allow_cloud_audio),
		"preferred_stt_code": row.preferred_stt_code,
		"preferred_tts_code": row.preferred_tts_code,
		"updated_at": row.updated_at.isoformat() if row.updated_at else None,
	}


def _parse_extra(raw: str | None) -> Dict[str, Any]:
	if not raw:
		return {}
	try:
		data = json.loads(raw)
	except Exception:
		return {}
	return data if isinstance(data, dict) else {}


def cloud_audio_allowed(db: Session, business_id: Optional[int]) -> bool:
	policy = AIVoicePolicyRepository(db).get_or_create()
	if not policy.allow_cloud_audio:
		return False
	if not business_id:
		return False
	biz = BusinessAIVoiceSettingsRepository(db).get_by_business(int(business_id))
	return bool(biz and biz.allow_cloud_audio)


def list_voice_models_for_user(
	db: Session,
	*,
	business_id: Optional[int],
	kind: Optional[str] = None,
) -> Dict[str, Any]:
	repo = AIVoiceModelRepository(db)
	policy = AIVoicePolicyRepository(db).get_or_create()
	allow_cloud = cloud_audio_allowed(db, business_id)
	rows = repo.get_active(kind=kind) if kind else repo.get_active()
	stt: List[Dict[str, Any]] = []
	tts: List[Dict[str, Any]] = []
	for row in rows:
		if provider_is_cloud(row.provider) and not allow_cloud:
			continue
		item = serialize_voice_model(row)
		if row.kind == VOICE_KIND_STT:
			stt.append(item)
		elif row.kind == VOICE_KIND_TTS:
			tts.append(item)
	if not stt or not tts:
		env_stt, env_tts = env_fallback_catalog_items()
		if not stt:
			stt = [env_stt]
		if not tts:
			tts = [env_tts]
	biz = (
		BusinessAIVoiceSettingsRepository(db).get_by_business(int(business_id))
		if business_id
		else None
	)
	default_stt = _pick_default_code(stt, biz.preferred_stt_code if biz else None, policy.default_stt_code)
	default_tts = _pick_default_code(tts, biz.preferred_tts_code if biz else None, policy.default_tts_code)
	return {
		"stt": stt,
		"tts": tts,
		"default_stt_code": default_stt,
		"default_tts_code": default_tts,
		"allow_cloud_audio": allow_cloud,
		"policy_allow_cloud_audio": bool(policy.allow_cloud_audio),
	}


def _pick_default_code(
	items: List[Dict[str, Any]],
	preferred: Optional[str],
	policy_default: Optional[str],
) -> Optional[str]:
	codes = {str(i.get("code")) for i in items}
	for candidate in (preferred, policy_default):
		if candidate and candidate in codes:
			return candidate
	for item in items:
		if item.get("is_default"):
			return str(item["code"])
	return str(items[0]["code"]) if items else None


def env_fallback_catalog_items() -> tuple[Dict[str, Any], Dict[str, Any]]:
	settings = get_settings()
	stt = {
		"id": None,
		"code": "stt-env-whisper",
		"kind": VOICE_KIND_STT,
		"display_name": "Whisper محلی (env)",
		"description": "مدل Whisper از تنظیمات سرور",
		"provider": "local",
		"model_id": settings.voice_stt_model_size_or_path,
		"language": settings.voice_stt_language,
		"voice_id": None,
		"tier": "basic",
		"is_default": True,
		"is_active": True,
		"is_cloud": False,
		"sort_order": 0,
		"from_env": True,
	}
	engine = (settings.voice_tts_engine or "dummy").strip().lower()
	tts = {
		"id": None,
		"code": "tts-env-default",
		"kind": VOICE_KIND_TTS,
		"display_name": f"TTS {engine} (env)",
		"description": "موتور TTS از تنظیمات سرور",
		"provider": "local" if engine != "dummy" else "dummy",
		"model_id": settings.voice_tts_model_name or settings.voice_tts_piper_voice_fa or engine,
		"language": settings.voice_tts_language,
		"voice_id": settings.voice_tts_piper_voice_fa,
		"tier": "basic",
		"is_default": True,
		"is_active": True,
		"is_cloud": False,
		"dummy": engine == "dummy",
		"sort_order": 0,
		"from_env": True,
	}
	return stt, tts


def seed_voice_models_from_env(db: Session, *, force: bool = False) -> Dict[str, Any]:
	repo = AIVoiceModelRepository(db)
	existing = db.query(AIVoiceModel).count()
	settings = get_settings()
	_ = force
	created = 0
	presets: List[Dict[str, Any]] = [
		{
			"code": "stt-local-whisper-small",
			"kind": VOICE_KIND_STT,
			"display_name": "Whisper محلی",
			"description": "تبدیل گفتار به متن روی سرور خودتان (faster-whisper)",
			"provider": "local",
			"model_id": settings.voice_stt_model_size_or_path or "small",
			"language": settings.voice_stt_language or "fa",
			"tier": "basic",
			"is_default": True,
			"sort_order": 10,
			"extra_json": json.dumps(
				{
					"device": settings.voice_stt_device,
					"compute_type": settings.voice_stt_compute_type,
				},
				ensure_ascii=False,
			),
		},
		{
			"code": "stt-parspack-whisper-1",
			"kind": VOICE_KIND_STT,
			"display_name": "ParsPack Whisper",
			"description": "گفتار به متن از درگاه پارس‌پک (openai/whisper-1). کلید در اعتبارنامه Custom ذخیره می‌شود.",
			"provider": "custom",
			"model_id": "openai/whisper-1",
			"language": "fa",
			"tier": "pro",
			"sort_order": 15,
			"extra_json": json.dumps(
				{
					"api_base_url": "https://ai.parspack.com/v1",
					"credential_provider": "custom",
					"audio_endpoint": "translations",
				},
				ensure_ascii=False,
			),
		},
		{
			"code": "stt-openai-whisper-1",
			"kind": VOICE_KIND_STT,
			"display_name": "OpenAI Whisper",
			"description": "transcription ابری؛ نیاز به اجازهٔ ارسال صوت به ابر",
			"provider": "openai",
			"model_id": "whisper-1",
			"language": "fa",
			"tier": "pro",
			"sort_order": 20,
		},
		{
			"code": "stt-openai-gpt-4o-mini-transcribe",
			"kind": VOICE_KIND_STT,
			"display_name": "OpenAI GPT-4o Mini Transcribe",
			"provider": "openai",
			"model_id": "gpt-4o-mini-transcribe",
			"language": "fa",
			"tier": "pro",
			"sort_order": 30,
		},
		{
			"code": "tts-local-piper-ganji",
			"kind": VOICE_KIND_TTS,
			"display_name": "Piper فارسی (محلی)",
			"description": "متن به گفتار ONNX روی سرور",
			"provider": "local",
			"model_id": settings.voice_tts_piper_voice_fa or "fa_IR-ganji-medium",
			"voice_id": settings.voice_tts_piper_voice_fa or "fa_IR-ganji-medium",
			"language": "fa",
			"tier": "basic",
			"is_default": True,
			"sort_order": 10,
		},
		{
			"code": "tts-parspack-gpt-4o-mini-tts",
			"kind": VOICE_KIND_TTS,
			"display_name": "ParsPack TTS",
			"description": "متن به گفتار از درگاه پارس‌پک (openai/gpt-4o-mini-tts). همان کلید Custom که برای Whisper استفاده می‌شود.",
			"provider": "custom",
			"model_id": "openai/gpt-4o-mini-tts",
			"voice_id": "alloy",
			"language": "fa",
			"tier": "pro",
			"sort_order": 15,
			"extra_json": json.dumps(
				{
					"api_base_url": "https://ai.parspack.com/v1",
					"credential_provider": "custom",
					"response_format": "wav",
				},
				ensure_ascii=False,
			),
		},
		{
			"code": "tts-dummy",
			"kind": VOICE_KIND_TTS,
			"display_name": "Dummy (سکوت / آزمایش)",
			"description": "فقط برای تست؛ در تولید فعال نکنید",
			"provider": "dummy",
			"model_id": "dummy",
			"language": "fa",
			"tier": "basic",
			"is_active": (settings.voice_tts_engine or "").strip().lower() == "dummy",
			"is_default": False,
			"sort_order": 90,
		},
		{
			"code": "tts-openai-gpt-4o-mini-tts",
			"kind": VOICE_KIND_TTS,
			"display_name": "OpenAI TTS",
			"provider": "openai",
			"model_id": "gpt-4o-mini-tts",
			"voice_id": "alloy",
			"language": "fa",
			"tier": "pro",
			"sort_order": 20,
		},
	]
	for fields in presets:
		if repo.get_by_code(fields["code"]):
			continue
		db.add(
			AIVoiceModel(
				code=fields["code"],
				kind=fields["kind"],
				display_name=fields["display_name"],
				description=fields.get("description"),
				provider=fields["provider"],
				model_id=fields["model_id"],
				language=fields.get("language") or "fa",
				voice_id=fields.get("voice_id"),
				tier=fields.get("tier"),
				is_default=bool(fields.get("is_default", False)),
				is_active=bool(fields.get("is_active", True)),
				sort_order=int(fields.get("sort_order") or 0),
				extra_json=fields.get("extra_json"),
			)
		)
		created += 1
	policy = AIVoicePolicyRepository(db).get_or_create()
	if not policy.default_stt_code:
		policy.default_stt_code = "stt-local-whisper-small"
	if not policy.default_tts_code:
		engine = (settings.voice_tts_engine or "dummy").strip().lower()
		policy.default_tts_code = "tts-dummy" if engine == "dummy" else "tts-local-piper-ganji"
	db.commit()
	return {"created": created, "skipped": False, "existing_count": existing}


def validate_kind(kind: str) -> str:
	k = (kind or "").strip().lower()
	if k not in VOICE_KINDS:
		raise ApiError("INVALID_VOICE_KIND", "نوع مدل صوت باید stt یا tts باشد", http_status=400)
	return k


def validate_code(code: str) -> str:
	c = (code or "").strip().lower()
	if not c or len(c) > _CODE_MAX:
		raise ApiError("CODE_REQUIRED", "کد مدل صوت الزامی است", http_status=400)
	return c


def apply_voice_model_payload(model: AIVoiceModel, payload: Dict[str, Any], *, creating: bool) -> None:
	if creating:
		model.code = validate_code(str(payload.get("code") or ""))
		model.kind = validate_kind(str(payload.get("kind") or ""))
	elif "kind" in payload:
		model.kind = validate_kind(str(payload.get("kind") or model.kind))
	if "display_name" in payload or creating:
		model.display_name = str(payload.get("display_name") or model.code)
	if "description" in payload or creating:
		model.description = payload.get("description")
	if "provider" in payload or creating:
		model.provider = str(payload.get("provider") or "local").strip().lower()
	if "model_id" in payload or creating:
		model.model_id = str(payload.get("model_id") or model.code)
	if "language" in payload or creating:
		model.language = str(payload.get("language") or "fa")[:16]
	if "voice_id" in payload or creating:
		raw = payload.get("voice_id")
		model.voice_id = str(raw).strip() if raw else None
	if "tier" in payload or creating:
		model.tier = payload.get("tier")
	if "reference_cost_per_minute" in payload:
		model.reference_cost_per_minute = payload.get("reference_cost_per_minute")
	if "reference_cost_per_1k_chars" in payload:
		model.reference_cost_per_1k_chars = payload.get("reference_cost_per_1k_chars")
	if "is_default" in payload or creating:
		model.is_default = bool(payload.get("is_default", False))
	if "is_active" in payload or creating:
		model.is_active = bool(payload.get("is_active", True))
	if "sort_order" in payload or creating:
		model.sort_order = int(payload.get("sort_order") or 0)
	extra_in = payload.get("extra") if "extra" in payload else None
	if extra_in is None and any(
		k in payload for k in ("api_base_url", "audio_endpoint", "response_format")
	):
		extra_in = _parse_extra(model.extra_json)
	if isinstance(extra_in, dict):
		if payload.get("api_base_url"):
			extra_in["api_base_url"] = str(payload.get("api_base_url")).strip()
		if payload.get("audio_endpoint"):
			extra_in["audio_endpoint"] = str(payload.get("audio_endpoint")).strip().lower()
		if payload.get("response_format"):
			extra_in["response_format"] = str(payload.get("response_format")).strip().lower()
		if model.provider in ("custom", "openai", "groq"):
			extra_in.setdefault("credential_provider", model.provider)
		model.extra_json = json.dumps(extra_in, ensure_ascii=False)
	elif "extra" in payload:
		model.extra_json = None
	model.updated_at = datetime.utcnow()


def persist_voice_gateway_credential(db: Session, payload: Dict[str, Any], model: AIVoiceModel) -> None:
	"""ذخیره کلید/آدرس درگاه همراه مدل صوت — بدون گذاشتن راز داخل خود ردیف کاتالوگ."""
	api_key = str(payload.get("api_key") or "").strip()
	api_base = str(payload.get("api_base_url") or "").strip() or None
	if not api_key and api_base is None:
		return
	from app.services.ai.ai_provider_service import create_or_update_credential

	extra = _parse_extra(model.extra_json)
	provider = str(extra.get("credential_provider") or model.provider or "custom").strip().lower()
	if provider in ("local", "dummy", "piper", "whisper"):
		provider = "custom"
	create_or_update_credential(
		db,
		provider,
		display_name="ParsPack / Custom Gateway" if provider == "custom" else None,
		api_base_url=api_base if api_base is not None else extra.get("api_base_url"),
		api_key=api_key or None,
		is_active=True,
	)


def clear_other_defaults(db: Session, kind: str, keep_id: Optional[int]) -> None:
	q = db.query(AIVoiceModel).filter(AIVoiceModel.kind == kind, AIVoiceModel.is_default.is_(True))
	if keep_id is not None:
		q = q.filter(AIVoiceModel.id != keep_id)
	for row in q.all():
		row.is_default = False
