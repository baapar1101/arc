from __future__ import annotations

import re
from typing import Any, Dict, List, Optional
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import select, and_, or_, func, exists, text, case, literal
from app.core.query_timeout import query_timeout

from adapters.api.v1.schemas import QueryInfo
from app.services.sort_resolution import effective_sort_specs
from .base_repo import BaseRepository
from ..models.product import Product
from ..models.product_general_barcode_alias import ProductGeneralBarcodeAlias
from ..models.product_instance import ProductInstance
from ..models.product_attribute_link import ProductAttributeLink
from ..models.category import BusinessCategory

from app.services.product_general_barcode_service import split_raw_general_barcodes

# فاصله، خط جدید، انواع خط تیره (بدون نیم‌فاصلهٔ ZWNJ که در فارسی پیوند واژه است)
_SEARCH_SPLIT_RE = re.compile(r"(?:\s+|(?:[\-‐‑–—])+)+")


def _search_query_tokens(search: str) -> List[str]:
    """جدا کردن عبارت جستجو به توکن‌های غیرخالی (فاصله، خط تیره و مشابه)."""
    s = str(search).strip()
    if not s:
        return []
    parts = [p for p in _SEARCH_SPLIT_RE.split(s) if p]
    if parts:
        return parts
    return [s]


def _like_escape(s: str) -> str:
    """ایمن‌سازی متن ورودی برای الگوهای ILIKE (PostgreSQL با escape '\\')."""
    return s.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def _column_contains_all_tokens(column, tokens: List[str]):
    """هر توکن باید به‌صورت زیررشته‌ای در مقدار ستون باشد (AND بین توکن‌ها)."""
    if not tokens:
        return True
    if len(tokens) == 1:
        return column.ilike(f"%{tokens[0]}%")
    return and_(*[column.ilike(f"%{t}%") for t in tokens])


