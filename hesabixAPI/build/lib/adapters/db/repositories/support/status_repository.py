from __future__ import annotations

from typing import List
from sqlalchemy.orm import Session

from adapters.db.repositories.base_repo import BaseRepository
from adapters.db.models.support.status import Status


class StatusRepository(BaseRepository[Status]):
    def __init__(self, db: Session):
        super().__init__(db, Status)
    
    def get_all_statuses(self) -> List[Status]:
        """دریافت تمام وضعیت‌ها"""
        return self.db.query(Status)\
            .order_by(Status.name)\
            .all()
    
    def get_final_statuses(self) -> List[Status]:
        """دریافت وضعیت‌های نهایی"""
        return self.db.query(Status)\
            .filter(Status.is_final == True)\
            .order_by(Status.name)\
            .all()
