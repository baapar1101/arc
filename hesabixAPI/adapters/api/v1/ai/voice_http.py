from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, File, Form, Query, Request, UploadFile
from fastapi.responses import Response
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.core.settings import get_settings
from app.services.ai.ai_ops_metrics import log_ai_event
from app.services.ai.ai_service import AIService
from app.services.voice.audio_wav import (
	looks_like_wav,
	max_pcm_bytes_for_seconds,
	pcm16_to_wav,
	pcm_duration_seconds,
	wav_to_pcm16,
)
from app.services.voice.contracts import VoiceResolveRequest
from app.services.voice.openai_audio import resample_to_output
from app.services.voice.runtime import resolve_voice_stack
from app.services.voice.tts import DummyTTSEngine, PiperTTSEngine
from app.services.voice.usage_log import log_voice_media_usage
from app.services.voice.voice_catalog import (
	cloud_audio_allowed,
	list_voice_models_for_user,
	serialize_business_voice_settings,
)
from adapters.db.repositories.ai_voice_model_repository import (
	AIVoicePolicyRepository,
	BusinessAIVoiceSettingsRepository,
)

router = APIRouter(prefix="/ai/voice", tags=["هوش مصنوعی"])


def _require_business(ctx: AuthContext, business_id: Optional[int]) -> int:
	bid = business_id or ctx.business_id
	if not bid:
		raise ApiError("BUSINESS_REQUIRED", "شناسه کسب‌وکار الزامی است", http_status=400)
	if not ctx.can_access_business(int(bid)):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)
	return int(bid)


def _ensure_voice_enabled() -> None:
	if not get_settings().voice_enabled:
		raise ApiError("VOICE_DISABLED", "گفت‌وگوی صوتی در این سرور غیرفعال است", http_status=403)


def _ensure_quota(db: Session, ctx: AuthContext, business_id: int) -> None:
	ai = AIService(db, ctx, business_id)
	availability = ai.check_availability(estimated_tokens=200)
	if not availability.get("can_use"):
		raise ApiError(
			availability.get("reason") or "AVAILABILITY_CHECK_FAILED",
			str((availability.get("details") or {}).get("message") or "امکان استفاده از هوش مصنوعی نیست"),
			http_status=402,
		)


async def _pcm_from_upload(upload: UploadFile, sample_rate_hz: int) -> tuple[bytes, int]:
	raw = await upload.read()
	if not raw:
		raise ApiError("EMPTY_AUDIO", "فایل صوتی خالی است", http_status=400)
	filename = (upload.filename or "").lower()
	content_type = (upload.content_type or "").lower()
	if looks_like_wav(raw) or filename.endswith(".wav") or "wav" in content_type:
		pcm, rate, channels = wav_to_pcm16(raw)
		if channels != 1:
			raise ApiError("INVALID_AUDIO", "فقط صدای مونو پشتیبانی می‌شود", http_status=400)
		return pcm, rate
	if filename.endswith(".webm") or "webm" in content_type:
		from app.services.voice.webm_decode import WebmOpusStreamDecoder

		decoder = WebmOpusStreamDecoder(sample_rate_hz)
		pcm = decoder.feed(raw)
		if not pcm:
			raise ApiError("INVALID_AUDIO", "رمزگشایی WebM ناموفق بود", http_status=400)
		return pcm, sample_rate_hz
	# raw pcm16le
	return raw, sample_rate_hz


