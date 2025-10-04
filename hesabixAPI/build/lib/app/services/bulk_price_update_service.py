from __future__ import annotations

from typing import Dict, Any, List, Optional
from decimal import Decimal
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from adapters.db.models.product import Product
from adapters.db.models.price_list import PriceItem
from adapters.db.models.category import BusinessCategory
from adapters.db.models.currency import Currency
from adapters.api.v1.schema_models.product import (
    BulkPriceUpdateRequest,
    BulkPriceUpdatePreview,
    BulkPriceUpdatePreviewResponse,
    BulkPriceUpdateType,
    BulkPriceUpdateTarget,
    BulkPriceUpdateDirection,
    ProductItemType
)


def _quantize_non_negative_integer(value: Decimal) -> Decimal:
    """رُند کردن به عدد صحیح غیرمنفی (بدون اعشار)."""
    # حذف اعشار: round-half-up به نزدیک‌ترین عدد صحیح
    quantized = value.quantize(Decimal('1'))
    if quantized < 0:
        return Decimal('0')
    return quantized

def _quantize_integer_keep_sign(value: Decimal) -> Decimal:
    """رُند کردن به عدد صحیح با حفظ علامت (بدون اعشار)."""
    return value.quantize(Decimal('1'))


def calculate_new_price(current_price: Optional[Decimal], update_type: BulkPriceUpdateType, direction: BulkPriceUpdateDirection, value: Decimal) -> Optional[Decimal]:
    """محاسبه قیمت جدید بر اساس نوع تغییر با جهت، سپس رُند و کلَمپ به صفر"""
    if current_price is None:
        return None
    
    delta = Decimal('0')
    if update_type == BulkPriceUpdateType.PERCENTAGE:
        sign = Decimal('1') if direction == BulkPriceUpdateDirection.INCREASE else Decimal('-1')
        multiplier = Decimal('1') + (sign * (value / Decimal('100')))
        new_value = current_price * multiplier
    else:
        sign = Decimal('1') if direction == BulkPriceUpdateDirection.INCREASE else Decimal('-1')
        delta = sign * value
        new_value = current_price + delta

    # رُند به عدد صحیح و کلَمپ به صفر
    return _quantize_non_negative_integer(new_value)


def get_filtered_products(db: Session, business_id: int, request: BulkPriceUpdateRequest) -> List[Product]:
    """دریافت کالاهای فیلتر شده بر اساس معیارهای درخواست"""
    query = db.query(Product).filter(Product.business_id == business_id)
    
    # فیلتر بر اساس دسته‌بندی
    if request.category_ids:
        query = query.filter(Product.category_id.in_(request.category_ids))
    
    # فیلتر بر اساس نوع آیتم
    if request.item_types:
        query = query.filter(Product.item_type.in_([t.value for t in request.item_types]))
    
    # فیلتر بر اساس ارز: محصولی که قیمت‌های لیست مرتبط با ارزهای انتخابی دارد
    if request.currency_ids:
        query = query.filter(
            db.query(PriceItem.id)
            .filter(
                PriceItem.product_id == Product.id,
                PriceItem.currency_id.in_(request.currency_ids)
            ).exists()
        )
    
    # فیلتر بر اساس لیست قیمت: محصولی که در هر یک از لیست‌های انتخابی آیتم قیمت دارد
    if request.price_list_ids:
        query = query.filter(
            db.query(PriceItem.id)
            .filter(
                PriceItem.product_id == Product.id,
                PriceItem.price_list_id.in_(request.price_list_ids)
            ).exists()
        )
    
    # فیلتر بر اساس شناسه‌های کالاهای خاص
    if request.product_ids:
        query = query.filter(Product.id.in_(request.product_ids))
    
    # فیلتر بر اساس موجودی
    if request.only_products_with_inventory is not None:
        if request.only_products_with_inventory:
            query = query.filter(Product.track_inventory == True)
        else:
            query = query.filter(Product.track_inventory == False)
    
    # فیلتر بر اساس وجود قیمت پایه
    if request.only_products_with_base_price:
        if request.target == BulkPriceUpdateTarget.SALES_PRICE:
            query = query.filter(Product.base_sales_price.isnot(None))
        elif request.target == BulkPriceUpdateTarget.PURCHASE_PRICE:
            query = query.filter(Product.base_purchase_price.isnot(None))
        else:
            # در حالت هر دو، حداقل یکی موجود باشد
            query = query.filter(or_(Product.base_sales_price.isnot(None), Product.base_purchase_price.isnot(None)))
    
    return query.all()


