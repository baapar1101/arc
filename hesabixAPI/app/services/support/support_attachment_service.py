from __future__ import annotations

import mimetypes
from typing import List, Optional
from uuid import UUID

from fastapi import UploadFile
from sqlalchemy.orm import Session

from adapters.db.repositories.support.attachment_repository import AttachmentRepository
from app.core.responses import ApiError
from app.services.file_storage_service import FileStorageService
from app.services.support.ticket_access_service import TicketAccessService

MAX_SUPPORT_ATTACHMENT_BYTES = 10 * 1024 * 1024
MAX_ATTACHMENTS_PER_MESSAGE = 5

ALLOWED_MIME_TYPES = {
    "image/jpeg",
    "image/png",
    "image/gif",
    "image/webp",
    "application/pdf",
    "text/plain",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
}


def _validate_mime(filename: str, mime_type: Optional[str]) -> str:
    resolved = (mime_type or mimetypes.guess_type(filename)[0] or "application/octet-stream").lower()
    if resolved not in ALLOWED_MIME_TYPES and not resolved.startswith("image/"):
        raise ApiError(
            "UNSUPPORTED_FILE_TYPE",
            "نوع فایل پشتیبانی نمی‌شود",
            http_status=400,
        )
    return resolved


class SupportAttachmentService:
    def __init__(self, db: Session):
        self.db = db
        self.repo = AttachmentRepository(db)
        self.access = TicketAccessService(db)
        self.storage = FileStorageService(db)

    async def upload_for_user(self, ticket_id: int, user_id: int, file: UploadFile):
        self.access.get_user_ticket(ticket_id, user_id)
        return await self._upload(ticket_id, user_id, file)

    async def upload_for_operator(self, ticket_id: int, operator_id: int, file: UploadFile):
        self.access.get_operator_ticket(ticket_id)
        return await self._upload(ticket_id, operator_id, file)

    async def _upload(self, ticket_id: int, user_id: int, file: UploadFile):
        filename = file.filename or "attachment"
        mime_type = _validate_mime(filename, file.content_type)

        saved = await self.storage.upload_file(
            file=file,
            user_id=user_id,
            module_context="support",
            context_id=str(ticket_id),
            check_storage_limit=False,
            is_temporary=False,
        )

        file_size = int(saved.get("file_size") or 0)
        if file_size > MAX_SUPPORT_ATTACHMENT_BYTES:
            raise ApiError(
                "FILE_TOO_LARGE",
                "حداکثر حجم هر پیوست ۱۰ مگابایت است",
                http_status=400,
            )

        attachment = self.repo.create(
            {
                "ticket_id": ticket_id,
                "file_storage_id": str(saved["file_id"]),
                "original_name": filename,
                "mime_type": mime_type,
                "size_bytes": file_size,
                "uploaded_by": user_id,
            }
        )
        self.db.commit()
        self.db.refresh(attachment)
        return attachment

    def list_for_ticket_user(self, ticket_id: int, user_id: int):
        self.access.get_user_ticket(ticket_id, user_id)
        return self.repo.list_for_ticket(ticket_id)

    def list_for_ticket_operator(self, ticket_id: int):
        self.access.get_operator_ticket(ticket_id)
        return self.repo.list_for_ticket(ticket_id)

    def attach_to_message(self, ticket_id: int, message_id: int, attachment_ids: List[int]) -> None:
        if not attachment_ids:
            return
        if len(attachment_ids) > MAX_ATTACHMENTS_PER_MESSAGE:
            raise ApiError(
                "TOO_MANY_ATTACHMENTS",
                f"حداکثر {MAX_ATTACHMENTS_PER_MESSAGE} پیوست در هر پیام",
                http_status=400,
            )
        count = self.repo.count_unlinked_for_ticket(ticket_id, attachment_ids)
        if count != len(attachment_ids):
            raise ApiError("INVALID_ATTACHMENTS", "برخی پیوست‌ها معتبر نیستند", http_status=400)
        self.repo.link_to_message(attachment_ids, ticket_id, message_id)
        self.db.commit()

    def get_download_for_user(self, attachment_id: int, user_id: int):
        attachment = self.repo.get_by_id(attachment_id)
        if not attachment:
            raise ApiError("ATTACHMENT_NOT_FOUND", "پیوست یافت نشد", http_status=404)
        self.access.get_user_ticket(attachment.ticket_id, user_id)
        return attachment, self.storage

    def get_download_for_operator(self, attachment_id: int):
        attachment = self.repo.get_by_id(attachment_id)
        if not attachment:
            raise ApiError("ATTACHMENT_NOT_FOUND", "پیوست یافت نشد", http_status=404)
        self.access.get_operator_ticket(attachment.ticket_id)
        return attachment, self.storage

    @staticmethod
    def to_dict(attachment) -> dict:
        return {
            "id": attachment.id,
            "ticket_id": attachment.ticket_id,
            "message_id": attachment.message_id,
            "file_storage_id": attachment.file_storage_id,
            "original_name": attachment.original_name,
            "mime_type": attachment.mime_type,
            "size_bytes": attachment.size_bytes,
            "uploaded_by": attachment.uploaded_by,
            "created_at": attachment.created_at,
        }
