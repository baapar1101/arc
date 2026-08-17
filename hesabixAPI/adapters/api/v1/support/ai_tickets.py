from typing import Dict, Any, TYPE_CHECKING
from fastapi import APIRouter, Depends, Request, Body, Path
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.core.permissions import require_app_permission
from app.services.ai.ai_service import AIService
from app.services.ai.prompt_service import get_prompt_by_key
from app.services.ai.ai_channel_policy import (
    CHANNEL_TICKET,
    CHANNEL_TICKET_READ_TOOLS,
    CHANNEL_ITERATION_CAP,
    filter_tools_by_allowlist,
)
from app.services.ai.ai_untrusted import wrap_untrusted_block
from adapters.db.repositories.support.ticket_repository import TicketRepository
from adapters.db.repositories.support.message_repository import MessageRepository
from adapters.api.v1.schemas import QueryInfo
from app.services.notification_service import NotificationService
from app.services.support.notification_helpers import support_notification_context
from pydantic import BaseModel
import logging

router = APIRouter(prefix="/support", tags=["support-ai"])

logger = logging.getLogger(__name__)


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
    
    # ساخت context برای AI (متن تیکت دادهٔ غیرقابل‌اعتماد است)
    context_messages = []
    if options.use_ticket_history:
        for msg in ticket_messages:
            sender_type_str = (
                msg.sender_type.value
                if hasattr(msg.sender_type, "value")
                else str(msg.sender_type)
            )
            wrapped = wrap_untrusted_block(
                "ticket",
                msg.content or "",
                title=f"ticket-{ticket_id}-{sender_type_str}",
            )
            if not wrapped:
                continue
            context_messages.append({
                "role": "user" if sender_type_str == "user" else "assistant",
                "content": wrapped,
            })
    
    # دریافت اطلاعات کسب‌وکار کاربر (اگر نیاز باشد)
    business_info = None
    if options.use_business_info and ticket.user:
        # TODO: دریافت اطلاعات کسب‌وکار کاربر
        pass
    
    # ایجاد AI Service
    ai_service = AIService(db, ctx)
    
    # چک اعتبار قبل از ارسال
    try:
        availability = ai_service.check_availability(estimated_tokens=1500)
        if not availability["can_use"]:
            reason = availability.get("reason")
            details = availability.get("details", {})
            message = details.get("message", "امکان استفاده از AI وجود ندارد")
            
            raise ApiError(
                reason or "AI_UNAVAILABLE",
                message,
                http_status=400,
                extra_data=details
            )
    except ApiError:
        raise
    except Exception as e:
        logger.warning(f"Error checking AI availability: {e}")
        # در صورت خطا، اجازه ادامه بده
    
    user_name = f"{ticket.user.first_name or ''} {ticket.user.last_name or ''}".strip()
    system_prompt = get_prompt_by_key(
        db,
        "support.ticket_suggest.system",
        {
            "user_name": user_name,
            "ticket_title": ticket.title,
            "category": ticket.category.name if ticket.category else "نامشخص",
            "priority": ticket.priority.name if ticket.priority else "نامشخص",
        },
    )
    
    ticket_user_prompt = get_prompt_by_key(
        db,
        "support.ticket_suggest.user",
        {
            "ticket_description": wrap_untrusted_block(
                "ticket",
                ticket.description or "",
                title=f"ticket-{ticket_id}-description",
            )
        },
    )
    ai_messages = [
        {"role": "system", "content": system_prompt},
        *context_messages,
        {"role": "user", "content": ticket_user_prompt},
    ]

    catalog = ai_service.get_available_functions(
        session_business_id=ai_service.business_id,
        user_query=ticket.title or ticket.description or "",
        execution_mode="analyzer",
    )
    tools = filter_tools_by_allowlist(catalog, CHANNEL_TICKET_READ_TOOLS)
    response = await ai_service.chat_completion(
        ai_messages,
        tools=tools,
        use_function_calling=True,
        execution_mode="analyzer",
        approve_writes=False,
        user_query=ticket.title or "",
        session_business_id=ai_service.business_id,
        iteration_cap=CHANNEL_ITERATION_CAP[CHANNEL_TICKET],
    )
    
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
    tools_used = []
    for item in response.get("_function_calls") or []:
        if isinstance(item, dict) and item.get("name"):
            tools_used.append(str(item["name"]))
    citations = response.get("citations") or []
    if not isinstance(citations, list):
        citations = []

    return success_response({
        "suggested_reply": suggested_reply,
        "tools_used": tools_used,
        "citations": citations,
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
    
    # ارسال ناتیفیکیشن به کاربر
    if ticket and ticket.user_id:
        try:
            notification_service = NotificationService(db)
            operator_name = f"{ctx.user.first_name or ''} {ctx.user.last_name or ''}".strip() or "اپراتور پشتیبانی"
            message_preview = suggested_reply[:200] + ("..." if len(suggested_reply) > 200 else "")
            
            context = support_notification_context({
                "subject": f"پاسخ جدید به تیکت #{ticket_id}",
                "message": f"اپراتور {operator_name} به تیکت شما پاسخ داد:\n\n{message_preview}",
                "ticket_id": ticket_id,
                "ticket_title": ticket.title if hasattr(ticket, 'title') else "تیکت",
                "operator_name": operator_name,
                "message_preview": message_preview,
                "user_id": ticket.user_id,
            }, ticket_id)
            
            notification_service.send(
                user_id=ticket.user_id,
                event_key="support.operator_reply",
                context=context,
                preferred_channels=["inapp", "email", "telegram", "sms"],
                broadcast_mode=False
            )
        except Exception as e:
            # در صورت خطا، لاگ می‌کنیم اما فرآیند اصلی ادامه می‌یابد
            logger = logging.getLogger(__name__)
            logger.error(f"خطا در ارسال ناتیفیکیشن برای پاسخ AI به تیکت {ticket_id}: {e}")
    
    return success_response({
        "message_id": message.id,
        "content": message.content,
        "suggested_reply": suggested_reply
    }, request, "پاسخ با موفقیت ارسال شد")