class ProductRepository(BaseRepository[Product]):
    def __init__(self, db: Session) -> None:
        super().__init__(db, Product)

    def search(self, *, business_id: int, take: int = 20, skip: int = 0, sort_by: str | None = None, sort_desc: bool = True, sort: list[Any] | None = None, search: str | None = None, search_fields: List[str] | None = None, filters: dict[str, Any] | None = None, category_ids: List[int] | None = None, include_inventory: bool = False, inventory_as_of_date: str | None = None) -> dict[str, Any]:
        stmt = select(Product).where(Product.business_id == business_id)
        search_s = (search or "").strip() if search else ""
        tokens = _search_query_tokens(search_s) if search_s else []

        if tokens:
            ors: List[Any] = []
            raw_fields = search_fields or []
            field_set = {str(x).strip().lower() for x in raw_fields if str(x).strip()}
            if not field_set:
                field_set = {"name", "code", "description", "general_barcodes", "barcode"}

            # فیلد legacy «barcode» علاوه بر بارکد عمومی، بارکد/سریال کالاهای یونیک را هم پوشش می‌دهد
            if "barcode" in field_set:
                field_set.add("general_barcodes")
                field_set.add("unique_instance_codes")
            if "serial" in field_set or "serial_number" in field_set:
                field_set.add("unique_instance_codes")

            if "name" in field_set:
                ors.append(_column_contains_all_tokens(Product.name, tokens))
            if "code" in field_set:
                ors.append(_column_contains_all_tokens(Product.code, tokens))
            if "description" in field_set:
                ors.append(_column_contains_all_tokens(Product.description, tokens))

            if "general_barcodes" in field_set:
                if len(tokens) == 1:
                    t = tokens[0]
                    term_lower = t.lower()
                    alias_match = exists(
                        select(1).select_from(ProductGeneralBarcodeAlias).where(
                            ProductGeneralBarcodeAlias.product_id == Product.id,
                            ProductGeneralBarcodeAlias.business_id == business_id,
                            ProductGeneralBarcodeAlias.token_normalized == term_lower,
                        )
                    )
                    partial_col = and_(
                        Product.general_barcodes.isnot(None),
                        Product.general_barcodes != "",
                        Product.general_barcodes.ilike(f"%{t}%"),
                    )
                    ors.append(or_(alias_match, partial_col))
                else:
                    partial_col = and_(
                        Product.general_barcodes.isnot(None),
                        Product.general_barcodes != "",
                        _column_contains_all_tokens(Product.general_barcodes, tokens),
                    )
                    alias_clauses = [
                        exists(
                            select(1).select_from(ProductGeneralBarcodeAlias).where(
                                ProductGeneralBarcodeAlias.product_id == Product.id,
                                ProductGeneralBarcodeAlias.business_id == business_id,
                                ProductGeneralBarcodeAlias.token_normalized == t.lower(),
                            )
                        )
                        for t in tokens
                    ]
                    alias_match_multi = and_(*alias_clauses)
                    ors.append(or_(alias_match_multi, partial_col))

            if "unique_instance_codes" in field_set:
                if len(tokens) == 1:
                    like_1 = f"%{tokens[0]}%"
                    instance_match = exists(
                        select(1).select_from(ProductInstance).where(
                            ProductInstance.business_id == business_id,
                            ProductInstance.product_id == Product.id,
                            or_(
                                ProductInstance.barcode.ilike(like_1),
                                ProductInstance.serial_number.ilike(like_1),
                            ),
                        )
                    )
                    ors.append(instance_match)
                else:
                    per_row = []
                    for t in tokens:
                        tk = f"%{t}%"
                        per_row.append(
                            exists(
                                select(1).select_from(ProductInstance).where(
                                    ProductInstance.business_id == business_id,
                                    ProductInstance.product_id == Product.id,
                                    or_(
                                        ProductInstance.barcode.ilike(tk),
                                        ProductInstance.serial_number.ilike(tk),
                                    ),
                                )
                            )
                        )
                    ors.append(and_(*per_row))

            if ors:
                stmt = stmt.where(or_(*ors))

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
                        nt = _search_query_tokens(value)
                        if nt:
                            stmt = stmt.where(_column_contains_all_tokens(Product.name, nt))
                    elif operator == "=":
                        stmt = stmt.where(Product.name == value)
                    continue

                if field == "item_type" and operator == "=" and value is not None:
                    # مقدار رشته‌ای enum (مثلاً product / service)
                    try:
                        from adapters.db.models.product import ProductItemType
                        iv = str(value).strip().lower()
                        if iv in (ProductItemType.PRODUCT.value, "product"):
                            stmt = stmt.where(Product.item_type == ProductItemType.PRODUCT)
                        elif iv in (ProductItemType.SERVICE.value, "service"):
                            stmt = stmt.where(Product.item_type == ProductItemType.SERVICE)
                    except Exception:
                        pass
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
            elif search_s:
                # بدون مرتب‌سازی صریح از کلاینت: نتایج مرتبط‌تر بالاتر (نام دقیق، شروع با عبارت، کد، ...)
                esc_q = _like_escape(search_s)
                esc_first = _like_escape(tokens[0]) if tokens else esc_q
                q_lower = search_s.lower()
                name_lower = func.lower(func.coalesce(Product.name, ""))
                code_lower = func.lower(func.coalesce(Product.code, ""))
                rel_order = [
                    case((name_lower == literal(q_lower), 0), else_=1).asc(),
                    case((Product.name.ilike(esc_q + "%", escape="\\"), 0), else_=1).asc(),
                    case((Product.name.ilike(esc_first + "%", escape="\\"), 0), else_=1).asc(),
                    case((code_lower == literal(q_lower), 0), else_=1).asc(),
                    case((Product.code.ilike(esc_q + "%", escape="\\"), 0), else_=1).asc(),
                    func.length(func.coalesce(Product.name, "")).asc(),
                    Product.id.desc(),
                ]
                stmt = stmt.order_by(*rel_order)
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
            
            # موجودی حسابداری و انبارداری برای همهٔ کالاهای با track_inventory
            all_tracked_product_ids = [p.id for p in rows if p.track_inventory]

            # موجودی حسابداری: اقلام فاکتور (invoice_item_lines) + در صورت نیاز DocumentLine قدیمی
            if all_tracked_product_ids:
                try:
                    from app.services.invoice_service import get_financial_stock_bulk

                    with query_timeout(self.db, timeout_seconds=30):
                        accounting_stocks = get_financial_stock_bulk(
                            db=self.db,
                            business_id=business_id,
                            product_ids=all_tracked_product_ids,
                            as_of_date=as_of_date_obj,
                            warehouse_id=None,
                        )
                    for pid, stock in accounting_stocks.items():
                        inventory_data.setdefault(pid, {})
                        inventory_data[pid]["accounting"] = float(stock)
                except Exception:
                    pass

            # موجودی انبارداری (فیزیکی): حواله‌های انبار قطعی — برای bulk و unique
            if all_tracked_product_ids:
                try:
                    from app.services.warehouse_service import get_physical_stock_bulk

                    with query_timeout(self.db, timeout_seconds=30):
                        warehouse_stocks = get_physical_stock_bulk(
                            db=self.db,
                            business_id=business_id,
                            product_ids=all_tracked_product_ids,
                            as_of_date=as_of_date_obj,
                        )
                    for pid, stock in warehouse_stocks.items():
                        inventory_data.setdefault(pid, {})
                        inventory_data[pid]["warehouse"] = float(stock)
                except Exception:
                    pass

        def _to_dict(p: Product) -> dict[str, Any]:
            # دریافت attribute_ids از ProductAttributeLink
            links = self.db.query(ProductAttributeLink).filter(ProductAttributeLink.product_id == p.id).all()
            attribute_ids = [link.attribute_id for link in links]

            gb_raw = getattr(p, "general_barcodes", None)
            gb_tokens = split_raw_general_barcodes(gb_raw) if gb_raw else []
            legacy_barcode = gb_tokens[0] if gb_tokens else None
            
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
                "general_barcodes": getattr(p, "general_barcodes", None),
                "barcode": legacy_barcode,
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

    def update(self, product_id: int, *, commit: bool = True, **data: Any) -> Optional[Product]:
        obj = self.db.get(Product, product_id)
        if not obj:
            return None
        # اجازه بده فیلدهای خاص حتی اگر None باشند هم ست شوند
        nullable_overrides = {
            "main_unit_id",
            "secondary_unit_id",
            "unit_conversion_factor",
            "default_warehouse_id",
            "base_sales_price",
            "base_purchase_price",
            "general_barcodes",
        }
        for k, v in data.items():
            if hasattr(obj, k):
                if k in nullable_overrides:
                    setattr(obj, k, v)
                elif v is not None:
                    setattr(obj, k, v)
        if commit:
            self.db.commit()
            self.db.refresh(obj)
        else:
            self.db.flush()
        return obj

    def delete(self, product_id: int) -> bool:
        obj = self.db.get(Product, product_id)
        if not obj:
            return False
        self.db.delete(obj)
        self.db.commit()
        return True


