from __future__ import annotations

from typing import Dict, Any, List, Optional
from fastapi import APIRouter, Depends, Request, Body, Path, Query, Response
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
import json
import logging

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError, format_datetime_fields
from app.services.ai.ai_service import AIService
from adapters.db.repositories.ai_chat_repository import AIChatSessionRepository, AIChatMessageRepository
from adapters.db.models.ai_chat_session import AIChatSession
from adapters.db.models.ai_chat_message import AIChatMessage, MessageRole
from pydantic import BaseModel

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ai/chat", tags=["هوش مصنوعی"])
DEFAULT_CHAT_TITLE = "گفت‌وگوی جدید"


class ChatMessageRequest(BaseModel):
    content: str
    session_id: Optional[int] = None


class CheckAvailabilityRequest(BaseModel):
    business_id: Optional[int] = None
    estimated_tokens: int = 1000


@router.post("/check-availability", summary="بررسی امکان استفاده از AI")
async def check_ai_availability(
    request: Request,
    params: CheckAvailabilityRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """
    بررسی اینکه آیا کاربر می‌تواند از AI استفاده کند
    (چک پیشگیرانه قبل از ارسال پیام)
    """
    business_id = params.business_id or ctx.business_id
    ai_service = AIService(db, ctx, business_id)
    
    availability = ai_service.check_availability(
        estimated_tokens=params.estimated_tokens
    )
    
    return success_response(availability, request)


@router.get("/sessions", summary="لیست گفت‌وگوها")
async def get_chat_sessions(
    request: Request,
    business_id: Optional[int] = None,
    limit: int = 50,
    skip: int = 0,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت لیست گفت‌وگوهای کاربر"""
    repo = AIChatSessionRepository(db)
    sessions = repo.get_user_sessions(
        user_id=ctx.get_user_id(),
        business_id=business_id or ctx.business_id,
        limit=limit,
        skip=skip
    )
    
    result = []
    for session in sessions:
        result.append({
            "id": session.id,
            "user_id": session.user_id,
            "title": session.title,
            "business_id": session.business_id,
            "created_at": session.created_at.isoformat() if session.created_at else None,
            "updated_at": session.updated_at.isoformat() if session.updated_at else None
        })
    
    return success_response(result, request)


@router.post("/sessions", summary="ایجاد گفت‌وگوی جدید")
async def create_chat_session(
    request: Request,
    title: Optional[str] = Body(None, embed=True),
    business_id: Optional[int] = Body(None, embed=True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """ایجاد گفت‌وگوی جدید"""
    session = AIChatSession(
        user_id=ctx.get_user_id(),
        business_id=business_id or ctx.business_id,
        title=title or DEFAULT_CHAT_TITLE
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    
    return success_response({
        "id": session.id,
        "user_id": session.user_id,
        "title": session.title,
        "business_id": session.business_id,
        "created_at": session.created_at.isoformat() if session.created_at else None,
        "updated_at": session.updated_at.isoformat() if session.updated_at else None
    }, request, "جلسه چت با موفقیت ایجاد شد")


@router.get("/sessions/{session_id}/messages", summary="دریافت پیام‌های جلسه")
async def get_session_messages(
    session_id: int = Path(...),
    limit: int = 100,
    skip: int = 0,
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت پیام‌های یک گفت‌وگو"""
    # بررسی دسترسی
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)
    
    message_repo = AIChatMessageRepository(db)
    messages = message_repo.get_session_messages(session_id, limit, skip)
    
    result = []
    for msg in messages:
        function_calls = msg.function_calls
        if isinstance(function_calls, str):
            try:
                import json
                function_calls = json.loads(function_calls)
            except Exception:
                pass
        
        function_results = msg.function_results
        if isinstance(function_results, str):
            try:
                import json
                function_results = json.loads(function_results)
            except Exception:
                pass
        
        result.append({
            "id": msg.id,
            "session_id": msg.session_id,
            "role": msg.role if isinstance(msg.role, str) else getattr(msg.role, "value", msg.role),
            "content": msg.content,
            "function_calls": function_calls,
            "function_results": function_results,
            "tokens_used": msg.tokens_used,
            "created_at": msg.created_at.isoformat() if msg.created_at else None
        })
    
    return success_response(result, request)


@router.post("/sessions/{session_id}/messages", summary="ارسال پیام به AI")
async def send_message(
    session_id: int = Path(...),
    request: Request = None,
    message_data: ChatMessageRequest = Body(...),
    stream: bool = Query(False, description="استفاده از streaming"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """ارسال پیام به AI و دریافت پاسخ (با یا بدون streaming)"""
    # بررسی دسترسی
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)
    
    # دریافت پیام‌های قبلی
    message_repo = AIChatMessageRepository(db)
    previous_messages = message_repo.get_session_messages(session_id, limit=50)
    
    # ساخت messages برای AI
    messages = []
    for msg in previous_messages:
        messages.append({
            "role": msg.role,
            "content": msg.content
        })
    
    # اضافه کردن پیام جدید
    messages.append({
        "role": "user",
        "content": message_data.content
    })
    
    # ذخیره پیام کاربر
    user_message = AIChatMessage(
        session_id=session_id,
        role=MessageRole.USER.value,
        content=message_data.content,
        tokens_used=0
    )
    db.add(user_message)
    
    # اگر streaming درخواست شده باشد
    if stream:
        # commit کردن پیام کاربر قبل از شروع streaming
        # تا اگر خطایی رخ داد، حداقل پیام کاربر ذخیره شده باشد
        db.commit()
        db.refresh(user_message)
        # refresh کردن session تا مطمئن شویم که به‌روزرسانی‌های بعدی کار می‌کنند
        db.refresh(session)
        
        # ذخیره business_id قبل از بستن session
        business_id = session.business_id
        
        # بستن session اصلی برای جلوگیری از connection leak
        # session برای streaming استفاده نمی‌شود (در _stream_message_response از session جدید استفاده می‌شود)
        db.close()
        
        return StreamingResponse(
            _stream_message_response(
                session_id=session_id,
                messages=messages,
                ctx=ctx,
                business_id=business_id,
                previous_messages=previous_messages,
                message_content=message_data.content
            ),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",  # برای nginx
            }
        )
    
    # برای non-streaming، بعد از ذخیره پیام AI commit می‌کنیم
    db.flush()
    
    # ذخیره business_id و session title قبل از بستن session
    business_id = session.business_id
    session_title = session.title
    is_first_message = len(previous_messages) == 0
    
    # بستن session اصلی برای جلوگیری از connection leak در طول async operation
    db.close()
    
    # حالت non-streaming (کد قبلی)
    # ارسال به AI به صورت async (بدون session)
    from adapters.db.session import get_db_session
    with get_db_session() as new_db:
        new_ai_service = AIService(new_db, ctx, business_id)
        response = await new_ai_service.chat_completion(messages, use_function_calling=True, session_business_id=business_id)
    
    response_content_preview = (response.get("message", {}).get("content") or "")[:500]
    logger.info(
        "[AI Response][session=%s][stream=%s] preview=%s",
        session_id,
        False,
        response_content_preview
    )
    
    # بررسی سهمیه و شارژ و ذخیره پاسخ (با session جدید)
    usage = response.get("usage", {})
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    
    with get_db_session() as commit_db:
        # خواندن session از دیتابیس
        commit_session_repo = AIChatSessionRepository(commit_db)
        commit_session = commit_session_repo.get_by_id(session_id)
        
        if not commit_session:
            raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)
        
        commit_ai_service = AIService(commit_db, ctx, business_id)
        charge_result = commit_ai_service.check_quota_and_charge(input_tokens, output_tokens)
        
        # ذخیره پاسخ AI
        assistant_message = AIChatMessage(
            session_id=session_id,
            role=MessageRole.ASSISTANT.value,
            content=response["message"]["content"],
            tokens_used=input_tokens + output_tokens
        )
        commit_db.add(assistant_message)
        
        # ثبت لاگ استفاده
        commit_ai_service.log_usage(
            provider=commit_ai_service.config.provider if commit_ai_service.config else "openai",
            model=commit_ai_service.config.model_name if commit_ai_service.config else "gpt-4",
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost=charge_result.get("cost", 0),
            payment_method=charge_result.get("payment_method", "free"),
            wallet_transaction_id=charge_result.get("wallet_transaction_id"),
            document_id=charge_result.get("document_id")
        )
        
        # اگر عنوان پیش‌فرض است و این اولین پیام کاربر است، عنوان هوشمند بساز
        if (not commit_session.title or commit_session.title == DEFAULT_CHAT_TITLE) and is_first_message:
            generated_title = await commit_ai_service.generate_chat_title(message_data.content)
            if generated_title:
                commit_session.title = generated_title[:80]
        
        # به‌روزرسانی زمان جلسه
        from datetime import datetime
        commit_session.updated_at = datetime.utcnow()
        
        commit_db.commit()
        commit_db.refresh(assistant_message)
        message_id = assistant_message.id
    
    return success_response({
        "message": {
            "id": message_id,
            "session_id": session_id,
            "role": MessageRole.ASSISTANT.value,
            "content": response["message"]["content"],
            "tokens_used": input_tokens + output_tokens,
            "created_at": None  # از دیتابیس خوانده می‌شود
        },
        "usage": {
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "total_tokens": input_tokens + output_tokens,
            "cost": charge_result.get("cost", 0),
            "payment_method": charge_result.get("payment_method", "free")
        }
    }, request)


