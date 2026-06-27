from __future__ import annotations

from typing import List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.support.response_template import SupportResponseTemplate
from adapters.db.repositories.base_repo import BaseRepository


class ResponseTemplateRepository(BaseRepository[SupportResponseTemplate]):
    def __init__(self, db: Session):
        super().__init__(db, SupportResponseTemplate)

    def list_active(self) -> List[SupportResponseTemplate]:
        return (
            self.db.query(SupportResponseTemplate)
            .filter(SupportResponseTemplate.is_active.is_(True))
            .order_by(SupportResponseTemplate.name.asc())
            .all()
        )

    def get_by_id(self, template_id: int) -> Optional[SupportResponseTemplate]:
        return self.db.query(SupportResponseTemplate).filter(SupportResponseTemplate.id == template_id).first()

    def create(self, data: dict) -> SupportResponseTemplate:
        row = SupportResponseTemplate(**data)
        self.db.add(row)
        self.db.commit()
        self.db.refresh(row)
        return row

    def update(self, template: SupportResponseTemplate, data: dict) -> SupportResponseTemplate:
        for key, value in data.items():
            setattr(template, key, value)
        self.db.commit()
        self.db.refresh(template)
        return template

    def soft_delete(self, template: SupportResponseTemplate) -> SupportResponseTemplate:
        template.is_active = False
        self.db.commit()
        self.db.refresh(template)
        return template

    def increment_usage(self, template_id: int) -> None:
        template = self.get_by_id(template_id)
        if template:
            template.usage_count = (template.usage_count or 0) + 1
            self.db.commit()
