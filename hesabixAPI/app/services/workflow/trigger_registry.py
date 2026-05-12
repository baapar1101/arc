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

    def get_all_metadata(self) -> list:
        """لیست metadata تمام triggerها به فرمت لیست برای API"""
        result = []
        for trigger_type, metadata in self.list_triggers().items():
            item = dict(metadata)
            item["key"] = trigger_type
            result.append(item)
        return result
    
    def _register_default_triggers(self):
        """ثبت triggerهای پیش‌فرض"""
        from app.services.workflow.triggers import (
            DocumentCreatedTrigger,
            InvoiceCreatedTrigger,
            ReceiptPaymentCreatedTrigger,
            ReceiptPaymentUpdatedTrigger,
            CheckDueDateTrigger,
            InventoryLowTrigger,
            PersonCreatedTrigger,
            ScheduledTrigger,
            WebhookTrigger,
        )
        from app.services.workflow.triggers.document_triggers import (
            DocumentUpdatedTrigger,
            InvoiceUpdatedTrigger,
        )
        from app.services.workflow.triggers.person_triggers import PersonUpdatedTrigger
        from app.services.workflow.triggers.crm_triggers import (
            LeadCreatedTrigger,
            LeadStageChangedTrigger,
            LeadConvertedTrigger,
            LeadAssignedTrigger,
            DealCreatedTrigger,
            DealStageChangedTrigger,
            DealClosedTrigger,
            DealAssignedTrigger,
            ActivityCreatedTrigger,
        )
        
        # Document triggers
        self.register("document.created", DocumentCreatedTrigger())
        self.register("document.updated", DocumentUpdatedTrigger())
        self.register("invoice.created", InvoiceCreatedTrigger())
        self.register("invoice.sales.created", InvoiceCreatedTrigger())
        self.register("invoice.purchase.created", InvoiceCreatedTrigger())
        self.register("invoice.updated", InvoiceUpdatedTrigger())
        self.register("invoice.sales.updated", InvoiceUpdatedTrigger())
        self.register("invoice.purchase.updated", InvoiceUpdatedTrigger())
        
        # Financial triggers
        self.register("receipt_payment.created", ReceiptPaymentCreatedTrigger())
        self.register("receipt_payment.updated", ReceiptPaymentUpdatedTrigger())
        self.register("check.due_date", CheckDueDateTrigger())
        
        # Inventory triggers
        self.register("inventory.low", InventoryLowTrigger())
        
        # Person triggers
        self.register("person.created", PersonCreatedTrigger())
        self.register("person.updated", PersonUpdatedTrigger())
        
        # Scheduled triggers
        self.register("scheduled", ScheduledTrigger())
        
        # Webhook triggers
        self.register("webhook", WebhookTrigger())

        # CRM triggers
        self.register("crm.lead.created", LeadCreatedTrigger())
        self.register("crm.lead.stage_changed", LeadStageChangedTrigger())
        self.register("crm.lead.converted", LeadConvertedTrigger())
        self.register("crm.lead.assigned", LeadAssignedTrigger())
        self.register("crm.deal.created", DealCreatedTrigger())
        self.register("crm.deal.stage_changed", DealStageChangedTrigger())
        self.register("crm.deal.closed", DealClosedTrigger())
        self.register("crm.deal.assigned", DealAssignedTrigger())
        self.register("crm.activity.created", ActivityCreatedTrigger())

        from app.services.workflow.triggers.crm_chat_triggers import (
            ChatConversationStartedTrigger,
            ChatMessageReceivedTrigger,
            ChatMessageSentTrigger,
            ChatConversationAssignedTrigger,
            ChatConversationResolvedTrigger,
            ChatConversationReopenedTrigger,
        )

        self.register("crm.chat.conversation.started", ChatConversationStartedTrigger())
        self.register("crm.chat.message.received", ChatMessageReceivedTrigger())
        self.register("crm.chat.message.sent", ChatMessageSentTrigger())
        self.register("crm.chat.conversation.assigned", ChatConversationAssignedTrigger())
        self.register("crm.chat.conversation.resolved", ChatConversationResolvedTrigger())
        self.register("crm.chat.conversation.reopened", ChatConversationReopenedTrigger())

        from app.services.workflow.triggers.distribution_triggers import DistributionVisitCompletedTrigger

        self.register("distribution.visit.completed", DistributionVisitCompletedTrigger())

        from app.services.workflow.triggers.basalam_triggers import (
            BasalamWebhookReceivedTrigger,
            BasalamOrderCreatedTrigger,
            BasalamOrderUpdatedTrigger,
            BasalamOrderPaidTrigger,
            BasalamChatMessageReceivedTrigger,
        )

        self.register("basalam.webhook.received", BasalamWebhookReceivedTrigger())
        self.register("basalam.order.created", BasalamOrderCreatedTrigger())
        self.register("basalam.order.updated", BasalamOrderUpdatedTrigger())
        self.register("basalam.order.paid", BasalamOrderPaidTrigger())
        self.register("basalam.chat.message.received", BasalamChatMessageReceivedTrigger())

