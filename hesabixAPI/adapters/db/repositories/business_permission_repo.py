from __future__ import annotations

from typing import Optional

from sqlalchemy import select, and_, text
from sqlalchemy.orm import Session

from adapters.db.models.business_permission import BusinessPermission
from adapters.db.repositories.base_repo import BaseRepository


class BusinessPermissionRepository(BaseRepository[BusinessPermission]):
    def __init__(self, db: Session) -> None:
        super().__init__(db, BusinessPermission)

    def get_by_user_and_business(self, user_id: int, business_id: int) -> Optional[BusinessPermission]:
        """دریافت دسترسی‌های کاربر برای کسب و کار خاص"""
        stmt = select(BusinessPermission).where(
            and_(
                BusinessPermission.user_id == user_id,
                BusinessPermission.business_id == business_id
            )
        )
        return self.db.execute(stmt).scalars().first()

    def create_or_update(self, user_id: int, business_id: int, permissions: dict) -> BusinessPermission:
        """ایجاد یا به‌روزرسانی دسترسی‌های کاربر برای کسب و کار"""
        existing = self.get_by_user_and_business(user_id, business_id)
        
        if existing:
            # Preserve existing permissions and enforce join=True
            existing_permissions = existing.business_permissions or {}

            # Always ignore incoming 'join' field from clients
            incoming_permissions = dict(permissions or {})
            if 'join' in incoming_permissions:
                incoming_permissions.pop('join', None)

            # Merge and enforce join flag
            merged_permissions = dict(existing_permissions)
            merged_permissions.update(incoming_permissions)
            merged_permissions['join'] = True

            existing.business_permissions = merged_permissions
            self.db.commit()
            self.db.refresh(existing)
            return existing
        else:
            # On creation, ensure join=True exists by default
            base_permissions = {'join': True}
            incoming_permissions = dict(permissions or {})
            if 'join' in incoming_permissions:
                incoming_permissions.pop('join', None)

            new_permission = BusinessPermission(
                user_id=user_id,
                business_id=business_id,
                business_permissions={**base_permissions, **incoming_permissions}
            )
            self.db.add(new_permission)
            self.db.commit()
            self.db.refresh(new_permission)
            return new_permission

    def delete_by_user_and_business(self, user_id: int, business_id: int) -> bool:
        """حذف دسترسی‌های کاربر برای کسب و کار"""
        existing = self.get_by_user_and_business(user_id, business_id)
        if existing:
            self.db.delete(existing)
            self.db.commit()
            return True
        return False

    def get_user_businesses(self, user_id: int) -> list[BusinessPermission]:
        """دریافت تمام کسب و کارهایی که کاربر دسترسی دارد"""
        stmt = select(BusinessPermission).where(BusinessPermission.user_id == user_id)
        return self.db.execute(stmt).scalars().all()

    def get_business_users(self, business_id: int) -> list[BusinessPermission]:
        """دریافت تمام کاربرانی که دسترسی به کسب و کار دارند"""
        stmt = select(BusinessPermission).where(BusinessPermission.business_id == business_id)
        return self.db.execute(stmt).scalars().all()
    
    def get_user_member_businesses(self, user_id: int) -> list[BusinessPermission]:
        """دریافت تمام کسب و کارهایی که کاربر عضو آن‌ها است (دسترسی join)"""
        # ابتدا تمام دسترسی‌های کاربر را دریافت می‌کنیم
        all_permissions = self.get_user_businesses(user_id)
        
        # سپس فیلتر می‌کنیم
        member_permissions = []
        for perm in all_permissions:
            if perm.business_permissions and perm.business_permissions.get('join') == True:
                member_permissions.append(perm)
        
        return member_permissions