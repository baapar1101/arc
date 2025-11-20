from typing import Dict, Any, TYPE_CHECKING
from fastapi import APIRouter, Depends, Request, Body, Path
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.core.permissions import require_app_permission
from app.services.ai.ai_service import AIService
from adapters.db.repositories.support.ticket_repository import TicketRepository
from adapters.db.repositories.support.message_repository import MessageRepository
from adapters.api.v1.schemas import QueryInfo
from pydantic import BaseModel

router = APIRouter(prefix="/support", tags=["support-ai"])


class AISuggestReplyRequest(BaseModel):
    use_ticket_history: bool = True
    use_business_info: bool = True


@router.post("/tickets/{ticket_id}/ai-suggest-reply", summary="پیشنهاد پاسخ AI")
@require_app_permission("support_operator")
async def suggest_ai_reply(
    ticket_id: int = Path(...),
    request: Request = None,
    options: AISuggestReplyRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت پیشنهاد پاسخ AI برای تیکت"""
    ticket_repo = TicketRepository(db)
    ticket = ticket_repo.get_operator_ticket_with_details(ticket_id)
    
    if not ticket:
        raise ApiError("TICKET_NOT_FOUND", "تیکت یافت نشد", http_status=404)
    
    # دریافت تاریخچه تیکت
    # استفاده از messages از طریق relationship در ticket (که قبلاً load شده)
    ticket_messages = ticket.messages if ticket.messages else []
    
    # ساخت context برای AI
    context_messages = []
    if options.use_ticket_history:
        for msg in ticket_messages:
            # تبدیل sender_type به string اگر enum باشد
            sender_type_str = msg.sender_type.value if hasattr(msg.sender_type, 'value') else str(msg.sender_type)
            context_messages.append({
                "role": "user" if sender_type_str == "user" else "assistant",
                "content": msg.content
            })
    
    # دریافت اطلاعات کسب‌وکار کاربر (اگر نیاز باشد)
    business_info = None
    if options.use_business_info and ticket.user:
        # TODO: دریافت اطلاعات کسب‌وکار کاربر
        pass
    
    # ایجاد AI Service
    ai_service = AIService(db, ctx)
    
    # ساخت prompt برای AI
    system_prompt = f"""شما یک دستیار هوشمند برای اپراتورهای پشتیبانی هستید.
تیکت مربوط به کاربر {ticket.user.first_name or ''} {ticket.user.last_name or ''} است.
موضوع تیکت: {ticket.title}
دسته‌بندی: {ticket.category.name if ticket.category else 'نامشخص'}
اولویت: {ticket.priority.name if ticket.priority else 'نامشخص'}

لطفاً یک پاسخ حرفه‌ای و مفید برای این تیکت پیشنهاد دهید."""
    
    # ارسال به AI
    ai_messages = [
        {"role": "system", "content": system_prompt},
        *context_messages,
        {"role": "user", "content": f"لطفاً برای این تیکت پاسخ مناسبی پیشنهاد دهید:\n\n{ticket.description}"}
    ]
    
    response = ai_service.chat_completion(ai_messages, use_function_calling=True)
    
    # بررسی سهمیه و شارژ
    usage = response.get("usage", {})
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    
    charge_result = ai_service.check_quota_and_charge(input_tokens, output_tokens)
    
    # ثبت لاگ استفاده
    ai_service.log_usage(
        provider=ai_service.config.provider if ai_service.config else "openai",
        model=ai_service.config.model_name if ai_service.config else "gpt-4",
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cost=charge_result.get("cost", 0),
        payment_method=charge_result.get("payment_method", "free"),
        wallet_transaction_id=charge_result.get("wallet_transaction_id"),
        document_id=charge_result.get("document_id"),
        context={"ticket_id": ticket_id, "type": "suggest_reply"}
    )
    
    suggested_reply = response["message"]["content"]
    
    return success_response({
        "suggested_reply": suggested_reply,
        "usage": {
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "total_tokens": input_tokens + output_tokens,
            "cost": charge_result.get("cost", 0),
            "payment_method": charge_result.get("payment_method", "free")
        }
    }, request)


@router.post("/tickets/{ticket_id}/ai-auto-reply", summary="پاسخ خودکار AI")
@require_app_permission("support_operator")
async def ai_auto_reply(
    ticket_id: int = Path(...),
    request: Request = None,
    options: AISuggestReplyRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """ارسال خودکار پاسخ AI به تیکت"""
    # دریافت پیشنهاد
    suggest_result = await suggest_ai_reply(ticket_id, request, options, db, ctx)
    suggested_reply = suggest_result["data"]["suggested_reply"]
    
    # ارسال پیام
    message_repo = MessageRepository(db)
    message = message_repo.create_message(
        ticket_id=ticket_id,
        sender_id=ctx.get_user_id(),
        sender_type="operator",
        content=suggested_reply,
        is_internal=False
    )
    
    # تخصیص تیکت به اپراتور (اگر هنوز تخصیص نشده)
    ticket_repo = TicketRepository(db)
    ticket = ticket_repo.get_by_id(ticket_id)
    if ticket and not ticket.assigned_operator_id:
        ticket_repo.assign_ticket(ticket_id, ctx.get_user_id())
    
    db.commit()
    
    return success_response({
        "message_id": message.id,
        "content": message.content,
        "suggested_reply": suggested_reply
    }, request, "پاسخ با موفقیت ارسال شد")

