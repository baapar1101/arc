from __future__ import annotations

from typing import List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import select, and_

from .base_repo import BaseRepository
from ..models.business import Business, BusinessType, BusinessField


class BusinessRepository(BaseRepository[Business]):
    """Repository برای مدیریت کسب و کارها"""
    
    def __init__(self, db: Session) -> None:
        super().__init__(db, Business)
    
    def get_by_owner_id(self, owner_id: int) -> List[Business]:
        """دریافت تمام کسب و کارهای یک مالک"""
        stmt = select(Business).where(Business.owner_id == owner_id)
        return list(self.db.execute(stmt).scalars().all())
    
    def get_by_business_type(self, business_type: BusinessType) -> List[Business]:
        """دریافت کسب و کارها بر اساس نوع"""
        stmt = select(Business).where(Business.business_type == business_type)
        return list(self.db.execute(stmt).scalars().all())
    
    def get_by_business_field(self, business_field: BusinessField) -> List[Business]:
        """دریافت کسب و کارها بر اساس زمینه فعالیت"""
        stmt = select(Business).where(Business.business_field == business_field)
        return list(self.db.execute(stmt).scalars().all())
    
    def get_by_owner_and_type(self, owner_id: int, business_type: BusinessType) -> List[Business]:
        """دریافت کسب و کارهای یک مالک بر اساس نوع"""
        stmt = select(Business).where(
            and_(
                Business.owner_id == owner_id,
                Business.business_type == business_type
            )
        )
        return list(self.db.execute(stmt).scalars().all())
    
    def search_by_name(self, name: str) -> List[Business]:
        """جستجوی کسب و کارها بر اساس نام (case-insensitive)"""
        stmt = select(Business).where(Business.name.ilike(f"%{name}%"))
        return list(self.db.execute(stmt).scalars().all())
    
    def create_business(
        self, 
        name: str, 
        business_type: BusinessType, 
        business_field: BusinessField, 
        owner_id: int,
        default_currency_id: int | None = None,
        address: str | None = None,
        phone: str | None = None,
        mobile: str | None = None,
        national_id: str | None = None,
        registration_number: str | None = None,
        economic_id: str | None = None,
        country: str | None = None,
        province: str | None = None,
        city: str | None = None,
        postal_code: str | None = None
        ) -> Business:
        """ایجاد کسب و کار جدید"""
        business = Business(
            name=name,
            business_type=business_type,
            business_field=business_field,
            owner_id=owner_id,
            default_currency_id=default_currency_id,
            address=address,
            phone=phone,
            mobile=mobile,
            national_id=national_id,
            registration_number=registration_number,
            economic_id=economic_id,
            country=country,
            province=province,
            city=city,
            postal_code=postal_code
        )
        self.db.add(business)
        self.db.commit()
        self.db.refresh(business)
        return business
    
    def get_by_national_id(self, national_id: str) -> Business | None:
        """دریافت کسب و کار بر اساس شناسه ملی"""
        stmt = select(Business).where(Business.national_id == national_id)
        return self.db.execute(stmt).scalars().first()
    
    def get_by_registration_number(self, registration_number: str) -> Business | None:
        """دریافت کسب و کار بر اساس شماره ثبت"""
        stmt = select(Business).where(Business.registration_number == registration_number)
        return self.db.execute(stmt).scalars().first()
    
    def get_by_economic_id(self, economic_id: str) -> Business | None:
        """دریافت کسب و کار بر اساس شناسه اقتصادی"""
        stmt = select(Business).where(Business.economic_id == economic_id)
        return self.db.execute(stmt).scalars().first()
    
    def search_by_phone(self, phone: str) -> List[Business]:
        """جستجوی کسب و کارها بر اساس شماره تلفن"""
        stmt = select(Business).where(
            (Business.phone == phone) | (Business.mobile == phone)
        )
        return list(self.db.execute(stmt).scalars().all())
    
    def get_by_country(self, country: str) -> List[Business]:
        """دریافت کسب و کارها بر اساس کشور"""
        stmt = select(Business).where(Business.country == country)
        return list(self.db.execute(stmt).scalars().all())
    
    def get_by_province(self, province: str) -> List[Business]:
        """دریافت کسب و کارها بر اساس استان"""
        stmt = select(Business).where(Business.province == province)
        return list(self.db.execute(stmt).scalars().all())
    
    def get_by_city(self, city: str) -> List[Business]:
        """دریافت کسب و کارها بر اساس شهرستان"""
        stmt = select(Business).where(Business.city == city)
        return list(self.db.execute(stmt).scalars().all())
    
    def get_by_postal_code(self, postal_code: str) -> List[Business]:
        """دریافت کسب و کارها بر اساس کد پستی"""
        stmt = select(Business).where(Business.postal_code == postal_code)
        return list(self.db.execute(stmt).scalars().all())
    
    def get_by_location(self, country: str | None = None, province: str | None = None, city: str | None = None) -> List[Business]:
        """دریافت کسب و کارها بر اساس موقعیت جغرافیایی"""
        stmt = select(Business)
        conditions = []
        
        if country:
            conditions.append(Business.country == country)
        if province:
            conditions.append(Business.province == province)
        if city:
            conditions.append(Business.city == city)
        
        if conditions:
            stmt = stmt.where(and_(*conditions))
        
        return list(self.db.execute(stmt).scalars().all())
