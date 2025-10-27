from __future__ import annotations

from typing import Optional, List
from sqlalchemy.orm import Session
from sqlalchemy import select, and_

from adapters.db.models.warehouse import Warehouse


class WarehouseRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def create(self, **kwargs) -> Warehouse:
        obj = Warehouse(**kwargs)
        self.db.add(obj)
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def get(self, warehouse_id: int) -> Optional[Warehouse]:
        return self.db.get(Warehouse, warehouse_id)

    def list(self, business_id: int) -> List[Warehouse]:
        stmt = select(Warehouse).where(Warehouse.business_id == business_id).order_by(Warehouse.id.desc())
        return [r[0] for r in self.db.execute(stmt).all()]

    def update(self, warehouse_id: int, **kwargs) -> Optional[Warehouse]:
        obj = self.db.get(Warehouse, warehouse_id)
        if not obj:
            return None
        for k, v in kwargs.items():
            if v is not None:
                setattr(obj, k, v)
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def delete(self, warehouse_id: int) -> bool:
        obj = self.db.get(Warehouse, warehouse_id)
        if not obj:
            return False
        self.db.delete(obj)
        self.db.commit()
        return True


