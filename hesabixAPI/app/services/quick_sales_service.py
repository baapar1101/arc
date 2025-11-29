from __future__ import annotations

from typing import Any, Dict
import json
from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from adapters.db.models.quick_sales_settings import QuickSalesSetting
from adapters.db.models.person import Person, PersonType
from adapters.db.models.business import Business
from adapters.api.v1.schema_models.person import PersonCreateRequest
from app.core.responses import ApiError
from app.services.person_service import create_person


def get_quick_sales_settings(db: Session, business_id: int) -> Dict[str, Any]:
    """دریافت تنظیمات فروش سریع یک کسب‌وکار"""
    obj = (
        db.query(QuickSalesSetting)
        .filter(QuickSalesSetting.business_id == int(business_id))
        .first()
    )
    
    if not obj:
        # بازگشت مقادیر پیش‌فرض
        business = db.query(Business).filter(Business.id == int(business_id)).first()
        default_currency_id = business.default_currency_id if business else None
        
        return {
            "business_id": int(business_id),
            "default_anonymous_customer_id": None,
            "auto_create_anonymous_customer": True,
            "anonymous_customer_name": "مشتری ناشناس",
            "default_warehouse_id": None,
            "default_cash_register_id": None,
            "default_currency_id": default_currency_id,
            "default_price_list_id": None,
            "auto_print": False,
            "print_template_id": None,
            "auto_post_warehouse": True,
            "show_inventory": True,
            "auto_create_payment_document": True,
            "show_purchase_price": False,
        }
    
    return {
        "business_id": int(business_id),
        "default_anonymous_customer_id": int(obj.default_anonymous_customer_id) if obj.default_anonymous_customer_id else None,
        "auto_create_anonymous_customer": bool(obj.auto_create_anonymous_customer),
        "anonymous_customer_name": obj.anonymous_customer_name if obj.anonymous_customer_name else "مشتری ناشناس",
        "default_warehouse_id": int(obj.default_warehouse_id) if obj.default_warehouse_id else None,
        "default_cash_register_id": int(obj.default_cash_register_id) if obj.default_cash_register_id else None,
        "default_currency_id": int(obj.default_currency_id) if obj.default_currency_id else None,
        "default_price_list_id": int(obj.default_price_list_id) if obj.default_price_list_id else None,
        "auto_print": bool(obj.auto_print),
        "print_template_id": int(obj.print_template_id) if obj.print_template_id else None,
        "auto_post_warehouse": bool(obj.auto_post_warehouse),
        "show_inventory": bool(obj.show_inventory),
        "auto_create_payment_document": bool(obj.auto_create_payment_document),
        "show_purchase_price": bool(obj.show_purchase_price),
    }


def update_quick_sales_settings(db: Session, business_id: int, payload: Dict[str, Any], user_id: int | None = None) -> Dict[str, Any]:
    """به‌روزرسانی تنظیمات فروش سریع یک کسب‌وکار"""
    obj = (
        db.query(QuickSalesSetting)
        .filter(QuickSalesSetting.business_id == int(business_id))
        .first()
    )
    
    if not obj:
        obj = QuickSalesSetting(business_id=int(business_id))
        db.add(obj)
    
    # به‌روزرسانی فیلدها
    if "default_anonymous_customer_id" in payload:
        customer_id = payload.get("default_anonymous_customer_id")
        if customer_id is not None:
            # بررسی وجود شخص
            person = db.query(Person).filter(
                and_(
                    Person.id == int(customer_id),
                    Person.business_id == int(business_id),
                    Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
                )
            ).first()
            if not person:
                raise ApiError("PERSON_NOT_FOUND", "مشتری یافت نشد", http_status=404)
        obj.default_anonymous_customer_id = int(customer_id) if customer_id is not None else None
    
    if "auto_create_anonymous_customer" in payload:
        obj.auto_create_anonymous_customer = bool(payload.get("auto_create_anonymous_customer"))
    
    if "anonymous_customer_name" in payload:
        name_data = payload.get("anonymous_customer_name")
        if name_data is not None:
            obj.anonymous_customer_name = str(name_data).strip()
        else:
            obj.anonymous_customer_name = None
    
    if "default_warehouse_id" in payload:
        warehouse_id = payload.get("default_warehouse_id")
        if warehouse_id is not None:
            from adapters.db.models.warehouse import Warehouse
            warehouse = db.query(Warehouse).filter(
                and_(
                    Warehouse.id == int(warehouse_id),
                    Warehouse.business_id == int(business_id),
                )
            ).first()
            if not warehouse:
                raise ApiError("WAREHOUSE_NOT_FOUND", "انبار یافت نشد", http_status=404)
        obj.default_warehouse_id = int(warehouse_id) if warehouse_id is not None else None
    
    if "default_cash_register_id" in payload:
        cash_register_id = payload.get("default_cash_register_id")
        if cash_register_id is not None:
            from adapters.db.models.cash_register import CashRegister
            cash_register = db.query(CashRegister).filter(
                and_(
                    CashRegister.id == int(cash_register_id),
                    CashRegister.business_id == int(business_id),
                )
            ).first()
            if not cash_register:
                raise ApiError("CASH_REGISTER_NOT_FOUND", "صندوق یافت نشد", http_status=404)
        obj.default_cash_register_id = int(cash_register_id) if cash_register_id is not None else None
    
    if "default_currency_id" in payload:
        currency_id = payload.get("default_currency_id")
        if currency_id is not None:
            from adapters.db.models.currency import Currency
            currency = db.query(Currency).filter(Currency.id == int(currency_id)).first()
            if not currency:
                raise ApiError("CURRENCY_NOT_FOUND", "ارز یافت نشد", http_status=404)
        obj.default_currency_id = int(currency_id) if currency_id is not None else None
    
    if "default_price_list_id" in payload:
        price_list_id = payload.get("default_price_list_id")
        if price_list_id is not None:
            from adapters.db.models.price_list import PriceList
            price_list = db.query(PriceList).filter(
                and_(
                    PriceList.id == int(price_list_id),
                    PriceList.business_id == int(business_id),
                )
            ).first()
            if not price_list:
                raise ApiError("PRICE_LIST_NOT_FOUND", "لیست قیمت یافت نشد", http_status=404)
        obj.default_price_list_id = int(price_list_id) if price_list_id is not None else None
    
    if "auto_print" in payload:
        obj.auto_print = bool(payload.get("auto_print"))
    
    if "print_template_id" in payload:
        template_id = payload.get("print_template_id")
        obj.print_template_id = int(template_id) if template_id is not None else None
    
    if "auto_post_warehouse" in payload:
        obj.auto_post_warehouse = bool(payload.get("auto_post_warehouse"))
    
    if "show_inventory" in payload:
        obj.show_inventory = bool(payload.get("show_inventory"))
    
    if "auto_create_payment_document" in payload:
        obj.auto_create_payment_document = bool(payload.get("auto_create_payment_document"))
    
    if "show_purchase_price" in payload:
        obj.show_purchase_price = bool(payload.get("show_purchase_price"))
    
    db.flush()
    db.commit()
    return get_quick_sales_settings(db, business_id)


