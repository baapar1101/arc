from __future__ import annotations

from typing import Any, Dict, List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import select, func, and_, or_

from adapters.api.v1.schemas import QueryInfo
from app.services.sort_resolution import effective_sort_specs
from .base_repo import BaseRepository
from ..models.price_list import PriceList, PriceItem


class PriceListRepository(BaseRepository[PriceList]):
    def __init__(self, db: Session) -> None:
        super().__init__(db, PriceList)

    def search(self, *, business_id: int, take: int = 20, skip: int = 0, sort_by: str | None = None, sort_desc: bool = True, sort: List[Any] | None = None, search: str | None = None) -> dict[str, Any]:
        stmt = select(PriceList).where(PriceList.business_id == business_id)
        if search:
            stmt = stmt.where(PriceList.name.ilike(f"%{search}%"))

        total = self.db.execute(select(func.count()).select_from(stmt.subquery())).scalar() or 0
        _allowed = frozenset({"name", "created_at", "id"})
        try:
            qi = QueryInfo(sort_by=sort_by, sort_desc=sort_desc, sort=sort)  # type: ignore[arg-type]
            specs = effective_sort_specs(qi, allowed=_allowed, default_when_empty=None)
        except Exception:
            specs = []
        order_parts = []
        for col_name, desc in specs:
            if col_name not in _allowed:
                continue
            col = getattr(PriceList, col_name)
            order_parts.append(col.desc() if desc else col.asc())
        if not order_parts:
            stmt = stmt.order_by(PriceList.id.desc() if sort_desc else PriceList.id.asc())
        else:
            if not specs or specs[-1][0] != "id":
                order_parts.append(PriceList.id.asc())
            stmt = stmt.order_by(*order_parts)

        rows = list(self.db.execute(stmt.offset(skip).limit(take)).scalars().all())
        items = [self._to_dict_list(pl) for pl in rows]
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

    def create(self, **data: Any) -> PriceList:
        obj = PriceList(**data)
        self.db.add(obj)
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def update(self, id: int, **data: Any) -> Optional[PriceList]:
        obj = self.db.get(PriceList, id)
        if not obj:
            return None
        for k, v in data.items():
            if hasattr(obj, k) and v is not None:
                setattr(obj, k, v)
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def delete(self, id: int) -> bool:
        obj = self.db.get(PriceList, id)
        if not obj:
            return False
        self.db.delete(obj)
        self.db.commit()
        return True

    def _to_dict_list(self, pl: PriceList) -> dict[str, Any]:
        return {
            "id": pl.id,
            "business_id": pl.business_id,
            "name": pl.name,
            "is_active": pl.is_active,
            "created_at": pl.created_at,
            "updated_at": pl.updated_at,
        }


class PriceItemRepository(BaseRepository[PriceItem]):
    def __init__(self, db: Session) -> None:
        super().__init__(db, PriceItem)

    def list_for_price_list(self, *, price_list_id: int, take: int = 50, skip: int = 0, product_id: int | None = None, currency_id: int | None = None) -> dict[str, Any]:
        stmt = select(PriceItem).where(PriceItem.price_list_id == price_list_id)
        if product_id is not None:
            stmt = stmt.where(PriceItem.product_id == product_id)
        if currency_id is not None:
            stmt = stmt.where(PriceItem.currency_id == currency_id)
        total = self.db.execute(select(func.count()).select_from(stmt.subquery())).scalar() or 0
        rows = list(self.db.execute(stmt.offset(skip).limit(take)).scalars().all())
        items = [self._to_dict(pi) for pi in rows]
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

    def upsert(self, *, price_list_id: int, product_id: int, unit_id: int | None, currency_id: int, tier_name: str | None, min_qty, price) -> PriceItem:
        # Try find existing unique combination
        stmt = select(PriceItem).where(
            and_(
                PriceItem.price_list_id == price_list_id,
                PriceItem.product_id == product_id,
                PriceItem.unit_id.is_(unit_id) if unit_id is None else PriceItem.unit_id == unit_id,
                PriceItem.tier_name == (tier_name or 'پیش‌فرض'),
                PriceItem.min_qty == min_qty,
                PriceItem.currency_id == currency_id,
            )
        )
        existing = self.db.execute(stmt).scalars().first()
        if existing:
            existing.price = price
            existing.currency_id = currency_id
            self.db.commit()
            self.db.refresh(existing)
            return existing
        obj = PriceItem(
            price_list_id=price_list_id,
            product_id=product_id,
            unit_id=unit_id,
            currency_id=currency_id,
            tier_name=(tier_name or 'پیش‌فرض'),
            min_qty=min_qty,
            price=price,
        )
        self.db.add(obj)
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def delete(self, id: int) -> bool:
        obj = self.db.get(PriceItem, id)
        if not obj:
            return False
        self.db.delete(obj)
        self.db.commit()
        return True

    def _to_dict(self, pi: PriceItem) -> dict[str, Any]:
        return {
            "id": pi.id,
            "price_list_id": pi.price_list_id,
            "product_id": pi.product_id,
            "unit_id": pi.unit_id,
            "currency_id": pi.currency_id,
            "tier_name": pi.tier_name,
            "min_qty": pi.min_qty,
            "price": pi.price,
            "created_at": pi.created_at,
            "updated_at": pi.updated_at,
        }


