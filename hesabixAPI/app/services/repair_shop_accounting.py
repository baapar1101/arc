"""
یکپارچگی افزونه مدیریت تعمیرگاه با سیستم حسابداری
"""
from __future__ import annotations

import logging
from datetime import datetime, date
from typing import Any, Dict, List, Optional
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_

from adapters.db.models.repair_shop import RepairOrder, RepairOrderPart, RepairInvoice
from adapters.db.models.business import Business
from adapters.db.models.product import Product
from adapters.db.models.document import Document
from adapters.db.repositories.repair_shop_repository import RepairInvoiceRepository
from app.core.responses import ApiError

logger = logging.getLogger(__name__)


def create_repair_invoice_accounting(
    db: Session,
    business_id: int,
    repair_order: RepairOrder,
    user_id: int
) -> Dict[str, Any]:
    """
    ثبت فاکتور تعمیر در سیستم حسابداری
    
    این تابع یک فاکتور فروش ایجاد می‌کند که شامل:
    - ردیف خدمات تعمیر (دستمزد)
    - ردیف‌های قطعات استفاده شده
    
    و اسناد حسابداری زیر را ثبت می‌کند:
    - حساب دریافتنی مشتری (بدهکار)
    - درآمد فروش خدمات (بستانکار)
    - درآمد فروش قطعات (بستانکار)
    - بهای تمام شده (اگر قطعه از انبار خارج شده باشد)
    """
    from app.services.invoice_service import create_invoice
    from app.services.repair_shop_service import _get_current_fiscal_year
    
    # بررسی اینکه فاکتور قبلاً ایجاد نشده باشد
    invoice_repo = RepairInvoiceRepository(db)
    existing = invoice_repo.get_by_order(repair_order.id)
    
    if existing:
        raise ApiError(
            "INVOICE_ALREADY_EXISTS",
            f"فاکتور قبلاً برای این سفارش ایجاد شده است (سند شماره: {existing.document_id})",
            http_status=409
        )
    
    # بررسی وضعیت سفارش
    if repair_order.status not in ["completed_fixed", "ready_for_pickup", "delivered"]:
        raise ApiError(
            "INVALID_STATUS_FOR_INVOICE",
            f"سفارش در وضعیت {repair_order.status} قابل صدور فاکتور نیست. ابتدا تعمیر را تکمیل کنید.",
            http_status=400
        )
    
    # دریافت اطلاعات کسب‌وکار
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
    
    # دریافت سال مالی
    fiscal_year = _get_current_fiscal_year(db, business_id)
    
    # ساخت payload فاکتور
    invoice_payload = {
        "invoice_type": "invoice_sales",  # فاکتور فروش
        "document_date": repair_order.completed_at.date() if repair_order.completed_at else date.today(),
        "currency_id": repair_order.currency_id,
        "fiscal_year_id": fiscal_year.id,
        "description": f"فاکتور تعمیر - {repair_order.code}",
        "extra_info": {
            "person_id": repair_order.customer_person_id,
            "source_type": "repair_shop",
            "source_id": repair_order.id,
            "repair_code": repair_order.code,
            "totals": {
                "labor_cost": float(repair_order.labor_cost),
                "parts_cost": float(repair_order.parts_cost),
                "final_cost": float(repair_order.final_cost),
                "technician_commission": float(repair_order.technician_commission),
            }
        },
        "lines": []
    }
    
    # 1. افزودن ردیف خدمات تعمیر (اگر دستمزد وجود داشته باشد)
    if repair_order.labor_cost > 0:
        # دریافت محصول خدمات تعمیر از تنظیمات (اگر تعریف شده باشد)
        from adapters.db.repositories.repair_shop_repository import RepairShopSettingsRepository
        
        settings_repo = RepairShopSettingsRepository(db)
        settings = settings_repo.get_by_business(business_id)
        
        service_product_id = None
        if settings and settings.default_service_product_id:
            service_product_id = settings.default_service_product_id
        
        if not service_product_id:
            # اگر محصول خدمات پیش‌فرض تعریف نشده، یک محصول پیش‌فرض جستجو می‌کنیم
            service_product = db.query(Product).filter(
                and_(
                    Product.business_id == business_id,
                    Product.code.like('SRV-REPAIR%'),
                    Product.product_type == 'service'
                )
            ).first()
            
            if service_product:
                service_product_id = service_product.id
        
        if service_product_id:
            invoice_payload["lines"].append({
                "product_id": service_product_id,
                "quantity": 1,
                "unit_price": float(repair_order.labor_cost),
                "description": f"خدمات تعمیر - {repair_order.product_name}",
                "extra_info": {
                    "line_type": "service",
                    "repair_order_id": repair_order.id,
                    "technician_id": repair_order.assigned_technician_id,
                    "technician_commission": float(repair_order.technician_commission),
                }
            })
        else:
            # اگر محصول خدمات یافت نشد، لاگ می‌کنیم
            logger.warning(
                f"محصول خدمات تعمیر برای کسب‌وکار {business_id} یافت نشد. "
                f"لطفاً یک محصول با نوع 'service' و کد 'SRV-REPAIR' ایجاد کنید."
            )
    
    # 2. افزودن ردیف‌های قطعات
    parts = db.query(RepairOrderPart).filter(
        RepairOrderPart.repair_order_id == repair_order.id
    ).all()
    
    for part in parts:
        product = db.query(Product).filter(Product.id == part.product_id).first()
        
        if not product:
            continue
        
        invoice_payload["lines"].append({
            "product_id": part.product_id,
            "quantity": float(part.quantity),
            "unit_price": float(part.unit_price),
            "description": part.description or f"قطعه تعمیر - {product.name}",
            "extra_info": {
                "line_type": "part",
                "repair_order_id": repair_order.id,
                "warehouse_id": part.warehouse_id,
                "inventory_tracked": product.track_inventory,
                "movement": "out"  # خروج از انبار
            }
        })
    
    # 3. ایجاد فاکتور از طریق invoice_service
    try:
        invoice_result = create_invoice(
            db=db,
            business_id=business_id,
            user_id=user_id,
            payload=invoice_payload
        )
    except Exception as e:
        logger.error(f"خطا در ایجاد فاکتور تعمیر: {e}")
        raise ApiError(
            "INVOICE_CREATION_FAILED",
            f"خطا در ایجاد فاکتور: {str(e)}",
            http_status=500
        )
    
    # 4. لینک فاکتور به سفارش تعمیر
    repair_invoice = RepairInvoice(
        repair_order_id=repair_order.id,
        document_id=invoice_result["document"]["id"],
        invoice_type="both" if (repair_order.labor_cost > 0 and len(parts) > 0) else (
            "repair_service" if repair_order.labor_cost > 0 else "parts_only"
        ),
    )
    db.add(repair_invoice)
    
    # 5. به‌روزرسانی extra_info سفارش
    if not repair_order.extra_info:
        repair_order.extra_info = {}
    repair_order.extra_info["invoice_document_id"] = invoice_result["document"]["id"]
    repair_order.extra_info["invoice_code"] = invoice_result["document"]["code"]
    
    db.flush()
    
    return {
        "repair_order_id": repair_order.id,
        "document": invoice_result["document"],
        "accounting_summary": {
            "labor_cost": float(repair_order.labor_cost),
            "parts_cost": float(repair_order.parts_cost),
            "final_cost": float(repair_order.final_cost),
            "technician_commission": float(repair_order.technician_commission),
        },
        "message": "فاکتور تعمیر با موفقیت ثبت شد و اسناد حسابداری ایجاد گردید."
    }


