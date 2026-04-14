from __future__ import annotations

from typing import Optional, List
from datetime import datetime
from sqlalchemy import select, and_, or_, func
from sqlalchemy.orm import Session

from adapters.db.models.warranty import (
    WarrantySetting,
    WarrantyCode,
    WarrantyActivation,
    WarrantyTracking,
    WarrantyTrackingLink,
)
from adapters.db.repositories.base_repo import BaseRepository


class WarrantySettingRepository(BaseRepository[WarrantySetting]):
    def __init__(self, db: Session) -> None:
        super().__init__(db, WarrantySetting)

    def get_by_business(self, business_id: int) -> Optional[WarrantySetting]:
        """دریافت تنظیمات گارانتی برای کسب و کار"""
        stmt = select(WarrantySetting).where(
            WarrantySetting.business_id == business_id
        )
        return self.db.execute(stmt).scalars().first()

    def create_or_update(self, business_id: int, settings_data: dict) -> WarrantySetting:
        """ایجاد یا به‌روزرسانی تنظیمات گارانتی"""
        existing = self.get_by_business(business_id)
        
        if existing:
            for key, value in settings_data.items():
                if hasattr(existing, key):
                    setattr(existing, key, value)
            existing.updated_at = datetime.utcnow()
            self.db.flush()
            return existing
        else:
            new_settings = WarrantySetting(
                business_id=business_id,
                **settings_data
            )
            self.db.add(new_settings)
            self.db.flush()
            return new_settings


class WarrantyCodeRepository(BaseRepository[WarrantyCode]):
    def __init__(self, db: Session) -> None:
        super().__init__(db, WarrantyCode)

    def get_by_code(self, code: str, business_id: Optional[int] = None) -> Optional[WarrantyCode]:
        """دریافت کد گارانتی بر اساس کد (و business_id در صورت وجود)"""
        if business_id:
            stmt = select(WarrantyCode).where(
                and_(
                    WarrantyCode.business_id == business_id,
                    WarrantyCode.code == code
                )
            )
        else:
            # Backward compatibility: جستجو بدون business_id
            stmt = select(WarrantyCode).where(WarrantyCode.code == code)
        return self.db.execute(stmt).scalars().first()

    def get_by_serial(self, business_id: int, warranty_serial: str) -> Optional[WarrantyCode]:
        """دریافت کد گارانتی بر اساس سریال"""
        stmt = select(WarrantyCode).where(
            and_(
                WarrantyCode.business_id == business_id,
                WarrantyCode.warranty_serial == warranty_serial
            )
        )
        return self.db.execute(stmt).scalars().first()

    def get_by_tracking_link_code(self, link_code: str) -> Optional[WarrantyCode]:
        """دریافت کد گارانتی بر اساس کد لینک رهگیری"""
        stmt = select(WarrantyCode).where(WarrantyCode.tracking_link_code == link_code)
        return self.db.execute(stmt).scalars().first()

    def list_by_business(
        self,
        business_id: int,
        status: Optional[str] = None,
        product_id: Optional[int] = None,
        limit: int = 100,
        skip: int = 0
    ) -> List[WarrantyCode]:
        """لیست کدهای گارانتی کسب و کار"""
        stmt = select(WarrantyCode).where(WarrantyCode.business_id == business_id)
        
        if status:
            stmt = stmt.where(WarrantyCode.status == status)
        if product_id:
            stmt = stmt.where(WarrantyCode.product_id == product_id)
        
        stmt = stmt.order_by(WarrantyCode.created_at.desc()).limit(limit).offset(skip)
        return list(self.db.execute(stmt).scalars().all())

    def count_by_business(
        self,
        business_id: int,
        status: Optional[str] = None,
        product_id: Optional[int] = None
    ) -> int:
        """شمارش کدهای گارانتی کسب و کار"""
        stmt = select(func.count(WarrantyCode.id)).where(
            WarrantyCode.business_id == business_id
        )
        
        if status:
            stmt = stmt.where(WarrantyCode.status == status)
        if product_id:
            stmt = stmt.where(WarrantyCode.product_id == product_id)
        
        return self.db.execute(stmt).scalar() or 0

    def check_code_exists(self, code: str, business_id: Optional[int] = None) -> bool:
        """بررسی وجود کد (در سطح کسب‌وکار یا سیستم)"""
        if business_id:
            stmt = select(func.count(WarrantyCode.id)).where(
                and_(
                    WarrantyCode.business_id == business_id,
                    WarrantyCode.code == code
                )
            )
        else:
            stmt = select(func.count(WarrantyCode.id)).where(WarrantyCode.code == code)
        count = self.db.execute(stmt).scalar() or 0
        return count > 0

    def check_serial_exists(self, business_id: int, warranty_serial: str) -> bool:
        """بررسی وجود سریال در کسب و کار"""
        stmt = select(func.count(WarrantyCode.id)).where(
            and_(
                WarrantyCode.business_id == business_id,
                WarrantyCode.warranty_serial == warranty_serial
            )
        )
        count = self.db.execute(stmt).scalar() or 0
        return count > 0

    def list_by_person(
        self,
        business_id: int,
        person_id: int,
        status: Optional[str] = None,
        limit: int = 100,
        skip: int = 0
    ) -> List[WarrantyCode]:
        """لیست کدهای گارانتی یک Person"""
        stmt = select(WarrantyCode).where(
            and_(
                WarrantyCode.business_id == business_id,
                WarrantyCode.activated_by_person_id == person_id
            )
        )
        
        if status:
            stmt = stmt.where(WarrantyCode.status == status)
        
        stmt = stmt.order_by(WarrantyCode.created_at.desc()).limit(limit).offset(skip)
        return list(self.db.execute(stmt).scalars().all())

    def count_by_person(
        self,
        business_id: int,
        person_id: int,
        status: Optional[str] = None
    ) -> int:
        """شمارش کدهای گارانتی یک Person"""
        stmt = select(func.count(WarrantyCode.id)).where(
            and_(
                WarrantyCode.business_id == business_id,
                WarrantyCode.activated_by_person_id == person_id
            )
        )
        
        if status:
            stmt = stmt.where(WarrantyCode.status == status)
        
        return self.db.execute(stmt).scalar() or 0


