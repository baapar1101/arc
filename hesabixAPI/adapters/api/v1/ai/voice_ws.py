from __future__ import annotations

from typing import Any, Optional
import asyncio
import json
import logging
import os
import base64
from datetime import datetime

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session

from adapters.db.session import SessionLocal, get_db_session
from adapters.db.repositories.api_key_repo import ApiKeyRepository
from adapters.db.repositories.ai_chat_repository import AIChatSessionRepository, AIChatMessageRepository
from adapters.db.models.user import User
from adapters.db.models.ai_chat_message import AIChatMessage, MessageRole
from adapters.db.models.ai_voice_interaction import AIVoiceInteraction
from app.core.security import hash_api_key
from app.services.ai.ai_service import AIService
from app.core.auth_dependency import AuthContext
from app.core.responses import ApiError
from app.core.settings import get_settings

from app.services.voice.vad import VadEndpointing, VadConfig
from app.services.voice.stt import WhisperSTT, STTConfig
from app.services.voice.tts import TTSFactory, TTSConfig, TextChunker

logger = logging.getLogger(__name__)

router = APIRouter(tags=["هوش مصنوعی"])


@router.websocket("/ws/ai/voice")
async def ai_voice_ws(websocket: WebSocket):
	"""
	WebSocket دوطرفه برای گفت‌وگوی صوتی با AI.

	- احراز هویت: `?api_key=...`
	- ورودی صوت: PCM16 (mono, sample_rate=voice_sample_rate_hz) به صورت binary frame
	- خروجی: JSON event + PCM16 output به صورت binary frame
	"""
	api_key = websocket.query_params.get("api_key")
	if not api_key:
		await websocket.close(code=4401)
		return

	# Auth (short DB session)
	db: Session = SessionLocal()
	user: Optional[User] = None
	api_key_id: Optional[int] = None
	try:
		key_hash = hash_api_key(api_key)
		repo = ApiKeyRepository(db)
		obj = repo.get_by_hash(key_hash)
		if not obj or obj.revoked_at is not None:
			await websocket.close(code=4401)
			return
		api_key_id = obj.id
		user = db.get(User, obj.user_id)
		if not user or not user.is_active:
			await websocket.close(code=4401)
			return
	finally:
		db.close()

	await websocket.accept()

	settings = get_settings()
	if not settings.voice_enabled:
		await websocket.close(code=4403)
		return

	# State
	session_id: Optional[int] = None
	business_id: Optional[int] = None
	collect_data_opt_in: bool = False
	cancel_event = asyncio.Event()
	currently_speaking = False
	audio_transport: str = "binary"  # binary | base64

	# Configs
	audio_sample_rate = int(settings.voice_sample_rate_hz)
	frame_ms = int(settings.voice_frame_ms)
	vad_cfg = VadConfig(
		sample_rate_hz=audio_sample_rate,
		frame_ms=frame_ms,
		mode=int(settings.voice_vad_mode),
		silence_ms=int(settings.voice_vad_silence_ms),
		min_speech_ms=int(settings.voice_vad_min_speech_ms),
		pre_roll_ms=int(settings.voice_vad_pre_roll_ms),
		max_utterance_ms=int(settings.voice_vad_max_utterance_ms),
	)
	vad = VadEndpointing(vad_cfg)

	stt = WhisperSTT(
		STTConfig(
			language=settings.voice_stt_language,
			model_size_or_path=settings.voice_stt_model_size_or_path,
			device=settings.voice_stt_device,
			compute_type=settings.voice_stt_compute_type,
		)
	)
	tts = TTSFactory.create(
		TTSConfig(
			engine=settings.voice_tts_engine,
			language=settings.voice_tts_language,
			model_name=settings.voice_tts_model_name,
			model_path=settings.voice_tts_model_path,
			output_sample_rate_hz=int(settings.voice_tts_output_sample_rate_hz),
			frame_ms=int(settings.voice_tts_frame_ms),
		)
	)
	text_chunker = TextChunker()

	async def send_event(event: dict[str, Any]) -> None:
		await websocket.send_text(json.dumps(event, ensure_ascii=False))

	async def _send_audio_frame(pcm_frame: bytes, capture: bytearray | None) -> None:
		if capture is not None:
			capture.extend(pcm_frame)
		if audio_transport == "base64":
			await send_event({"type": "assistant_audio", "audio_b64": base64.b64encode(pcm_frame).decode("ascii")})
		else:
			await websocket.send_bytes(pcm_frame)

	async def _handle_utterance(utterance_pcm: bytes) -> None:
		nonlocal currently_speaking

		await send_event({"type": "speech_end"})

		# STT
		try:
			await send_event({"type": "stt_started"})
			text = await stt.transcribe_pcm16(utterance_pcm, sample_rate_hz=audio_sample_rate)
			text = (text or "").strip()
			await send_event({"type": "transcript_final", "text": text})
		except Exception as exc:
			logger.exception("STT failed")
			await send_event({"type": "error", "error": "STT_FAILED", "message": str(exc)})
			return

		if not text:
			await send_event({"type": "error", "error": "EMPTY_TRANSCRIPT", "message": "متن قابل تشخیص نیست"})
			return

		# save user message + build history
		with get_db_session() as db3:
			msg_repo = AIChatMessageRepository(db3)
			prev = msg_repo.get_session_messages(session_id, limit=50)
			messages = [{"role": m.role, "content": m.content} for m in prev]
			messages.append({"role": "user", "content": text})

			user_message = AIChatMessage(session_id=session_id, role=MessageRole.USER.value, content=text, tokens_used=0)
			db3.add(user_message)
			db3.commit()

		# LLM streaming + TTS streaming
		cancel_event.clear()
		currently_speaking = True
		text_chunker.reset()

		accumulated_text = ""
		final_usage: dict[str, Any] | None = None
		assistant_audio_capture: bytearray | None = bytearray() if collect_data_opt_in else None
		assistant_message_id: int | None = None

		try:
			with get_db_session() as db4:
				ctx = AuthContext(user=user, api_key_id=api_key_id or 0, language="fa", db=None)
				ai_service = AIService(db4, ctx, business_id)

				async for chunk in ai_service.chat_completion_stream(
					messages=messages,
					use_function_calling=True,
					session_business_id=business_id,
				):
					if cancel_event.is_set():
						await send_event({"type": "cancelled"})
						break

					delta = chunk.get("delta", {})
					delta_text = delta.get("content", "") or ""
					if delta_text:
						accumulated_text += delta_text
						await send_event({"type": "assistant_text_delta", "text": delta_text})

						for speak_text in text_chunker.push(delta_text):
							async for pcm_frame in tts.synthesize_stream_pcm16(text=speak_text, cancel_event=cancel_event):
								if cancel_event.is_set():
									break
								await _send_audio_frame(pcm_frame, assistant_audio_capture)

					if chunk.get("usage"):
						final_usage = chunk["usage"]
					if chunk.get("done", False):
						break

				if not cancel_event.is_set():
					remaining = text_chunker.flush()
					if remaining:
						async for pcm_frame in tts.synthesize_stream_pcm16(text=remaining, cancel_event=cancel_event):
							if cancel_event.is_set():
								break
							await _send_audio_frame(pcm_frame, assistant_audio_capture)

		except ApiError as exc:
			await send_event({"type": "error", "error": exc.error_code, "message": exc.message})
		except Exception as exc:
			logger.exception("LLM/TTS streaming failed")
			await send_event({"type": "error", "error": "VOICE_STREAM_FAILED", "message": str(exc)})
		finally:
			currently_speaking = False

		# commit assistant + charge/log
		if not cancel_event.is_set() and accumulated_text.strip():
			try:
				with get_db_session() as db_commit:
					session_repo = AIChatSessionRepository(db_commit)
					commit_session = session_repo.get_by_id(session_id)
					if not commit_session:
						raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)

					ctx_commit = AuthContext(user=user, api_key_id=api_key_id or 0, language="fa", db=None)
					ai_commit_service = AIService(db_commit, ctx_commit, business_id)

					usage = final_usage or {}
					input_tokens = int(usage.get("input_tokens", 0) or 0)
					output_tokens = int(usage.get("output_tokens", 0) or 0)
					charge_result = ai_commit_service.check_quota_and_charge(input_tokens, output_tokens)

					assistant_message = AIChatMessage(
						session_id=session_id,
						role=MessageRole.ASSISTANT.value,
						content=accumulated_text,
						tokens_used=input_tokens + output_tokens,
					)
					db_commit.add(assistant_message)

					ai_commit_service.log_usage(
						provider=ai_commit_service.config.provider if ai_commit_service.config else "openai",
						model=ai_commit_service.config.model_name if ai_commit_service.config else "gpt-4",
						input_tokens=input_tokens,
						output_tokens=output_tokens,
						cost=charge_result.get("cost", 0),
						payment_method=charge_result.get("payment_method", "free"),
						wallet_transaction_id=charge_result.get("wallet_transaction_id"),
						document_id=charge_result.get("document_id"),
						context={"type": "voice_chat", "ai_session_id": session_id},
					)

					from datetime import datetime as _dt
					commit_session.updated_at = _dt.utcnow()
					db_commit.commit()
					db_commit.refresh(assistant_message)
					assistant_message_id = assistant_message.id
			except Exception:
				logger.exception("Failed to commit assistant voice message")

		# opt-in data collection
		interaction_id: int | None = None
		if collect_data_opt_in and settings.voice_data_collection_enabled:
			try:
				base_dir = settings.voice_data_collection_dir
				now = datetime.utcnow()
				day = now.strftime("%Y-%m-%d")
				dir_path = os.path.join(base_dir, day, f"user_{user.id}", f"ai_session_{session_id}")
				os.makedirs(dir_path, exist_ok=True)

				ts = now.strftime("%H%M%S_%f")
				in_path = os.path.join(dir_path, f"{ts}_input.pcm16")
				out_path = os.path.join(dir_path, f"{ts}_assistant.pcm16")
				with open(in_path, "wb") as f:
					f.write(utterance_pcm)
				if assistant_audio_capture is not None:
					with open(out_path, "wb") as f:
						f.write(bytes(assistant_audio_capture))
				else:
					out_path = None  # type: ignore[assignment]

				meta = {
					"input_audio": {"format": "pcm_s16le", "sample_rate": audio_sample_rate, "channels": 1},
					"output_audio": {"format": "pcm_s16le", "sample_rate": int(settings.voice_tts_output_sample_rate_hz), "channels": 1},
					"stt": {"engine": "faster-whisper", "language": settings.voice_stt_language, "model": settings.voice_stt_model_size_or_path},
					"tts": {"engine": settings.voice_tts_engine, "model_name": settings.voice_tts_model_name, "model_path": settings.voice_tts_model_path},
					"usage": final_usage,
				}

				with get_db_session() as db5:
					obj = AIVoiceInteraction(
						user_id=user.id,
						business_id=business_id,
						ai_session_id=session_id,
						consent=True,
						input_transcript=text,
						input_audio_path=in_path,
						assistant_text=accumulated_text,
						assistant_audio_path=out_path,
						stt_model=settings.voice_stt_model_size_or_path,
						tts_engine=settings.voice_tts_engine,
						tts_model=settings.voice_tts_model_name or settings.voice_tts_model_path,
						meta_json=json.dumps(meta, ensure_ascii=False),
					)
					db5.add(obj)
					db5.commit()
					db5.refresh(obj)
					interaction_id = obj.id
			except Exception:
				logger.exception("voice data collection failed")

		await send_event(
			{
				"type": "assistant_done",
				"text": accumulated_text,
				"usage": final_usage,
				"message_id": assistant_message_id,
				"interaction_id": interaction_id,
			}
		)

	await send_event(
		{
			"type": "ready",
			"input_audio": {"format": "pcm_s16le", "sample_rate": audio_sample_rate, "channels": 1, "frame_ms": frame_ms},
			"output_audio": {
				"format": "pcm_s16le",
				"sample_rate": int(settings.voice_tts_output_sample_rate_hz),
				"channels": 1,
				"frame_ms": int(settings.voice_tts_frame_ms),
			},
		}
	)

	try:
		while True:
			message = await websocket.receive()
			msg_type = message.get("type")

			# control
			if msg_type == "websocket.receive" and message.get("text") is not None:
				try:
					payload = json.loads(message["text"])
				except Exception:
					await send_event({"type": "error", "error": "INVALID_JSON", "message": "فرمت پیام نامعتبر است"})
					continue

				action = payload.get("type")
				if action == "audio":
					# Web/client base64 audio frame
					b64 = payload.get("audio_b64")
					if not isinstance(b64, str) or not b64:
						await send_event({"type": "error", "error": "INVALID_AUDIO", "message": "audio_b64 نامعتبر است"})
						continue
					try:
						frame = base64.b64decode(b64)
					except Exception:
						await send_event({"type": "error", "error": "INVALID_AUDIO", "message": "base64 نامعتبر است"})
						continue

					if session_id is None or business_id is None:
						await send_event({"type": "error", "error": "NOT_STARTED", "message": "ابتدا پیام start را ارسال کنید"})
						continue

					vad_event = vad.process_bytes(frame)
					if vad_event.speech_started:
						if currently_speaking:
							cancel_event.set()
						await send_event({"type": "speech_start"})

					if vad_event.utterance_completed and vad_event.utterance_pcm is not None:
						await _handle_utterance(vad_event.utterance_pcm)
					continue

				if action == "start":
					requested_session_id = payload.get("session_id")
					if not isinstance(requested_session_id, int):
						await send_event({"type": "error", "error": "SESSION_ID_REQUIRED", "message": "session_id الزامی است"})
						continue

					collect_data_opt_in = bool(payload.get("collect_data", False))
					if collect_data_opt_in and not settings.voice_data_collection_enabled:
						collect_data_opt_in = False

					transport = payload.get("audio_transport", "binary")
					if transport not in ("binary", "base64"):
						await send_event({"type": "error", "error": "INVALID_TRANSPORT", "message": "audio_transport نامعتبر است"})
						continue
					audio_transport = transport

					with get_db_session() as db2:
						session_repo = AIChatSessionRepository(db2)
						ai_session = session_repo.get_by_id(requested_session_id)
						if not ai_session or ai_session.user_id != user.id:
							await send_event({"type": "error", "error": "SESSION_NOT_FOUND", "message": "گفت‌وگو یافت نشد"})
							continue
						session_id = requested_session_id
						business_id = ai_session.business_id

					cancel_event.clear()
					vad.reset()
					await send_event(
						{
							"type": "started",
							"session_id": session_id,
							"business_id": business_id,
							"audio_transport": audio_transport,
							"data_collection": {"enabled": bool(settings.voice_data_collection_enabled), "opt_in": collect_data_opt_in},
						}
					)
					continue

				if action == "barge_in":
					cancel_event.set()
					await send_event({"type": "barge_in_ack"})
					continue

				if action == "stop":
					await send_event({"type": "stopped"})
					break

				await send_event({"type": "error", "error": "UNKNOWN_COMMAND", "message": "دستور ناشناخته"})
				continue

			# audio frames
			if msg_type == "websocket.receive" and message.get("bytes") is not None:
				if session_id is None or business_id is None:
					await send_event({"type": "error", "error": "NOT_STARTED", "message": "ابتدا پیام start را ارسال کنید"})
					continue

				frame = message["bytes"]
				vad_event = vad.process_bytes(frame)

				if vad_event.speech_started:
					if currently_speaking:
						cancel_event.set()
					await send_event({"type": "speech_start"})

				if vad_event.utterance_completed and vad_event.utterance_pcm is not None:
					await _handle_utterance(vad_event.utterance_pcm)
					continue

				continue

			if msg_type == "websocket.disconnect":
				break

	except WebSocketDisconnect:
		pass
	finally:
		try:
			await websocket.close()
		except Exception:
			pass