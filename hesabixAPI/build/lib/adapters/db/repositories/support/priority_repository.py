from __future__ import annotations

from typing import List
from sqlalchemy.orm import Session

from adapters.db.repositories.base_repo import BaseRepository
from adapters.db.models.support.priority import Priority


class PriorityRepository(BaseRepository[Priority]):
    def __init__(self, db: Session):
        super().__init__(db, Priority)
    
    def get_priorities_ordered(self) -> List[Priority]:
        """دریافت اولویت‌ها به ترتیب"""
        return self.db.query(Priority)\
            .order_by(Priority.order, Priority.name)\
            .all()
