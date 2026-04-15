from __future__ import annotations

from typing import Dict, Any, Optional, Tuple
from datetime import datetime, date
from decimal import Decimal, InvalidOperation
from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from adapters.db.repositories.product_attribute_repository import ProductAttributeRepository
from adapters.db.models.product_attribute import ProductAttribute
from adapters.db.models.product_attribute_link import ProductAttributeLink
from adapters.api.v1.schema_models.product_attribute import (
    ProductAttributeCreateRequest,
    ProductAttributeUpdateRequest,
)
from app.core.responses import ApiError


def create_attribute(db: Session, business_id: int, payload: ProductAttributeCreateRequest) -> Dict[str, Any]:
    repo = ProductAttributeRepository(db)
    # جلوگیری از عنوان تکراری در هر کسب‌وکار
    dup = db.query(ProductAttribute).filter(
        and_(ProductAttribute.business_id == business_id, func.lower(ProductAttribute.title) == func.lower(payload.title.strip()))
    ).first()
    if dup:
        raise ApiError("DUPLICATE_ATTRIBUTE_TITLE", "عنوان ویژگی تکراری است", http_status=400)

    # اعتبارسنجی: اگر data_type='select' باشد، options باید وجود داشته باشد
    data_type = payload.data_type or 'text'
    options = payload.options if payload.options else None
    
    if data_type == 'select':
        if not options or len(options) == 0:
            raise ApiError("INVALID_OPTIONS", "برای نوع select باید حداقل یک گزینه مشخص شود", http_status=400)
        # تبدیل لیست به dict برای ذخیره در JSON
        options_dict = {"items": options}
    else:
        options_dict = None

    obj = repo.create(
        business_id=business_id, 
        title=payload.title.strip(), 
        description=payload.description,
        data_type=data_type,
        options=options_dict
    )
    return {
        "message": "ویژگی با موفقیت ایجاد شد",
        "data": _to_dict(obj),
    }


