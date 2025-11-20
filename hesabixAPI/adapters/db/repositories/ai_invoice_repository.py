from typing import Optional, List
from sqlalchemy.orm import Session
from sqlalchemy import and_
from adapters.db.models.ai_invoice import AIInvoice
from adapters.db.repositories.base_repo import BaseRepository


class AIInvoiceRepository(BaseRepository[AIInvoice]):
    def __init__(self, db: Session):
        super().__init__(db, AIInvoice)
    
    def get_by_code(self, code: str) -> Optional[AIInvoice]:
        """دریافت صورتحساب بر اساس کد"""
        return self.db.query(self.model_class).filter(
            self.model_class.code == code
        ).first()
    
    def get_business_invoices(
        self,
        business_id: int,
        invoice_type: Optional[str] = None,
        limit: int = 50,
        skip: int = 0
    ) -> List[AIInvoice]:
        """دریافت صورتحساب‌های یک کسب‌وکار"""
        query = self.db.query(self.model_class).filter(
            self.model_class.business_id == business_id
        )
        
        if invoice_type:
            query = query.filter(self.model_class.invoice_type == invoice_type)
        
        return query.order_by(self.model_class.created_at.desc()).offset(skip).limit(limit).all()
    
    def get_subscription_invoices(
        self,
        subscription_id: int
    ) -> List[AIInvoice]:
        """دریافت صورتحساب‌های یک اشتراک"""
        return self.db.query(self.model_class).filter(
            self.model_class.subscription_id == subscription_id
        ).order_by(self.model_class.created_at.desc()).all()

