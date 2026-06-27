from __future__ import annotations

from typing import Dict, Any, List, Optional
from fastapi import APIRouter, Depends, Request, Body, Path, Query, Response, UploadFile, File
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
import json
import logging

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError, format_datetime_fields
from app.services.ai.ai_service import AIService
from app.services.ai.chat_message_builder import (
    build_llm_messages_from_history,
    parse_json_field,
    serialize_function_metadata,
)
from adapters.db.repositories.ai_chat_repository import AIChatSessionRepository, AIChatMessageRepository
from adapters.db.models.ai_chat_session import AIChatSession
from adapters.db.models.ai_chat_message import AIChatMessage, MessageRole
from app.services.ai.ai_execution_policy import (
    exploration_mode_for_execution,
    resolve_execution_mode,
)
from pydantic import BaseModel

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ai/chat", tags=["هوش مصنوعی"])
DEFAULT_CHAT_TITLE = "گفت‌وگوی جدید"


from app.services.ai.ai_constants import AI_OPERATION_CHAT
from app.services.ai.ai_tool_intent import estimate_query_complexity


def _prepare_ai_service_model(ai_service: AIService, model: Optional[str]) -> None:
    if model:
        ai_service.set_request_model(model)
        ai_service._validate_request_model_if_set()


def _apply_chat_routing_context(
    ai_service: AIService,
    *,
    user_query: Optional[str],
    messages: Optional[List[Dict[str, Any]]] = None,
    use_function_calling: bool = True,
) -> None:
    needs_tools = False
    if use_function_calling and user_query:
        complexity = estimate_query_complexity(user_query, messages)
        needs_tools = complexity in ("medium", "complex")
    ai_service.set_routing_context(
        operation=AI_OPERATION_CHAT,
        user_query=user_query,
        history_messages=messages,
        needs_tools=needs_tools,
    )


def _usage_provider_and_model(ai_service: AIService) -> tuple[str, str]:
    try:
        return ai_service.get_effective_provider_type(), ai_service.get_effective_model_code()
    except ApiError:
        provider = ai_service.config.provider if ai_service.config else "openai"
        model_name = ai_service.config.model_name if ai_service.config else "gpt-4"
        return provider, model_name


def _usage_log_context(ai_service: AIService) -> Optional[Dict[str, Any]]:
    try:
        requested = ai_service.get_requested_model_code()
        resolved = ai_service.get_effective_model_code()
        if requested != resolved:
            return {"requested_model": requested, "resolved_model": resolved}
    except Exception:
        return None
    return None


def _session_needs_title(session: AIChatSession) -> bool:
    title = (session.title or "").strip()
    return not title or title == DEFAULT_CHAT_TITLE


async def _maybe_generate_session_title(
    db: Session,
    session: AIChatSession,
    ctx: AuthContext,
    business_id: Optional[int],
    message_content: str,
) -> None:
    if not _session_needs_title(session):
        return
    content = (message_content or "").strip()
    if not content:
        return
    try:
        ai_service = AIService(db, ctx, business_id or session.business_id)
        generated_title = await ai_service.generate_chat_title(content)
        if not generated_title:
            logger.warning(
                "Chat title generation returned empty for session %s",
                session.id,
            )
            return
        session.title = generated_title.strip()[:80]
    except Exception as exc:
        logger.warning(
            "Chat title generation failed for session %s: %s",
            session.id,
            exc,
        )


def _schedule_session_title_generation(
    session_id: int,
    message_content: str,
    ctx: AuthContext,
    business_id: int,
) -> None:
    """تولید عنوان گفت‌وگو در پس‌زمینه تا رویداد done مسدود نشود."""
    import asyncio

    async def _task() -> None:
        try:
            from adapters.db.session import get_db_session
            from adapters.db.repositories.ai_chat_repository import AIChatSessionRepository

            with get_db_session() as db:
                session_repo = AIChatSessionRepository(db)
                updated_session = session_repo.get_by_id(session_id)
                if not updated_session:
                    return
                if updated_session.title and updated_session.title != DEFAULT_CHAT_TITLE:
                    return
                ai_service = AIService(db, ctx, business_id)
                generated_title = await ai_service.generate_chat_title(message_content)
                if not generated_title:
                    return
                updated_session.title = generated_title[:80]
                from datetime import datetime

                updated_session.updated_at = datetime.utcnow()
                db.commit()
        except Exception as exc:
            logger.warning(
                "Background chat title generation failed for session %s: %s",
                session_id,
                exc,
            )

    asyncio.create_task(_task())


def _approval_from_result_entry(entry: Any) -> Optional[Dict[str, Any]]:
    if isinstance(entry, dict) and isinstance(entry.get("result"), dict):
        entry = entry["result"]
    if not isinstance(entry, dict):
        return None
    if entry.get("error") != "APPROVAL_REQUIRED":
        return None
    function_name = entry.get("function")
    arguments = entry.get("arguments")
    if not isinstance(function_name, str) or not isinstance(arguments, dict):
        return None
    return {"function": function_name, "arguments": arguments}


def _extract_pending_write_approvals(messages: List[AIChatMessage]) -> List[Dict[str, Any]]:
    """فقط approvalهای آخرین پاسخ assistant را معتبر می‌داند."""
    for msg in reversed(messages):
        role = msg.role if isinstance(msg.role, str) else getattr(msg.role, "value", str(msg.role))
        if role != MessageRole.ASSISTANT.value:
            continue
        raw_results = parse_json_field(msg.function_results)
        approvals: List[Dict[str, Any]] = []
        if isinstance(raw_results, dict):
            for key, value in raw_results.items():
                if str(key).startswith("_"):
                    continue
                approval = _approval_from_result_entry(value)
                if approval:
                    approvals.append(approval)
        elif isinstance(raw_results, list):
            for value in raw_results:
                approval = _approval_from_result_entry(value)
                if approval:
                    approvals.append(approval)
        return approvals
    return []


def _session_execution_mode(session: AIChatSession) -> str:
    return resolve_execution_mode(getattr(session, "execution_mode", None))


def _resolve_request_execution_mode(
    session: AIChatSession,
    request_mode: Optional[str],
) -> str:
    if request_mode and str(request_mode).strip():
        return resolve_execution_mode(request_mode)
    return _session_execution_mode(session)


def _resolve_exploration_mode(
    query_mode: Optional[str],
    body_mode: Optional[str],
    execution_mode: str,
) -> str:
    explicit = (query_mode or body_mode or "").strip().lower()
    if explicit:
        return explicit
    return exploration_mode_for_execution(execution_mode)


def _session_response_dict(session: AIChatSession) -> Dict[str, Any]:
    return {
        "id": session.id,
        "user_id": session.user_id,
        "title": session.title,
        "business_id": session.business_id,
        "execution_mode": _session_execution_mode(session),
        "created_at": session.created_at.isoformat() if session.created_at else None,
        "updated_at": session.updated_at.isoformat() if session.updated_at else None,
    }


