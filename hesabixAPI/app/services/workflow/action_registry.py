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
            SendBusinessSmsAction,
            HttpRequestAction,
            SetVariableAction,
            LogAction,
            AIAgentAction,
        )
        from app.services.workflow.actions.crm_actions import (
            CreateLeadAction,
            CreateDealAction,
            CreateCrmActivityAction,
            UpdateLeadAction,
            UpdateDealAction,
            CrmLinkDealDocumentAction,
            CrmWebChatSendMessageAction,
        )
        from app.services.workflow.actions.basalam_actions import (
            BasalamSendChatReplyAction,
            BasalamSyncOrdersAction,
            BasalamSyncProductsAction,
            BasalamPullProductsAction,
            BasalamPushProductsIncrementalAction,
            BasalamPublishProductsAction,
            BasalamRetryProductPublishQueueAction,
            BasalamListSyncDeadLetterAction,
            BasalamClearSyncDeadLetterAction,
        )
        from app.services.workflow.actions.backup_action import BusinessBackupAction
        from app.services.workflow.actions.hesabix_query_actions import (
            QueryPersonsAction,
            QueryPersonAction,
            QueryProductsAction,
            QueryProductAction,
            QueryDocumentsAction,
            QueryDocumentAction,
            QueryInvoicesAction,
            QueryReceiptsPaymentsAction,
            QueryWarehouseDocumentsAction,
        )
        from app.services.workflow.actions.flow_control_actions import (
            WaitAction,
            CodeExpressionAction,
            SubWorkflowAction,
        )
        from app.services.workflow.actions.merge_split_actions import (
            MergeDataAction,
            SplitInBatchesAction,
        )
        
        # Communication actions
        self.register("send_email", SendEmailAction())
        self.register("send_telegram", SendTelegramAction())
        self.register("send_bale", SendBaleAction())
        self.register("create_notification", CreateNotificationAction())
        self.register("send_business_sms", SendBusinessSmsAction())
        
        # Document actions
        self.register("create_document", CreateDocumentAction())
        self.register("create_invoice", CreateInvoiceAction())
        
        # Inventory actions
        self.register("update_inventory", UpdateInventoryAction())
        
        # CRM actions
        self.register("crm_create_lead", CreateLeadAction())
        self.register("crm_create_deal", CreateDealAction())
        self.register("crm_create_activity", CreateCrmActivityAction())
        self.register("crm_update_lead", UpdateLeadAction())
        self.register("crm_update_deal", UpdateDealAction())
        self.register("crm_link_deal_document", CrmLinkDealDocumentAction())
        self.register("crm_web_chat_send_message", CrmWebChatSendMessageAction())

        # Basalam integration
        self.register("basalam_send_chat_reply", BasalamSendChatReplyAction())
        self.register("basalam_sync_orders", BasalamSyncOrdersAction())
        self.register("basalam_sync_products", BasalamSyncProductsAction())
        self.register("basalam_pull_products", BasalamPullProductsAction())
        self.register("basalam_push_products_incremental", BasalamPushProductsIncrementalAction())
        self.register("basalam_publish_products", BasalamPublishProductsAction())
        self.register("basalam_retry_product_publish_queue", BasalamRetryProductPublishQueueAction())
        self.register("basalam_list_sync_dead_letter", BasalamListSyncDeadLetterAction())
        self.register("basalam_clear_sync_dead_letter", BasalamClearSyncDeadLetterAction())

        # HTTP actions
        self.register("http_request", HttpRequestAction())
        
        # Utility actions
        self.register("set_variable", SetVariableAction())
        self.register("log", LogAction())
        self.register("business_backup", BusinessBackupAction())

        # AI Agent
        self.register("ai_agent", AIAgentAction())

        # Hesabix data / query
        self.register("query_persons", QueryPersonsAction())
        self.register("query_person", QueryPersonAction())
        self.register("query_products", QueryProductsAction())
        self.register("query_product", QueryProductAction())
        self.register("query_documents", QueryDocumentsAction())
        self.register("query_document", QueryDocumentAction())
        self.register("query_invoices", QueryInvoicesAction())
        self.register("query_receipts_payments", QueryReceiptsPaymentsAction())
        self.register("query_warehouse_documents", QueryWarehouseDocumentsAction())

        # Flow control
        self.register("wait", WaitAction())
        self.register("code_expression", CodeExpressionAction())
        self.register("sub_workflow", SubWorkflowAction())
        self.register("merge_data", MergeDataAction())
        self.register("split_in_batches", SplitInBatchesAction())

