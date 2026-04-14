from __future__ import annotations

from typing import Dict, Any, List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import select, and_, func

from .base_repo import BaseRepository
from ..models.product_attribute import ProductAttribute


class ProductAttributeRepository(BaseRepository[ProductAttribute]):
    def __init__(self, db: Session):
        super().__init__(db, ProductAttribute)

    def search(
        self,
        *,
        business_id: int,
        take: int = 20,
        skip: int = 0,
        sort_by: str | None = None,
        sort_desc: bool = True,
        search: str | None = None,
        filters: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        stmt = select(ProductAttribute).where(ProductAttribute.business_id == business_id)

        if search:
            stmt = stmt.where(ProductAttribute.title.ilike(f"%{search}%"))

        total = self.db.execute(select(func.count()).select_from(stmt.subquery())).scalar() or 0

        # Sorting
        if sort_by == 'title':
            order_col = ProductAttribute.title.desc() if sort_desc else ProductAttribute.title.asc()
            stmt = stmt.order_by(order_col)
        else:
            order_col = ProductAttribute.id.desc() if sort_desc else ProductAttribute.id.asc()
            stmt = stmt.order_by(order_col)

        # Paging
        stmt = stmt.offset(skip).limit(take)
        rows = list(self.db.execute(stmt).scalars().all())

        items: list[dict[str, Any]] = [
            {
                "id": r.id,
                "business_id": r.business_id,
                "title": r.title,
                "description": r.description,
                "data_type": r.data_type if hasattr(r, 'data_type') else 'text',
                "options": r.options if hasattr(r, 'options') else None,
                "created_at": r.created_at,
                "updated_at": r.updated_at,
            }
            for r in rows
        ]

        return {
            "items": items,
            "pagination": {
                "total": total,
                "page": (skip // take) + 1 if take else 1,
                "per_page": take,
                "total_pages": (total + take - 1) // take if take else 1,
                "has_next": skip + take < total,
                "has_prev": skip > 0,
            },
        }

    def create(self, *, business_id: int, title: str, description: str | None, 
               data_type: str = 'text', options: dict | None = None) -> ProductAttribute:
        obj = ProductAttribute(
            business_id=business_id, 
            title=title, 
            description=description,
            data_type=data_type,
            options=options
        )
        self.db.add(obj)
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def update(self, *, attribute_id: int, title: str | None, description: str | None,
               data_type: str | None = None, options: dict | None = None) -> Optional[ProductAttribute]:
        obj = self.db.get(ProductAttribute, attribute_id)
        if not obj:
            return None
        if title is not None:
            obj.title = title
        if description is not None:
            obj.description = description
        if data_type is not None:
            obj.data_type = data_type
        if options is not None:
            obj.options = options
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def delete(self, *, attribute_id: int) -> bool:
        obj = self.db.get(ProductAttribute, attribute_id)
        if not obj:
            return False
        self.db.delete(obj)
        self.db.commit()
        return True


