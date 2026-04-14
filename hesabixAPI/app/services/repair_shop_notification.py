"""
سرویس ارسال نوتیفیکیشن برای افزونه مدیریت تعمیرگاه

این سرویس از سیستم نوتیفیکیشن جامع استفاده می‌کند
"""
from __future__ import annotations

import logging
from typing import Any, Dict, Optional
from datetime import datetime

from sqlalchemy.orm import Session

from adapters.db.models.person import Person
from adapters.db.models.repair_shop import RepairOrder
from adapters.db.models.business import Business
from app.services.business_notification_service import BusinessNotificationService

logger = logging.getLogger(__name__)


class RepairShopNotificationService:
    """سرویس ارسال نوتیفیکیشن برای تعمیرگاه"""
    
    def __init__(self, db: Session):
        self.db = db
        self.notification_service = BusinessNotificationService(db)
    
    def _get_status_label(self, status: str) -> str:
        """برگرداندن برچسب فارسی وضعیت"""
        status_labels = {
            "received": "دریافت شده",
            "assigned": "اختصاص داده شده",
            "in_progress": "در حال تعمیر",
            "waiting_parts": "منتظر قطعات",
            "testing": "در حال تست",
            "completed_fixed": "تعمیر موفق",
            "completed_unfixable": "غیرقابل تعمیر",
            "ready_for_pickup": "آماده تحویل",
            "delivered": "تحویل داده شده",
            "cancelled": "لغو شده",
        }
        return status_labels.get(status, status)
    
    def send_to_customer(
        self,
        business_id: int,
        repair_order: RepairOrder,
        event_type: str,
        triggered_by_user_id: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        ارسال نوتیفیکیشن به مشتری با استفاده از سیستم جامع
        
        Args:
            business_id: شناسه کسب‌وکار
            repair_order: سفارش تعمیر
            event_type: نوع رویداد (repair_shop.received, repair_shop.ready, ...)
            triggered_by_user_id: کاربری که این عملیات را انجام داده
        
        Returns:
            نتیجه ارسال
        """
        # دریافت مشتری
        customer = self.db.query(Person).filter(Person.id == repair_order.customer_person_id).first()
        if not customer:
            logger.warning(f"Customer not found for repair order {repair_order.id}")
            return {"success": False, "error": "مشتری یافت نشد"}
        
        # دریافت کسب‌وکار
        business = self.db.query(Business).filter(Business.id == business_id).first()
        
        # ساخت context برای قالب
        context = {
            "repair_code": repair_order.code,
            "customer_name": customer.name,
            "product_name": repair_order.product_name,
            "product_serial": repair_order.product_serial or "",
            "status": self._get_status_label(repair_order.status),
            "business_name": business.name if business else "",
            "business_phone": business.phone if business else "",
        }
        
        if repair_order.received_at:
            context["received_date"] = repair_order.received_at.strftime("%Y/%m/%d")
        
        if repair_order.estimated_delivery_at:
            context["estimated_delivery"] = repair_order.estimated_delivery_at.strftime("%Y/%m/%d")
        
        if repair_order.final_cost > 0:
            context["final_cost"] = float(repair_order.final_cost)
        
        # ارسال از طریق سیستم جامع
        return self.notification_service.send_to_person(
            business_id=business_id,
            person_id=customer.id,
            event_type=event_type,
            context=context,
            channel=None,  # ارسال به همه کانال‌های فعال
            triggered_by_user_id=triggered_by_user_id
        )
    
    


def send_repair_notification(
    db: Session,
    business_id: int,
    repair_order: RepairOrder,
    event_type: str,
    triggered_by_user_id: Optional[int] = None
) -> Dict[str, Any]:
    """
    تابع helper برای ارسال نوتیفیکیشن تعمیرگاه
    
    Args:
        db: Session دیتابیس
        business_id: شناسه کسب‌وکار
        repair_order: سفارش تعمیر
        event_type: نوع رویداد (repair_shop.received, repair_shop.ready, ...)
        triggered_by_user_id: کاربر trigger کننده
    
    Returns:
        نتیجه ارسال از سیستم جامع
    """
    service = RepairShopNotificationService(db)
    
    return service.send_to_customer(
        business_id=business_id,
        repair_order=repair_order,
        event_type=event_type,
        triggered_by_user_id=triggered_by_user_id
    )

