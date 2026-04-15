from __future__ import annotations

from typing import Any, Dict, List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import select, and_, func

from adapters.api.v1.schemas import QueryInfo
from app.services.sort_resolution import effective_sort_specs
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
        sort: list[Any] | None = None,
        search: str | None = None,
        filters: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        stmt = select(ProductAttribute).where(ProductAttribute.business_id == business_id)

        if search:
            stmt = stmt.where(ProductAttribute.title.ilike(f"%{search}%"))

        total = self.db.execute(select(func.count()).select_from(stmt.subquery())).scalar() or 0

        # Sorting
        _allowed = frozenset({"title", "id", "created_at"})
        try:
            qi = QueryInfo(sort_by=sort_by, sort_desc=sort_desc, sort=sort)  # type: ignore[arg-type]
            specs = effective_sort_specs(qi, allowed=_allowed, default_when_empty=None)
        except Exception:
            specs = []
        order_parts = []
        for col_name, desc in specs:
            if col_name not in _allowed:
                continue
            col = getattr(ProductAttribute, col_name)
            order_parts.append(col.desc() if desc else col.asc())
        if not order_parts:
            stmt = stmt.order_by(ProductAttribute.id.desc() if sort_desc else ProductAttribute.id.asc())
        else:
            if not specs or specs[-1][0] != "id":
                order_parts.append(ProductAttribute.id.asc())
            stmt = stmt.order_by(*order_parts)

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


