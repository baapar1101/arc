from adapters.db.session import Base  # re-export Base for Alembic

# Import models to register with SQLAlchemy metadata
from .user import User  # noqa: F401
from .user_ui_preferences import UserUiPreferences  # noqa: F401
from .business_user_menu_preferences import BusinessUserMenuPreference  # noqa: F401
from .api_key import ApiKey  # noqa: F401
from .captcha import Captcha  # noqa: F401
from .auth_security_event import AuthSecurityEvent  # noqa: F401
from .sms_destination_send_log import SmsDestinationSendLog  # noqa: F401
from .firewall_rule import FirewallRule, FirewallRequestLog, FirewallAuditLog  # noqa: F401
from .firewall_rate_policy import FirewallRatePolicy  # noqa: F401
from .password_reset import PasswordReset  # noqa: F401
from .email_verification import EmailVerificationToken  # noqa: F401
from .mobile_verification import MobileVerificationToken  # noqa: F401
from .otp_login_session import OtpLoginSession  # noqa: F401
from .business import Business  # noqa: F401
from .business_frequent_description import BusinessFrequentDescription  # noqa: F401
from .business_dashboard_layout import (  # noqa: F401
	BusinessUserDashboardLayout,
	BusinessDashboardDefaultLayout,
)
from .business_user_quick_links import BusinessUserQuickLink  # noqa: F401
from .data_table_user_column_settings import DataTableUserColumnSettings  # noqa: F401
from .business_print_settings import BusinessPrintSettings  # noqa: F401
from .business_permission import BusinessPermission  # noqa: F401
from .person import Person, PersonBankAccount, PersonSocialContact  # noqa: F401
from .person_group import PersonGroup  # noqa: F401
from .person_share_link import PersonShareLink  # noqa: F401
from .document_share_link import DocumentShareLink  # noqa: F401
# Business user models removed - using business_permissions instead

# Import support models
from .support import *  # noqa: F401, F403

# Import file storage models
from .file_storage import *

# Import email config models
from .email_config import EmailConfig  # noqa: F401, F403


# Accounting / Fiscal models
from .fiscal_year import FiscalYear  # noqa: F401

# Currency models
from .currency import Currency, BusinessCurrency  # noqa: F401
from .business_currency_rate import BusinessCurrencyRate  # noqa: F401