class WarrantyActivationRepository(BaseRepository[WarrantyActivation]):
    def __init__(self, db: Session) -> None:
        super().__init__(db, WarrantyActivation)

    def get_by_warranty_code(self, warranty_code_id: int) -> Optional[WarrantyActivation]:
        """دریافت فعال‌سازی بر اساس کد گارانتی"""
        stmt = select(WarrantyActivation).where(
            WarrantyActivation.warranty_code_id == warranty_code_id
        ).order_by(WarrantyActivation.created_at.desc())
        return self.db.execute(stmt).scalars().first()

    def list_by_person(self, person_id: int) -> List[WarrantyActivation]:
        """لیست فعال‌سازی‌های یک Person"""
        stmt = select(WarrantyActivation).where(
            WarrantyActivation.person_id == person_id
        ).order_by(WarrantyActivation.created_at.desc())
        return list(self.db.execute(stmt).scalars().all())


class WarrantyTrackingRepository(BaseRepository[WarrantyTracking]):
    def __init__(self, db: Session) -> None:
        super().__init__(db, WarrantyTracking)

    def list_by_warranty_code(
        self,
        warranty_code_id: int,
        limit: int = 100
    ) -> List[WarrantyTracking]:
        """لیست رویدادهای رهگیری یک کد گارانتی"""
        stmt = select(WarrantyTracking).where(
            WarrantyTracking.warranty_code_id == warranty_code_id
        ).order_by(WarrantyTracking.created_at.desc()).limit(limit)
        return list(self.db.execute(stmt).scalars().all())

    def list_by_person(
        self,
        person_id: int,
        limit: int = 100
    ) -> List[WarrantyTracking]:
        """لیست رویدادهای رهگیری یک Person"""
        stmt = select(WarrantyTracking).where(
            WarrantyTracking.person_id == person_id
        ).order_by(WarrantyTracking.created_at.desc()).limit(limit)
        return list(self.db.execute(stmt).scalars().all())


class WarrantyTrackingLinkRepository(BaseRepository[WarrantyTrackingLink]):
    def __init__(self, db: Session) -> None:
        super().__init__(db, WarrantyTrackingLink)

    def get_by_link_code(self, link_code: str) -> Optional[WarrantyTrackingLink]:
        """دریافت لینک بر اساس کد"""
        stmt = select(WarrantyTrackingLink).where(
            and_(
                WarrantyTrackingLink.link_code == link_code,
                WarrantyTrackingLink.is_active == True
            )
        )
        return self.db.execute(stmt).scalars().first()

    def list_by_person(self, person_id: int) -> List[WarrantyTrackingLink]:
        """لیست لینک‌های رهگیری یک Person"""
        stmt = select(WarrantyTrackingLink).where(
            WarrantyTrackingLink.person_id == person_id
        ).order_by(WarrantyTrackingLink.created_at.desc())
        return list(self.db.execute(stmt).scalars().all())

    def list_by_warranty_code(self, warranty_code_id: int) -> List[WarrantyTrackingLink]:
        """لیست لینک‌های رهگیری یک کد گارانتی"""
        stmt = select(WarrantyTrackingLink).where(
            WarrantyTrackingLink.warranty_code_id == warranty_code_id
        ).order_by(WarrantyTrackingLink.created_at.desc())
        return list(self.db.execute(stmt).scalars().all())

    def check_link_code_exists(self, link_code: str) -> bool:
        """بررسی وجود کد لینک"""
        stmt = select(func.count(WarrantyTrackingLink.id)).where(
            WarrantyTrackingLink.link_code == link_code
        )
        count = self.db.execute(stmt).scalar() or 0
        return count > 0

    def increment_access_count(self, link_id: int) -> None:
        """افزایش تعداد دسترسی به لینک"""
        link = self.get_by_id(link_id)
        if link:
            link.access_count += 1
            link.last_accessed_at = datetime.utcnow()
            self.db.flush()

