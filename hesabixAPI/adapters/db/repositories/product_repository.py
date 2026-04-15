from __future__ import annotations

from typing import Any, Dict, List, Optional
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import select, and_, or_, func, text
from app.core.query_timeout import query_timeout

from adapters.api.v1.schemas import QueryInfo
from app.services.sort_resolution import effective_sort_specs
from .base_repo import BaseRepository
from ..models.product import Product
from ..models.product_attribute_link import ProductAttributeLink
from ..models.category import BusinessCategory


class ProductRepository(BaseRepository[Product]):
    def __init__(self, db: Session) -> None:
        super().__init__(db, Product)

    def search(self, *, business_id: int, take: int = 20, skip: int = 0, sort_by: str | None = None, sort_desc: bool = True, sort: list[Any] | None = None, search: str | None = None, filters: dict[str, Any] | None = None, category_ids: List[int] | None = None, include_inventory: bool = False, inventory_as_of_date: str | None = None) -> dict[str, Any]:
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

                # Category ID filter (supports "in" operator for multi-select)
                if field == "category_id":
                    if operator == "in" and isinstance(value, (list, tuple)):
                        # Convert string IDs to integers with error handling
                        category_ids = []
                        for v in value:
                            if v:
                                try:
                                    category_ids.append(int(v))
                                except (ValueError, TypeError):
                                    pass
                        if category_ids:
                            stmt = stmt.where(Product.category_id.in_(category_ids))
                    elif operator == "=":
                        try:
                            category_id = int(value) if value else None
                            if category_id:
                                stmt = stmt.where(Product.category_id == category_id)
                        except (ValueError, TypeError):
                            pass
                    continue

        if category_ids:
            stmt = stmt.where(Product.category_id.in_(list(category_ids)))

        # استفاده از timeout برای query های طولانی
        with query_timeout(self.db, timeout_seconds=60):
            total = self.db.execute(select(func.count()).select_from(stmt.subquery())).scalar() or 0

            # Sorting: آرایه sort در اولویت، وگرنه sort_by/sort_desc (سازگار با کلاینت قدیمی)
            _allowed_product_sort = frozenset({"name", "code", "created_at"})
            try:
                qi = QueryInfo(sort_by=sort_by, sort_desc=sort_desc, sort=sort)  # type: ignore[arg-type]
                specs = effective_sort_specs(qi, allowed=_allowed_product_sort, default_when_empty=None)
            except Exception:
                specs = []
            if specs:
                order_parts = []
                for col_name, desc in specs:
                    col = getattr(Product, col_name)
                    order_parts.append(col.desc() if desc else col.asc())
                order_parts.append(Product.id.asc())
                stmt = stmt.order_by(*order_parts)
            else:
                stmt = stmt.order_by(Product.id.desc() if sort_desc else Product.id.asc())

            stmt = stmt.offset(skip).limit(take)
            # Load relationships
            stmt = stmt.options(
                joinedload(Product.default_warehouse),
                joinedload(Product.category)
            )
            rows = list(self.db.execute(stmt).unique().scalars().all())

        # محاسبه موجودی‌ها اگر include_inventory فعال باشد
        inventory_data = {}
        if include_inventory:
            from datetime import date as date_type
            from decimal import Decimal
            
            # تبدیل تاریخ
            as_of_date_obj = date_type.today()
            if inventory_as_of_date:
                try:
                    # پشتیبانی از فرمت YYYY-MM-DD و YYYY/MM/DD
                    date_str = inventory_as_of_date.replace('/', '-')
                    as_of_date_obj = date_type.fromisoformat(date_str)
                except Exception:
                    pass
            
            # جدا کردن کالاهای unique و bulk
            unique_products = [p for p in rows if p.track_inventory and getattr(p, 'inventory_mode', None) == "unique"]
            bulk_products = [p for p in rows if p.track_inventory and getattr(p, 'inventory_mode', None) != "unique"]
            
            unique_product_ids = [p.id for p in unique_products]
            bulk_product_ids = [p.id for p in bulk_products]
            
            # محاسبه موجودی برای کالاهای unique (از ProductInstance)
            if unique_product_ids:
                try:
                    from adapters.db.models.product_instance import ProductInstance
                    
                    # استفاده از timeout برای query های موجودی
                    with query_timeout(self.db, timeout_seconds=30):
                        # شمارش ProductInstance های available برای موجودی حسابداری
                        # (برای unique، موجودی حسابداری و انبارداری یکسان است - تعداد instance های available)
                        accounting_counts = (
                            self.db.query(
                                ProductInstance.product_id,
                                func.count(ProductInstance.id).label('count')
                            )
                            .filter(
                                and_(
                                    ProductInstance.business_id == business_id,
                                    ProductInstance.product_id.in_(unique_product_ids),
                                    ProductInstance.status == "available",
                                )
                            )
                            .group_by(ProductInstance.product_id)
                            .all()
                        )
                    
                    for pid, count in accounting_counts:
                        inventory_data[pid] = {
                            'accounting': float(count),
                            'warehouse': float(count),  # برای unique، هر دو یکسان هستند
                        }
                    
                    # برای کالاهای unique که instance ندارند، موجودی 0 است
                    for pid in unique_product_ids:
                        if pid not in inventory_data:
                            inventory_data[pid] = {
                                'accounting': 0.0,
                                'warehouse': 0.0,
                            }
                except Exception:
                    # در صورت خطا، موجودی 0 برای همه unique products
                    for pid in unique_product_ids:
                        if pid not in inventory_data:
                            inventory_data[pid] = {
                                'accounting': 0.0,
                                'warehouse': 0.0,
                            }
            
            # محاسبه موجودی برای کالاهای bulk (از حرکات اسناد)
            if bulk_product_ids:
                # محاسبه موجودی حسابداری (از اسناد حسابداری)
                try:
                    from app.services.invoice_service import get_financial_stock_bulk
                    # استفاده از timeout برای query های موجودی
                    with query_timeout(self.db, timeout_seconds=30):
                        accounting_stocks = get_financial_stock_bulk(
                            db=self.db,
                            business_id=business_id,
                            product_ids=bulk_product_ids,
                            as_of_date=as_of_date_obj,
                            warehouse_id=None,  # موجودی کل (بدون تفکیک انبار)
                        )
                    for pid, stock in accounting_stocks.items():
                        if pid not in inventory_data:
                            inventory_data[pid] = {}
                        inventory_data[pid]['accounting'] = float(stock)
                except Exception:
                    pass
                
                # محاسبه موجودی انبارداری (از حواله‌های انبار)
                try:
                    from app.services.warehouse_service import get_physical_stock_bulk
                    # استفاده از timeout برای query های موجودی
                    with query_timeout(self.db, timeout_seconds=30):
                        warehouse_stocks = get_physical_stock_bulk(
                            db=self.db,
                            business_id=business_id,
                            product_ids=bulk_product_ids,
                            as_of_date=as_of_date_obj,
                        )
                    for pid, stock in warehouse_stocks.items():
                        if pid not in inventory_data:
                            inventory_data[pid] = {}
                        inventory_data[pid]['warehouse'] = float(stock)
                except Exception:
                    pass

        def _to_dict(p: Product) -> dict[str, Any]:
            # دریافت attribute_ids از ProductAttributeLink
            links = self.db.query(ProductAttributeLink).filter(ProductAttributeLink.product_id == p.id).all()
            attribute_ids = [link.attribute_id for link in links]
            
            result = {
                "id": p.id,
                "business_id": p.business_id,
                "item_type": p.item_type.value if hasattr(p.item_type, 'value') else str(p.item_type),
                "code": p.code,
                "name": p.name,
                "description": p.description,
                "category_id": p.category_id,
                "category_name": (
                    (p.category.title_translations or {}).get("fa")
                    or (p.category.title_translations or {}).get("en")
                    or ""
                ) if (p.category and hasattr(p.category, 'title_translations')) else None,
                "main_unit": p.main_unit,
                "secondary_unit": p.secondary_unit,
                "unit_conversion_factor": p.unit_conversion_factor,
                "base_sales_price": p.base_sales_price,
                "base_sales_note": p.base_sales_note,
                "base_purchase_price": p.base_purchase_price,
                "base_purchase_note": p.base_purchase_note,
                "track_inventory": p.track_inventory,
                "reorder_point": p.reorder_point,
                "min_order_qty": p.min_order_qty,
                "lead_time_days": p.lead_time_days,
                "inventory_mode": getattr(p, 'inventory_mode', None) or "bulk",
                "track_serial": p.track_serial,
                "track_barcode": p.track_barcode,
                "is_sales_taxable": p.is_sales_taxable,
                "is_purchase_taxable": p.is_purchase_taxable,
                "sales_tax_rate": p.sales_tax_rate,
                "purchase_tax_rate": p.purchase_tax_rate,
                "tax_type_id": p.tax_type_id,
                "tax_code": p.tax_code,
                "tax_unit_id": p.tax_unit_id,
                "attribute_ids": attribute_ids,
                "image_file_id": p.image_file_id,
                "image_url": f"/api/v1/business/{p.business_id}/storage/files/{p.image_file_id}/download" if p.image_file_id else None,
                "thumbnail_url": f"/api/v1/business/{p.business_id}/storage/files/{p.image_file_id}/thumbnail?size=small" if p.image_file_id else None,
                "default_warehouse_id": p.default_warehouse_id,
                "default_warehouse_name": (p.default_warehouse.name if hasattr(p.default_warehouse, 'name') else None) if p.default_warehouse else None,
                "default_warehouse_code": (p.default_warehouse.code if hasattr(p.default_warehouse, 'code') else None) if p.default_warehouse else None,
                "is_active": getattr(p, 'is_active', True),  # اضافه کردن فیلد is_active
                "created_at": p.created_at,
                "updated_at": p.updated_at,
            }
            
            # اضافه کردن موجودی‌ها اگر محاسبه شده باشند
            if include_inventory and p.track_inventory:
                pid = p.id
                if pid in inventory_data:
                    # استفاده از get با مقدار پیش‌فرض 0.0 برای اطمینان از برگرداندن عدد
                    result["inventory_stock_accounting"] = inventory_data[pid].get("accounting", 0.0)
                    result["inventory_stock_warehouse"] = inventory_data[pid].get("warehouse", 0.0)
                else:
                    # اگر در inventory_data نیست، یعنی موجودی 0 است (نه null)
                    result["inventory_stock_accounting"] = 0.0
                    result["inventory_stock_warehouse"] = 0.0
            elif include_inventory:
                # اگر track_inventory false باشد، موجودی null است
                result["inventory_stock_accounting"] = None
                result["inventory_stock_warehouse"] = None
            
            return result

        items = [_to_dict(r) for r in rows]

        return {
            "items": items,
            "total_count": total,  # اضافه کردن total_count برای سازگاری با response model
            "has_more": skip + take < total,  # اضافه کردن has_more برای سازگاری با response model
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
        # اجازه بده فیلدهای خاص حتی اگر None باشند هم ست شوند
        nullable_overrides = {"main_unit_id", "secondary_unit_id", "unit_conversion_factor", "default_warehouse_id", "base_sales_price", "base_purchase_price"}
        for k, v in data.items():
            if hasattr(obj, k):
                if k in nullable_overrides:
                    setattr(obj, k, v)
                elif v is not None:
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


