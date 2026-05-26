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
    serialize_function_metadata,
)
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
    approve_writes: bool = False


class CheckAvailabilityRequest(BaseModel):
    business_id: Optional[int] = None
    estimated_tokens: int = 1000


class AIMemoryUpdateRequest(BaseModel):
    business_id: Optional[int] = None
    content: str = ""


class AIKnowledgeCreateRequest(BaseModel):
    business_id: Optional[int] = None
    title: str
    content: str


class ChatEditMessageRequest(BaseModel):
    content: str
    approve_writes: bool = False
    regenerate_after: bool = True


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
        estimated_tokens=params.estimated_tokens
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

    items = get_dynamic_suggestions(db, int(effective_business_id), ctx)
    return success_response(items, request)


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

    alerts = load_alerts(db, int(effective_business_id), ctx)
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

    row = upsert_memory(db, int(effective_business_id), ctx.get_user_id(), params.content)
    return success_response(memory_to_dict(row), request, "حافظه ذخیره شد")


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
    return success_response(connector_to_dict(row, include_secrets=True), request, "کانکتور ایجاد شد")


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

    row = upsert_feedback(
        db,
        message_id,
        ctx.get_user_id(),
        params.rating,
        params.comment,
    )
    return success_response(feedback_to_dict(row), request, "بازخورد ثبت شد")


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
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)
    session = AIChatSession(
        user_id=ctx.get_user_id(),
        business_id=effective_business_id,
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
    
    # ساخت messages برای AI (شامل تاریخچه tool)
    messages = build_llm_messages_from_history(previous_messages)
    messages.append({
        "role": "user",
        "content": message_data.content
    })
    approve_writes = bool(message_data.approve_writes)
    
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
        response = await new_ai_service.chat_completion(
            messages,
            use_function_calling=True,
            session_business_id=business_id,
            session_id=session_id,
            approve_writes=approve_writes,
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
        charge_result = commit_ai_service.check_quota_and_charge(input_tokens, output_tokens)
        
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


async def _stream_message_response(
    session_id: int,
    messages: List[Dict[str, Any]],
    ctx: AuthContext,
    business_id: int,
    previous_messages: List[AIChatMessage],
    message_content: str,
    approve_writes: bool = False,
):
    """Generator برای streaming response
    
    ⚠️ مهم: از session جدید برای هر عملیات استفاده می‌کنیم تا از connection leak جلوگیری کنیم.
    Session فقط برای commit نهایی استفاده می‌شود و بلافاصله بسته می‌شود.
    """
    import asyncio

    from adapters.db.session import get_db_session
    from app.services.ai.ai_stream_helpers import iter_with_heartbeat
    from app.services.ai.ai_tool_keys import status_event

    try:
        # بلافاصله به کلاینت سیگنال بده (قبل از کارهای سنگین DB)
        yield _sse_payload({"type": "status", "phase": "connecting", "done": False})
        await asyncio.sleep(0)

        accumulated_content = ""
        final_usage = None
        final_function_calls: Optional[List[Dict[str, Any]]] = None
        final_function_results: Optional[Dict[str, Any]] = None
        final_agent_trace: Optional[List[Dict[str, Any]]] = None
        stream_ai_config = None

        with get_db_session() as temp_db:
            temp_ai_service = AIService(temp_db, ctx, business_id)
            stream_ai_config = temp_ai_service.config

            async def _stream_factory():
                async for chunk in temp_ai_service.chat_completion_stream(
                    messages,
                    use_function_calling=True,
                    session_business_id=business_id,
                    session_id=session_id,
                    approve_writes=approve_writes,
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

                for payload in _emit_chunk_as_sse(chunk):
                    yield payload
                    await asyncio.sleep(0)

                if chunk.get("done", False):
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
        for payload in _emit_chunk_as_sse(status_event("saving")):
            yield payload

        # اگر usage موجود نبود، از provider تخمین بزن
        if not final_usage:
            # تخمین tokens از accumulated_content
            from app.services.ai.ai_provider import create_provider
            from app.services.ai.encryption import decrypt_api_key
            
            if stream_ai_config:
                api_key = (
                    decrypt_api_key(stream_ai_config.api_key)
                    if stream_ai_config.api_key
                    else None
                )
                if api_key:
                    provider = create_provider(
                        provider_type=stream_ai_config.provider,
                        api_key=api_key,
                        api_base_url=stream_ai_config.api_base_url,
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
                    yield _sse_payload({"error": "Session not found", "done": True})
                    return
                
                new_ai_service = AIService(new_db, ctx, updated_session.business_id)
                
                charge_result = new_ai_service.check_quota_and_charge(input_tokens, output_tokens)
                
                from app.services.ai.ai_trace import merge_trace_into_function_results

                merged_results = merge_trace_into_function_results(
                    final_function_results, final_agent_trace or []
                )
                fc_json, fr_json = serialize_function_metadata(
                    final_function_calls, merged_results
                )
                assistant_message = AIChatMessage(
                    session_id=session_id,
                    role=MessageRole.ASSISTANT.value,
                    content=accumulated_content,
                    function_calls=fc_json,
                    function_results=fr_json,
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
            
            yield _sse_payload({
                "content": "",
                "done": True,
                "usage": final_usage,
                "message_id": message_id,
                "function_calls": final_function_calls,
                "function_results": final_function_results,
                "agent_trace": final_agent_trace,
            })
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
            yield _sse_payload({
                "content": "",
                "done": True,
                "usage": None,
                "message_id": message_id,
                "warning": "Usage information not available",
            })
            
    except Exception as e:
        # ارسال خطا به صورت SSE
        import traceback
        logger.error(f"Error in streaming response: {e}", exc_info=True)
        error_data = {
            "error": str(e),
            "done": True
        }
        yield _sse_payload(error_data)


@router.post("/sessions/{session_id}/regenerate", summary="تولید مجدد آخرین پاسخ AI")
async def regenerate_last_response(
    session_id: int = Path(...),
    request: Request = None,
    stream: bool = Query(True, description="استفاده از streaming"),
    approve_writes: bool = Query(False),
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
        response = await new_ai_service.chat_completion(
            messages,
            use_function_calling=True,
            session_business_id=business_id,
            session_id=session_id,
            approve_writes=approve_writes,
        )

    usage = response.get("usage", {})
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)

    with get_db_session() as commit_db:
        commit_session = AIChatSessionRepository(commit_db).get_by_id(session_id)
        if not commit_session:
            raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)
        commit_ai_service = AIService(commit_db, ctx, business_id)
        charge_result = commit_ai_service.check_quota_and_charge(input_tokens, output_tokens)
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
        commit_ai_service.log_usage(
            provider=commit_ai_service.config.provider if commit_ai_service.config else "openai",
            model=commit_ai_service.config.model_name if commit_ai_service.config else "gpt-4",
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost=charge_result.get("cost", 0),
            payment_method=charge_result.get("payment_method", "free"),
            wallet_transaction_id=charge_result.get("wallet_transaction_id"),
            document_id=charge_result.get("document_id"),
        )
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
        response = await new_ai_service.chat_completion(
            messages,
            use_function_calling=True,
            session_business_id=business_id,
            session_id=session_id,
            approve_writes=params.approve_writes,
            user_query=user_text,
        )

    usage = response.get("usage", {})
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)

    with get_db_session() as commit_db:
        commit_session = AIChatSessionRepository(commit_db).get_by_id(session_id)
        if not commit_session:
            raise ApiError("SESSION_NOT_FOUND", "گفت‌وگو یافت نشد", http_status=404)
        commit_ai_service = AIService(commit_db, ctx, business_id)
        charge_result = commit_ai_service.check_quota_and_charge(input_tokens, output_tokens)
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
        commit_ai_service.log_usage(
            provider=commit_ai_service.config.provider if commit_ai_service.config else "openai",
            model=commit_ai_service.config.model_name if commit_ai_service.config else "gpt-4",
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost=charge_result.get("cost", 0),
            payment_method=charge_result.get("payment_method", "free"),
            wallet_transaction_id=charge_result.get("wallet_transaction_id"),
            document_id=charge_result.get("document_id"),
        )
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
    
    db.delete(session)
    db.commit()
    
    return success_response({"id": session_id}, request, "گفت‌وگو با موفقیت حذف شد")

