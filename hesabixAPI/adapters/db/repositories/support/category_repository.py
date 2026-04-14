from __future__ import annotations

from typing import List
from sqlalchemy.orm import Session

from adapters.db.repositories.base_repo import BaseRepository
from adapters.db.models.support.category import Category


class CategoryRepository(BaseRepository[Category]):
    def __init__(self, db: Session):
        super().__init__(db, Category)
    
    def get_active_categories(self) -> List[Category]:
        """دریافت دسته‌بندی‌های فعال"""
        return self.db.query(Category)\
            .filter(Category.is_active == True)\
            .order_by(Category.name)\
            .all()
