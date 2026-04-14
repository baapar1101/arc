from __future__ import annotations

from datetime import date
from sqlalchemy.orm import Session

from .base_repo import BaseRepository
from ..models.fiscal_year import FiscalYear


class FiscalYearRepository(BaseRepository[FiscalYear]):
    """Repository برای مدیریت سال‌های مالی"""

    def __init__(self, db: Session) -> None:
        super().__init__(db, FiscalYear)

    def create_fiscal_year(
        self,
        *,
        business_id: int,
        title: str,
        start_date: date,
        end_date: date,
        is_last: bool = True,
    ) -> FiscalYear:
        fiscal_year = FiscalYear(
            business_id=business_id,
            title=title,
            start_date=start_date,
            end_date=end_date,
            is_last=is_last,
        )
        self.db.add(fiscal_year)
        self.db.commit()
        self.db.refresh(fiscal_year)
        return fiscal_year


