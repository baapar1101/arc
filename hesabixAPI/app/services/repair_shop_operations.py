"""
عملیات پیشرفته افزونه مدیریت تعمیرگاه
(تغییر وضعیت، افزودن قطعات، محاسبه هزینه‌ها)
"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Dict, List, Optional
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_

from adapters.db.models.repair_shop import (
    RepairOrder,
    RepairOrderPart,
    RepairOrderStatus,
    RepairTechnician,
)
from adapters.db.models.product import Product
from adapters.db.models.warehouse import Warehouse
from adapters.db.repositories.repair_shop_repository import (
    RepairOrderRepository,
    RepairOrderPartRepository,
    RepairOrderStatusRepository,
)
from app.core.responses import ApiError

logger = logging.getLogger(__name__)


def assign_technician_to_order(
    db: Session,
    business_id: int,
    repair_order_id: int,
    technician_id: int,
    user_id: int
) -> Dict[str, Any]:
    """اختصاص تعمیرکار به سفارش"""
    from app.services.repair_shop_service import get_repair_order
    
    repo = RepairOrderRepository(db)
    order = repo.get_by_id(repair_order_id, business_id)
    
    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)
    
    # بررسی تعمیرکار
    technician = db.query(RepairTechnician).filter(
        and_(
            RepairTechnician.id == technician_id,
            RepairTechnician.business_id == business_id,
            RepairTechnician.is_active == True
        )
    ).first()
    
    if not technician:
        raise ApiError("TECHNICIAN_NOT_FOUND", "تعمیرکار یافت نشد یا غیرفعال است", http_status=404)
    
    # به‌روزرسانی
    order.assigned_technician_id = technician_id
    order.status = "assigned"
    order.updated_at = datetime.utcnow()
    
    # ثبت در تاریخچه
    status_repo = RepairOrderStatusRepository(db)
    status_repo.create({
        "repair_order_id": order.id,
        "status": "assigned",
        "notes": f"اختصاص به تعمیرکار",
        "created_by_user_id": user_id,
    })
    
    db.commit()
    
    return get_repair_order(db, business_id, repair_order_id)


def update_repair_order_status(
    db: Session,
    business_id: int,
    repair_order_id: int,
    new_status: str,
    notes: Optional[str],
    user_id: int,
    send_notification: bool = True
) -> Dict[str, Any]:
    """تغییر وضعیت سفارش تعمیر"""
    from app.services.repair_shop_service import get_repair_order, VALID_STATUSES
    
    if new_status not in VALID_STATUSES:
        raise ApiError("INVALID_STATUS", f"وضعیت نامعتبر: {new_status}", http_status=400)
    
    repo = RepairOrderRepository(db)
    order = repo.get_by_id(repair_order_id, business_id)
    
    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)
    
    old_status = order.status
    
    # به‌روزرسانی وضعیت
    order.status = new_status
    order.updated_at = datetime.utcnow()
    
    # به‌روزرسانی تاریخ‌های مرتبط
    if new_status in ["completed_fixed", "completed_unfixable"]:
        if not order.completed_at:
            order.completed_at = datetime.utcnow()
    
    elif new_status == "delivered":
        if not order.delivered_at:
            order.delivered_at = datetime.utcnow()
    
    # ثبت در تاریخچه
    status_repo = RepairOrderStatusRepository(db)
    status_entry = status_repo.create({
        "repair_order_id": order.id,
        "status": new_status,
        "notes": notes,
        "created_by_user_id": user_id,
    })
    
    db.flush()
    
    # ارسال نوتیفیکیشن (اگر فعال باشد)
    if send_notification:
        from app.services.repair_shop_notification import send_repair_notification
        try:
            # تعیین event_type براساس وضعیت جدید
            event_map = {
                "ready_for_pickup": "repair_shop.ready",
                "completed_fixed": "repair_shop.completed",
                "completed_unfixable": "repair_shop.completed",
                "delivered": "repair_shop.delivered"
            }
            event = event_map.get(new_status, "repair_shop.status_changed")
            
            send_repair_notification(
                db=db,
                business_id=business_id,
                repair_order=order,
                event_type=event,
                triggered_by_user_id=user_id
            )
        except Exception as e:
            logger.error(f"خطا در ارسال نوتیفیکیشن تغییر وضعیت: {e}")
            # ادامه می‌دهیم حتی اگر نوتیفیکیشن ارسال نشد
    
    db.commit()
    
    return get_repair_order(db, business_id, repair_order_id)


def add_parts_to_repair_order(
    db: Session,
    business_id: int,
    repair_order_id: int,
    parts: List[Dict[str, Any]],
    user_id: int
) -> Dict[str, Any]:
    """افزودن قطعات به سفارش تعمیر"""
    from app.services.repair_shop_service import get_repair_order
    from app.services.warehouse_service import get_product_stock
    
    repo = RepairOrderRepository(db)
    order = repo.get_by_id(repair_order_id, business_id)
    
    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)
    
    if not parts or len(parts) == 0:
        raise ApiError("PARTS_REQUIRED", "حداقل یک قطعه باید اضافه شود", http_status=400)
    
    # لیست برای warehouse document
    warehouse_lines = []
    total_parts_cost = Decimal("0")
    
    parts_repo = RepairOrderPartRepository(db)
    
    for part in parts:
        product_id = part.get("product_id")
        quantity = part.get("quantity")
        warehouse_id = part.get("warehouse_id")
        
        if not product_id or not quantity:
            raise ApiError("INVALID_PART_DATA", "اطلاعات قطعه نامعتبر است", http_status=400)
        
        # بررسی محصول
        product = db.query(Product).filter(
            and_(
                Product.id == product_id,
                Product.business_id == business_id
            )
        ).first()
        
        if not product:
            raise ApiError("PRODUCT_NOT_FOUND", f"قطعه با ID {product_id} یافت نشد", http_status=404)
        
        # بررسی موجودی (اگر کالا کنترل موجودی داشته باشد)
        if product.track_inventory and warehouse_id:
            current_stock = get_product_stock(db, business_id, product_id, warehouse_id)
            
            if current_stock < Decimal(str(quantity)):
                raise ApiError(
                    "INSUFFICIENT_STOCK",
                    f"موجودی کافی نیست. موجودی فعلی: {current_stock}، مقدار درخواستی: {quantity}",
                    http_status=409,
                    extra_data={
                        "product_id": product_id,
                        "product_name": product.name,
                        "current_stock": float(current_stock),
                        "requested": float(quantity)
                    }
                )
        
        # قیمت
        unit_price = Decimal(str(part.get("unit_price", 0)))
        if unit_price == 0 and product.price:
            unit_price = product.price
        
        quantity_dec = Decimal(str(quantity))
        total_price = unit_price * quantity_dec
        
        # ایجاد قطعه
        part_data = {
            "repair_order_id": repair_order_id,
            "product_id": product_id,
            "quantity": quantity_dec,
            "unit_price": unit_price,
            "total_price": total_price,
            "warehouse_id": warehouse_id,
            "description": part.get("description"),
        }
        
        parts_repo.create(part_data)
        total_parts_cost += total_price
        
        # اضافه کردن به لیست warehouse
        if product.track_inventory and warehouse_id:
            warehouse_lines.append({
                "product_id": product_id,
                "quantity": float(quantity_dec),
                "warehouse_id": warehouse_id,
                "movement": "out",
                "description": f"قطعات تعمیر - {order.code}"
            })
    
    # به‌روزرسانی هزینه قطعات
    order.parts_cost = total_parts_cost
    order.final_cost = order.labor_cost + total_parts_cost
    order.updated_at = datetime.utcnow()
    
    db.flush()
    
    # ایجاد حواله خروج پیش‌نویس (اگر قطعه‌ای با موجودی وجود داشت)
    if warehouse_lines:
        from app.services.warehouse_service import create_manual_warehouse_document
        
        try:
            warehouse_doc_data = {
                "doc_type": "issue",
                "document_date": datetime.utcnow().date(),
                "status": "draft",
                "warehouse_id_from": warehouse_lines[0]["warehouse_id"],
                "extra_info": {
                    "source_type": "repair_shop",
                    "source_id": order.id,
                    "repair_code": order.code,
                    "description": f"قطعات تعمیر - {order.code}"
                },
                "lines": warehouse_lines
            }
            
            warehouse_doc = create_manual_warehouse_document(
                db=db,
                business_id=business_id,
                user_id=user_id,
                data=warehouse_doc_data
            )
            
            # ذخیره اطلاعات حواله در order
            if not order.extra_info:
                order.extra_info = {}
            order.extra_info["warehouse_document_id"] = warehouse_doc.id
            order.extra_info["warehouse_doc_code"] = warehouse_doc.code
            
        except Exception as e:
            logger.error(f"خطا در ایجاد حواله خروج: {e}")
            # ادامه می‌دهیم، حواله را بعداً دستی ایجاد می‌کنند
    
    db.commit()
    
    return get_repair_order(db, business_id, repair_order_id)


def calculate_repair_costs(
    db: Session,
    business_id: int,
    repair_order_id: int,
    labor_cost: Decimal,
    user_id: int
) -> Dict[str, Any]:
    """محاسبه هزینه‌های نهایی تعمیر"""
    from app.services.repair_shop_service import get_repair_order
    
    repo = RepairOrderRepository(db)
    order = repo.get_by_id(repair_order_id, business_id)
    
    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)
    
    # محاسبه حق‌الزحمه تعمیرکار
    technician_commission = Decimal("0")
    
    if order.assigned_technician_id:
        technician = db.query(RepairTechnician).filter(
            RepairTechnician.id == order.assigned_technician_id
        ).first()
        
        if technician:
            if technician.commission_type == "fixed":
                # مبلغ فیکس
                technician_commission = technician.commission_value
            
            elif technician.commission_type == "percentage":
                # درصد از دستمزد
                technician_commission = (labor_cost * technician.commission_value) / Decimal("100")
            
            # برای case_by_case، باید دستی وارد شود
    
    # به‌روزرسانی
    order.labor_cost = labor_cost
    order.technician_commission = technician_commission
    order.final_cost = order.parts_cost + labor_cost
    order.updated_at = datetime.utcnow()
    
    db.commit()
    
    return {
        "repair_order_id": order.id,
        "parts_cost": float(order.parts_cost),
        "labor_cost": float(order.labor_cost),
        "technician_commission": float(order.technician_commission),
        "final_cost": float(order.final_cost),
    }


def complete_repair_order(
    db: Session,
    business_id: int,
    repair_order_id: int,
    is_fixed: bool,
    user_id: int,
    notes: Optional[str] = None
) -> Dict[str, Any]:
    """اتمام تعمیر و پست حواله"""
    from app.services.repair_shop_service import get_repair_order
    
    repo = RepairOrderRepository(db)
    order = repo.get_by_id(repair_order_id, business_id)
    
    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)
    
    # تعیین وضعیت
    new_status = "completed_fixed" if is_fixed else "completed_unfixable"
    
    # پست حواله خروج (اگر وجود داشته باشد)
    warehouse_doc_id = (order.extra_info or {}).get("warehouse_document_id")
    
    if warehouse_doc_id:
        from app.services.warehouse_service import post_warehouse_document
        
        try:
            post_result = post_warehouse_document(db, warehouse_doc_id)
            
            # به‌روزرسانی اطلاعات
            if not order.extra_info:
                order.extra_info = {}
            order.extra_info["warehouse_posted"] = True
            order.extra_info["warehouse_posted_at"] = datetime.utcnow().isoformat()
            
        except ApiError as e:
            if e.code == "INSUFFICIENT_STOCK":
                # در صورت کمبود موجودی، خطا برگردانده می‌شود
                raise ApiError(
                    "CANNOT_COMPLETE_REPAIR",
                    f"امکان تکمیل تعمیر وجود ندارد: {e.message}",
                    http_status=409,
                    extra_data=e.extra_data
                )
            raise
    
    # تغییر وضعیت
    order.status = new_status
    order.completed_at = datetime.utcnow()
    order.updated_at = datetime.utcnow()
    
    # ثبت در تاریخچه
    status_repo = RepairOrderStatusRepository(db)
    status_repo.create({
        "repair_order_id": order.id,
        "status": new_status,
        "notes": notes or ("تعمیر موفق" if is_fixed else "غیرقابل تعمیر"),
        "created_by_user_id": user_id,
    })
    
    db.commit()
    
    # ارسال پیامک/ایمیل
    from app.services.repair_shop_notification import send_repair_notification
    try:
        event = "repair_shop.ready" if new_status == "ready_for_pickup" else "repair_shop.completed"
        send_repair_notification(
            db=db,
            business_id=business_id,
            repair_order=order,
            event_type=event,
            triggered_by_user_id=user_id
        )
    except Exception as e:
        logger.error(f"خطا در ارسال نوتیفیکیشن اتمام تعمیر: {e}")
    
    return get_repair_order(db, business_id, repair_order_id)


def deliver_repair_order(
    db: Session,
    business_id: int,
    repair_order_id: int,
    user_id: int,
    notes: Optional[str] = None
) -> Dict[str, Any]:
    """تحویل کالا به مشتری"""
    from app.services.repair_shop_service import get_repair_order
    
    repo = RepairOrderRepository(db)
    order = repo.get_by_id(repair_order_id, business_id)
    
    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)
    
    if order.status not in ["completed_fixed", "completed_unfixable", "ready_for_pickup"]:
        raise ApiError(
            "INVALID_STATUS_FOR_DELIVERY",
            f"سفارش در وضعیت {order.status} قابل تحویل نیست",
            http_status=400
        )
    
    # تغییر وضعیت
    order.status = "delivered"
    order.delivered_at = datetime.utcnow()
    order.updated_at = datetime.utcnow()
    
    # ثبت در تاریخچه
    status_repo = RepairOrderStatusRepository(db)
    status_repo.create({
        "repair_order_id": order.id,
        "status": "delivered",
        "notes": notes or "تحویل کالا به مشتری",
        "created_by_user_id": user_id,
    })
    
    db.commit()
    
    return get_repair_order(db, business_id, repair_order_id)


def get_repair_history_by_warranty(
    db: Session,
    business_id: int,
    warranty_code_id: int
) -> List[Dict[str, Any]]:
    """دریافت تاریخچه تعمیرات براساس کد گارانتی"""
    from adapters.db.models.person import Person
    
    orders = db.query(RepairOrder).filter(
        and_(
            RepairOrder.business_id == business_id,
            RepairOrder.warranty_code_id == warranty_code_id
        )
    ).order_by(RepairOrder.received_at.desc()).all()
    
    result = []
    for order in orders:
        customer = db.query(Person).filter(Person.id == order.customer_person_id).first()
        
        result.append({
            "id": order.id,
            "code": order.code,
            "customer_name": customer.name if customer else "",
            "problem_description": order.problem_description,
            "status": order.status,
            "final_cost": float(order.final_cost),
            "received_at": order.received_at.isoformat(),
            "completed_at": order.completed_at.isoformat() if order.completed_at else None,
        })
    
    return result

