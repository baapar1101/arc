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
        commit: bool = True,
    ) -> FiscalYear:
        fiscal_year = FiscalYear(
            business_id=business_id,
            title=title,
            start_date=start_date,
            end_date=end_date,
            is_last=is_last,
        )
        self.db.add(fiscal_year)
        if commit:
            self.db.commit()
        else:
            self.db.flush()
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

    def get_by_id_for_business(self, business_id: int, fiscal_year_id: int) -> FiscalYear | None:
        from sqlalchemy import select

        stmt = select(FiscalYear).where(
            FiscalYear.business_id == business_id,
            FiscalYear.id == fiscal_year_id,
        )
        return self.db.execute(stmt).scalars().first()

    def set_current_for_business(
        self,
        business_id: int,
        fiscal_year_id: int,
        *,
        commit: bool = True,
    ) -> FiscalYear:
        """
        تعویض نرم سال مالی جاری (فقط is_last) بدون بستن حسابداری.
        برای مهاجرت تاریخچه سال‌به‌سال استفاده می‌شود.
        """
        from sqlalchemy import update

        target = self.get_by_id_for_business(business_id, fiscal_year_id)
        if target is None:
            from app.core.responses import ApiError

            raise ApiError(
                "FISCAL_YEAR_NOT_FOUND",
                "سال مالی یافت نشد یا به این کسب‌وکار تعلق ندارد",
                http_status=404,
            )

        self.db.execute(
            update(FiscalYear)
            .where(FiscalYear.business_id == business_id, FiscalYear.is_last == True)  # noqa: E712
            .values(is_last=False)
        )
        target.is_last = True
        self.db.add(target)
        if commit:
            self.db.commit()
        else:
            self.db.flush()
        self.db.refresh(target)
        return target


