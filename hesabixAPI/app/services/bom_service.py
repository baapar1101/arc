from __future__ import annotations

from typing import Dict, Any, Optional, List, Set
from decimal import Decimal
from sqlalchemy.orm import Session
from sqlalchemy import and_

from app.core.responses import ApiError
from adapters.db.models.product import Product
from adapters.db.models.product_bom import ProductBOM, ProductBOMItem, ProductBOMOutput, ProductBOMOperation
from adapters.db.repositories.product_bom_repository import ProductBOMRepository
from adapters.api.v1.schema_models.product_bom import (
    ProductBOMCreateRequest,
    ProductBOMUpdateRequest,
    BOMExplosionRequest,
    ProductionDraftRequest,
    BomItem,
    BomOutput,
    BomOperation,
)


def _validate_product_belongs_to_business(db: Session, product_id: int, business_id: int, field_name: str = "product") -> Product:
    """بررسی می‌کند که محصول به business تعلق دارد"""
    if product_id <= 0:
        raise ApiError("INVALID_PRODUCT", f"{field_name} باید انتخاب شود", http_status=400)
    product = db.get(Product, product_id)
    if not product or product.business_id != business_id:
        raise ApiError("INVALID_PRODUCT", f"{field_name} انتخابی معتبر نیست یا به کسب‌وکار دیگری تعلق دارد", http_status=400)
    return product


def _validate_bom_items(db: Session, business_id: int, product_id: int, items: List[BomItem]) -> None:
    """اعتبارسنجی اقلام مواد اولیه BOM"""
    if not items:
        return
    
    component_ids: Set[int] = set()
    line_nos: Set[int] = set()
    
    for item in items:
        # بررسی component_product_id معتبر و تعلق به business
        if item.component_product_id <= 0:
            raise ApiError("INVALID_BOM_ITEM", "کالای مواد اولیه باید انتخاب شود", http_status=400)
        
        component_product = _validate_product_belongs_to_business(
            db, item.component_product_id, business_id, "کالای مواد اولیه"
        )
        
        # بررسی وابستگی چرخه‌ای - یک کالا نمی‌تواند برای خودش ماده اولیه باشد
        if item.component_product_id == product_id:
            raise ApiError("CIRCULAR_DEPENDENCY", f"کالا نمی‌تواند برای خودش به عنوان ماده اولیه استفاده شود", http_status=400)
        
        # بررسی qty_per مثبت
        if item.qty_per <= 0:
            raise ApiError("INVALID_BOM_ITEM", "مقدار برای تولید (qty_per) باید بزرگ‌تر از صفر باشد", http_status=400)
        
        # بررسی wastage_percent در محدوده 0-100
        if item.wastage_percent is not None:
            if item.wastage_percent < 0 or item.wastage_percent > 100:
                raise ApiError("INVALID_BOM_ITEM", "درصد پرت باید بین 0 تا 100 باشد", http_status=400)
        
        # بررسی line_no تکراری
        if item.line_no in line_nos:
            raise ApiError("INVALID_BOM_ITEM", f"شماره ردیف {item.line_no} تکراری است", http_status=400)
        line_nos.add(item.line_no)
        
        component_ids.add(item.component_product_id)


def _validate_bom_outputs(db: Session, business_id: int, outputs: List[BomOutput]) -> None:
    """اعتبارسنجی خروجی‌های BOM"""
    if not outputs:
        return
    
    line_nos: Set[int] = set()
    
    for output in outputs:
        # بررسی output_product_id معتبر و تعلق به business
        if output.output_product_id <= 0:
            raise ApiError("INVALID_BOM_OUTPUT", "محصول خروجی باید انتخاب شود", http_status=400)
        
        _validate_product_belongs_to_business(
            db, output.output_product_id, business_id, "محصول خروجی"
        )
        
        # بررسی ratio مثبت
        if output.ratio <= 0:
            raise ApiError("INVALID_BOM_OUTPUT", "نسبت خروجی باید بزرگ‌تر از صفر باشد", http_status=400)
        
        # بررسی line_no تکراری
        if output.line_no in line_nos:
            raise ApiError("INVALID_BOM_OUTPUT", f"شماره ردیف {output.line_no} تکراری است", http_status=400)
        line_nos.add(output.line_no)