def get_or_create_anonymous_customer(
    db: Session, 
    business_id: int, 
    settings: Dict[str, Any] | None = None
) -> Person:
    """دریافت یا ایجاد مشتری ناشناس"""
    if settings is None:
        settings = get_quick_sales_settings(db, business_id)
    
    # بررسی مشتری پیش‌فرض
    customer_id = settings.get("default_anonymous_customer_id")
    if customer_id:
        customer = db.query(Person).filter(
            and_(
                Person.id == int(customer_id),
                Person.business_id == int(business_id),
                Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
            )
        ).first()
        if customer:
            return customer
    
    # جستجوی مشتری ناشناس موجود
    customer_name = settings.get("anonymous_customer_name", "مشتری ناشناس")
    name_fa = str(customer_name) if customer_name else "مشتری ناشناس"
    
    # جستجوی مشتری با نام و نوع مشتری
    # اولویت با مشتری‌هایی که کد دارند (کد None نباشد)
    customer = db.query(Person).filter(
        and_(
            Person.business_id == int(business_id),
            Person.alias_name == name_fa,
            Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
            Person.code.isnot(None),  # اولویت با مشتری‌هایی که کد دارند
        )
    ).first()
    
    # اگر مشتری با کد پیدا نشد، مشتری بدون کد را جستجو کن
    if not customer:
        customer = db.query(Person).filter(
            and_(
                Person.business_id == int(business_id),
                Person.alias_name == name_fa,
                Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
            )
        ).first()
    
    if customer:
        # به‌روزرسانی تنظیمات (مستقیماً بدون بررسی مجدد)
        obj = (
            db.query(QuickSalesSetting)
            .filter(QuickSalesSetting.business_id == int(business_id))
            .first()
        )
        if not obj:
            obj = QuickSalesSetting(business_id=int(business_id))
            db.add(obj)
        obj.default_anonymous_customer_id = customer.id
        db.flush()
        db.commit()
        return customer
    
    # ایجاد جدید با استفاده از create_person برای تولید صحیح کد
    if settings.get("auto_create_anonymous_customer", True):
        # استفاده از create_person برای تولید صحیح کد
        person_data = PersonCreateRequest(
            alias_name=name_fa,
            person_types=[PersonType.CUSTOMER],
            code=None,  # None = تولید خودکار کد
        )
        
        result = create_person(db, int(business_id), person_data)
        customer_id = result.get("data", {}).get("id")
        
        if not customer_id:
            raise ApiError(
                "FAILED_TO_CREATE_ANONYMOUS_CUSTOMER",
                "خطا در ایجاد مشتری ناشناس",
                http_status=500
            )
        
        # دریافت مشتری ایجاد شده
        customer = db.query(Person).filter(
            and_(
                Person.id == int(customer_id),
                Person.business_id == int(business_id),
            )
        ).first()
        
        if not customer:
            raise ApiError(
                "ANONYMOUS_CUSTOMER_NOT_FOUND",
                "مشتری ناشناس ایجاد شد اما یافت نشد",
                http_status=500
            )
        
        # به‌روزرسانی تنظیمات (مستقیماً بدون بررسی مجدد)
        obj = (
            db.query(QuickSalesSetting)
            .filter(QuickSalesSetting.business_id == int(business_id))
            .first()
        )
        if not obj:
            obj = QuickSalesSetting(business_id=int(business_id))
            db.add(obj)
        obj.default_anonymous_customer_id = customer.id
        db.flush()
        db.commit()
        return customer
    
    raise ApiError(
        "ANONYMOUS_CUSTOMER_NOT_SET", 
        "مشتری ناشناس تعریف نشده است. لطفاً در تنظیمات فروش سریع یک مشتری پیش‌فرض انتخاب کنید.",
        http_status=400
    )

