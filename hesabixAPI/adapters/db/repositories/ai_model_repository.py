from __future__ import annotations

from typing import List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_model import AIModel
from adapters.db.repositories.base_repo import BaseRepository


class AIModelRepository(BaseRepository[AIModel]):
    def __init__(self, db: Session):
        super().__init__(db, AIModel)

    def get_by_code(self, code: str) -> Optional[AIModel]:
        return (
            self.db.query(self.model_class)
            .filter(self.model_class.code == code)
            .first()
        )

    def get_active_models(self) -> List[AIModel]:
        return (
            self.db.query(self.model_class)
            .filter(self.model_class.is_active == True)  # noqa: E712
            .order_by(self.model_class.sort_order.asc(), self.model_class.id.asc())
            .all()
        )

    def get_by_codes(self, codes: List[str], *, only_active: bool = True) -> List[AIModel]:
        if not codes:
            return []
        query = self.db.query(self.model_class).filter(self.model_class.code.in_(codes))
        if only_active:
            query = query.filter(self.model_class.is_active == True)  # noqa: E712
        models = query.all()
        order = {code: idx for idx, code in enumerate(codes)}
        models.sort(key=lambda m: order.get(m.code, 9999))
        return models