# Documents
from .document import Document  # noqa: F401
from .document_invoice_tag import DocumentInvoiceTag, DocumentInvoiceTagLink  # noqa: F401
from .report_template_status_event import ReportTemplateStatusEvent  # noqa: F401
from .document_line import DocumentLine  # noqa: F401
from .account import Account  # noqa: F401
from .category import BusinessCategory  # noqa: F401
from .product_attribute import ProductAttribute  # noqa: F401
from .product import Product  # noqa: F401
from .public_catalog_contact_message import PublicCatalogContactMessage  # noqa: F401
from .product_general_barcode_alias import ProductGeneralBarcodeAlias  # noqa: F401
from .product_instance import ProductInstance  # noqa: F401
from .price_list import PriceList, PriceItem  # noqa: F401
from .product_attribute_link import ProductAttributeLink  # noqa: F401
from .tax_unit import TaxUnit  # noqa: F401
from .product_tax_code import ProductTaxCode  # noqa: F401
from .tax_type import TaxType  # noqa: F401
from .tax_setting import TaxSetting  # noqa: F401
from .bank_account import BankAccount  # noqa: F401
from .cash_register import CashRegister  # noqa: F401
from .petty_cash import PettyCash  # noqa: F401
from .received_loan_facility import (  # noqa: F401
	ReceivedLoanFacility,
	ReceivedLoanInstallment,
	ReceivedLoanInstallmentPayment,
)
from .check import Check  # noqa: F401
from .warehouse import Warehouse  # noqa: F401
from .warehouse_location import WarehouseLocation  # noqa: F401
from .warehouse_product_placement import WarehouseProductPlacement  # noqa: F401
from .warehouse_document import WarehouseDocument  # noqa: F401
from .warehouse_document_line import WarehouseDocumentLine  # noqa: F401
from .product_bom import ProductBOM, ProductBOMItem, ProductBOMOutput, ProductBOMOperation  # noqa: F401
from .ping_pong_score import PingPongScore  # noqa: F401
from .storage_plan import StoragePlan, BusinessStorageSubscription, StorageInvoice, StorageUsageTransaction  # noqa: F401
from .document_monetization import (  # noqa: F401
	DocumentSubscriptionPlan,
	BusinessDocumentSubscription,
	DocumentUsagePolicy,
	DocumentUsageCharge,
	DocumentUsagePeriod,
	DocumentUsageCursor,
)
# Wallet models
from .wallet import WalletAccount, WalletTransaction, WalletPayout, WalletSetting  # noqa: F401
from .business_backup_import_log import BusinessBackupImportLog  # noqa: F401
# AI models
from .ai_config import AIConfig, AIProvider  # noqa: F401
from .ai_plan import AIPlan, AIPlanType  # noqa: F401
from .ai_subscription import UserAISubscription, SubscriptionType  # noqa: F401
from .ai_invoice import AIInvoice, AIInvoiceType, AIInvoiceStatus  # noqa: F401
from .ai_usage_log import AIUsageLog, PaymentMethod  # noqa: F401
from .ai_chat_session import AIChatSession  # noqa: F401
from .ai_chat_message import AIChatMessage, MessageRole  # noqa: F401
from .ai_business_memory import AIBusinessMemory  # noqa: F401
from .ai_chat_attachment import AIChatAttachment  # noqa: F401
from .ai_knowledge_document import AIKnowledgeDocument  # noqa: F401
from .ai_knowledge_chunk import AIKnowledgeChunk  # noqa: F401
from .ai_eval_case import AIEvalCase  # noqa: F401
from .ai_eval_run import AIEvalRun  # noqa: F401
from .ai_eval_result import AIEvalResult  # noqa: F401
from .ai_connector import AIConnector  # noqa: F401
from .ai_message_feedback import AIMessageFeedback  # noqa: F401
from .ai_eval_schedule import AIEvalSchedule  # noqa: F401
from .ai_prompt import AIPrompt, PromptRole, PromptType  # noqa: F401
from .ai_voice_interaction import AIVoiceInteraction  # noqa: F401
# Activity Log models
from .activity_log import ActivityLog  # noqa: F401
from .admin_script_run import AdminScriptRun, AdminScriptRunLog  # noqa: F401
# Workflow models
from .workflow import (  # noqa: F401
    Workflow,
    WorkflowStatus,
    WorkflowExecution,
    WorkflowExecutionStatus,
    WorkflowLog,
    WorkflowLogLevel,
    WorkflowNodeType,
)
from .workflow_marketplace import (  # noqa: F401
    WorkflowMarketplacePackage,
    WorkflowMarketplaceInstall,
    WorkflowMarketplacePackageStatus,
)
# Monitoring models
from .monitoring import MonitoringMetric, MonitoringServiceStatus, MonitoringAlert  # noqa: F401
# Zohal service models
from .zohal import ZohalService, ZohalServiceLog  # noqa: F401
# Warranty models
from .warranty import (  # noqa: F401
    WarrantySetting,
    WarrantyCode,
    WarrantyActivation,
    WarrantyTracking,
    WarrantyTrackingLink,
)
# Project models
from .project import Project  # noqa: F401
# Bale messenger linking
from .bale import BaleLinkToken  # noqa: F401
from .messenger_operator_session import MessengerOperatorSession  # noqa: F401
from .business_ftp_backup_setting import BusinessFtpBackupSetting  # noqa: F401
from .business_crm_settings import BusinessCrmSettings  # noqa: F401
# CRM
from .crm import (  # noqa: F401
    CrmProcessDefinition,
    CrmProcessStage,
    Lead,
    Deal,
    CrmActivity,
    CrmChangeHistory,
    CrmNoteType,
    CrmNote,
    CrmNoteAclUser,
    CrmNoteComment,
    CrmNoteAuditEvent,
)
from .customer_club import (  # noqa: F401
	CustomerClubSettings,
	CustomerClubBalance,
	CustomerClubLedger,
	CustomerClubInvoiceSnapshot,
	CustomerClubTier,
	CustomerClubRfmSnapshot,
)
from .distribution import (  # noqa: F401
	DistributionBusinessSettings,
	DistributionTerritory,
	DistributionRoute,
	DistributionRouteStop,
	DistributionRouteAssignment,
	DistributionFieldVisit,
	DistributionReturnRequest,
	DistributionVan,
	DistributionOfflineSyncBatch,
)