def create_receipt_for_repair_payment(
    db: Session,
    business_id: int,
    repair_order_id: int,
    payment_data: Dict[str, Any],
    user_id: int
) -> Dict[str, Any]:
    """
    ثبت سند دریافت برای پرداخت هزینه تعمیر
    
    این تابع یک سند دریافت ایجاد می‌کند:
    - صندوق/بانک (بدهکار)
    - حساب دریافتنی مشتری (بستانکار)
    """
    from app.services.receipt_payment_service import create_receipt_payment
    from adapters.db.repositories.repair_shop_repository import RepairOrderRepository
    
    repo = RepairOrderRepository(db)
    repair_order = repo.get_by_id(repair_order_id, business_id)
    
    if not repair_order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)
    
    # بررسی اینکه فاکتور ایجاد شده باشد
    invoice_repo = RepairInvoiceRepository(db)
    repair_invoice = invoice_repo.get_by_order(repair_order_id)
    
    if not repair_invoice:
        raise ApiError(
            "NO_INVOICE_FOUND",
            "ابتدا باید فاکتور تعمیر ایجاد شود",
            http_status=400
        )
    
    # ساخت payload سند دریافت
    receipt_payload = {
        "document_type": "receipt",
        "document_date": payment_data.get("payment_date", date.today()),
        "currency_id": repair_order.currency_id,
        "description": f"دریافت وجه تعمیر - {repair_order.code}",
        "person_lines": [
            {
                "person_id": repair_order.customer_person_id,
                "amount": float(repair_order.final_cost),
                "description": f"بابت هزینه تعمیر - فاکتور {(repair_order.extra_info or {}).get('invoice_code', '')}"
            }
        ],
        "account_lines": [
            {
                "account_id": payment_data.get("account_id"),  # صندوق یا بانک
                "amount": float(repair_order.final_cost),
                "description": ""
            }
        ],
        "extra_info": {
            "source_type": "repair_shop",
            "repair_order_id": repair_order.id,
            "repair_code": repair_order.code,
        }
    }
    
    # ایجاد سند دریافت
    try:
        receipt_result = create_receipt_payment(
            db=db,
            business_id=business_id,
            user_id=user_id,
            payload=receipt_payload
        )
    except Exception as e:
        logger.error(f"خطا در ایجاد سند دریافت: {e}")
        raise ApiError(
            "RECEIPT_CREATION_FAILED",
            f"خطا در ایجاد سند دریافت: {str(e)}",
            http_status=500
        )
    
    return receipt_result


def get_repair_accounting_summary(
    db: Session,
    business_id: int,
    repair_order_id: int
) -> Dict[str, Any]:
    """دریافت خلاصه حسابداری یک سفارش تعمیر"""
    from adapters.db.repositories.repair_shop_repository import RepairOrderRepository
    
    repo = RepairOrderRepository(db)
    repair_order = repo.get_by_id(repair_order_id, business_id)
    
    if not repair_order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)
    
    # دریافت فاکتور
    invoice_repo = RepairInvoiceRepository(db)
    repair_invoice = invoice_repo.get_by_order(repair_order_id)
    
    invoice_info = None
    if repair_invoice:
        document = db.query(Document).filter(Document.id == repair_invoice.document_id).first()
        if document:
            invoice_info = {
                "document_id": document.id,
                "code": document.code,
                "document_date": document.document_date.isoformat(),
                "type": repair_invoice.invoice_type,
            }
    
    return {
        "repair_order_id": repair_order.id,
        "repair_code": repair_order.code,
        "customer_person_id": repair_order.customer_person_id,
        "costs": {
            "labor_cost": float(repair_order.labor_cost),
            "parts_cost": float(repair_order.parts_cost),
            "final_cost": float(repair_order.final_cost),
            "technician_commission": float(repair_order.technician_commission),
        },
        "invoice": invoice_info,
        "has_invoice": invoice_info is not None,
    }