def _validate_bom_operations(operations: List[BomOperation]) -> None:
    """اعتبارسنجی عملیات BOM"""
    if not operations:
        return
    
    line_nos: Set[int] = set()
    
    for op in operations:
        # بررسی نام عملیات خالی نباشد
        if not op.operation_name or not op.operation_name.strip():
            raise ApiError("INVALID_BOM_OPERATION", "نام عملیات نمی‌تواند خالی باشد", http_status=400)
        
        # بررسی line_no تکراری
        if op.line_no in line_nos:
            raise ApiError("INVALID_BOM_OPERATION", f"شماره ردیف {op.line_no} تکراری است", http_status=400)
        line_nos.add(op.line_no)


def _validate_version_uniqueness(db: Session, business_id: int, product_id: int, version: str, exclude_bom_id: Optional[int] = None) -> None:
    """بررسی یکتایی نسخه برای محصول"""
    query = db.query(ProductBOM).filter(
        and_(
            ProductBOM.business_id == business_id,
            ProductBOM.product_id == product_id,
            ProductBOM.version == version.strip()
        )
    )
    if exclude_bom_id:
        query = query.filter(ProductBOM.id != exclude_bom_id)
    
    existing = query.first()
    if existing:
        raise ApiError("DUPLICATE_VERSION", f"نسخه '{version}' برای این کالا قبلاً استفاده شده است", http_status=400)


def _validate_effective_dates(effective_from: Optional[str], effective_to: Optional[str]) -> None:
    """بررسی اعتبار تاریخ‌های effective"""
    if effective_from and effective_to:
        try:
            from datetime import datetime
            from_date = datetime.fromisoformat(effective_from.replace('Z', '+00:00') if 'Z' in effective_from else effective_from)
            to_date = datetime.fromisoformat(effective_to.replace('Z', '+00:00') if 'Z' in effective_to else effective_to)
            if from_date.date() > to_date.date():
                raise ApiError("INVALID_DATE_RANGE", "تاریخ شروع نمی‌تواند بعد از تاریخ پایان باشد", http_status=400)
        except (ValueError, AttributeError):
            pass  # اگر فرمت تاریخ اشتباه باشد، validation در schema انجام می‌شود


def _validate_yield_wastage_percent(yield_percent: Optional[Decimal], wastage_percent: Optional[Decimal]) -> None:
    """اعتبارسنجی درصد بازده و پرت"""
    if yield_percent is not None:
        if yield_percent < 0 or yield_percent > 100:
            raise ApiError("INVALID_YIELD_PERCENT", "درصد بازده باید بین 0 تا 100 باشد", http_status=400)
    
    if wastage_percent is not None:
        if wastage_percent < 0 or wastage_percent > 100:
            raise ApiError("INVALID_WASTAGE_PERCENT", "درصد پرت باید بین 0 تا 100 باشد", http_status=400)


def _to_bom_dict(bom: ProductBOM, db: Session) -> Dict[str, Any]:
    items = db.query(ProductBOMItem).filter(ProductBOMItem.bom_id == bom.id).order_by(ProductBOMItem.line_no).all()
    outputs = db.query(ProductBOMOutput).filter(ProductBOMOutput.bom_id == bom.id).order_by(ProductBOMOutput.line_no).all()
    operations = db.query(ProductBOMOperation).filter(ProductBOMOperation.bom_id == bom.id).order_by(ProductBOMOperation.line_no).all()
    
    # دریافت اطلاعات محصولات برای نمایش نام و کد
    product_ids: Set[int] = set()
    if items:
        product_ids.update([it.component_product_id for it in items])
    if outputs:
        product_ids.update([ot.output_product_id for ot in outputs])
    
    products_by_id: Dict[int, Product] = {}
    if product_ids:
        for p in db.query(Product).filter(Product.id.in_(product_ids)).all():
            products_by_id[p.id] = p
    
    return {
        "id": bom.id,
        "business_id": bom.business_id,
        "product_id": bom.product_id,
        "version": bom.version,
        "name": bom.name,
        "is_default": bom.is_default,
        "effective_from": bom.effective_from,
        "effective_to": bom.effective_to,
        "yield_percent": bom.yield_percent,
        "wastage_percent": bom.wastage_percent,
        "status": bom.status,
        "notes": bom.notes,
        "created_at": bom.created_at,
        "updated_at": bom.updated_at,
        "items": [
            {
                "line_no": it.line_no,
                "component_product_id": it.component_product_id,
                "component_product_name": (lambda p: p.name if p else None)(products_by_id.get(it.component_product_id)),
                "component_product_code": (lambda p: p.code if p else None)(products_by_id.get(it.component_product_id)),
                "qty_per": it.qty_per,
                "uom": it.uom,
                "wastage_percent": it.wastage_percent,
                "is_optional": it.is_optional,
                "substitute_group": it.substitute_group,
                "suggested_warehouse_id": it.suggested_warehouse_id,
            }
            for it in items
        ],
        "outputs": [
            {
                "line_no": ot.line_no,
                "output_product_id": ot.output_product_id,
                "output_product_name": (lambda p: p.name if p else None)(products_by_id.get(ot.output_product_id)),
                "output_product_code": (lambda p: p.code if p else None)(products_by_id.get(ot.output_product_id)),
                "ratio": ot.ratio,
                "uom": ot.uom,
            }
            for ot in outputs
        ],
        "operations": [
            {
                "line_no": op.line_no,
                "operation_name": op.operation_name,
                "cost_fixed": op.cost_fixed,
                "cost_per_unit": op.cost_per_unit,
                "cost_uom": op.cost_uom,
                "work_center": op.work_center,
            }
            for op in operations
        ],
    }


