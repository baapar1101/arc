from __future__ import annotations

from typing import List, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import select, and_, or_

from .base_repo import BaseRepository
from ..models.category import BusinessCategory


class CategoryRepository(BaseRepository[BusinessCategory]):
    def __init__(self, db: Session):
        super().__init__(db, BusinessCategory)

    def get_tree(self, business_id: int, type_: str | None = None) -> list[Dict[str, Any]]:
        stmt = select(BusinessCategory).where(BusinessCategory.business_id == business_id)
        # درخت سراسری: نوع نادیده گرفته می‌شود (همه رکوردها)
        stmt = stmt.order_by(BusinessCategory.sort_order.asc(), BusinessCategory.id.asc())
        rows = list(self.db.execute(stmt).scalars().all())
        flat = [
            {
                "id": r.id,
                "parent_id": r.parent_id,
                "translations": r.title_translations or {},
                # برچسب واحد بر اساس زبان پیش‌فرض: ابتدا fa سپس en
                "title": (r.title_translations or {}).get("fa")
                         or (r.title_translations or {}).get("en")
                         or "",
            }
            for r in rows
        ]
        return self._build_tree(flat)

    def _build_tree(self, nodes: list[Dict[str, Any]]) -> list[Dict[str, Any]]:
        by_id: dict[int, Dict[str, Any]] = {}
        roots: list[Dict[str, Any]] = []
        for n in nodes:
            item = {
                "id": n["id"],
                "parent_id": n.get("parent_id"),
                "title": n.get("title", ""),
                "translations": n.get("translations", {}),
                "children": [],
            }
            by_id[item["id"]] = item
        for item in list(by_id.values()):
            pid = item.get("parent_id")
            if pid and pid in by_id:
                by_id[pid]["children"].append(item)
            else:
                roots.append(item)
        return roots

    def create_category(self, *, business_id: int, parent_id: int | None, translations: dict[str, str]) -> BusinessCategory:
        obj = BusinessCategory(
            business_id=business_id,
            parent_id=parent_id,
            title_translations=translations or {},
        )
        self.db.add(obj)
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def update_category(self, *, category_id: int, translations: dict[str, str] | None = None) -> BusinessCategory | None:
        obj = self.db.get(BusinessCategory, category_id)
        if not obj:
            return None
        if translations:
            obj.title_translations = {**(obj.title_translations or {}), **translations}
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def move_category(self, *, category_id: int, new_parent_id: int | None) -> BusinessCategory | None:
        obj = self.db.get(BusinessCategory, category_id)
        if not obj:
            return None
        obj.parent_id = new_parent_id
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def delete_category(self, *, category_id: int) -> bool:
        obj = self.db.get(BusinessCategory, category_id)
        if not obj:
            return False
        self.db.delete(obj)
        self.db.commit()
        return True


