from __future__ import annotations

from typing import Any, Dict, Optional
from sqlalchemy.orm import Session
from sqlalchemy import select, and_, or_, func

from .base_repo import BaseRepository
from ..models.product import Product


class ProductRepository(BaseRepository[Product]):
    def __init__(self, db: Session) -> None:
        super().__init__(db, Product)

    def search(self, *, business_id: int, take: int = 20, skip: int = 0, sort_by: str | None = None, sort_desc: bool = True, search: str | None = None, filters: dict[str, Any] | None = None) -> dict[str, Any]:
        stmt = select(Product).where(Product.business_id == business_id)

        if search:
            like = f"%{search}%"
            stmt = stmt.where(
                or_(
                    Product.name.ilike(like),
                    Product.code.ilike(like),
                    Product.description.ilike(like),
                )
            )

        # Apply filters (supports minimal set used by clients)
        if filters:
            for f in filters:
                # Support both dict and pydantic-like objects
                if isinstance(f, dict):
                    field = f.get("property")
                    operator = f.get("operator")
                    value = f.get("value")
                else:
                    field = getattr(f, "property", None)
                    operator = getattr(f, "operator", None)
                    value = getattr(f, "value", None)

                if not field or not operator:
                    continue

                # Code filters
                if field == "code":
                    if operator == "=":
                        stmt = stmt.where(Product.code == value)
                    elif operator == "in" and isinstance(value, (list, tuple)):
                        stmt = stmt.where(Product.code.in_(list(value)))
                    continue

                # Name contains
                if field == "name":
                    if operator in {"contains", "ilike"} and isinstance(value, str):
                        stmt = stmt.where(Product.name.ilike(f"%{value}%"))
                    elif operator == "=":
                        stmt = stmt.where(Product.name == value)
                    continue

        total = self.db.execute(select(func.count()).select_from(stmt.subquery())).scalar() or 0

        # Sorting
        if sort_by in {"name", "code", "created_at"}:
            col = getattr(Product, sort_by)
            stmt = stmt.order_by(col.desc() if sort_desc else col.asc())
        else:
            stmt = stmt.order_by(Product.id.desc() if sort_desc else Product.id.asc())

        stmt = stmt.offset(skip).limit(take)
        rows = list(self.db.execute(stmt).scalars().all())

        def _to_dict(p: Product) -> dict[str, Any]:
            return {
                "id": p.id,
                "business_id": p.business_id,
                "item_type": p.item_type.value if hasattr(p.item_type, 'value') else str(p.item_type),
                "code": p.code,
                "name": p.name,
                "description": p.description,
                "category_id": p.category_id,
                "main_unit_id": p.main_unit_id,
                "secondary_unit_id": p.secondary_unit_id,
                "unit_conversion_factor": p.unit_conversion_factor,
                "base_sales_price": p.base_sales_price,
                "base_sales_note": p.base_sales_note,
                "base_purchase_price": p.base_purchase_price,
                "base_purchase_note": p.base_purchase_note,
                "track_inventory": p.track_inventory,
                "reorder_point": p.reorder_point,
                "min_order_qty": p.min_order_qty,
                "lead_time_days": p.lead_time_days,
                "is_sales_taxable": p.is_sales_taxable,
                "is_purchase_taxable": p.is_purchase_taxable,
                "sales_tax_rate": p.sales_tax_rate,
                "purchase_tax_rate": p.purchase_tax_rate,
                "tax_type_id": p.tax_type_id,
                "tax_code": p.tax_code,
                "tax_unit_id": p.tax_unit_id,
                "created_at": p.created_at,
                "updated_at": p.updated_at,
            }

        items = [_to_dict(r) for r in rows]

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

    def create(self, **data: Any) -> Product:
        obj = Product(**data)
        self.db.add(obj)
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def update(self, product_id: int, **data: Any) -> Optional[Product]:
        obj = self.db.get(Product, product_id)
        if not obj:
            return None
        for k, v in data.items():
            if hasattr(obj, k) and v is not None:
                setattr(obj, k, v)
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def delete(self, product_id: int) -> bool:
        obj = self.db.get(Product, product_id)
        if not obj:
            return False
        self.db.delete(obj)
        self.db.commit()
        return True