def list_attributes(db: Session, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
    repo = ProductAttributeRepository(db)
    take = int(query.get("take", 20) or 20)
    skip = int(query.get("skip", 0) or 0)
    sort_by = query.get("sort_by")
    sort_desc = bool(query.get("sort_desc", True))
    sort_multi = query.get("sort") if isinstance(query.get("sort"), list) else None
    search = query.get("search")
    filters = query.get("filters")
    result = repo.search(
        business_id=business_id,
        take=take,
        skip=skip,
        sort_by=sort_by,
        sort_desc=sort_desc,
        sort=sort_multi,
        search=search,
        filters=filters,
    )
    for item in result.get("items", []):
        item["options"] = _options_raw_to_api_list(item.get("options"))
    return result


def get_attribute(db: Session, attribute_id: int, business_id: int) -> Optional[Dict[str, Any]]:
    obj = db.get(ProductAttribute, attribute_id)
    if not obj or obj.business_id != business_id:
        return None
    return _to_dict(obj)


def update_attribute(db: Session, attribute_id: int, business_id: int, payload: ProductAttributeUpdateRequest) -> Optional[Dict[str, Any]]:
    repo = ProductAttributeRepository(db)
    # کنترل مالکیت
    obj = db.get(ProductAttribute, attribute_id)
    if not obj or obj.business_id != business_id:
        return None
    # بررسی تکراری نبودن عنوان
    if payload.title is not None:
        title_norm = payload.title.strip()
        dup = db.query(ProductAttribute).filter(
            and_(
                ProductAttribute.business_id == business_id,
                func.lower(ProductAttribute.title) == func.lower(title_norm),
                ProductAttribute.id != attribute_id,
            )
        ).first()
        if dup:
            raise ApiError("DUPLICATE_ATTRIBUTE_TITLE", "عنوان ویژگی تکراری است", http_status=400)
    
    # تعیین data_type جدید (یا استفاده از موجود)
    new_data_type = payload.data_type if payload.data_type is not None else obj.data_type
    new_options = payload.options if payload.options is not None else obj.options
    
    # اعتبارسنجی: اگر data_type='select' باشد، options باید وجود داشته باشد
    if new_data_type == 'select':
        if not new_options or (isinstance(new_options, list) and len(new_options) == 0):
            raise ApiError("INVALID_OPTIONS", "برای نوع select باید حداقل یک گزینه مشخص شود", http_status=400)
        # اگر options به صورت لیست است، به dict تبدیل کن
        if isinstance(new_options, list):
            new_options = {"items": new_options}
    else:
        # اگر data_type تغییر کرد و دیگر select نیست، options را None کن
        if payload.data_type is not None and payload.data_type != 'select':
            new_options = None
    
    updated = repo.update(
        attribute_id=attribute_id,
        title=payload.title.strip() if isinstance(payload.title, str) else None,
        description=payload.description,
        data_type=payload.data_type,
        options=new_options if payload.options is not None or payload.data_type is not None else None,
    )
    if not updated:
        return None
    return {
        "message": "ویژگی با موفقیت ویرایش شد",
        "data": _to_dict(updated),
    }


def delete_attribute(db: Session, attribute_id: int, business_id: int) -> bool:
    repo = ProductAttributeRepository(db)
    obj = db.get(ProductAttribute, attribute_id)
    if not obj or obj.business_id != business_id:
        return False
    return repo.delete(attribute_id=attribute_id)


def _options_raw_to_api_list(raw: Any) -> Optional[list]:
    """یکسان‌سازی شکل options برای خروجی API (لیست یا dict ذخیره‌شده در JSON)."""
    if not raw:
        return None
    if isinstance(raw, dict) and "items" in raw:
        items = raw.get("items")
        if isinstance(items, list):
            return items
        return None
    if isinstance(raw, list):
        return raw
    return None


def _to_dict(obj: ProductAttribute) -> Dict[str, Any]:
    options_list = _options_raw_to_api_list(getattr(obj, "options", None))

    return {
        "id": obj.id,
        "business_id": obj.business_id,
        "title": obj.title,
        "description": obj.description,
        "data_type": getattr(obj, 'data_type', 'text'),
        "options": options_list,
        "created_at": obj.created_at,
        "updated_at": obj.updated_at,
    }


def validate_custom_attributes(
    db: Session,
    business_id: int,
    product_id: int,
    custom_attributes: Optional[Dict[str, Any]]
) -> Tuple[bool, Optional[str]]:
    """
    اعتبارسنجی custom_attributes بر اساس data_type ویژگی‌های کالا
    
    Args:
        db: Session دیتابیس
        business_id: شناسه کسب‌وکار
        product_id: شناسه کالا
        custom_attributes: دیکشنری ویژگی‌های سفارشی
    
    Returns:
        (is_valid, error_message): اگر معتبر باشد True و None برمی‌گرداند، در غیر این صورت False و پیام خطا
    """
    if not custom_attributes:
        return True, None
    
    if not isinstance(custom_attributes, dict):
        return False, "custom_attributes باید یک دیکشنری باشد"
    
    # دریافت ویژگی‌های مرتبط با کالا
    attribute_links = db.query(ProductAttributeLink).filter(
        ProductAttributeLink.product_id == product_id
    ).all()
    
    if not attribute_links:
        # اگر کالا ویژگی ندارد، custom_attributes باید خالی باشد
        if custom_attributes:
            return False, "این کالا ویژگی تعریف شده‌ای ندارد"
        return True, None
    
    # دریافت اطلاعات کامل ویژگی‌ها
    attribute_ids = [link.attribute_id for link in attribute_links]
    attributes = db.query(ProductAttribute).filter(
        and_(
            ProductAttribute.id.in_(attribute_ids),
            ProductAttribute.business_id == business_id
        )
    ).all()
    
    # ایجاد دیکشنری برای دسترسی سریع به ویژگی‌ها بر اساس title
    attributes_by_title = {attr.title: attr for attr in attributes}
    
    # بررسی هر ویژگی در custom_attributes
    for attr_title, attr_value in custom_attributes.items():
        if attr_title not in attributes_by_title:
            return False, f"ویژگی '{attr_title}' برای این کالا تعریف نشده است"
        
        attribute = attributes_by_title[attr_title]
        data_type = getattr(attribute, 'data_type', 'text')
        
        # اعتبارسنجی بر اساس نوع داده
        if attr_value is None:
            continue  # مقادیر None مجاز هستند
        
        validation_result = _validate_attribute_value(attribute, attr_value, data_type)
        if not validation_result[0]:
            return validation_result
    
    return True, None


def _validate_attribute_value(
    attribute: ProductAttribute,
    value: Any,
    data_type: str
) -> Tuple[bool, Optional[str]]:
    """
    اعتبارسنجی یک مقدار ویژگی بر اساس نوع داده
    
    Args:
        attribute: شیء ProductAttribute
        value: مقدار برای اعتبارسنجی
        data_type: نوع داده (text, number, date, select, boolean)
    
    Returns:
        (is_valid, error_message)
    """
    attr_title = attribute.title
    
    if data_type == 'text':
        if not isinstance(value, str):
            return False, f"ویژگی '{attr_title}' باید از نوع متن باشد"
        return True, None
    
    elif data_type == 'number':
        # پشتیبانی از int, float, Decimal, و رشته‌های عددی
        if isinstance(value, (int, float, Decimal)):
            return True, None
        if isinstance(value, str):
            try:
                # تلاش برای تبدیل به عدد
                float(value)
                return True, None
            except (ValueError, TypeError):
                return False, f"ویژگی '{attr_title}' باید یک عدد معتبر باشد"
        return False, f"ویژگی '{attr_title}' باید یک عدد باشد"
    
    elif data_type == 'date':
        # پشتیبانی از datetime, date, و رشته‌های ISO
        if isinstance(value, (datetime, date)):
            return True, None
        if isinstance(value, str):
            # تلاش برای پارس کردن تاریخ
            try:
                # فرمت ISO: YYYY-MM-DD
                datetime.fromisoformat(value.replace('Z', '+00:00'))
                return True, None
            except (ValueError, AttributeError):
                try:
                    # فرمت دیگر: YYYY-MM-DD
                    datetime.strptime(value, '%Y-%m-%d')
                    return True, None
                except (ValueError, TypeError):
                    return False, f"ویژگی '{attr_title}' باید یک تاریخ معتبر باشد (فرمت: YYYY-MM-DD)"
        return False, f"ویژگی '{attr_title}' باید یک تاریخ باشد"
    
    elif data_type == 'boolean':
        # پشتیبانی از bool, و مقادیر قابل تبدیل به bool
        if isinstance(value, bool):
            return True, None
        if isinstance(value, (int, str)):
            # تبدیل مقادیر رایج به bool
            if str(value).lower() in ('true', '1', 'yes', 'on'):
                return True, None
            if str(value).lower() in ('false', '0', 'no', 'off', ''):
                return True, None
        return False, f"ویژگی '{attr_title}' باید یک مقدار بولی (true/false) باشد"
    
    elif data_type == 'select':
        # دریافت گزینه‌های select
        options = None
        if attribute.options:
            if isinstance(attribute.options, dict) and "items" in attribute.options:
                options = attribute.options["items"]
            elif isinstance(attribute.options, list):
                options = attribute.options
        
        if not options:
            return False, f"ویژگی '{attr_title}' از نوع select است اما گزینه‌ای تعریف نشده است"
        
        # تبدیل گزینه‌ها به رشته برای مقایسه
        options_str = [str(opt) for opt in options]
        value_str = str(value)
        
        if value_str not in options_str:
            return False, f"ویژگی '{attr_title}' باید یکی از گزینه‌های زیر باشد: {', '.join(options_str)}"
        
        return True, None
    
    else:
        # نوع داده ناشناخته - به عنوان text در نظر می‌گیریم
        return True, None


