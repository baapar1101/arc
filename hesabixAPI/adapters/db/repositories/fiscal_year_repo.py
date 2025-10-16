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

    def list_by_business(self, business_id: int) -> list[FiscalYear]:
        """لیست سال‌های مالی یک کسب‌وکار بر اساس business_id"""
        from sqlalchemy import select

        stmt = select(FiscalYear).where(FiscalYear.business_id == business_id).order_by(FiscalYear.start_date.desc())
        return list(self.db.execute(stmt).scalars().all())

    def get_current_for_business(self, business_id: int) -> FiscalYear | None:
        """دریافت سال مالی جاری یک کسب و کار (بر اساس is_last)"""
        from sqlalchemy import select

        stmt = select(FiscalYear).where(FiscalYear.business_id == business_id, FiscalYear.is_last == True)  # noqa: E712
        return self.db.execute(stmt).scalars().first()


