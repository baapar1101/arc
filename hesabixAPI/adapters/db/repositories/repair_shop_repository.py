"""
Repository برای افزونه مدیریت تعمیرگاه
"""
from typing import Any, Dict, List, Optional
from datetime import datetime, date

from sqlalchemy import and_, or_, desc, func
from sqlalchemy.orm import Session

from adapters.db.models.repair_shop import (
    RepairShopSettings,
    RepairTechnician,
    RepairOrder,
    RepairOrderPart,
    RepairOrderStatus,
    RepairOrderAttachment,
    RepairInvoice,
)


class RepairShopSettingsRepository:
    """Repository برای تنظیمات تعمیرگاه"""
    
    def __init__(self, db: Session):
        self.db = db
        self.model_class = RepairShopSettings
    
    def get_by_business(self, business_id: int) -> Optional[RepairShopSettings]:
        """دریافت تنظیمات یک کسب‌وکار"""
        return self.db.query(self.model_class).filter(
            self.model_class.business_id == business_id
        ).first()
    
    def create_or_update(self, business_id: int, data: Dict[str, Any]) -> RepairShopSettings:
        """ایجاد یا به‌روزرسانی تنظیمات"""
        existing = self.get_by_business(business_id)
        
        if existing:
            for key, value in data.items():
                if hasattr(existing, key):
                    setattr(existing, key, value)
            existing.updated_at = datetime.utcnow()
            self.db.flush()
            return existing
        else:
            settings = RepairShopSettings(
                business_id=business_id,
                **data
            )
            self.db.add(settings)
            self.db.flush()
            return settings


class RepairTechnicianRepository:
    """Repository برای تعمیرکاران"""
    
    def __init__(self, db: Session):
        self.db = db
        self.model_class = RepairTechnician
    
    def get_by_id(self, technician_id: int, business_id: int) -> Optional[RepairTechnician]:
        """دریافت تعمیرکار با ID"""
        return self.db.query(self.model_class).filter(
            and_(
                self.model_class.id == technician_id,
                self.model_class.business_id == business_id
            )
        ).first()
    
    def get_by_code(self, code: str, business_id: int) -> Optional[RepairTechnician]:
        """دریافت تعمیرکار با کد"""
        return self.db.query(self.model_class).filter(
            and_(
                self.model_class.code == code,
                self.model_class.business_id == business_id
            )
        ).first()
    
    def list_by_business(
        self,
        business_id: int,
        only_active: bool = True,
        offset: int = 0,
        limit: int = 100
    ) -> List[RepairTechnician]:
        """لیست تعمیرکاران یک کسب‌وکار"""
        query = self.db.query(self.model_class).filter(
            self.model_class.business_id == business_id
        )
        
        if only_active:
            query = query.filter(self.model_class.is_active == True)
        
        query = query.order_by(self.model_class.created_at.desc())
        query = query.offset(offset).limit(limit)
        
        return query.all()
    
    def create(self, data: Dict[str, Any]) -> RepairTechnician:
        """ایجاد تعمیرکار جدید"""
        technician = RepairTechnician(**data)
        self.db.add(technician)
        self.db.flush()
        return technician
    
    def update(self, technician: RepairTechnician, data: Dict[str, Any]) -> RepairTechnician:
        """به‌روزرسانی تعمیرکار"""
        for key, value in data.items():
            if hasattr(technician, key):
                setattr(technician, key, value)
        technician.updated_at = datetime.utcnow()
        self.db.flush()
        return technician