@router.get("/catalog", summary="کاتالوگ STT/TTS مجاز کاربر")
async def get_voice_catalog(
	request: Request,
	business_id: Optional[int] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	_ensure_voice_enabled()
	bid = _require_business(ctx, business_id)
	data = list_voice_models_for_user(db, business_id=bid)
	return success_response(data, request)


@router.get("/settings", summary="تنظیمات صوت کسب‌وکار")
async def get_business_voice_settings(
	request: Request,
	business_id: Optional[int] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	bid = _require_business(ctx, business_id)
	repo = BusinessAIVoiceSettingsRepository(db)
	row = repo.get_or_create(bid)
	policy = AIVoicePolicyRepository(db).get_or_create()
	payload = serialize_business_voice_settings(row)
	payload["policy_allow_cloud_audio"] = bool(policy.allow_cloud_audio)
	payload["effective_allow_cloud_audio"] = cloud_audio_allowed(db, bid)
	return success_response(payload, request)


@router.put("/settings", summary="ذخیره تنظیمات صوت کسب‌وکار")
async def update_business_voice_settings(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	business_id: Optional[int] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	bid = _require_business(ctx, business_id)
	if not (ctx.is_superadmin() or ctx.is_business_owner(bid)):
		raise ApiError("FORBIDDEN", "فقط مالک کسب‌وکار می‌تواند تنظیمات صوت را تغییر دهد", http_status=403)
	row = BusinessAIVoiceSettingsRepository(db).get_or_create(bid)
	policy = AIVoicePolicyRepository(db).get_or_create()
	if "allow_cloud_audio" in payload:
		want = bool(payload.get("allow_cloud_audio"))
		if want and not policy.allow_cloud_audio and not ctx.is_superadmin():
			raise ApiError(
				"CLOUD_AUDIO_DISABLED",
				"ارسال صوت به ابر در سطح سیستم خاموش است",
				http_status=403,
			)
		row.allow_cloud_audio = want
	if "preferred_stt_code" in payload:
		row.preferred_stt_code = payload.get("preferred_stt_code") or None
	if "preferred_tts_code" in payload:
		row.preferred_tts_code = payload.get("preferred_tts_code") or None
	row.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(row)
	out = serialize_business_voice_settings(row)
	out["policy_allow_cloud_audio"] = bool(policy.allow_cloud_audio)
	out["effective_allow_cloud_audio"] = cloud_audio_allowed(db, bid)
	return success_response(out, request, "تنظیمات صوت ذخیره شد")


@router.post("/stt", summary="تبدیل صدا به متن (دیکته)")
async def transcribe_audio(
	request: Request,
	business_id: Optional[int] = Query(None),
	stt_code: Optional[str] = Form(None),
	sample_rate: Optional[int] = Form(None),
	file: UploadFile = File(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	_ensure_voice_enabled()
	bid = _require_business(ctx, business_id)
	_ensure_quota(db, ctx, bid)
	settings = get_settings()
	target_rate = int(sample_rate or settings.voice_sample_rate_hz)
	pcm, rate = await _pcm_from_upload(file, target_rate)
	max_bytes = max_pcm_bytes_for_seconds(int(settings.voice_stt_max_seconds), rate)
	if len(pcm) > max_bytes:
		raise ApiError("AUDIO_TOO_LONG", "مدت صدا از سقف مجاز بیشتر است", http_status=400)
	stack = resolve_voice_stack(
		db,
		VoiceResolveRequest(business_id=bid, stt_code=stt_code),
	)
	try:
		result = await stack.stt.transcribe_pcm16(pcm, rate, language=stack.language)
	except ApiError:
		raise
	except Exception as exc:
		raise ApiError(
			"STT_FAILED",
			str(exc)[:400] or "تبدیل گفتار به متن ناموفق بود",
			http_status=502,
		) from exc
	log_voice_media_usage(
		db,
		ctx,
		bid,
		kind="stt",
		provider=stack.stt_provider,
		model=stack.stt_model_id,
		duration_ms=int(pcm_duration_seconds(pcm, rate) * 1000),
		cloud=stack.cloud_stt,
		extra={"stt_code": stack.stt_code, "engine_ms": result.duration_ms},
	)
	log_ai_event(
		"voice_stt_ms",
		business_id=bid,
		user_id=ctx.get_user_id(),
		extra={"ms": result.duration_ms, "cloud": stack.cloud_stt, "code": stack.stt_code},
	)
	return success_response(
		{
			"text": result.text,
			"language": result.language or stack.language,
			"stt_code": stack.stt_code,
			"engine": result.engine,
		},
		request,
	)


@router.post("/tts", summary="تبدیل متن به صدا (بلندخوانی)")
async def synthesize_speech(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	business_id: Optional[int] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_ensure_voice_enabled()
	bid = _require_business(ctx, business_id)
	_ensure_quota(db, ctx, bid)
	text = str(payload.get("text") or "").strip()
	if not text:
		raise ApiError("TEXT_REQUIRED", "متن برای تبدیل به صدا الزامی است", http_status=400)
	if len(text) > 4000:
		text = text[:4000]
	tts_code = payload.get("tts_code")
	settings = get_settings()
	stack = resolve_voice_stack(
		db,
		VoiceResolveRequest(business_id=bid, tts_code=str(tts_code) if tts_code else None),
	)
	engine = stack.tts_engine
	import time

	started = time.perf_counter()
	try:
		if isinstance(engine, (PiperTTSEngine, DummyTTSEngine)) or hasattr(engine, "synthesize_pcm16_async"):
			pcm, sr = await engine.synthesize_pcm16_async(text)
		else:
			pcm, sr = engine.synthesize_pcm16(text)
	except ApiError:
		raise
	except Exception as exc:
		raise ApiError(
			"TTS_FAILED",
			str(exc)[:400] or "تبدیل متن به صدا ناموفق بود",
			http_status=502,
		) from exc
	out_rate = int(settings.voice_tts_output_sample_rate_hz)
	pcm = resample_to_output(pcm, sr, out_rate)
	elapsed = int((time.perf_counter() - started) * 1000)
	log_voice_media_usage(
		db,
		ctx,
		bid,
		kind="tts",
		provider=stack.tts_provider,
		model=stack.tts_model_id,
		duration_ms=int(pcm_duration_seconds(pcm, out_rate) * 1000),
		char_count=len(text),
		cloud=stack.cloud_tts,
		extra={"tts_code": stack.tts_code, "engine_ms": elapsed, "dummy": stack.dummy_tts},
	)
	log_ai_event(
		"voice_tts_ms",
		business_id=bid,
		user_id=ctx.get_user_id(),
		extra={"ms": elapsed, "cloud": stack.cloud_tts, "code": stack.tts_code},
	)
	wav = pcm16_to_wav(pcm, out_rate)
	return Response(
		content=wav,
		media_type="audio/wav",
		headers={
			"X-Voice-Tts-Code": stack.tts_code,
			"X-Voice-Dummy": "1" if stack.dummy_tts else "0",
			"Cache-Control": "no-store",
		},
	)
