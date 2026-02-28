"""
ثبت و مدیریت Action Handlers
"""

from abc import ABC, abstractmethod
from typing import Any, Dict, Optional
import logging

logger = logging.getLogger(__name__)


class ActionHandler(ABC):
    """Base class برای action handlers"""
    
    @abstractmethod
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        اجرای action
        
        Args:
            context: context اجرای workflow
            config: تنظیمات action
            node_results: نتایج nodeهای قبلی
        
        Returns:
            Dict[str, Any]: نتیجه action
        """
        pass


class ActionRegistry:
    """ثبت action handlers"""
    
    def __init__(self):
        self._handlers: Dict[str, ActionHandler] = {}
        self._register_default_actions()
    
    def register(self, action_type: str, handler: ActionHandler):
        """ثبت یک action handler"""
        self._handlers[action_type] = handler
        logger.info(f"Registered action handler: {action_type}")
    
    def get_handler(self, action_type: str) -> Optional[ActionHandler]:
        """دریافت action handler"""
        return self._handlers.get(action_type)
    
    def list_actions(self) -> Dict[str, Dict[str, Any]]:
        """لیست تمام actionهای موجود"""
        result = {}
        for action_type, handler in self._handlers.items():
            if hasattr(handler, "get_metadata"):
                result[action_type] = handler.get_metadata()
            else:
                result[action_type] = {"name": action_type}
        return result

    def get_all_metadata(self) -> list:
        """لیست metadata تمام actionها به فرمت لیست برای API"""
        result = []
        for action_type, metadata in self.list_actions().items():
            item = dict(metadata)
            item["key"] = action_type
            result.append(item)
        return result
    
    def _register_default_actions(self):
        """ثبت actionهای پیش‌فرض"""
        from app.services.workflow.actions import (
            SendEmailAction,
            SendTelegramAction,
            SendBaleAction,
            CreateDocumentAction,
            CreateInvoiceAction,
            UpdateInventoryAction,
            CreateNotificationAction,
            HttpRequestAction,
            SetVariableAction,
            LogAction,
            AIAgentAction,
        )
        
        # Communication actions
        self.register("send_email", SendEmailAction())
        self.register("send_telegram", SendTelegramAction())
        self.register("send_bale", SendBaleAction())
        self.register("create_notification", CreateNotificationAction())
        
        # Document actions
        self.register("create_document", CreateDocumentAction())
        self.register("create_invoice", CreateInvoiceAction())
        
        # Inventory actions
        self.register("update_inventory", UpdateInventoryAction())
        
        # HTTP actions
        self.register("http_request", HttpRequestAction())
        
        # Utility actions
        self.register("set_variable", SetVariableAction())
        self.register("log", LogAction())

        # AI Agent
        self.register("ai_agent", AIAgentAction())

