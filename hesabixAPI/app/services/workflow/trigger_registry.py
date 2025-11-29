"""
ثبت و مدیریت Trigger Handlers
"""

from abc import ABC, abstractmethod
from typing import Any, Dict, Optional
import logging

logger = logging.getLogger(__name__)


class TriggerHandler(ABC):
    """Base class برای trigger handlers"""
    
    @abstractmethod
    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        """
        اجرای trigger و برگرداندن داده‌های trigger
        
        Args:
            context: context اجرای workflow
            config: تنظیمات trigger
        
        Returns:
            Dict[str, Any]: داده‌های trigger
        """
        pass


class TriggerRegistry:
    """ثبت trigger handlers"""
    
    def __init__(self):
        self._handlers: Dict[str, TriggerHandler] = {}
        self._register_default_triggers()
    
    def register(self, trigger_type: str, handler: TriggerHandler):
        """ثبت یک trigger handler"""
        self._handlers[trigger_type] = handler
        logger.info(f"Registered trigger handler: {trigger_type}")
    
    def get_handler(self, trigger_type: str) -> Optional[TriggerHandler]:
        """دریافت trigger handler"""
        return self._handlers.get(trigger_type)
    
    def list_triggers(self) -> Dict[str, Dict[str, Any]]:
        """لیست تمام triggerهای موجود"""
        result = {}
        for trigger_type, handler in self._handlers.items():
            if hasattr(handler, "get_metadata"):
                result[trigger_type] = handler.get_metadata()
            else:
                result[trigger_type] = {"name": trigger_type}
        return result
    
    def _register_default_triggers(self):
        """ثبت triggerهای پیش‌فرض"""
        from app.services.workflow.triggers import (
            DocumentCreatedTrigger,
            InvoiceCreatedTrigger,
            ReceiptPaymentCreatedTrigger,
            CheckDueDateTrigger,
            InventoryLowTrigger,
            PersonCreatedTrigger,
            ScheduledTrigger,
            WebhookTrigger,
        )
        
        # Document triggers
        self.register("document.created", DocumentCreatedTrigger())
        self.register("invoice.created", InvoiceCreatedTrigger())
        self.register("invoice.sales.created", InvoiceCreatedTrigger())
        self.register("invoice.purchase.created", InvoiceCreatedTrigger())
        
        # Financial triggers
        self.register("receipt_payment.created", ReceiptPaymentCreatedTrigger())
        self.register("check.due_date", CheckDueDateTrigger())
        
        # Inventory triggers
        self.register("inventory.low", InventoryLowTrigger())
        
        # Person triggers
        self.register("person.created", PersonCreatedTrigger())
        
        # Scheduled triggers
        self.register("scheduled", ScheduledTrigger())
        
        # Webhook triggers
        self.register("webhook", WebhookTrigger())