def create_bom(db: Session, business_id: int, payload: ProductBOMCreateRequest) -> Dict[str, Any]:
    # product must belong to business
    product = _validate_product_belongs_to_business(db, payload.product_id, business_id, "کالا")
    
    # اعتبارسنجی نسخه تکراری
    _validate_version_uniqueness(db, business_id, payload.product_id, payload.version)
    
    # اعتبارسنجی تاریخ‌های effective
    _validate_effective_dates(payload.effective_from, payload.effective_to)
    
    # اعتبارسنجی درصد بازده و پرت
    _validate_yield_wastage_percent(payload.yield_percent, payload.wastage_percent)
    
    # اعتبارسنجی اقلام مواد اولیه
    _validate_bom_items(db, business_id, payload.product_id, payload.items)
    
    # اعتبارسنجی خروجی‌ها
    _validate_bom_outputs(db, business_id, payload.outputs)
    
    # اعتبارسنجی عملیات
    _validate_bom_operations(payload.operations)

    try:
        repo = ProductBOMRepository(db)
        bom = repo.create_bom(
            business_id=business_id,
            product_id=payload.product_id,
            version=payload.version.strip(),
            name=payload.name.strip(),
            is_default=bool(payload.is_default),
            effective_from=payload.effective_from,
            effective_to=payload.effective_to,
            yield_percent=payload.yield_percent,
            wastage_percent=payload.wastage_percent,
            status=payload.status,
            notes=payload.notes,
        )

        # Replace child rows - همه در یک transaction
        try:
            items = [it.model_dump() for it in payload.items]
            outputs = [ot.model_dump() for ot in payload.outputs]
            operations = [op.model_dump() for op in payload.operations]
            repo.replace_items(bom.id, items)
            repo.replace_outputs(bom.id, outputs)
            repo.replace_operations(bom.id, operations)

            # enforce single default per product
            if bom.is_default:
                db.query(ProductBOM).filter(
                    and_(ProductBOM.business_id == business_id, ProductBOM.product_id == payload.product_id, ProductBOM.id != bom.id)
                ).update({ProductBOM.is_default: False})
            
            db.commit()
        except Exception as e:
            db.rollback()
            # حذف BOM ایجاد شده در صورت خطا در child rows
            try:
                db.delete(bom)
                db.commit()
            except Exception:
                db.rollback()
            if isinstance(e, ApiError):
                raise
            raise ApiError("BOM_CREATE_FAILED", f"خطا در ایجاد اقلام فرمول تولید: {str(e)}", http_status=500)

        return {"message": "BOM_CREATED", "data": _to_bom_dict(bom, db)}
    except Exception as e:
        db.rollback()
        if isinstance(e, ApiError):
            raise
        raise ApiError("BOM_CREATE_FAILED", f"خطا در ایجاد فرمول تولید: {str(e)}", http_status=500)


def get_bom(db: Session, business_id: int, bom_id: int) -> Optional[Dict[str, Any]]:
    repo = ProductBOMRepository(db)
    bom = repo.get_bom(bom_id, business_id)
    if not bom:
        return None
    return _to_bom_dict(bom, db)


def list_boms(db: Session, business_id: int, product_id: Optional[int] = None) -> Dict[str, Any]:
    repo = ProductBOMRepository(db)
    rows = repo.list_boms(business_id, product_id)
    return {"items": [_to_bom_dict(b, db) for b in rows]}


