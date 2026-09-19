from uuid import UUID

from fastapi import APIRouter, Depends, File, Request, UploadFile
from fastapi.responses import Response
from sqlalchemy.orm import Session

from adapters.api.v1.support.dependencies import require_end_user_support_open
from adapters.api.v1.schemas import SuccessResponse
from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.services.support.support_attachment_service import SupportAttachmentService

router = APIRouter()


@router.post("/{ticket_id}/attachments", response_model=SuccessResponse)
async def upload_ticket_attachment(
    request: Request,
    ticket_id: int,
    file: UploadFile = File(...),
    _require_support: None = Depends(require_end_user_support_open),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    service = SupportAttachmentService(db)
    attachment = await service.upload_for_user(ticket_id, current_user.get_user_id(), file)
    data = format_datetime_fields(SupportAttachmentService.to_dict(attachment), request)
    return success_response(data, request)


@router.get("/{ticket_id}/attachments", response_model=SuccessResponse)
async def list_ticket_attachments(
    request: Request,
    ticket_id: int,
    _require_support: None = Depends(require_end_user_support_open),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    service = SupportAttachmentService(db)
    attachments = service.list_for_ticket_user(ticket_id, current_user.get_user_id())
    items = [SupportAttachmentService.to_dict(a) for a in attachments]
    return success_response(format_datetime_fields(items, request), request)


@router.get("/attachments/{attachment_id}/download")
async def download_ticket_attachment(
    attachment_id: int,
    _require_support: None = Depends(require_end_user_support_open),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    service = SupportAttachmentService(db)
    attachment, storage = service.get_download_for_user(attachment_id, current_user.get_user_id())
    file_data = await storage.download_file(UUID(attachment.file_storage_id))
    return Response(
        content=file_data["content"],
        media_type=file_data["mime_type"],
        headers={"Content-Disposition": f'attachment; filename="{attachment.original_name}"'},
    )