class RepairOrderRepository:
    """Repository برای سفارشات تعمیر"""
    
    def __init__(self, db: Session):
        self.db = db
        self.model_class = RepairOrder
    
    def get_by_id(self, order_id: int, business_id: int) -> Optional[RepairOrder]:
        """دریافت سفارش با ID"""
        return self.db.query(self.model_class).filter(
            and_(
                self.model_class.id == order_id,
                self.model_class.business_id == business_id
            )
        ).first()
    
    def get_by_code(self, code: str, business_id: int) -> Optional[RepairOrder]:
        """دریافت سفارش با کد"""
        return self.db.query(self.model_class).filter(
            and_(
                self.model_class.code == code,
                self.model_class.business_id == business_id
            )
        ).first()
    
    def list_by_business(
        self,
        business_id: int,
        filters: Optional[Dict[str, Any]] = None,
        offset: int = 0,
        limit: int = 50
    ) -> tuple[List[RepairOrder], int]:
        """لیست سفارشات با فیلتر"""
        from adapters.db.models.person import Person
        
        query = self.db.query(self.model_class).filter(
            self.model_class.business_id == business_id
        )
        
        # اعمال فیلترها
        if filters:
            if filters.get("status"):
                query = query.filter(self.model_class.status == filters["status"])
            
            if filters.get("customer_person_id"):
                query = query.filter(
                    self.model_class.customer_person_id == filters["customer_person_id"]
                )
            
            if filters.get("assigned_technician_id"):
                query = query.filter(
                    self.model_class.assigned_technician_id == filters["assigned_technician_id"]
                )
            
            if filters.get("warranty_code_id"):
                query = query.filter(
                    self.model_class.warranty_code_id == filters["warranty_code_id"]
                )
            
            if filters.get("from_date"):
                query = query.filter(
                    self.model_class.received_at >= filters["from_date"]
                )
            
            if filters.get("to_date"):
                query = query.filter(
                    self.model_class.received_at <= filters["to_date"]
                )
            
            if filters.get("search"):
                search_term = f"%{filters['search']}%"
                # جستجو در اطلاعات سفارش و اطلاعات مشتری (با join به Person)
                query = query.join(
                    Person, 
                    self.model_class.customer_person_id == Person.id
                ).filter(
                    or_(
                        self.model_class.code.like(search_term),
                        self.model_class.product_name.like(search_term),
                        self.model_class.product_serial.like(search_term),
                        Person.name.like(search_term),
                        Person.mobile.like(search_term),
                        Person.mobile_2.like(search_term),
                        Person.mobile_3.like(search_term),
                        Person.phone.like(search_term),
                        Person.email.like(search_term)
                    )
                )
        
        # شمارش کل
        total = query.count()
        
        # مرتب‌سازی و صفحه‌بندی
        query = query.order_by(self.model_class.received_at.desc())
        query = query.offset(offset).limit(limit)
        
        return query.all(), total
    
    def get_next_sequential_number(self, business_id: int, prefix: str, year: int) -> int:
        """دریافت شماره ترتیبی بعدی"""
        like_pattern = f"{prefix}-{year}-%"
        
        last = self.db.query(self.model_class).filter(
            and_(
                self.model_class.business_id == business_id,
                self.model_class.code.like(like_pattern)
            )
        ).order_by(self.model_class.id.desc()).first()
        
        if last and last.code.startswith(f"{prefix}-{year}-"):
            try:
                last_number = int(last.code.split("-")[-1])
                return last_number + 1
            except:
                return 1
        
        return 1
    
    def create(self, data: Dict[str, Any]) -> RepairOrder:
        """ایجاد سفارش جدید"""
        order = RepairOrder(**data)
        self.db.add(order)
        self.db.flush()
        return order
    
    def update(self, order: RepairOrder, data: Dict[str, Any]) -> RepairOrder:
        """به‌روزرسانی سفارش"""
        for key, value in data.items():
            if hasattr(order, key):
                setattr(order, key, value)
        order.updated_at = datetime.utcnow()
        self.db.flush()
        return order
    
    def delete(self, order: RepairOrder) -> None:
        """حذف سفارش"""
        self.db.delete(order)
        self.db.flush()


class RepairOrderPartRepository:
    """Repository برای قطعات سفارش تعمیر"""
    
    def __init__(self, db: Session):
        self.db = db
        self.model_class = RepairOrderPart
    
    def list_by_order(self, repair_order_id: int) -> List[RepairOrderPart]:
        """لیست قطعات یک سفارش"""
        return self.db.query(self.model_class).filter(
            self.model_class.repair_order_id == repair_order_id
        ).all()
    
    def create(self, data: Dict[str, Any]) -> RepairOrderPart:
        """ایجاد قطعه جدید"""
        part = RepairOrderPart(**data)
        self.db.add(part)
        self.db.flush()
        return part
    
    def delete_by_order(self, repair_order_id: int) -> None:
        """حذف تمام قطعات یک سفارش"""
        self.db.query(self.model_class).filter(
            self.model_class.repair_order_id == repair_order_id
        ).delete()
        self.db.flush()


class RepairOrderStatusRepository:
    """Repository برای تاریخچه وضعیت‌ها"""
    
    def __init__(self, db: Session):
        self.db = db
        self.model_class = RepairOrderStatus
    
    def list_by_order(self, repair_order_id: int) -> List[RepairOrderStatus]:
        """لیست تاریخچه وضعیت‌های یک سفارش"""
        return self.db.query(self.model_class).filter(
            self.model_class.repair_order_id == repair_order_id
        ).order_by(self.model_class.created_at.desc()).all()
    
    def create(self, data: Dict[str, Any]) -> RepairOrderStatus:
        """ثبت تغییر وضعیت"""
        status = RepairOrderStatus(**data)
        self.db.add(status)
        self.db.flush()
        return status


class RepairOrderAttachmentRepository:
    """Repository برای ضمائم سفارش تعمیر"""
    
    def __init__(self, db: Session):
        self.db = db
        self.model_class = RepairOrderAttachment
    
    def list_by_order(
        self,
        repair_order_id: int,
        attachment_type: Optional[str] = None
    ) -> List[RepairOrderAttachment]:
        """لیست ضمائم یک سفارش"""
        query = self.db.query(self.model_class).filter(
            self.model_class.repair_order_id == repair_order_id
        )
        
        if attachment_type:
            query = query.filter(self.model_class.attachment_type == attachment_type)
        
        return query.order_by(self.model_class.created_at.desc()).all()
    
    def create(self, data: Dict[str, Any]) -> RepairOrderAttachment:
        """ایجاد ضمیمه جدید"""
        attachment = RepairOrderAttachment(**data)
        self.db.add(attachment)
        self.db.flush()
        return attachment
    
    def delete(self, attachment: RepairOrderAttachment) -> None:
        """حذف ضمیمه"""
        self.db.delete(attachment)
        self.db.flush()


class RepairInvoiceRepository:
    """Repository برای لینک به فاکتورها"""
    
    def __init__(self, db: Session):
        self.db = db
        self.model_class = RepairInvoice
    
    def get_by_order(self, repair_order_id: int) -> Optional[RepairInvoice]:
        """دریافت فاکتور مرتبط با سفارش"""
        return self.db.query(self.model_class).filter(
            self.model_class.repair_order_id == repair_order_id
        ).first()
    
    def create(self, data: Dict[str, Any]) -> RepairInvoice:
        """ایجاد لینک به فاکتور"""
        invoice = RepairInvoice(**data)
        self.db.add(invoice)
        self.db.flush()
        return invoice

