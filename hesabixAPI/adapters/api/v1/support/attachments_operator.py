from uuid import UUID

from fastapi import APIRouter, Depends, File, Request, UploadFile
from fastapi.responses import Response
from sqlalchemy.orm import Session

from adapters.api.v1.schemas import SuccessResponse
from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_app_permission
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.services.support.support_attachment_service import SupportAttachmentService
from adapters.api.v1.support.schemas import (
    ResponseTemplateCreateRequest,
    ResponseTemplateUpdateRequest,
)
from adapters.db.repositories.support.response_template_repository import ResponseTemplateRepository

router = APIRouter()


@router.post("/tickets/{ticket_id}/attachments", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def upload_operator_ticket_attachment(
    request: Request,
    ticket_id: int,
    file: UploadFile = File(...),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    service = SupportAttachmentService(db)
    attachment = await service.upload_for_operator(ticket_id, current_user.get_user_id(), file)
    data = format_datetime_fields(SupportAttachmentService.to_dict(attachment), request)
    return success_response(data, request)


@router.get("/tickets/{ticket_id}/attachments", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def list_operator_ticket_attachments(
    request: Request,
    ticket_id: int,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    service = SupportAttachmentService(db)
    attachments = service.list_for_ticket_operator(ticket_id)
    items = [SupportAttachmentService.to_dict(a) for a in attachments]
    return success_response(format_datetime_fields(items, request), request)


@router.get("/attachments/{attachment_id}/download")
@require_app_permission("support_operator")
async def download_operator_ticket_attachment(
    attachment_id: int,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    service = SupportAttachmentService(db)
    attachment, storage = service.get_download_for_operator(attachment_id)
    file_data = await storage.download_file(UUID(attachment.file_storage_id))
    return Response(
        content=file_data["content"],
        media_type=file_data["mime_type"],
        headers={"Content-Disposition": f'attachment; filename="{attachment.original_name}"'},
    )


@router.get("/templates", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def list_response_templates(
    request: Request,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    repo = ResponseTemplateRepository(db)
    templates = repo.list_active()
    if not templates:
        repo.create(
            {
                "name": "سلام و تشکر",
                "content": "سلام {user_name}،\n\nبا تشکر از تماس شما. تیم پشتیبانی در حال بررسی درخواست شماست.\n\nبا احترام",
                "created_by": current_user.get_user_id(),
                "is_global": True,
                "is_active": True,
            }
        )
        templates = repo.list_active()
    items = [
        {
            "id": t.id,
            "name": t.name,
            "content": t.content,
            "category_id": t.category_id,
            "is_global": t.is_global,
            "created_by": t.created_by,
            "is_active": t.is_active,
            "usage_count": t.usage_count,
            "created_at": t.created_at,
            "updated_at": t.updated_at,
        }
        for t in templates
    ]
    return success_response(format_datetime_fields(items, request), request)


@router.post("/templates", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def create_response_template(
    request: Request,
    body: ResponseTemplateCreateRequest,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    repo = ResponseTemplateRepository(db)
    row = repo.create(
        {
            "name": body.name,
            "content": body.content,
            "category_id": body.category_id,
            "is_global": body.is_global,
            "created_by": current_user.get_user_id(),
            "is_active": True,
        }
    )
    data = {
        "id": row.id,
        "name": row.name,
        "content": row.content,
        "category_id": row.category_id,
        "is_global": row.is_global,
        "created_by": row.created_by,
        "is_active": row.is_active,
        "usage_count": row.usage_count,
        "created_at": row.created_at,
        "updated_at": row.updated_at,
    }
    return success_response(format_datetime_fields(data, request), request)


@router.put("/templates/{template_id}", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def update_response_template(
    request: Request,
    template_id: int,
    body: ResponseTemplateUpdateRequest,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    repo = ResponseTemplateRepository(db)
    row = repo.get_by_id(template_id)
    if not row:
        raise ApiError("TEMPLATE_NOT_FOUND", "قالب یافت نشد", http_status=404)
    updates = {k: v for k, v in body.dict(exclude_unset=True).items() if v is not None}
    row = repo.update(row, updates)
    data = {
        "id": row.id,
        "name": row.name,
        "content": row.content,
        "category_id": row.category_id,
        "is_global": row.is_global,
        "created_by": row.created_by,
        "is_active": row.is_active,
        "usage_count": row.usage_count,
        "created_at": row.created_at,
        "updated_at": row.updated_at,
    }
    return success_response(format_datetime_fields(data, request), request)


@router.delete("/templates/{template_id}", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def delete_response_template(
    request: Request,
    template_id: int,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    repo = ResponseTemplateRepository(db)
    row = repo.get_by_id(template_id)
    if not row:
        raise ApiError("TEMPLATE_NOT_FOUND", "قالب یافت نشد", http_status=404)
    repo.soft_delete(row)
    return success_response({"id": template_id, "deleted": True}, request)