async def _stream_message_response(
    session_id: int,
    messages: List[Dict[str, Any]],
    ctx: AuthContext,
    business_id: int,
    previous_messages: List[AIChatMessage],
    message_content: str
):
    """Generator برای streaming response
    
    ⚠️ مهم: از session جدید برای هر عملیات استفاده می‌کنیم تا از connection leak جلوگیری کنیم.
    Session فقط برای commit نهایی استفاده می‌شود و بلافاصله بسته می‌شود.
    """
    from adapters.db.session import get_db_session
    
    try:
        # استفاده از session جدید برای AI service (فقط برای خواندن config)
        with get_db_session() as db:
            ai_service = AIService(db, ctx, business_id)
            # کپی کردن config برای استفاده بعد از بسته شدن session
            ai_config = ai_service.config
        
        # استفاده از config برای streaming (بدون session)
        accumulated_content = ""
        final_usage = None
        
        # ایجاد AI service موقت برای streaming
        # برای streaming، از session موقت استفاده می‌کنیم که بعد از streaming بسته می‌شود
        with get_db_session() as temp_db:
            temp_ai_service = AIService(temp_db, ctx, business_id)
            # ارسال chunks به صورت streaming
            async for chunk in temp_ai_service.chat_completion_stream(messages, use_function_calling=True, session_business_id=business_id):
                delta = chunk.get("delta", {})
                content_chunk = delta.get("content", "")
                
                if content_chunk:
                    accumulated_content += content_chunk
                    logger.info(
                        "[AI Stream][session=%s] chunk=%s",
                        session_id,
                        content_chunk[:200]
                    )
                
                # ذخیره usage از chunk آخر
                if chunk.get("usage"):
                    final_usage = chunk["usage"]
                
                # فرمت SSE: data: {json}\n\n
                yield f"data: {json.dumps({'content': content_chunk, 'done': chunk.get('done', False)})}\n\n"
                
                # اگر streaming تمام شده باشد
                if chunk.get("done", False):
                    # در chunk نهایی، accumulated_content باید کامل باشد
                    # اما برای اطمینان، از content_chunk هم استفاده نمی‌کنیم چون خالی است
                    break
        
        logger.info(
            "[AI Stream][session=%s] final_response_length=%s preview=%s",
            session_id,
            len(accumulated_content),
            (accumulated_content or "")[:500]
        )
        
        # بعد از تمام شدن streaming:
        # 1. ذخیره پیام در دیتابیس
        # 2. بررسی سهمیه و شارژ
        # 3. ارسال chunk نهایی با usage stats
        
        # اگر usage موجود نبود، از provider تخمین بزن
        if not final_usage:
            # تخمین tokens از accumulated_content
            from app.services.ai.ai_provider import create_provider
            from app.services.ai.encryption import decrypt_api_key
            
            if ai_service.config:
                api_key = decrypt_api_key(ai_service.config.api_key) if ai_service.config.api_key else None
                if api_key:
                    provider = create_provider(
                        provider_type=ai_service.config.provider,
                        api_key=api_key,
                        api_base_url=ai_service.config.api_base_url
                    )
                    
                    # تخمین input tokens از messages
                    input_tokens_estimate = 0
                    for msg in messages:
                        input_tokens_estimate += provider.estimate_tokens(msg.get("content", ""))
                    
                    # تخمین output tokens از accumulated_content
                    output_tokens_estimate = provider.estimate_tokens(accumulated_content)
                    
                    final_usage = {
                        "input_tokens": input_tokens_estimate,
                        "output_tokens": output_tokens_estimate,
                        "total_tokens": input_tokens_estimate + output_tokens_estimate
                    }
        
        if final_usage:
            input_tokens = final_usage.get("input_tokens", 0)
            output_tokens = final_usage.get("output_tokens", 0)
            
            # استفاده از session جدید برای commit (جلوگیری از connection leak)
            with get_db_session() as new_db:
                # خواندن session و message از دیتابیس
                from adapters.db.repositories.ai_chat_repository import AIChatSessionRepository
                session_repo = AIChatSessionRepository(new_db)
                updated_session = session_repo.get_by_id(session_id)
                
                if not updated_session:
                    logger.error(f"Session {session_id} not found for commit")
                    yield f"data: {json.dumps({'error': 'Session not found', 'done': True})}\n\n"
                    return
                
                # ایجاد AI service جدید با session جدید
                new_ai_service = AIService(new_db, ctx, updated_session.business_id)
                
                charge_result = new_ai_service.check_quota_and_charge(input_tokens, output_tokens)
                
                # ذخیره پاسخ AI
                assistant_message = AIChatMessage(
                    session_id=session_id,
                    role=MessageRole.ASSISTANT.value,
                    content=accumulated_content,
                    tokens_used=input_tokens + output_tokens
                )
                new_db.add(assistant_message)
                
                # ثبت لاگ استفاده
                new_ai_service.log_usage(
                    provider=new_ai_service.config.provider if new_ai_service.config else "openai",
                    model=new_ai_service.config.model_name if new_ai_service.config else "gpt-4",
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                    cost=charge_result.get("cost", 0),
                    payment_method=charge_result.get("payment_method", "free"),
                    wallet_transaction_id=charge_result.get("wallet_transaction_id"),
                    document_id=charge_result.get("document_id")
                )
                
                # اگر عنوان پیش‌فرض است و این اولین پیام کاربر است، عنوان هوشمند بساز
                if (not updated_session.title or updated_session.title == DEFAULT_CHAT_TITLE) and len(previous_messages) == 0:
                    generated_title = await new_ai_service.generate_chat_title(message_content)
                    if generated_title:
                        updated_session.title = generated_title[:80]
                
                # به‌روزرسانی زمان جلسه
                from datetime import datetime
                updated_session.updated_at = datetime.utcnow()
                
                new_db.commit()
                new_db.refresh(assistant_message)
                message_id = assistant_message.id
            
            # ارسال chunk نهایی با usage (بعد از بسته شدن session)
            yield f"data: {json.dumps({'content': '', 'done': True, 'usage': final_usage, 'message_id': message_id})}\n\n"
        else:
            # در صورت خطا - حداقل پیام را ذخیره کن (با session جدید)
            with get_db_session() as new_db:
                from adapters.db.repositories.ai_chat_repository import AIChatSessionRepository
                session_repo = AIChatSessionRepository(new_db)
                updated_session = session_repo.get_by_id(session_id)
                
                if updated_session:
                    assistant_message = AIChatMessage(
                        session_id=session_id,
                        role=MessageRole.ASSISTANT.value,
                        content=accumulated_content or "خطا در دریافت پاسخ",
                        tokens_used=0
                    )
                    new_db.add(assistant_message)
                    from datetime import datetime
                    updated_session.updated_at = datetime.utcnow()
                    new_db.commit()
                    new_db.refresh(assistant_message)
                    message_id = assistant_message.id
                else:
                    message_id = None
            
            # ارسال chunk نهایی بدون usage (اما با message_id)
            yield f"data: {json.dumps({'content': '', 'done': True, 'usage': None, 'message_id': message_id, 'warning': 'Usage information not available'})}\n\n"
            
    except Exception as e:
        # ارسال خطا به صورت SSE
        import traceback
        logger.error(f"Error in streaming response: {e}", exc_info=True)
        error_data = {
            "error": str(e),
            "done": True
        }
        yield f"data: {json.dumps(error_data)}\n\n"


@router.delete("/sessions/{session_id}", summary="حذف گفت‌وگو")
async def delete_chat_session(
    session_id: int = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """حذف گفت‌وگو"""
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)
    
    db.delete(session)
    db.commit()
    
    return success_response({"id": session_id}, request, "گفت‌وگو با موفقیت حذف شد")