def update_bom(db: Session, business_id: int, bom_id: int, payload: ProductBOMUpdateRequest) -> Optional[Dict[str, Any]]:
    repo = ProductBOMRepository(db)
    bom = repo.get_bom(bom_id, business_id)
    if not bom:
        return None

    # اعتبارسنجی نسخه تکراری در صورت تغییر
    if payload.version is not None:
        # پردازش version: strip کردن و بررسی خالی نبودن
        if isinstance(payload.version, str):
            version_stripped = payload.version.strip()
            if not version_stripped:
                raise ApiError("INVALID_VERSION", "نسخه نمی‌تواند خالی باشد", http_status=400)
            version_to_check = version_stripped
        else:
            version_to_check = payload.version
        
        # بررسی یکتایی فقط در صورت تغییر
        if version_to_check != bom.version:
            _validate_version_uniqueness(db, business_id, bom.product_id, version_to_check, exclude_bom_id=bom_id)
    
    # اعتبارسنجی تاریخ‌های effective
    effective_from = payload.effective_from if payload.effective_from is not None else bom.effective_from
    effective_to = payload.effective_to if payload.effective_to is not None else bom.effective_to
    if effective_from or effective_to:
        _validate_effective_dates(
            effective_from.isoformat() if effective_from else None,
            effective_to.isoformat() if effective_to else None
        )
    
    # اعتبارسنجی درصد بازده و پرت
    yield_percent = payload.yield_percent if payload.yield_percent is not None else bom.yield_percent
    wastage_percent = payload.wastage_percent if payload.wastage_percent is not None else bom.wastage_percent
    _validate_yield_wastage_percent(yield_percent, wastage_percent)
    
    # اعتبارسنجی اقلام مواد اولیه در صورت تغییر
    if payload.items is not None:
        _validate_bom_items(db, business_id, bom.product_id, payload.items)
    
    # اعتبارسنجی خروجی‌ها در صورت تغییر
    if payload.outputs is not None:
        _validate_bom_outputs(db, business_id, payload.outputs)
    
    # اعتبارسنجی عملیات در صورت تغییر
    if payload.operations is not None:
        _validate_bom_operations(payload.operations)

    try:
        # ذخیره وضعیت قبلی برای rollback در صورت خطا
        old_items = list(db.query(ProductBOMItem).filter(ProductBOMItem.bom_id == bom_id).all())
        old_outputs = list(db.query(ProductBOMOutput).filter(ProductBOMOutput.bom_id == bom_id).all())
        old_operations = list(db.query(ProductBOMOperation).filter(ProductBOMOperation.bom_id == bom_id).all())
        
        # پردازش version و name با بررسی رشته خالی
        version_value = None
        if payload.version is not None:
            if isinstance(payload.version, str):
                version_stripped = payload.version.strip()
                if not version_stripped:
                    raise ApiError("INVALID_VERSION", "نسخه نمی‌تواند خالی باشد", http_status=400)
                version_value = version_stripped
            else:
                version_value = payload.version
        
        name_value = None
        if payload.name is not None:
            if isinstance(payload.name, str):
                name_stripped = payload.name.strip()
                if not name_stripped:
                    raise ApiError("INVALID_NAME", "عنوان نمی‌تواند خالی باشد", http_status=400)
                name_value = name_stripped
            else:
                name_value = payload.name
        
        updated = repo.update_bom(
            bom_id,
            version=version_value,
            name=name_value,
            is_default=payload.is_default if payload.is_default is not None else None,
            effective_from=payload.effective_from,
            effective_to=payload.effective_to,
            yield_percent=payload.yield_percent,
            wastage_percent=payload.wastage_percent,
            status=payload.status,
            notes=payload.notes,
        )
        if not updated:
            return None

        # Update child rows - همه در یک transaction
        try:
            if payload.items is not None:
                repo.replace_items(bom_id, [it.model_dump() for it in payload.items])
            if payload.outputs is not None:
                repo.replace_outputs(bom_id, [ot.model_dump() for ot in payload.outputs])
            if payload.operations is not None:
                repo.replace_operations(bom_id, [op.model_dump() for op in payload.operations])

            if updated.is_default:
                db.query(ProductBOM).filter(
                    and_(ProductBOM.business_id == business_id, ProductBOM.product_id == updated.product_id, ProductBOM.id != updated.id)
                ).update({ProductBOM.is_default: False})
            
            db.commit()
        except Exception as e:
            db.rollback()
            # بازگرداندن وضعیت قبلی child rows
            try:
                # حذف همه child rows فعلی که ممکن است اضافه شده باشند
                db.query(ProductBOMItem).filter(ProductBOMItem.bom_id == bom_id).delete(synchronize_session=False)
                db.query(ProductBOMOutput).filter(ProductBOMOutput.bom_id == bom_id).delete(synchronize_session=False)
                db.query(ProductBOMOperation).filter(ProductBOMOperation.bom_id == bom_id).delete(synchronize_session=False)
                
                # بازگرداندن child rows قبلی
                for item in old_items:
                    db.merge(item)  # استفاده از merge به جای add برای جلوگیری از خطای duplicate
                for output in old_outputs:
                    db.merge(output)
                for op in old_operations:
                    db.merge(op)
                
                db.commit()
            except Exception as rollback_error:
                db.rollback()
                # در صورت خطا در rollback، session را expire کنیم تا وضعیت قبلی بازگردد
                db.expire_all()
                # لاگ کردن خطا برای debugging
                import logging
                logger = logging.getLogger(__name__)
                logger.error(f"خطا در بازگرداندن وضعیت قبلی BOM {bom_id}: {str(rollback_error)}")
            
            if isinstance(e, ApiError):
                raise
            raise ApiError("BOM_UPDATE_FAILED", f"خطا در به‌روزرسانی اقلام فرمول تولید: {str(e)}", http_status=500)

        return {"message": "BOM_UPDATED", "data": _to_bom_dict(updated, db)}
    except Exception as e:
        db.rollback()
        if isinstance(e, ApiError):
            raise
        raise ApiError("BOM_UPDATE_FAILED", f"خطا در به‌روزرسانی فرمول تولید: {str(e)}", http_status=500)