def preview_bulk_price_update(db: Session, business_id: int, request: BulkPriceUpdateRequest) -> BulkPriceUpdatePreviewResponse:
    """پیش‌نمایش تغییرات قیمت گروهی"""
    products = get_filtered_products(db, business_id, request)
    
    # کش نام دسته‌ها برای کاهش کوئری
    category_titles: Dict[int, str] = {}
    def _resolve_category_name(cid: Optional[int]) -> Optional[str]:
        if cid is None:
            return None
        if cid in category_titles:
            return category_titles[cid]
        try:
            cat = db.query(BusinessCategory).filter(BusinessCategory.id == cid, BusinessCategory.business_id == business_id).first()
            if cat and isinstance(cat.title_translations, dict):
                title = cat.title_translations.get('fa') or cat.title_translations.get('default') or ''
                category_titles[cid] = title
                return title
        except Exception:
            return None
        return None

    affected_products = []
    total_sales_change = Decimal('0')
    total_purchase_change = Decimal('0')
    products_with_sales_change = 0
    products_with_purchase_change = 0
    
    for product in products:
        preview = BulkPriceUpdatePreview(
            product_id=product.id,
            product_name=product.name or "بدون نام",
            product_code=product.code or "بدون کد",
            category_name=_resolve_category_name(product.category_id),
            current_sales_price=product.base_sales_price,
            current_purchase_price=product.base_purchase_price,
            new_sales_price=None,
            new_purchase_price=None,
            sales_price_change=None,
            purchase_price_change=None
        )
        
        # محاسبه تغییرات قیمت فروش
        if request.target in [BulkPriceUpdateTarget.SALES_PRICE, BulkPriceUpdateTarget.BOTH] and product.base_sales_price is not None:
            new_sales_price = calculate_new_price(product.base_sales_price, request.update_type, request.direction, request.value)
            preview.new_sales_price = new_sales_price
            preview.sales_price_change = (new_sales_price - product.base_sales_price) if new_sales_price is not None else None
            total_sales_change += (preview.sales_price_change or Decimal('0'))
            products_with_sales_change += 1
        
        # محاسبه تغییرات قیمت خرید
        if request.target in [BulkPriceUpdateTarget.PURCHASE_PRICE, BulkPriceUpdateTarget.BOTH] and product.base_purchase_price is not None:
            new_purchase_price = calculate_new_price(product.base_purchase_price, request.update_type, request.direction, request.value)
            preview.new_purchase_price = new_purchase_price
            preview.purchase_price_change = (new_purchase_price - product.base_purchase_price) if new_purchase_price is not None else None
            total_purchase_change += (preview.purchase_price_change or Decimal('0'))
            products_with_purchase_change += 1
        
        affected_products.append(preview)
    
    summary = {
        "total_products": len(products),
        "affected_products": len(affected_products),
        "products_with_sales_change": products_with_sales_change,
        "products_with_purchase_change": products_with_purchase_change,
        "total_sales_change": float(_quantize_integer_keep_sign(total_sales_change)),
        "total_purchase_change": float(_quantize_integer_keep_sign(total_purchase_change)),
        "update_type": request.update_type.value,
        "direction": request.direction.value,
        "target": request.target.value,
        "value": float(_quantize_non_negative_integer(request.value)) if request.update_type == BulkPriceUpdateType.AMOUNT else float(request.value)
    }
    
    return BulkPriceUpdatePreviewResponse(
        total_products=len(products),
        affected_products=affected_products,
        summary=summary
    )


def apply_bulk_price_update(db: Session, business_id: int, request: BulkPriceUpdateRequest) -> Dict[str, Any]:
    """اعمال تغییرات قیمت گروهی"""
    products = get_filtered_products(db, business_id, request)
    
    updated_count = 0
    errors = []
    
    # اگر price_list_ids مشخص شده باشد، هم قیمت پایه و هم PriceItemها باید بهروزرسانی شوند
    for product in products:
        try:
            # بروزرسانی قیمت فروش
            if request.target in [BulkPriceUpdateTarget.SALES_PRICE, BulkPriceUpdateTarget.BOTH] and product.base_sales_price is not None:
                new_sales_price = calculate_new_price(product.base_sales_price, request.update_type, request.direction, request.value)
                product.base_sales_price = new_sales_price
            
            # بروزرسانی قیمت خرید
            if request.target in [BulkPriceUpdateTarget.PURCHASE_PRICE, BulkPriceUpdateTarget.BOTH] and product.base_purchase_price is not None:
                new_purchase_price = calculate_new_price(product.base_purchase_price, request.update_type, request.direction, request.value)
                product.base_purchase_price = new_purchase_price
            
            # بروزرسانی آیتم‌های لیست قیمت مرتبط (در صورت مشخص بودن فیلترها)
            q = db.query(PriceItem).filter(PriceItem.product_id == product.id)
            if request.currency_ids:
                q = q.filter(PriceItem.currency_id.in_(request.currency_ids))
            if request.price_list_ids:
                q = q.filter(PriceItem.price_list_id.in_(request.price_list_ids))
            # اگر هدف فقط فروش/خرید نیست چون PriceItem فقط یک فیلد price دارد، همان price را تغییر می‌دهیم
            for pi in q.all():
                new_pi_price = calculate_new_price(Decimal(pi.price), request.update_type, request.direction, request.value)
                pi.price = new_pi_price

            updated_count += 1
            
        except Exception as e:
            errors.append(f"خطا در بروزرسانی کالای {product.name}: {str(e)}")
    
    db.commit()
    
    return {
        "message": f"تغییرات قیمت برای {updated_count} کالا اعمال شد",
        "updated_count": updated_count,
        "total_products": len(products),
        "errors": errors
    }
