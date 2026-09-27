"""Task attachment service backed by Hesabix FileStorage."""

from __future__ import annotations

from uuid import UUID

from fastapi import UploadFile
from sqlalchemy.orm import Session

from adapters.db.models.task_management import Task, TaskActivity, TaskAttachment
from adapters.db.repositories.task_repository import TaskRepository
from app.core.responses import ApiError
from app.services.file_storage_service import FileStorageService

MAX_ATTACHMENTS_PER_TASK = 50


class TaskAttachmentService:
    def __init__(self, db: Session):
        self.db = db
        self.storage = FileStorageService(db)

    def _task(self, business_id: int, task_id: int) -> Task:
        task = TaskRepository(self.db).get_by_id(task_id, business_id)
        if not task:
            raise ApiError("TASK_NOT_FOUND", "Task not found", http_status=404)
        return task

    def _attachment(
        self,
        business_id: int,
        task_id: int,
        attachment_id: int,
    ) -> TaskAttachment:
        self._task(business_id, task_id)
        row = self.db.query(TaskAttachment).filter(
            TaskAttachment.id == attachment_id,
            TaskAttachment.business_id == business_id,
            TaskAttachment.task_id == task_id,
        ).first()
        if not row:
            raise ApiError(
                "TASK_ATTACHMENT_NOT_FOUND",
                "Task attachment not found",
                http_status=404,
            )
        return row

    async def upload(
        self,
        *,
        business_id: int,
        task_id: int,
        user_id: int,
        file: UploadFile,
    ) -> TaskAttachment:
        task = self._task(business_id, task_id)
        count = self.db.query(TaskAttachment.id).filter(
            TaskAttachment.business_id == business_id,
            TaskAttachment.task_id == task.id,
        ).count()
        if count >= MAX_ATTACHMENTS_PER_TASK:
            raise ApiError(
                "TASK_ATTACHMENT_LIMIT",
                f"Maximum {MAX_ATTACHMENTS_PER_TASK} attachments per task",
                http_status=400,
            )

        saved = await self.storage.upload_file(
            file=file,
            user_id=user_id,
            module_context="tasks",
            context_id=str(task.id),
            developer_data={
                "entity": "task",
                "task_id": task.id,
                "business_id": business_id,
            },
            is_temporary=False,
            business_id=business_id,
            check_storage_limit=True,
        )
        file_id = str(saved["file_id"])
        attachment = TaskAttachment(
            business_id=business_id,
            task_id=task.id,
            file_storage_id=file_id,
            storage_key=file_id,
            original_name=str(saved.get("original_name") or file.filename or "attachment"),
            mime_type=str(saved.get("mime_type") or file.content_type or "application/octet-stream"),
            size_bytes=int(saved.get("file_size") or 0),
            uploaded_by_user_id=user_id,
        )
        self.db.add(attachment)
        self.db.flush()
        self.db.add(TaskActivity(
            business_id=business_id,
            task_id=task.id,
            actor_user_id=user_id,
            event_type="attachment_added",
            event_data={
                "attachment_id": attachment.id,
                "file_storage_id": file_id,
                "original_name": attachment.original_name,
            },
        ))
        self.db.commit()
        self.db.refresh(attachment)
        return attachment

    def list(self, business_id: int, task_id: int) -> list[TaskAttachment]:
        self._task(business_id, task_id)
        return self.db.query(TaskAttachment).filter(
            TaskAttachment.business_id == business_id,
            TaskAttachment.task_id == task_id,
        ).order_by(
            TaskAttachment.created_at.asc(),
            TaskAttachment.id.asc(),
        ).all()

    async def download(
        self,
        business_id: int,
        task_id: int,
        attachment_id: int,
    ) -> dict:
        row = self._attachment(business_id, task_id, attachment_id)
        if not row.file_storage_id:
            raise ApiError(
                "TASK_ATTACHMENT_FILE_MISSING",
                "Attachment storage file is unavailable",
                http_status=404,
            )
        return await self.storage.download_file(UUID(row.file_storage_id))

    async def delete(
        self,
        *,
        business_id: int,
        task_id: int,
        attachment_id: int,
        actor_user_id: int,
    ) -> None:
        row = self._attachment(business_id, task_id, attachment_id)
        file_id = row.file_storage_id
        task = row.task

        self.db.add(TaskActivity(
            business_id=business_id,
            task_id=task_id,
            actor_user_id=actor_user_id,
            event_type="attachment_removed",
            event_data={
                "attachment_id": row.id,
                "file_storage_id": file_id,
                "original_name": row.original_name,
            },
        ))
        self.db.delete(row)
        self.db.commit()

        if file_id:
            await self.storage.delete_file(UUID(file_id))

    @staticmethod
    def to_dict(row: TaskAttachment) -> dict:
        uploader = row.uploaded_by
        uploader_name = None
        if uploader is not None:
            uploader_name = (
                f"{uploader.first_name or ''} {uploader.last_name or ''}".strip()
                or uploader.email
                or uploader.mobile
            )
        return {
            "id": row.id,
            "task_id": row.task_id,
            "file_storage_id": row.file_storage_id,
            "original_name": row.original_name,
            "mime_type": row.mime_type,
            "size_bytes": int(row.size_bytes or 0),
            "uploaded_by_user_id": row.uploaded_by_user_id,
            "uploaded_by_name": uploader_name,
            "created_at": row.created_at,
        }