def delete_bom(db: Session, business_id: int, bom_id: int) -> bool:
    repo = ProductBOMRepository(db)
    bom = repo.get_bom(bom_id, business_id)
    if not bom:
        return False
    return repo.delete_bom(bom_id)


def explode_bom(db: Session, business_id: int, req: BOMExplosionRequest) -> Dict[str, Any]:
    # minimal explosion without stock checks
    if not req.bom_id and not req.product_id:
        raise ApiError("INVALID_REQUEST", "bom_id یا product_id الزامی است", http_status=400)

    bom: Optional[ProductBOM] = None
    if req.bom_id:
        bom = db.get(ProductBOM, req.bom_id)
        if not bom or bom.business_id != business_id:
            raise ApiError("NOT_FOUND", "BOM یافت نشد", http_status=404)
    else:
        # pick default bom for product
        bom = db.query(ProductBOM).filter(
            and_(ProductBOM.business_id == business_id, ProductBOM.product_id == req.product_id, ProductBOM.is_default == True)
        ).first()
        if not bom:
            raise ApiError("NOT_FOUND", "برای این کالا فرمول پیش‌فرضی تعریف نشده است", http_status=404)

    items = db.query(ProductBOMItem).filter(ProductBOMItem.bom_id == bom.id).order_by(ProductBOMItem.line_no).all()
    outputs = db.query(ProductBOMOutput).filter(ProductBOMOutput.bom_id == bom.id).order_by(ProductBOMOutput.line_no).all()

    # Prepare product lookup for enriching names/units in response
    product_ids: set[int] = set([it.component_product_id for it in items] + [ot.output_product_id for ot in outputs])
    products_by_id: dict[int, Product] = {}
    if product_ids:
        for p in db.query(Product).filter(Product.id.in_(product_ids)).all():
            products_by_id[p.id] = p

    qty = Decimal(str(req.quantity))

    # Apply BOM-level wastage and yield to inputs
    # factor_inputs scales required input quantities. Example: yield 80% => factor 1.25; wastage 5% => factor * 1.05
    factor_inputs = Decimal("1")
    if bom.wastage_percent:
        factor_inputs *= (Decimal("1.0") + Decimal(str(bom.wastage_percent)) / Decimal("100"))
    if bom.yield_percent:
        try:
            y = Decimal(str(bom.yield_percent))
            if y > 0:
                factor_inputs *= (Decimal("100") / y)
        except Exception:
            pass
    explosion_items: List[Dict[str, Any]] = []
    for it in items:
        base = Decimal(str(it.qty_per)) * qty
        # apply line wastage
        if it.wastage_percent:
            base = base * (Decimal("1.0") + Decimal(str(it.wastage_percent)) / Decimal("100"))
        # apply BOM-level factors
        base = base * factor_inputs
        prod = products_by_id.get(it.component_product_id)

        # Unit conversion to main unit (if BOM line uom equals secondary and factor exists)
        required_qty_main_unit = None
        main_unit = getattr(prod, "main_unit", None) if prod else None
        secondary_unit = getattr(prod, "secondary_unit", None) if prod else None
        unit_factor = getattr(prod, "unit_conversion_factor", None) if prod else None
        if it.uom and prod and secondary_unit and main_unit and unit_factor is not None:
            try:
                # When line uom is secondary, convert to main by multiplying factor
                if str(it.uom) == str(secondary_unit):
                    required_qty_main_unit = base * Decimal(str(unit_factor))
                elif str(it.uom) == str(main_unit):
                    required_qty_main_unit = base
                else:
                    required_qty_main_unit = None
            except Exception:
                required_qty_main_unit = None
        explosion_items.append({
            "component_product_id": it.component_product_id,
            "required_qty": base,
            "uom": it.uom,
            "suggested_warehouse_id": it.suggested_warehouse_id,
            "is_optional": it.is_optional,
            "substitute_group": it.substitute_group,
            # enriched (optional) fields for UI friendliness
            "component_product_name": getattr(prod, "name", None) if prod else None,
            "component_product_code": getattr(prod, "code", None) if prod else None,
            "component_product_main_unit": getattr(prod, "main_unit", None) if prod else None,
            "required_qty_main_unit": required_qty_main_unit,
            "main_unit": main_unit,
        })

    # outputs scaling
    out_scaled = []
    for ot in outputs:
        prod = products_by_id.get(ot.output_product_id)
        # Convert output to main unit if needed
        ratio_val = Decimal(str(ot.ratio)) * qty
        ratio_main_unit = None
        try:
            main_unit = getattr(prod, "main_unit", None) if prod else None
            secondary_unit = getattr(prod, "secondary_unit", None) if prod else None
            unit_factor = getattr(prod, "unit_conversion_factor", None) if prod else None
            if ot.uom and prod and secondary_unit and main_unit and unit_factor is not None:
                if str(ot.uom) == str(secondary_unit):
                    ratio_main_unit = ratio_val * Decimal(str(unit_factor))
                elif str(ot.uom) == str(main_unit):
                    ratio_main_unit = ratio_val
        except Exception:
            ratio_main_unit = None
        out_scaled.append({
            "line_no": ot.line_no,
            "output_product_id": ot.output_product_id,
            "ratio": ratio_val,
            "uom": ot.uom,
            # enriched optional fields
            "output_product_name": getattr(prod, "name", None) if prod else None,
            "output_product_code": getattr(prod, "code", None) if prod else None,
            "ratio_main_unit": ratio_main_unit,
            "main_unit": getattr(prod, "main_unit", None) if prod else None,
        })

    return {"items": explosion_items, "outputs": out_scaled}


