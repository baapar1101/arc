from __future__ import annotations

from typing import Optional, List
from sqlalchemy.orm import Session
from sqlalchemy import select, and_

from adapters.db.models.product_bom import ProductBOM, ProductBOMItem, ProductBOMOutput, ProductBOMOperation


class ProductBOMRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    # BOM header
    def create_bom(self, **kwargs) -> ProductBOM:
        obj = ProductBOM(**kwargs)
        self.db.add(obj)
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def get_bom(self, bom_id: int, business_id: int) -> Optional[ProductBOM]:
        obj = self.db.get(ProductBOM, bom_id)
        if not obj or obj.business_id != business_id:
            return None
        return obj

    def list_boms(self, business_id: int, product_id: Optional[int] = None) -> List[ProductBOM]:
        stmt = select(ProductBOM).where(ProductBOM.business_id == business_id)
        if product_id:
            stmt = stmt.where(ProductBOM.product_id == product_id)
        return [r[0] for r in self.db.execute(stmt.order_by(ProductBOM.id.desc())).all()]

    def update_bom(self, bom_id: int, **kwargs) -> Optional[ProductBOM]:
        obj = self.db.get(ProductBOM, bom_id)
        if not obj:
            return None
        for k, v in kwargs.items():
            if v is not None:
                setattr(obj, k, v)
        self.db.commit()
        self.db.refresh(obj)
        return obj

    def delete_bom(self, bom_id: int) -> bool:
        obj = self.db.get(ProductBOM, bom_id)
        if not obj:
            return False
        self.db.delete(obj)
        self.db.commit()
        return True

    # Items
    def replace_items(self, bom_id: int, items: List[dict], commit: bool = False) -> None:
        """جایگزین کردن اقلام مواد اولیه. commit=False برای استفاده در transaction"""
        self.db.query(ProductBOMItem).filter(ProductBOMItem.bom_id == bom_id).delete()
        for it in items:
            self.db.add(ProductBOMItem(bom_id=bom_id, **it))
        if commit:
            self.db.commit()

    def replace_outputs(self, bom_id: int, outputs: List[dict], commit: bool = False) -> None:
        """جایگزین کردن خروجی‌ها. commit=False برای استفاده در transaction"""
        self.db.query(ProductBOMOutput).filter(ProductBOMOutput.bom_id == bom_id).delete()
        for out in outputs:
            self.db.add(ProductBOMOutput(bom_id=bom_id, **out))
        if commit:
            self.db.commit()

    def replace_operations(self, bom_id: int, operations: List[dict], commit: bool = False) -> None:
        """جایگزین کردن عملیات. commit=False برای استفاده در transaction"""
        self.db.query(ProductBOMOperation).filter(ProductBOMOperation.bom_id == bom_id).delete()
        for op in operations:
            self.db.add(ProductBOMOperation(bom_id=bom_id, **op))
        if commit:
            self.db.commit()


