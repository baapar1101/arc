from __future__ import annotations

from typing import Dict, Any, List, Optional
from fastapi import APIRouter, Depends, Request, Body, Path
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError, format_datetime_fields
from app.services.ai.ai_service import AIService
from adapters.db.repositories.ai_chat_repository import AIChatSessionRepository, AIChatMessageRepository
from adapters.db.models.ai_chat_session import AIChatSession
from adapters.db.models.ai_chat_message import AIChatMessage, MessageRole
from pydantic import BaseModel

router = APIRouter(prefix="/ai/chat", tags=["ai-chat"])


class ChatMessageRequest(BaseModel):
    content: str
    session_id: Optional[int] = None


@router.get("/sessions", summary="لیست جلسات چت")
async def get_chat_sessions(
    request: Request,
    business_id: Optional[int] = None,
    limit: int = 50,
    skip: int = 0,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت لیست جلسات چت کاربر"""
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


@router.post("/sessions", summary="ایجاد جلسه چت جدید")
async def create_chat_session(
    request: Request,
    title: str = Body(..., embed=True),
    business_id: Optional[int] = Body(None, embed=True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """ایجاد جلسه چت جدید"""
    session = AIChatSession(
        user_id=ctx.get_user_id(),
        business_id=business_id or ctx.business_id,
        title=title
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
    """دریافت پیام‌های یک جلسه چت"""
    # بررسی دسترسی
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "جلسه چت یافت نشد", http_status=404)
    
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
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """ارسال پیام به AI و دریافت پاسخ"""
    # بررسی دسترسی
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "جلسه چت یافت نشد", http_status=404)
    
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
    db.flush()
    
    # ارسال به AI
    ai_service = AIService(db, ctx, session.business_id)
    response = ai_service.chat_completion(messages, use_function_calling=True)
    
    # بررسی سهمیه و شارژ
    usage = response.get("usage", {})
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    
    charge_result = ai_service.check_quota_and_charge(input_tokens, output_tokens)
    
    # ذخیره پاسخ AI
    assistant_message = AIChatMessage(
        session_id=session_id,
        role=MessageRole.ASSISTANT.value,
        content=response["message"]["content"],
        tokens_used=input_tokens + output_tokens
    )
    db.add(assistant_message)
    
    # ثبت لاگ استفاده
    ai_service.log_usage(
        provider=ai_service.config.provider if ai_service.config else "openai",
        model=ai_service.config.model_name if ai_service.config else "gpt-4",
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cost=charge_result.get("cost", 0),
        payment_method=charge_result.get("payment_method", "free"),
        wallet_transaction_id=charge_result.get("wallet_transaction_id"),
        document_id=charge_result.get("document_id")
    )
    
    # به‌روزرسانی زمان جلسه
    from datetime import datetime
    session.updated_at = datetime.utcnow()
    
    db.commit()
    
    return success_response({
        "message": {
            "id": assistant_message.id,
            "session_id": assistant_message.session_id,
            "role": assistant_message.role if isinstance(assistant_message.role, str) else getattr(assistant_message.role, "value", assistant_message.role),
            "content": assistant_message.content,
            "tokens_used": assistant_message.tokens_used,
            "created_at": assistant_message.created_at.isoformat() if assistant_message.created_at else None
        },
        "usage": {
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "total_tokens": input_tokens + output_tokens,
            "cost": charge_result.get("cost", 0),
            "payment_method": charge_result.get("payment_method", "free")
        }
    }, request)


@router.delete("/sessions/{session_id}", summary="حذف جلسه چت")
async def delete_chat_session(
    session_id: int = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """حذف جلسه چت"""
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "جلسه چت یافت نشد", http_status=404)
    
    db.delete(session)
    db.commit()
    
    return success_response({"id": session_id}, request, "جلسه چت با موفقیت حذف شد")