def produce_draft(db: Session, business_id: int, req: ProductionDraftRequest) -> Dict[str, Any]:
    """Create a draft payload for a production document based on BOM explosion (no persistence)."""
    exp = explode_bom(db, business_id, BOMExplosionRequest(product_id=req.product_id, bom_id=req.bom_id, quantity=req.quantity))

    # Build draft lines: for UI to prefill later; debit/credit left 0 to be set by user
    lines: list[dict[str, Any]] = []
    for it in exp["items"]:
        lines.append({
            "product_id": it["component_product_id"],
            "quantity": it["required_qty"],
            "debit": 0,
            "credit": 0,
            "description": f"مصرف مواد برای تولید",
            "extra_info": {
                "uom": it.get("uom"),
                "suggested_warehouse_id": it.get("suggested_warehouse_id"),
                "is_optional": it.get("is_optional"),
                "substitute_group": it.get("substitute_group"),
            },
        })

    for ot in exp["outputs"]:
        lines.append({
            "product_id": ot["output_product_id"],
            "quantity": ot["ratio"],
            "debit": 0,
            "credit": 0,
            "description": "خروجی تولید",
            "extra_info": {"uom": ot.get("uom")},
        })

    desc = "پیش‌نویس سند تولید بر اساس BOM"
    return {
        "document_type": "production",
        "description": desc,
        "lines": lines,
        "extra_info": {"source": "bom", "bom_id": int(req.bom_id) if req.bom_id else None, "product_id": int(req.product_id) if req.product_id else None, "quantity": str(req.quantity)},
    }