class ChatMessageRequest(BaseModel):
    content: str
    session_id: Optional[int] = None
    approve_writes: bool = False
    mode: Optional[str] = None  # explore | auto | off
    execution_mode: Optional[str] = None  # analyzer | supervised | autonomous
    model: Optional[str] = None


class CheckAvailabilityRequest(BaseModel):
    business_id: Optional[int] = None
    estimated_tokens: int = 1000
    model: Optional[str] = None
    user_query: Optional[str] = None


class AIMemoryStructuredPatch(BaseModel):
    sales_goal_monthly: Optional[float] = None
    sales_goal_unit: Optional[str] = None
    currency_display: Optional[str] = None
    report_style: Optional[str] = None
    preferred_language: Optional[str] = None
    business_role: Optional[str] = None
    internal_terms: Optional[List[Dict[str, str]]] = None
    knowledge_hints: Optional[List[str]] = None


class AIMemoryUpdateRequest(BaseModel):
    business_id: Optional[int] = None
    content: str = ""
    structured: Optional[AIMemoryStructuredPatch] = None


class AIKnowledgeCreateRequest(BaseModel):
    business_id: Optional[int] = None
    title: str
    content: str


class ChatEditMessageRequest(BaseModel):
    content: str
    approve_writes: bool = False
    regenerate_after: bool = True
    mode: Optional[str] = None
    execution_mode: Optional[str] = None
    model: Optional[str] = None


class ChatSessionUpdateRequest(BaseModel):
    execution_mode: Optional[str] = None
    title: Optional[str] = None


class AIConnectorCreateRequest(BaseModel):
    business_id: Optional[int] = None
    name: Optional[str] = None
    title: str
    description: Optional[str] = None
    http_method: str = "GET"
    url: str
    headers: Optional[Dict[str, str]] = None
    body_template: Optional[str] = None


class MessageFeedbackRequest(BaseModel):
    rating: int
    comment: Optional[str] = None


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
    if not business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)
    ai_service = AIService(db, ctx, business_id)
    
    availability = ai_service.check_availability(
        estimated_tokens=params.estimated_tokens,
        model=params.model,
        user_query=params.user_query,
    )
    
    return success_response(availability, request)


