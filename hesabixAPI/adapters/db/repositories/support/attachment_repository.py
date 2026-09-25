from __future__ import annotations

from typing import List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.support.attachment import SupportAttachment
from adapters.db.repositories.base_repo import BaseRepository


class AttachmentRepository(BaseRepository[SupportAttachment]):
    def __init__(self, db: Session):
        super().__init__(db, SupportAttachment)

    def create(self, data: dict) -> SupportAttachment:
        row = SupportAttachment(**data)
        self.db.add(row)
        self.db.flush()
        return row

    def get_by_id(self, attachment_id: int) -> Optional[SupportAttachment]:
        return self.db.query(SupportAttachment).filter(SupportAttachment.id == attachment_id).first()

    def list_for_ticket(self, ticket_id: int) -> List[SupportAttachment]:
        return (
            self.db.query(SupportAttachment)
            .filter(SupportAttachment.ticket_id == ticket_id)
            .order_by(SupportAttachment.created_at.asc())
            .all()
        )

    def list_for_message(self, message_id: int) -> List[SupportAttachment]:
        return (
            self.db.query(SupportAttachment)
            .filter(SupportAttachment.message_id == message_id)
            .order_by(SupportAttachment.created_at.asc())
            .all()
        )

    def link_to_message(self, attachment_ids: List[int], ticket_id: int, message_id: int) -> int:
        updated = (
            self.db.query(SupportAttachment)
            .filter(
                SupportAttachment.id.in_(attachment_ids),
                SupportAttachment.ticket_id == ticket_id,
                SupportAttachment.message_id.is_(None),
            )
            .update({SupportAttachment.message_id: message_id}, synchronize_session=False)
        )
        self.db.flush()
        return updated

    def count_unlinked_for_ticket(self, ticket_id: int, attachment_ids: List[int]) -> int:
        return (
            self.db.query(SupportAttachment)
            .filter(
                SupportAttachment.id.in_(attachment_ids),
                SupportAttachment.ticket_id == ticket_id,
                SupportAttachment.message_id.is_(None),
            )
            .count()
        )
