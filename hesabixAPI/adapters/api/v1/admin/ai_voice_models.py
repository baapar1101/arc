from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Path, Request
from sqlalchemy.orm import Session

from adapters.db.models.ai_voice_model import AIVoiceModel
from adapters.db.repositories.ai_voice_model_repository import (
	AIVoiceModelRepository,
	AIVoicePolicyRepository,
)
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.core.settings import get_settings
from app.services.voice.audio_wav import pcm16_to_wav
from app.services.voice.contracts import VoiceResolveRequest
from app.services.voice.openai_audio import resample_to_output
from app.services.voice.runtime import resolve_voice_stack
from app.services.voice.tts import DummyTTSEngine, PiperTTSEngine
from app.services.voice.voice_catalog import (
	apply_voice_model_payload,
	clear_other_defaults,
	seed_voice_models_from_env,
	serialize_policy,
	serialize_voice_model,
)

router = APIRouter(prefix="/admin/ai/voice-models", tags=["admin-ai-voice"])


def _require_admin(ctx: AuthContext) -> None:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند مدل‌های صوت را مدیریت کند", http_status=403)


@router.get("", summary="لیست مدل‌های صوت")
async def list_voice_models(
	request: Request,
	kind: Optional[str] = None,
	only_active: Optional[bool] = None,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	_require_admin(ctx)
	repo = AIVoiceModelRepository(db)
	if only_active:
		rows = repo.get_active(kind=kind)
	elif kind:
		rows = [m for m in repo.get_all_ordered() if m.kind == kind]
	else:
		rows = repo.get_all_ordered()
	return success_response([serialize_voice_model(m) for m in rows], request)


@router.get("/policy", summary="سیاست سراسری صوت")
async def get_voice_policy(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	_require_admin(ctx)
	policy = AIVoicePolicyRepository(db).get_or_create()
	return success_response(serialize_policy(policy), request)


@router.put("/policy", summary="ویرایش سیاست سراسری صوت")
async def update_voice_policy(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	_require_admin(ctx)
	policy = AIVoicePolicyRepository(db).get_or_create()
	if "allow_cloud_audio" in payload:
		policy.allow_cloud_audio = bool(payload.get("allow_cloud_audio"))
	if "default_stt_code" in payload:
		policy.default_stt_code = payload.get("default_stt_code") or None
	if "default_tts_code" in payload:
		policy.default_tts_code = payload.get("default_tts_code") or None
	policy.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(policy)
	return success_response(serialize_policy(policy), request, "سیاست صوت ذخیره شد")


@router.post("/seed-from-env", summary="ایجاد خودکار مدل‌های صوت از تنظیمات سرور")
async def seed_voice_models(
	request: Request,
	force: bool = Body(False, embed=True),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	_require_admin(ctx)
	result = seed_voice_models_from_env(db, force=force)
	return success_response(result, request, "عملیات seed انجام شد")


@router.get("/{model_id}", summary="جزئیات مدل صوت")
async def get_voice_model(
	model_id: int = Path(...),
	request: Request = None,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	_require_admin(ctx)
	model = AIVoiceModelRepository(db).get_by_id(model_id)
	if not model:
		raise ApiError("MODEL_NOT_FOUND", "مدل صوت یافت نشد", http_status=404)
	return success_response(serialize_voice_model(model), request)


@router.post("", summary="ایجاد مدل صوت")
async def create_voice_model(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	_require_admin(ctx)
	repo = AIVoiceModelRepository(db)
	code = str(payload.get("code") or "").strip()
	if repo.get_by_code(code):
		raise ApiError("DUPLICATE_MODEL_CODE", "کد مدل تکراری است", http_status=400)
	model = AIVoiceModel(
		code="tmp",
		kind="stt",
		display_name="tmp",
		provider="local",
		model_id="tmp",
	)
	apply_voice_model_payload(model, payload, creating=True)
	if model.is_default:
		clear_other_defaults(db, model.kind, None)
	db.add(model)
	db.commit()
	db.refresh(model)
	return success_response(serialize_voice_model(model), request, "مدل صوت ایجاد شد")


@router.put("/{model_id}", summary="ویرایش مدل صوت")
async def update_voice_model(
	model_id: int = Path(...),
	request: Request = None,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	_require_admin(ctx)
	repo = AIVoiceModelRepository(db)
	model = repo.get_by_id(model_id)
	if not model:
		raise ApiError("MODEL_NOT_FOUND", "مدل صوت یافت نشد", http_status=404)
	apply_voice_model_payload(model, payload, creating=False)
	if model.is_default:
		clear_other_defaults(db, model.kind, model.id)
	db.commit()
	db.refresh(model)
	return success_response(serialize_voice_model(model), request, "مدل صوت به‌روزرسانی شد")


@router.delete("/{model_id}", summary="غیرفعال کردن مدل صوت")
async def deactivate_voice_model(
	model_id: int = Path(...),
	request: Request = None,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	_require_admin(ctx)
	repo = AIVoiceModelRepository(db)
	model = repo.get_by_id(model_id)
	if not model:
		raise ApiError("MODEL_NOT_FOUND", "مدل صوت یافت نشد", http_status=404)
	model.is_active = False
	db.commit()
	return success_response({"id": model.id}, request, "مدل صوت غیرفعال شد")


@router.post("/{model_id}/test", summary="آزمایش کوتاه STT/TTS")
async def test_voice_model(
	model_id: int = Path(...),
	request: Request = None,
	payload: Dict[str, Any] = Body(default={}),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	_require_admin(ctx)
	model = AIVoiceModelRepository(db).get_by_id(model_id)
	if not model:
		raise ApiError("MODEL_NOT_FOUND", "مدل صوت یافت نشد", http_status=404)
	settings = get_settings()
	stack = resolve_voice_stack(
		db,
		VoiceResolveRequest(
			business_id=ctx.business_id or 0,
			stt_code=model.code if model.kind == "stt" else None,
			tts_code=model.code if model.kind == "tts" else None,
			force_allow_cloud=True,
		),
	)
	if model.kind == "tts":
		text = str(payload.get("text") or "سلام، این یک آزمایش کیفیت صدا است.")
		engine = stack.tts_engine
		if isinstance(engine, (PiperTTSEngine, DummyTTSEngine)) or hasattr(engine, "synthesize_pcm16_async"):
			pcm, sr = await engine.synthesize_pcm16_async(text)
		else:
			pcm, sr = engine.synthesize_pcm16(text)
		pcm = resample_to_output(pcm, sr, int(settings.voice_tts_output_sample_rate_hz))
		return success_response(
			{
				"ok": True,
				"kind": "tts",
				"bytes": len(pcm),
				"sample_rate": int(settings.voice_tts_output_sample_rate_hz),
				"dummy": bool(getattr(engine, "dummy", False)),
			},
			request,
			"آزمایش TTS موفق بود",
		)
	# STT: بدون فایل فقط سلامت adapter را گزارش می‌کنیم
	return success_response(
		{
			"ok": True,
			"kind": "stt",
			"engine": getattr(stack.stt, "engine_name", ""),
			"model_id": getattr(stack.stt, "model_id", ""),
			"cloud": bool(getattr(stack.stt, "is_cloud", False)),
		},
		request,
		"آداپتور STT آماده است",
	)