@router.get("/insights", summary="بینش لحظه‌ای کسب‌وکار برای AI")
async def get_business_insights(
    request: Request,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_insight_service import get_business_insights as load_insights

    data = load_insights(db, int(effective_business_id), ctx)
    return success_response(data, request)


@router.get("/suggestions", summary="پیشنهادهای پویا برای شروع گفتگو")
async def get_chat_suggestions(
    request: Request,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_insight_service import get_dynamic_suggestions
    from app.services.ai.ai_memory_proactive_service import get_memory_proactive_suggestions

    bid = int(effective_business_id)
    items = get_dynamic_suggestions(db, bid, ctx)
    memory_items = get_memory_proactive_suggestions(db, bid, ctx)
    seen = {i.get("label") for i in items}
    for m in memory_items:
        if m.get("label") not in seen:
            items.insert(0, m)
            seen.add(m.get("label"))
        if len(items) >= 8:
            break
    return success_response(items[:8], request)


@router.get("/alerts", summary="هشدارهای پیشگیرانه کسب‌وکار")
async def get_proactive_alerts(
    request: Request,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_insight_service import get_proactive_alerts as load_alerts
    from app.services.ai.ai_memory_proactive_service import get_memory_enriched_alerts

    bid = int(effective_business_id)
    base_alerts = load_alerts(db, bid, ctx)
    alerts = get_memory_enriched_alerts(db, bid, ctx, base_alerts=base_alerts)
    return success_response({"alerts": alerts}, request)


@router.get("/feedback/analytics", summary="تحلیل بازخورد پیام‌های دستیار")
async def get_feedback_analytics(
    request: Request,
    business_id: Optional[int] = None,
    days: int = Query(30, ge=1, le=365),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_feedback_analytics_service import get_feedback_analytics as load_analytics

    data = load_analytics(db, business_id=int(effective_business_id), days=days)
    return success_response(data, request)


@router.get("/memory", summary="حافظه دستیار برای کسب‌وکار")
async def get_ai_memory(
    request: Request,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_memory_service import get_memory, memory_to_dict

    row = get_memory(db, int(effective_business_id), ctx.get_user_id())
    return success_response(memory_to_dict(row), request)


@router.delete("/memory", summary="پاک کردن حافظه دستیار")
async def delete_ai_memory(
    request: Request,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_memory_service import clear_memory, memory_to_dict

    clear_memory(db, int(effective_business_id), ctx.get_user_id())
    return success_response(memory_to_dict(None), request, "حافظه پاک شد")


@router.put("/memory", summary="ذخیره حافظه دستیار")
async def update_ai_memory(
    request: Request,
    params: AIMemoryUpdateRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = params.business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_memory_service import upsert_memory, memory_to_dict

    structured_patch = (
        params.structured.model_dump(exclude_none=True) if params.structured else None
    )
    row = upsert_memory(
        db,
        int(effective_business_id),
        ctx.get_user_id(),
        params.content,
        structured=structured_patch,
    )
    return success_response(memory_to_dict(row), request, "حافظه ذخیره شد")


@router.get("/memory/digest", summary="خلاصهٔ خواندنی حافظه دستیار")
async def get_ai_memory_digest(
    request: Request,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_memory_service import get_memory_digest

    digest = get_memory_digest(db, int(effective_business_id), ctx.get_user_id())
    return success_response(digest, request)


@router.get("/knowledge", summary="لیست اسناد دانشنامه کسب‌وکار")
async def list_knowledge_documents(
    request: Request,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_knowledge_service import document_to_dict, list_documents

    rows = list_documents(db, int(effective_business_id))
    return success_response([document_to_dict(r) for r in rows], request)


@router.post("/knowledge", summary="افزودن سند به دانشنامه")
async def create_knowledge_document(
    request: Request,
    params: AIKnowledgeCreateRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = params.business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_knowledge_service import create_document, document_to_dict

    try:
        row = create_document(
            db,
            int(effective_business_id),
            ctx.get_user_id(),
            params.title,
            params.content,
        )
    except ValueError as exc:
        raise ApiError("INVALID_CONTENT", str(exc), http_status=400) from exc
    return success_response(document_to_dict(row, include_content=True), request, "سند ذخیره شد")


@router.post("/knowledge/upload", summary="آپلود فایل به دانشنامه")
async def upload_knowledge_document(
    request: Request,
    business_id: Optional[int] = None,
    title: Optional[str] = Query(None),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_attachment_service import extract_text_from_bytes
    from app.services.ai.ai_knowledge_service import create_document, document_to_dict

    data = await file.read()
    filename = file.filename or "document.txt"
    text = extract_text_from_bytes(filename, data, file.content_type)
    doc_title = (title or filename).strip()[:512]
    row = create_document(
        db,
        int(effective_business_id),
        ctx.get_user_id(),
        doc_title,
        text,
        source_filename=filename,
    )
    return success_response(document_to_dict(row, include_content=True), request, "فایل به دانشنامه اضافه شد")


@router.delete("/knowledge/{document_id}", summary="حذف سند دانشنامه")
async def delete_knowledge_document(
    document_id: int = Path(...),
    request: Request = None,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_knowledge_service import delete_document

    if not delete_document(db, document_id, int(effective_business_id)):
        raise ApiError("NOT_FOUND", "سند یافت نشد", http_status=404)
    return success_response({"id": document_id}, request, "سند حذف شد")


@router.post("/knowledge/reindex", summary="بازسازی embedding دانشنامه")
async def reindex_knowledge(
    request: Request,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_embedding_service import reindex_business

    stats = reindex_business(db, int(effective_business_id))
    return success_response(stats, request, "دانشنامه بازنمایه‌سازی شد")


@router.get("/connectors", summary="لیست کانکتورهای HTTP کسب‌وکار")
async def list_connectors(
    request: Request,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_connector_service import connector_to_dict, list_connectors as list_conn

    rows = list_conn(db, int(effective_business_id))
    return success_response([connector_to_dict(r) for r in rows], request)


@router.post("/connectors", summary="افزودن کانکتور HTTP")
async def create_connector(
    request: Request,
    params: AIConnectorCreateRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = params.business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_connector_service import connector_to_dict, create_connector as create_conn

    row = create_conn(
        db,
        int(effective_business_id),
        ctx.get_user_id(),
        params.model_dump(),
    )
    return success_response(connector_to_dict(row), request, "کانکتور ایجاد شد")


@router.delete("/connectors/{connector_id}", summary="حذف کانکتور")
async def delete_connector_endpoint(
    connector_id: int = Path(...),
    request: Request = None,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    from app.services.ai.ai_connector_service import delete_connector

    if not delete_connector(db, connector_id, int(effective_business_id)):
        raise ApiError("NOT_FOUND", "کانکتور یافت نشد", http_status=404)
    return success_response({"id": connector_id}, request, "کانکتور حذف شد")


@router.post(
    "/sessions/{session_id}/messages/{message_id}/feedback",
    summary="ثبت بازخورد روی پیام",
)
async def post_message_feedback(
    session_id: int = Path(...),
    message_id: int = Path(...),
    request: Request = None,
    params: MessageFeedbackRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)

    from app.services.ai.ai_feedback_service import feedback_to_dict, upsert_feedback
    from app.services.ai.ai_memory_feedback_service import apply_feedback_to_memory

    row = upsert_feedback(
        db,
        message_id,
        ctx.get_user_id(),
        params.rating,
        params.comment,
    )
    memory_updated = apply_feedback_to_memory(
        db,
        message_id,
        ctx.get_user_id(),
        params.rating,
        params.comment,
    )
    payload = feedback_to_dict(row)
    payload["memory_updated"] = memory_updated
    return success_response(payload, request, "بازخورد ثبت شد")


@router.get("/sessions/{session_id}/attachments", summary="لیست پیوست‌های گفت‌وگو")
async def list_session_attachments(
    session_id: int = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)

    from app.services.ai.ai_attachment_service import (
        list_session_attachments as list_att,
        attachment_to_dict,
    )

    rows = list_att(db, session_id)
    return success_response([attachment_to_dict(r) for r in rows], request)


@router.post("/sessions/{session_id}/attachments", summary="آپلود پیوست متنی")
async def upload_session_attachment(
    session_id: int = Path(...),
    request: Request = None,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)

    from app.services.ai.ai_attachment_service import create_attachment, attachment_to_dict

    data = await file.read()
    row = create_attachment(
        db,
        session_id=session_id,
        user_id=ctx.get_user_id(),
        filename=file.filename or "file.txt",
        file_bytes=data,
        mime_type=file.content_type,
    )
    return success_response(attachment_to_dict(row), request, "پیوست با موفقیت اضافه شد")


@router.delete("/sessions/{session_id}/attachments/{attachment_id}", summary="حذف پیوست")
async def delete_session_attachment(
    session_id: int = Path(...),
    attachment_id: int = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)

    from app.services.ai.ai_attachment_service import delete_attachment

    if not delete_attachment(db, attachment_id, ctx.get_user_id()):
        raise ApiError("ATTACHMENT_NOT_FOUND", "پیوست یافت نشد", http_status=404)
    return success_response({"id": attachment_id}, request, "پیوست حذف شد")


@router.get("/sessions/{session_id}/messages/search", summary="جستجو در پیام‌های گفت‌وگو")
async def search_session_messages(
    session_id: int = Path(...),
    q: str = Query(..., min_length=1, max_length=200),
    limit: int = Query(30, ge=1, le=100),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)

    message_repo = AIChatMessageRepository(db)
    messages = message_repo.get_session_messages(session_id, limit=500)
    term = q.strip().lower()
    hits = []
    for msg in messages:
        if term in (msg.content or "").lower():
            hits.append({
                "id": msg.id,
                "role": msg.role,
                "content": msg.content,
                "created_at": msg.created_at.isoformat() if msg.created_at else None,
            })
            if len(hits) >= limit:
                break
    return success_response(hits, request)


@router.get("/sessions", summary="لیست گفت‌وگوها")
async def get_chat_sessions(
    request: Request,
    business_id: Optional[int] = None,
    search: Optional[str] = Query(None, description="جستجو در عنوان گفت‌وگو"),
    limit: int = 50,
    skip: int = 0,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت لیست گفت‌وگوهای کاربر"""
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)
    repo = AIChatSessionRepository(db)
    sessions = repo.get_user_sessions(
        user_id=ctx.get_user_id(),
        business_id=effective_business_id,
        limit=limit,
        skip=skip,
        search=search,
    )
    
    result = []
    for session in sessions:
        result.append(_session_response_dict(session))
    
    return success_response(result, request)


@router.post("/sessions", summary="ایجاد گفت‌وگوی جدید")
async def create_chat_session(
    request: Request,
    title: Optional[str] = Body(None, embed=True),
    business_id: Optional[int] = Body(None, embed=True),
    execution_mode: Optional[str] = Body(None, embed=True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """ایجاد گفت‌وگوی جدید"""
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)
    session = AIChatSession(
        user_id=ctx.get_user_id(),
        business_id=effective_business_id,
        title=title or DEFAULT_CHAT_TITLE,
        execution_mode=resolve_execution_mode(execution_mode),
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    
    return success_response(_session_response_dict(session), request, "جلسه چت با موفقیت ایجاد شد")


@router.patch("/sessions/{session_id}", summary="به‌روزرسانی گفت‌وگو")
async def update_chat_session(
    session_id: int = Path(...),
    request: Request = None,
    params: ChatSessionUpdateRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)
    if params.title is not None and params.title.strip():
        session.title = params.title.strip()[:255]
    if params.execution_mode is not None:
        session.execution_mode = resolve_execution_mode(params.execution_mode)
    from datetime import datetime
    session.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(session)
    return success_response(_session_response_dict(session), request, "گفت‌وگو به‌روزرسانی شد")


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
    mode: Optional[str] = Query(
        None,
        description="حالت agent: explore (تحلیل عمیق), auto (پیش‌فرض), off",
    ),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """ارسال پیام به AI و دریافت پاسخ (با یا بدون streaming)"""
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)

    execution_mode = _resolve_request_execution_mode(
        session, message_data.execution_mode
    )
    exploration_mode = _resolve_exploration_mode(
        mode, message_data.mode, execution_mode
    )
    session.execution_mode = execution_mode
    
    # دریافت پیام‌های قبلی
    message_repo = AIChatMessageRepository(db)
    previous_messages = message_repo.get_session_messages(session_id, limit=50)
    
    # ساخت messages برای AI (شامل تاریخچه tool)
    messages = build_llm_messages_from_history(previous_messages)
    messages.append({
        "role": "user",
        "content": message_data.content
    })
    approve_writes = bool(message_data.approve_writes)
    approved_write_calls = (
        _extract_pending_write_approvals(previous_messages)
        if approve_writes
        else []
    )
    
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
                message_content=message_data.content,
                approve_writes=approve_writes,
                approved_write_calls=approved_write_calls,
                exploration_mode=exploration_mode,
                execution_mode=execution_mode,
                request_model=message_data.model,
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
        _prepare_ai_service_model(new_ai_service, message_data.model)
        response = await new_ai_service.chat_completion(
            messages,
            use_function_calling=True,
            session_business_id=business_id,
            session_id=session_id,
            approve_writes=approve_writes,
            approved_write_calls=approved_write_calls,
            user_query=message_data.content,
            request_model=message_data.model,
            execution_mode=execution_mode,
        )
    
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
        _prepare_ai_service_model(commit_ai_service, message_data.model)
        _apply_chat_routing_context(
            commit_ai_service,
            user_query=message_data.content,
            messages=messages,
        )
        charge_result = commit_ai_service.check_quota_and_charge(
            input_tokens, output_tokens, model_code=commit_ai_service.get_effective_model_code()
        )
        
        fc_meta = response.get("_function_calls")
        fr_meta = response.get("_function_results")
        fc_json, fr_json = serialize_function_metadata(fc_meta, fr_meta)

        # ذخیره پاسخ AI
        assistant_message = AIChatMessage(
            session_id=session_id,
            role=MessageRole.ASSISTANT.value,
            content=response["message"]["content"] or "",
            function_calls=fc_json,
            function_results=fr_json,
            tokens_used=input_tokens + output_tokens
        )
        commit_db.add(assistant_message)
        
        # ثبت لاگ استفاده
        provider_name, model_code = _usage_provider_and_model(commit_ai_service)
        commit_ai_service.log_usage(
            provider=provider_name,
            model=model_code,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost=charge_result.get("cost", 0),
            payment_method=charge_result.get("payment_method", "free"),
            wallet_transaction_id=charge_result.get("wallet_transaction_id"),
            document_id=charge_result.get("document_id"),
            context=_usage_log_context(commit_ai_service),
        )
        commit_ai_service.clear_routing_context()
        
        # به‌روزرسانی زمان جلسه
        from datetime import datetime
        commit_session.updated_at = datetime.utcnow()

        needs_title = _session_needs_title(commit_session) and is_first_message

        if needs_title:
            await _maybe_generate_session_title(
                commit_db,
                commit_session,
                ctx,
                business_id,
                message_data.content,
            )

        commit_db.commit()
        commit_db.refresh(assistant_message)
        message_id = assistant_message.id

        if needs_title and _session_needs_title(commit_session):
            _schedule_session_title_generation(
                session_id,
                message_data.content,
                ctx,
                business_id,
            )

        from app.services.ai.ai_memory_hooks import schedule_memory_update_after_chat

        schedule_memory_update_after_chat(session_id, business_id, ctx)
    
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


def _sse_payload(data: Dict[str, Any]) -> str:
    from app.core.json_safe import json_dumps_safe

    # comment بلند برای عبور از بافر nginx/پروکسی (حدود ۲KB)
    pad = ":" + (" " * 2048) + "\n"
    return f"{pad}data: {json_dumps_safe(data)}\n\n"


def _emit_chunk_as_sse(chunk: Dict[str, Any]):
    """تبدیل chunk داخلی به payloadهای SSE (generator)."""
    from app.services.ai.ai_stream_helpers import chunk_to_sse_data

    for data in chunk_to_sse_data(chunk):
        yield _sse_payload(data)


def _extract_content_from_agent_trace(
    accumulated_content: str,
    agent_trace: Optional[List[Dict[str, Any]]],
) -> str:
    """اگر متن delta خالی بود، از narrative/answer در trace استفاده کن."""
    text = (accumulated_content or "").strip()
    if text:
        return accumulated_content
    if not agent_trace:
        return accumulated_content or ""
    for kind in ("answer", "narrative"):
        for step in reversed(agent_trace):
            if step.get("kind") != kind:
                continue
            body = (step.get("body_markdown") or "").strip()
            if body:
                return body
    return accumulated_content or ""


def _estimate_stream_usage_if_missing(
    final_usage: Optional[Dict[str, Any]],
    stream_ai_config: Any,
    messages: List[Dict[str, Any]],
    accumulated_content: str,
) -> Optional[Dict[str, Any]]:
    if final_usage:
        return final_usage
    if not stream_ai_config:
        return None

    from adapters.db.session import get_db_session
    from app.services.ai.ai_provider import create_provider
    from app.services.ai.ai_provider_service import resolve_provider_connection

    api_key = None
    api_base_url = stream_ai_config.api_base_url
    provider_type = (stream_ai_config.provider or "openai").strip().lower()
    try:
        with get_db_session() as est_db:
            _, api_key, api_base_url, _ = resolve_provider_connection(
                est_db, provider_type, legacy_config=stream_ai_config
            )
    except Exception:
        api_key = None

    if not api_key:
        return None

    provider = create_provider(
        provider_type=provider_type,
        api_key=api_key,
        api_base_url=api_base_url,
    )
    input_tokens_estimate = sum(
        provider.estimate_tokens(msg.get("content", "")) for msg in messages
    )
    output_tokens_estimate = provider.estimate_tokens(accumulated_content)
    return {
        "input_tokens": input_tokens_estimate,
        "output_tokens": output_tokens_estimate,
        "total_tokens": input_tokens_estimate + output_tokens_estimate,
    }


async def _persist_stream_assistant_message(
    *,
    session_id: int,
    ctx: AuthContext,
    business_id: int,
    messages: List[Dict[str, Any]],
    message_content: str,
    previous_messages: List[AIChatMessage],
    request_model: Optional[str],
    accumulated_content: str,
    final_usage: Optional[Dict[str, Any]],
    final_function_calls: Optional[List[Dict[str, Any]]],
    final_function_results: Optional[Dict[str, Any]],
    final_agent_trace: Optional[List[Dict[str, Any]]],
    stream_ai_config: Any = None,
) -> tuple[Optional[int], Optional[Dict[str, Any]]]:
    """ذخیره پاسخ assistant و ثبت usage. برمی‌گرداند (message_id, usage)."""
    from adapters.db.session import get_db_session
    from app.services.ai.ai_trace import merge_trace_into_function_results

    content = _extract_content_from_agent_trace(
        accumulated_content, final_agent_trace
    )
    usage = _estimate_stream_usage_if_missing(
        final_usage, stream_ai_config, messages, content
    )

    if usage:
        input_tokens = usage.get("input_tokens", 0)
        output_tokens = usage.get("output_tokens", 0)

        with get_db_session() as new_db:
            session_repo = AIChatSessionRepository(new_db)
            updated_session = session_repo.get_by_id(session_id)
            if not updated_session:
                logger.error("Session %s not found for commit", session_id)
                return None, usage

            new_ai_service = AIService(new_db, ctx, updated_session.business_id)
            _prepare_ai_service_model(new_ai_service, request_model)
            _apply_chat_routing_context(
                new_ai_service,
                user_query=message_content,
                messages=messages,
            )

            charge_result = new_ai_service.check_quota_and_charge(
                input_tokens,
                output_tokens,
                model_code=new_ai_service.get_effective_model_code(),
            )

            merged_results = merge_trace_into_function_results(
                final_function_results, final_agent_trace or []
            )
            fc_json, fr_json = serialize_function_metadata(
                final_function_calls, merged_results
            )
            assistant_message = AIChatMessage(
                session_id=session_id,
                role=MessageRole.ASSISTANT.value,
                content=content,
                function_calls=fc_json,
                function_results=fr_json,
                tokens_used=input_tokens + output_tokens,
            )
            new_db.add(assistant_message)

            provider_name, model_code = _usage_provider_and_model(new_ai_service)
            new_ai_service.log_usage(
                provider=provider_name,
                model=model_code,
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                cost=charge_result.get("cost", 0),
                payment_method=charge_result.get("payment_method", "free"),
                wallet_transaction_id=charge_result.get("wallet_transaction_id"),
                document_id=charge_result.get("document_id"),
                context=_usage_log_context(new_ai_service),
            )
            new_ai_service.clear_routing_context()

            from datetime import datetime

            updated_session.updated_at = datetime.utcnow()

            needs_title = _session_needs_title(updated_session) and len(
                previous_messages
            ) == 0

            if needs_title:
                await _maybe_generate_session_title(
                    new_db,
                    updated_session,
                    ctx,
                    updated_session.business_id or business_id,
                    message_content,
                )

            new_db.commit()
            new_db.refresh(assistant_message)
            message_id = assistant_message.id

            if needs_title and _session_needs_title(updated_session):
                _schedule_session_title_generation(
                    session_id,
                    message_content,
                    ctx,
                    updated_session.business_id or business_id,
                )

            from app.services.ai.ai_memory_hooks import schedule_memory_update_after_chat

            schedule_memory_update_after_chat(
                session_id,
                updated_session.business_id or business_id,
                ctx,
            )

        return message_id, usage

    with get_db_session() as new_db:
        session_repo = AIChatSessionRepository(new_db)
        updated_session = session_repo.get_by_id(session_id)
        if not updated_session:
            return None, None

        assistant_message = AIChatMessage(
            session_id=session_id,
            role=MessageRole.ASSISTANT.value,
            content=content or "خطا در دریافت پاسخ",
            tokens_used=0,
        )
        new_db.add(assistant_message)
        from datetime import datetime

        updated_session.updated_at = datetime.utcnow()
        new_db.commit()
        new_db.refresh(assistant_message)
        return assistant_message.id, None


def _schedule_stream_persist_after_disconnect(
    *,
    session_id: int,
    ctx: AuthContext,
    business_id: int,
    messages: List[Dict[str, Any]],
    message_content: str,
    previous_messages: List[AIChatMessage],
    request_model: Optional[str],
    accumulated_content: str,
    final_usage: Optional[Dict[str, Any]],
    final_function_calls: Optional[List[Dict[str, Any]]],
    final_function_results: Optional[Dict[str, Any]],
    final_agent_trace: Optional[List[Dict[str, Any]]],
    stream_ai_config: Any = None,
) -> None:
    """ذخیره پاسخ در پس‌زمینه وقتی کلاینت قبل از done قطع می‌کند."""
    import asyncio

    has_payload = bool(
        (accumulated_content or "").strip()
        or final_agent_trace
        or final_function_results
    )
    if not has_payload:
        return

    async def _task() -> None:
        try:
            await _persist_stream_assistant_message(
                session_id=session_id,
                ctx=ctx,
                business_id=business_id,
                messages=messages,
                message_content=message_content,
                previous_messages=previous_messages,
                request_model=request_model,
                accumulated_content=accumulated_content,
                final_usage=final_usage,
                final_function_calls=final_function_calls,
                final_function_results=final_function_results,
                final_agent_trace=final_agent_trace,
                stream_ai_config=stream_ai_config,
            )
        except Exception as exc:
            logger.warning(
                "Background persist after stream disconnect failed (session=%s): %s",
                session_id,
                exc,
            )

    try:
        asyncio.get_running_loop().create_task(_task())
    except RuntimeError:
        pass


async def _stream_message_response(
    session_id: int,
    messages: List[Dict[str, Any]],
    ctx: AuthContext,
    business_id: int,
    previous_messages: List[AIChatMessage],
    message_content: str,
    approve_writes: bool = False,
    approved_write_calls: Optional[List[Dict[str, Any]]] = None,
    exploration_mode: str = "auto",
    execution_mode: str = "analyzer",
    request_model: Optional[str] = None,
):
    """Generator برای streaming response.

    فاز ۱: ساخت system prompt در session کوتاه‌عمر.
    فاز ۲: استریم LLM در session جدا (بدون نگه‌داشتن اتصال در فاز ۱).
    فاز ۳: ذخیره پاسخ در session تازه؛ در صورت قطع کلاینت، ذخیره پس‌زمینه.
    """
    import asyncio

    from adapters.db.session import get_db_session
    from app.services.ai.ai_stream_helpers import iter_with_heartbeat
    from app.services.ai.ai_tool_keys import status_event

    accumulated_content = ""
    final_usage = None
    final_function_calls: Optional[List[Dict[str, Any]]] = None
    final_function_results: Optional[Dict[str, Any]] = None
    final_agent_trace: Optional[List[Dict[str, Any]]] = None
    stream_ai_config = None
    prebuilt_prompt: Optional[str] = None
    message_id: Optional[int] = None

    def _capture_chunk(chunk: Dict[str, Any]) -> None:
        nonlocal accumulated_content, final_usage, final_function_calls
        nonlocal final_function_results, final_agent_trace
        delta = chunk.get("delta", {})
        content_chunk = delta.get("content", "")
        if content_chunk:
            accumulated_content += content_chunk
        if chunk.get("usage"):
            final_usage = chunk["usage"]
        if chunk.get("function_calls"):
            final_function_calls = chunk["function_calls"]
        if chunk.get("function_results"):
            final_function_results = chunk["function_results"]
        if chunk.get("agent_trace"):
            final_agent_trace = chunk["agent_trace"]

    def _schedule_persist_on_disconnect() -> None:
        _schedule_stream_persist_after_disconnect(
            session_id=session_id,
            ctx=ctx,
            business_id=business_id,
            messages=messages,
            message_content=message_content,
            previous_messages=previous_messages,
            request_model=request_model,
            accumulated_content=accumulated_content,
            final_usage=final_usage,
            final_function_calls=final_function_calls,
            final_function_results=final_function_results,
            final_agent_trace=final_agent_trace,
            stream_ai_config=stream_ai_config,
        )

    try:
        yield _sse_payload({"type": "status", "phase": "connecting", "done": False})
        await asyncio.sleep(0)
        yield _sse_payload({"type": "status", "phase": "thinking", "done": False})
        await asyncio.sleep(0)

        # فاز ۱: آماده‌سازی prompt (session کوتاه)
        with get_db_session() as prep_db:
            prep_service = AIService(prep_db, ctx, business_id)
            _prepare_ai_service_model(prep_service, request_model)
            stream_ai_config = prep_service.config
            prebuilt_prompt = ""
            async for build_item in prep_service.build_system_prompt_stream(
                session_business_id=business_id,
                session_id=session_id,
                user_query=message_content,
                execution_mode=execution_mode,
            ):
                if build_item.get("event") == "prompt_ready":
                    prebuilt_prompt = build_item.get("prompt") or ""
                    continue
                if build_item.get("event") == "trace_step":
                    for payload in _emit_chunk_as_sse(build_item):
                        yield payload
                    await asyncio.sleep(0)
                    continue
                for payload in _emit_chunk_as_sse(build_item):
                    yield payload
                    await asyncio.sleep(0)

        # فاز ۲: استریم LLM (session جدا — فقط برای tool calls در صورت نیاز)
        with get_db_session() as stream_db:
            stream_ai_service = AIService(stream_db, ctx, business_id)
            _prepare_ai_service_model(stream_ai_service, request_model)

            async def _stream_factory():
                async for chunk in stream_ai_service.chat_completion_stream(
                    messages,
                    use_function_calling=True,
                    session_business_id=business_id,
                    session_id=session_id,
                    approve_writes=approve_writes,
                    approved_write_calls=approved_write_calls,
                    exploration_mode=exploration_mode,
                    execution_mode=execution_mode,
                    user_query=message_content,
                    request_model=request_model,
                    prebuilt_system_prompt=prebuilt_prompt,
                ):
                    yield chunk

            async for chunk in iter_with_heartbeat(
                _stream_factory,
                initial_status=None,
            ):
                event_type = chunk.get("event")
                if event_type == "heartbeat":
                    yield _sse_payload({
                        "type": "heartbeat",
                        "elapsed_ms": chunk.get("elapsed_ms", 0),
                        "done": False,
                    })
                    continue

                if event_type == "prompt_ready":
                    continue

                _capture_chunk(chunk)

                for payload in _emit_chunk_as_sse(chunk):
                    yield payload
                    await asyncio.sleep(0)

                if chunk.get("done", False):
                    break

        logger.info(
            "[AI Stream][session=%s] final_response_length=%s preview=%s",
            session_id,
            len(accumulated_content),
            (accumulated_content or "")[:500],
        )

        for payload in _emit_chunk_as_sse(status_event("saving")):
            yield payload

        message_id, final_usage = await _persist_stream_assistant_message(
            session_id=session_id,
            ctx=ctx,
            business_id=business_id,
            messages=messages,
            message_content=message_content,
            previous_messages=previous_messages,
            request_model=request_model,
            accumulated_content=accumulated_content,
            final_usage=final_usage,
            final_function_calls=final_function_calls,
            final_function_results=final_function_results,
            final_agent_trace=final_agent_trace,
            stream_ai_config=stream_ai_config,
        )

        yield _sse_payload({
            "content": "",
            "done": True,
            "usage": final_usage,
            "message_id": message_id,
            "function_calls": final_function_calls,
            "function_results": final_function_results,
            "agent_trace": final_agent_trace,
            **({"warning": "Usage information not available"} if not final_usage else {}),
        })

    except asyncio.CancelledError:
        _schedule_persist_on_disconnect()
        raise
    except Exception as e:
        _schedule_persist_on_disconnect()
        logger.error("Error in streaming response: %s", e, exc_info=True)
        from app.services.ai.ai_retry_policy import is_retryable_error

        recoverable = is_retryable_error(e)
        error_data = {
            "type": "error",
            "error": str(e),
            "recoverable": recoverable,
            "suggested_action": "retry" if recoverable else "dismiss",
            "done": True,
        }
        yield _sse_payload(error_data)


@router.post("/sessions/{session_id}/regenerate", summary="تولید مجدد آخرین پاسخ AI")
async def regenerate_last_response(
    session_id: int = Path(...),
    request: Request = None,
    stream: bool = Query(True, description="استفاده از streaming"),
    approve_writes: bool = Query(False),
    model: Optional[str] = Query(None, description="مدل AI"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """حذف آخرین پاسخ assistant و تولید مجدد بر اساس آخرین پیام کاربر."""
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)

    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)

    message_repo = AIChatMessageRepository(db)
    all_messages = message_repo.get_session_messages(session_id, limit=200)

    last_user_idx = -1
    for i, msg in enumerate(all_messages):
        role = msg.role if isinstance(msg.role, str) else getattr(msg.role, "value", msg.role)
        if role == MessageRole.USER.value or role == "user":
            last_user_idx = i

    if last_user_idx < 0:
        raise ApiError("NO_USER_MESSAGE", "پیام کاربری برای تولید مجدد یافت نشد", http_status=400)

    to_delete = all_messages[last_user_idx + 1 :]
    for msg in to_delete:
        db.delete(msg)
    db.commit()

    remaining = all_messages[: last_user_idx + 1]
    last_user = remaining[-1]
    messages = build_llm_messages_from_history(remaining)

    business_id = session.business_id
    approved_write_calls = _extract_pending_write_approvals(remaining) if approve_writes else []
    execution_mode = _session_execution_mode(session)
    exploration_mode = exploration_mode_for_execution(execution_mode)

    if stream:
        db.close()
        return StreamingResponse(
            _stream_message_response(
                session_id=session_id,
                messages=messages,
                ctx=ctx,
                business_id=business_id,
                previous_messages=remaining,
                message_content=last_user.content,
                approve_writes=approve_writes,
                approved_write_calls=approved_write_calls,
                exploration_mode=exploration_mode,
                execution_mode=execution_mode,
                request_model=model,
            ),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",
            },
        )

    db.close()
    from adapters.db.session import get_db_session

    with get_db_session() as new_db:
        new_ai_service = AIService(new_db, ctx, business_id)
        _prepare_ai_service_model(new_ai_service, model)
        response = await new_ai_service.chat_completion(
            messages,
            use_function_calling=True,
            session_business_id=business_id,
            session_id=session_id,
            approve_writes=approve_writes,
            approved_write_calls=approved_write_calls,
            user_query=last_user.content,
            request_model=model,
            execution_mode=execution_mode,
        )

    usage = response.get("usage", {})
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)

    with get_db_session() as commit_db:
        commit_session = AIChatSessionRepository(commit_db).get_by_id(session_id)
        if not commit_session:
            raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)
        commit_ai_service = AIService(commit_db, ctx, business_id)
        _prepare_ai_service_model(commit_ai_service, model)
        _apply_chat_routing_context(
            commit_ai_service,
            user_query=last_user.content,
            messages=messages,
        )
        charge_result = commit_ai_service.check_quota_and_charge(
            input_tokens, output_tokens, model_code=commit_ai_service.get_effective_model_code()
        )
        fc_json, fr_json = serialize_function_metadata(
            response.get("_function_calls"), response.get("_function_results")
        )
        assistant_message = AIChatMessage(
            session_id=session_id,
            role=MessageRole.ASSISTANT.value,
            content=response["message"]["content"] or "",
            function_calls=fc_json,
            function_results=fr_json,
            tokens_used=input_tokens + output_tokens,
        )
        commit_db.add(assistant_message)
        provider_name, model_code = _usage_provider_and_model(commit_ai_service)
        commit_ai_service.log_usage(
            provider=provider_name,
            model=model_code,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost=charge_result.get("cost", 0),
            payment_method=charge_result.get("payment_method", "free"),
            wallet_transaction_id=charge_result.get("wallet_transaction_id"),
            document_id=charge_result.get("document_id"),
            context=_usage_log_context(commit_ai_service),
        )
        commit_ai_service.clear_routing_context()
        from datetime import datetime
        commit_session.updated_at = datetime.utcnow()
        commit_db.commit()
        commit_db.refresh(assistant_message)

    return success_response(
        {
            "message": {
                "id": assistant_message.id,
                "content": response["message"]["content"],
                "tokens_used": input_tokens + output_tokens,
            },
            "usage": usage,
        },
        request,
    )


def _prepare_edit_or_regenerate_context(
    db: Session,
    session_id: int,
    ctx: AuthContext,
    *,
    message_id: Optional[int] = None,
    new_content: Optional[str] = None,
    regenerate_after: bool = True,
) -> tuple[AIChatSession, List[AIChatMessage], List[Dict[str, Any]], str, bool]:
    """آماده‌سازی تاریخچه پس از ویرایش پیام؛ خروجی آخر: آیا باید پاسخ جدید استریم شود."""
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)

    message_repo = AIChatMessageRepository(db)
    all_messages = message_repo.get_session_messages(session_id, limit=500)

    if message_id is not None:
        target_idx = -1
        for i, msg in enumerate(all_messages):
            if msg.id == message_id:
                target_idx = i
                break
        if target_idx < 0:
            raise ApiError("MESSAGE_NOT_FOUND", "پیام یافت نشد", http_status=404)
        target = all_messages[target_idx]
        role = target.role if isinstance(target.role, str) else getattr(target.role, "value", target.role)
        is_user = role in (MessageRole.USER.value, "user")
        is_assistant = role in (MessageRole.ASSISTANT.value, "assistant")
        if not is_user and not is_assistant:
            raise ApiError("INVALID_MESSAGE", "نقش پیام پشتیبانی نمی‌شود", http_status=400)
        if new_content is not None:
            target.content = new_content.strip()
            if not target.content:
                raise ApiError("EMPTY_MESSAGE", "متن پیام نمی‌تواند خالی باشد", http_status=400)

        if is_assistant and not regenerate_after:
            db.commit()
            llm_messages = build_llm_messages_from_history(all_messages[: target_idx + 1])
            return session, all_messages[: target_idx + 1], llm_messages, target.content, False

        if is_assistant:
            for msg in all_messages[target_idx:]:
                db.delete(msg)
            db.commit()
            remaining = all_messages[:target_idx]
        else:
            for msg in all_messages[target_idx + 1 :]:
                db.delete(msg)
            db.commit()
            remaining = all_messages[: target_idx + 1]

        user_text = ""
        for msg in reversed(remaining):
            r = msg.role if isinstance(msg.role, str) else getattr(msg.role, "value", msg.role)
            if r in (MessageRole.USER.value, "user"):
                user_text = msg.content or ""
                break
        if not user_text:
            raise ApiError("NO_USER_MESSAGE", "پیام کاربری برای ادامه یافت نشد", http_status=400)
    else:
        last_user_idx = -1
        for i, msg in enumerate(all_messages):
            role = msg.role if isinstance(msg.role, str) else getattr(msg.role, "value", msg.role)
            if role == MessageRole.USER.value or role == "user":
                last_user_idx = i
        if last_user_idx < 0:
            raise ApiError("NO_USER_MESSAGE", "پیام کاربری یافت نشد", http_status=400)
        for msg in all_messages[last_user_idx + 1 :]:
            db.delete(msg)
        db.commit()
        remaining = all_messages[: last_user_idx + 1]
        user_text = remaining[-1].content

    llm_messages = build_llm_messages_from_history(remaining)
    return session, remaining, llm_messages, user_text, True


@router.post("/sessions/{session_id}/messages/{message_id}/edit", summary="ویرایش پیام و تولید پاسخ جدید")
async def edit_user_message(
    session_id: int = Path(...),
    message_id: int = Path(...),
    request: Request = None,
    stream: bool = Query(True),
    params: ChatEditMessageRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    session, remaining, messages, user_text, should_stream = _prepare_edit_or_regenerate_context(
        db,
        session_id,
        ctx,
        message_id=message_id,
        new_content=params.content,
        regenerate_after=params.regenerate_after,
    )
    business_id = session.business_id
    approved_write_calls = (
        _extract_pending_write_approvals(remaining)
        if params.approve_writes
        else []
    )
    execution_mode = _resolve_request_execution_mode(session, params.execution_mode)
    exploration_mode = _resolve_exploration_mode(None, params.mode, execution_mode)
    session.execution_mode = execution_mode
    db.commit()

    if not should_stream:
        return success_response(
            {
                "message": {
                    "id": message_id,
                    "content": params.content,
                },
                "regenerated": False,
            },
            request,
            "پیام به‌روزرسانی شد",
        )

    if stream:
        db.close()
        return StreamingResponse(
            _stream_message_response(
                session_id=session_id,
                messages=messages,
                ctx=ctx,
                business_id=business_id,
                previous_messages=remaining,
                message_content=user_text,
                approve_writes=params.approve_writes,
                approved_write_calls=approved_write_calls,
                exploration_mode=exploration_mode,
                execution_mode=execution_mode,
                request_model=params.model,
            ),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",
            },
        )

    db.close()
    from adapters.db.session import get_db_session

    with get_db_session() as new_db:
        new_ai_service = AIService(new_db, ctx, business_id)
        _prepare_ai_service_model(new_ai_service, params.model)
        response = await new_ai_service.chat_completion(
            messages,
            use_function_calling=True,
            session_business_id=business_id,
            session_id=session_id,
            approve_writes=params.approve_writes,
            approved_write_calls=approved_write_calls,
            user_query=user_text,
            request_model=params.model,
            execution_mode=execution_mode,
        )

    usage = response.get("usage", {})
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)

    with get_db_session() as commit_db:
        commit_session = AIChatSessionRepository(commit_db).get_by_id(session_id)
        if not commit_session:
            raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)
        commit_ai_service = AIService(commit_db, ctx, business_id)
        _prepare_ai_service_model(commit_ai_service, params.model)
        _apply_chat_routing_context(
            commit_ai_service,
            user_query=user_text,
            messages=messages,
        )
        charge_result = commit_ai_service.check_quota_and_charge(
            input_tokens, output_tokens, model_code=commit_ai_service.get_effective_model_code()
        )
        fc_json, fr_json = serialize_function_metadata(
            response.get("_function_calls"), response.get("_function_results")
        )
        assistant_message = AIChatMessage(
            session_id=session_id,
            role=MessageRole.ASSISTANT.value,
            content=response["message"]["content"] or "",
            function_calls=fc_json,
            function_results=fr_json,
            tokens_used=input_tokens + output_tokens,
        )
        commit_db.add(assistant_message)
        provider_name, model_code = _usage_provider_and_model(commit_ai_service)
        commit_ai_service.log_usage(
            provider=provider_name,
            model=model_code,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost=charge_result.get("cost", 0),
            payment_method=charge_result.get("payment_method", "free"),
            wallet_transaction_id=charge_result.get("wallet_transaction_id"),
            document_id=charge_result.get("document_id"),
            context=_usage_log_context(commit_ai_service),
        )
        commit_ai_service.clear_routing_context()
        from datetime import datetime

        commit_session.updated_at = datetime.utcnow()
        commit_db.commit()
        commit_db.refresh(assistant_message)

    return success_response(
        {
            "message": {
                "id": assistant_message.id,
                "content": response["message"]["content"],
                "tokens_used": input_tokens + output_tokens,
            },
            "usage": usage,
        },
        request,
    )


@router.post("/sessions/{session_id}/fork", summary="شاخه‌سازی گفت‌وگو")
async def fork_chat_session(
    session_id: int = Path(...),
    request: Request = None,
    up_to_message_id: Optional[int] = Query(None, description="کپی تا این پیام (شامل)"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)

    message_repo = AIChatMessageRepository(db)
    all_messages = message_repo.get_session_messages(session_id, limit=500)
    to_copy = all_messages
    if up_to_message_id is not None:
        cut = -1
        for i, msg in enumerate(all_messages):
            if msg.id == up_to_message_id:
                cut = i
                break
        if cut < 0:
            raise ApiError("MESSAGE_NOT_FOUND", "پیام یافت نشد", http_status=404)
        to_copy = all_messages[: cut + 1]

    from datetime import datetime

    base_title = (session.title or DEFAULT_CHAT_TITLE)[:200]
    fork_title = f"{base_title} (شاخه)"[:255]
    new_session = AIChatSession(
        user_id=session.user_id,
        business_id=session.business_id,
        title=fork_title,
        execution_mode=_session_execution_mode(session),
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    db.add(new_session)
    db.flush()

    for msg in to_copy:
        role = msg.role if isinstance(msg.role, str) else getattr(msg.role, "value", msg.role)
        clone = AIChatMessage(
            session_id=new_session.id,
            role=role,
            content=msg.content,
            function_calls=msg.function_calls,
            function_results=msg.function_results,
            tokens_used=msg.tokens_used or 0,
            created_at=msg.created_at or datetime.utcnow(),
        )
        db.add(clone)
    db.commit()
    db.refresh(new_session)

    return success_response(
        {
            "session": {
                "id": new_session.id,
                "title": new_session.title,
                "business_id": new_session.business_id,
                "execution_mode": _session_execution_mode(new_session),
                "created_at": new_session.created_at.isoformat() if new_session.created_at else None,
            },
            "message_count": len(to_copy),
        },
        request,
        "گفت‌وگوی شاخه ایجاد شد",
    )


@router.get("/sessions/{session_id}/export", summary="خروجی Markdown گفت‌وگو")
async def export_chat_session(
    session_id: int = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    session_repo = AIChatSessionRepository(db)
    session = session_repo.get_by_id(session_id)
    if not session or session.user_id != ctx.get_user_id():
        raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)

    message_repo = AIChatMessageRepository(db)
    messages = message_repo.get_session_messages(session_id, limit=500)

    lines = [f"# {session.title or DEFAULT_CHAT_TITLE}", ""]
    for msg in messages:
        role = msg.role if isinstance(msg.role, str) else getattr(msg.role, "value", msg.role)
        label = "کاربر" if role in (MessageRole.USER.value, "user") else "دستیار"
        ts = msg.created_at.strftime("%Y-%m-%d %H:%M") if msg.created_at else ""
        header = f"## {label}"
        if ts:
            header += f" — {ts}"
        lines.extend([header, "", msg.content or "", ""])

    markdown = "\n".join(lines).strip()
    return success_response(
        {"title": session.title, "markdown": markdown, "message_count": len(messages)},
        request,
    )


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

    from app.services.ai.ai_memory_hooks import schedule_memory_update_on_session_delete

    schedule_memory_update_on_session_delete(session.business_id, ctx, session_id)
    
    db.delete(session)
    db.commit()
    
    return success_response({"id": session_id}, request, "گفت‌وگو با موفقیت حذف شد")


# ---- Scheduled Tasks ----

@router.get("/scheduled-tasks", summary="لیست task های زمان‌بندی‌شده")
async def list_scheduled_tasks(
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """لیست task های پیش‌فرض زمان‌بندی‌شده."""
    from app.services.ai.ai_scheduled_task_service import get_built_in_tasks
    tasks = get_built_in_tasks(db)
    return success_response({"tasks": tasks}, request)


@router.post("/scheduled-tasks/{task_id}/run", summary="اجرای فوری یک scheduled task")
async def run_scheduled_task_now(
    task_id: str = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """اجرای فوری یک scheduled task برای کسب‌وکار فعلی."""
    from app.services.ai.ai_scheduled_task_service import get_task_by_id, run_scheduled_task

    task = get_task_by_id(task_id, db)
    if not task:
        raise ApiError("TASK_NOT_FOUND", f"task '{task_id}' یافت نشد", http_status=404)

    business_id = ctx.business_id
    if not business_id:
        raise ApiError("BUSINESS_REQUIRED", "کسب‌وکار مشخص نشده", http_status=400)

    ai_service = AIService(db, ctx, business_id)
    result = await run_scheduled_task(db, task, business_id, ai_service)
    return success_response(result, request)


@router.get("/cache-stats", summary="آمار کش ابزار (debug)")
async def get_tool_cache_stats(
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """آمار کش نتایج tool — فقط برای ادمین."""
    if not (ctx.is_superadmin() or ctx.can_access_support_operator()):
        raise ApiError("FORBIDDEN", "دسترسی محدود", http_status=403)
    from app.services.ai.ai_tool_cache import cache_stats
    return success_response(cache_stats(), request)

