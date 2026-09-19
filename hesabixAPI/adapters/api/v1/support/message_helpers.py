from __future__ import annotations

from typing import List

from adapters.db.repositories.support.attachment_repository import AttachmentRepository
from app.services.support.support_attachment_service import SupportAttachmentService


def serialize_message(message, attachment_repo: AttachmentRepository) -> dict:
    attachments = attachment_repo.list_for_message(message.id)
    return {
        "id": message.id,
        "ticket_id": message.ticket_id,
        "sender_id": message.sender_id,
        "sender_type": message.sender_type,
        "content": message.content,
        "is_internal": message.is_internal,
        "created_at": message.created_at,
        "sender": {
            "id": message.sender.id,
            "first_name": message.sender.first_name,
            "last_name": message.sender.last_name,
            "email": message.sender.email,
        } if message.sender else None,
        "attachments": [SupportAttachmentService.to_dict(a) for a in attachments],
    }


def serialize_messages(messages: List, attachment_repo: AttachmentRepository) -> List[dict]:
    return [serialize_message(m, attachment_repo) for m in messages]
