"""کاتالوگ Metadata ابزارهای AI — منبع حقیقت Discovery / Intent / Alias.

Handler و JSON Schema در Registry ثبت می‌شوند.
این ماژول طبقه‌بندی پایدار را نگه می‌دارد و هنگام bind روی AIFunction کپی می‌شود.
هر Tool ثبت‌شده باید یک ورودی داشته باشد.
"""
from __future__ import annotations

from typing import Any, Dict, Optional, Tuple

from app.services.ai.ai_permission_policy import permission_policy_for_name
from app.services.ai.ai_tool_capability import (
    namespace_for_capability,
    resolve_tool_capability,
)
from app.services.ai.ai_tool_search_meta import search_meta_for
from app.services.ai.ai_tool_spec import (
    ToolManifestEntry,
    infer_side_effect,
)

TOOL_MANIFEST: Dict[str, Dict[str, Any]] = {
    'list_crm_process_definitions': {'domains': ('crm',)},
    'get_crm_process_definition': {'domains': ('crm',)},
    'create_crm_process_definition': {'domains': ('crm',), 'intent_write': True},
    'update_crm_process_definition': {'domains': ('crm',), 'intent_write': True},
    'delete_crm_process_definition': {'domains': ('crm',), 'intent_write': True, 'always_confirm': True},
    'list_crm_process_stages': {'domains': ('crm',)},
    'create_crm_process_stage': {'domains': ('crm',), 'intent_write': True},
    'update_crm_process_stage': {'domains': ('crm',), 'intent_write': True},
    'delete_crm_process_stage': {'domains': ('crm',), 'intent_write': True, 'always_confirm': True},
    'get_crm_lead_history': {'domains': ('crm',)},
    'get_crm_deal_history': {'domains': ('crm',)},
    'get_crm_customer_360': {'domains': ('crm',)},
    'get_crm_my_work_queue': {'domains': ('crm',)},
    'get_crm_follow_ups': {'domains': ('crm',)},
    'get_crm_pipeline_report': {'domains': ('crm',)},
    'get_crm_lead_sources_report': {'domains': ('crm',)},
    'get_crm_weighted_forecast': {'domains': ('crm',)},
    'get_crm_sales_trend': {'domains': ('crm',)},
    'get_crm_employee_performance': {'domains': ('crm',)},
    'get_crm_lost_reasons_report': {'domains': ('crm',)},
    'get_crm_won_reasons_report': {'domains': ('crm',)},
    'get_invoice_installments': {'domains': ('invoices',)},
    'search_invoice_installments': {'domains': ('invoices',)},
    'calculate_invoice_balances': {'domains': ('invoices',)},
    'list_invoice_tags': {'domains': ('invoices',)},
    'create_invoice_tag': {'domains': ('invoices',), 'intent_write': True},
    'update_invoice_tag': {'domains': ('invoices',), 'intent_write': True},
    'get_invoice_share_link': {'domains': ('invoices',)},
    'create_invoice_share_link': {'domains': ('invoices',), 'intent_write': True, 'always_confirm': True},
    'revoke_invoice_share_link': {'domains': ('invoices',), 'intent_write': True, 'always_confirm': True},
    'update_invoice_share_link_payment': {'domains': ('invoices',), 'intent_write': True, 'always_confirm': True},
    'get_invoice_delete_impact': {'domains': ('invoices',)},
    'bulk_delete_invoices': {'domains': ('invoices',), 'intent_write': True, 'always_confirm': True},
    'bulk_upsert_invoices': {'domains': ('invoices',), 'intent_write': True, 'always_confirm': True},
    'endorse_check': {'domains': ('checks',), 'intent_write': True, 'always_confirm': True},
    'clear_check': {'domains': ('checks',), 'intent_write': True, 'always_confirm': True},
    'return_check': {'domains': ('checks',), 'intent_write': True, 'always_confirm': True},
    'bounce_check': {'domains': ('checks',), 'intent_write': True, 'always_confirm': True},
    'pay_check': {'domains': ('checks',), 'intent_write': True, 'always_confirm': True},
    'deposit_check': {'domains': ('checks',), 'intent_write': True, 'always_confirm': True},
    'get_check_history': {'domains': ('checks',)},
    'calculate_checks_reconciliation': {'domains': ('checks',)},
    'create_checks_reconciliation': {'domains': ('checks',), 'intent_write': True},
    'list_checks_reconciliations': {'domains': ('checks',)},
    'get_checks_reconciliation': {'domains': ('checks',)},
    'delete_checks_reconciliation': {'domains': ('checks',), 'intent_write': True, 'always_confirm': True},
    'start_stock_count': {'domains': ('warehouse',)},
    'calculate_stock_count_differences': {'domains': ('warehouse',)},
    'create_stock_count_adjustment': {'domains': ('warehouse',), 'intent_write': True, 'always_confirm': True},
    'list_crm_note_types': {'domains': ('crm',)},
    'create_crm_note_type': {'domains': ('crm',), 'intent_write': True},
    'update_crm_note_type': {'domains': ('crm',), 'intent_write': True},
    'delete_crm_note_type': {'domains': ('crm',), 'intent_write': True, 'always_confirm': True},
    'get_crm_note_audit': {'domains': ('crm',)},
    'list_crm_notes': {'domains': ('crm',)},
    'get_crm_note': {'domains': ('crm',)},
    'create_crm_note': {'domains': ('crm',), 'intent_write': True},
    'update_crm_note': {'domains': ('crm',), 'intent_write': True},
    'delete_crm_note': {'domains': ('crm',), 'intent_write': True, 'always_confirm': True},
    'list_crm_note_comments': {'domains': ('crm',)},
    'add_crm_note_comment': {'domains': ('crm',), 'intent_write': True},
    'delete_crm_note_comment': {'domains': ('crm',), 'intent_write': True, 'always_confirm': True},
    'list_crm_tags': {'domains': ('crm',)},
    'create_crm_tag': {'domains': ('crm',), 'intent_write': True},
    'update_crm_tag': {'domains': ('crm',), 'intent_write': True},
    'delete_crm_tag': {'domains': ('crm',), 'intent_write': True, 'always_confirm': True},
    'set_crm_lead_tags': {'domains': ('crm',), 'intent_write': True},
    'set_crm_deal_tags': {'domains': ('crm',), 'intent_write': True},
    'list_crm_close_reasons': {'domains': ('crm',)},
    'create_crm_close_reason': {'domains': ('crm',), 'intent_write': True},
    'update_crm_close_reason': {'domains': ('crm',), 'intent_write': True},
    'delete_crm_close_reason': {'domains': ('crm',), 'intent_write': True, 'always_confirm': True},
    'list_crm_custom_fields': {'domains': ('crm',)},
    'create_crm_custom_field': {'domains': ('crm',), 'intent_write': True},
    'update_crm_custom_field': {'domains': ('crm',), 'intent_write': True},
    'delete_crm_custom_field': {'domains': ('crm',), 'intent_write': True, 'always_confirm': True},
    'adjust_customer_club_points': {
        'domains': ('customer_club',),
        'intent_write': True,
        'always_confirm': True,
    },
    'await_subagent': {
        'domains': ('agent',),
    },
    'batch_query_business_data': {
        'domains': ('query', 'reports_meta'),
    },
    'cancel_subagent': {
        'domains': ('agent',),
    },
    'cancel_invoice_in_tax_system': {
        'domains': ('tax',),
        'companion_tools': ('get_invoice_details', 'send_corrective_invoice_to_tax_system'),
        'intent_write': True,
        'always_confirm': True,
    },
    'get_invoice_tax_status': {
        'domains': ('tax',),
        'companion_tools': ('get_invoice_details', 'validate_invoice_for_tax'),
    },
    'validate_invoice_for_tax': {
        'domains': ('tax',),
        'companion_tools': ('get_invoice_details', 'send_invoice_to_tax_system'),
    },
    'inquire_invoice_tax_status': {
        'domains': ('tax',),
        'companion_tools': ('get_invoice_tax_status', 'search_invoices'),
        'intent_write': True,
    },
    'search_tax_reference_candidates': {
        'domains': ('tax',),
        'companion_tools': ('add_invoice_to_tax_workspace', 'search_invoices'),
    },
    'get_invoice_tax_timeline': {
        'domains': ('tax',),
        'companion_tools': ('get_invoice_tax_status', 'list_tax_failed_invoices'),
    },
    'validate_tax_invoice_batch': {
        'domains': ('tax',),
        'companion_tools': ('send_invoice_to_tax_system', 'search_invoices'),
    },
    'list_tax_failed_invoices': {
        'domains': ('tax',),
        'companion_tools': ('get_invoice_tax_timeline', 'send_invoice_to_tax_system'),
    },
    'check_tax_system_health': {
        'domains': ('tax',),
        'always_confirm': True,
    },
    'send_tax_invoice_batch': {
        'domains': ('tax',),
        'companion_tools': ('list_tax_failed_invoices', 'search_invoices', 'validate_tax_invoice_batch'),
        'intent_write': True,
        'always_confirm': True,
    },
    'retry_tax_failed_invoice': {
        'domains': ('tax',),
        'companion_tools': ('get_invoice_tax_timeline', 'list_tax_failed_invoices'),
        'intent_write': True,
        'always_confirm': True,
    },
    'remove_tax_invoice_batch': {
        'domains': ('tax',),
        'companion_tools': ('list_tax_failed_invoices', 'search_invoices'),
        'intent_write': True,
        'always_confirm': True,
    },
    'add_invoice_to_tax_workspace': {
        'domains': ('tax',),
        'companion_tools': ('get_invoice_details', 'search_invoices'),
        'intent_write': True,
    },
    'create_account': {
        'domains': ('financial',),
        'companion_tools': ('get_account', 'list_accounts'),
        'intent_write': True,
    },
    'create_check': {
        'domains': ('financial',),
        'aliases': ('چک', 'چک دریافتی', 'چک پرداختی'),
        'companion_tools': ('get_check_details', 'list_currencies', 'search_checks', 'search_persons'),
        'intent_write': True,
    },
    'create_expense_income': {
        'domains': ('financial',),
        'aliases': ('هزینه', 'درآمد', 'ثبت هزینه', 'ثبت درآمد', 'سند هزینه', 'سند درآمد'),
        'companion_tools': ('list_accounts', 'list_bank_accounts', 'list_cash_registers', 'list_currencies', 'list_petty_cash', 'search_checks', 'search_expense_income', 'search_persons', 'search_projects'),
        'intent_write': True,
    },
    'create_invoice': {
        'domains': ('financial',),
        'aliases': ('فاکتور جدید', 'ثبت فاکتور', 'بزن فاکتور'),
        'companion_tools': ('get_current_fiscal_year', 'get_product_info', 'get_tax_settings', 'list_accounts', 'list_bank_accounts', 'list_cash_registers', 'list_currencies', 'list_petty_cash', 'list_warehouses', 'search_checks', 'search_persons', 'search_products', 'search_projects'),
        'intent_write': True,
    },
    'create_lead': {
        'domains': ('crm',),
        'companion_tools': ('get_pipeline_report', 'search_leads'),
        'intent_write': True,
    },
    'update_lead': {
        'domains': ('crm',),
        'companion_tools': ('get_lead_details', 'search_leads'),
        'intent_write': True,
    },
    'delete_lead': {
        'domains': ('crm',),
        'companion_tools': ('get_lead_details', 'search_leads'),
        'intent_write': True,
        'always_confirm': True,
    },
    'convert_lead_to_customer': {
        'domains': ('crm', 'people'),
        'companion_tools': ('get_lead_details', 'search_leads', 'search_persons'),
        'intent_write': True,
        'always_confirm': True,
    },
    'create_person': {
        'domains': ('people',),
        'aliases': ('مشتری جدید', 'شخص جدید', 'اضافه کردن مشتری'),
        'companion_tools': ('list_person_groups', 'search_persons'),
        'intent_write': True,
    },
    'create_product': {
        'domains': ('products_write',),
        'aliases': ('کالای جدید', 'کالا جدید', 'محصول جدید', 'خدمت جدید', 'اضافه کردن کالا', 'تعریف کالا'),
        'companion_tools': ('get_current_fiscal_year', 'get_tax_settings', 'list_currencies', 'list_price_list_items', 'list_price_lists', 'list_product_attributes', 'list_warehouses', 'search_categories', 'search_persons', 'search_products'),
        'intent_write': True,
    },
    'create_product_attribute': {
        'domains': ('products_write',),
        'intent_write': True,
    },
    'create_receipt_payment': {
        'domains': ('financial',),
        'aliases': ('دریافت', 'پرداخت', 'ثبت دریافت', 'ثبت پرداخت', 'سند دریافت', 'سند پرداخت'),
        'companion_tools': ('list_bank_accounts', 'list_cash_registers', 'list_currencies', 'list_petty_cash', 'search_checks', 'search_invoices', 'search_persons', 'search_projects', 'search_receipts_payments'),
        'intent_write': True,
    },
    'create_session_plan': {
        'domains': ('agent',),
    },
    'create_transfer': {
        'domains': ('financial',),
        'aliases': ('انتقال وجه', 'انتقال بین حساب'),
        'companion_tools': ('list_bank_accounts', 'list_cash_registers', 'list_currencies', 'list_petty_cash', 'search_transfers'),
        'intent_write': True,
    },
    'check_product_usage': {
        'domains': ('products_write',),
        'companion_tools': ('delete_product', 'get_product_info'),
    },
    'cancel_warehouse_document': {
        'domains': ('warehouse',),
        'companion_tools': ('get_warehouse_document_details', 'search_warehouse_documents'),
        'intent_write': True,
        'always_confirm': True,
    },
    'delete_warehouse_document': {
        'domains': ('warehouse',),
        'companion_tools': ('get_warehouse_document_details', 'search_warehouse_documents'),
        'intent_write': True,
        'always_confirm': True,
    },
    'delete_product': {
        'domains': ('products_write',),
        'companion_tools': ('check_product_usage', 'get_product_info'),
        'intent_write': True,
        'always_confirm': True,
    },
    'create_warehouse_document': {
        'domains': ('warehouse',),
        'aliases': ('حواله', 'حواله انبار', 'ورود انبار', 'خروج انبار'),
        'companion_tools': ('get_current_fiscal_year', 'get_inventory_status', 'list_warehouses', 'search_products', 'search_warehouse_documents'),
        'intent_write': True,
    },
    'create_workflow': {
        'domains': ('workflow',),
        'aliases': ('اتوماسیون', 'گردش کار جدید', 'workflow جدید'),
        'companion_tools': ('get_workflow_design_rules', 'list_workflow_action_catalog', 'list_workflow_trigger_catalog', 'list_workflows', 'validate_workflow_draft'),
        'intent_write': True,
        'always_confirm': True,
    },
    'delete_account': {
        'domains': ('financial',),
        'intent_write': True,
    },
    'delete_check': {
        'domains': ('financial',),
        'intent_write': True,
    },
    'delete_expense_income': {
        'domains': ('financial',),
        'intent_write': True,
    },
    'delete_invoice': {
        'domains': ('financial',),
        'intent_write': True,
        'always_confirm': True,
    },
    'delete_memory_entry': {
        'domains': ('memory',),
        'intent_write': True,
    },
    'delete_person': {
        'domains': ('people',),
        'intent_write': True,
        'always_confirm': True,
    },
    'delete_product_attribute': {
        'domains': ('products_write',),
        'intent_write': True,
    },
    'delete_receipt_payment': {
        'domains': ('financial',),
        'intent_write': True,
    },
    'delete_transfer': {
        'domains': ('financial',),
        'intent_write': True,
    },
    'delete_workflow': {
        'domains': ('workflow',),
        'intent_write': True,
        'always_confirm': True,
    },
    'execute_workflow': {
        'domains': ('workflow',),
        'companion_tools': ('get_workflow', 'list_workflows'),
        'intent_write': True,
        'always_confirm': True,
    },
    'export_business_data': {
        'domains': ('reports_meta',),
        'intent_write': True,
        'always_confirm': True,
    },
    'get_account': {
        'domains': ('financial',),
        'aliases': ('سرفصل', 'حساب'),
    },
    'get_basalam_overview': {
        'domains': ('integration',),
        'aliases': ('باسلام', 'basalam', 'خلاصه باسلام'),
    },
    'get_bom_details': {
        'domains': ('warehouse',),
    },
    'get_business_credit_settings': {
        'domains': ('financial',),
    },
    'get_business_dashboard': {
        'domains': ('financial', 'reports_meta'),
        'is_core': True,
    },
    'get_business_info': {
        'domains': ('misc',),
        'is_core': True,
    },
    'get_cash_flow': {
        'domains': ('financial', 'reports_meta'),
        'aliases': ('جریان نقد', 'نقدینگی', 'cash flow'),
    },
    'get_check_details': {
        'domains': ('financial',),
    },
    'get_creditors_report': {
        'domains': ('financial', 'reports_meta'),
        'aliases': ('بستانکار', 'بستانکاران', 'creditor'),
    },
    'get_crm_summary': {
        'domains': ('crm',),
        'aliases': ('خلاصه crm', 'crm'),
    },
    'get_current_fiscal_year': {
        'domains': ('financial',),
        'aliases': ('سال مالی', 'fiscal'),
    },
    'get_customer_club_rfm_summary': {
        'domains': ('customer_club',),
        'aliases': ('rfm', 'باشگاه'),
    },
    'get_customer_club_settings': {
        'domains': ('customer_club',),
        'aliases': ('باشگاه', 'امتیاز', 'وفادار'),
    },
    'get_customer_info': {
        'domains': ('people',),
    },
    'get_deal_details': {
        'domains': ('crm',),
    },
    'get_debtors_report': {
        'domains': ('financial', 'reports_meta'),
        'aliases': ('بدهکار', 'بدهکاران', 'debtor'),
    },
    'get_document_details': {
        'domains': ('financial',),
    },
    'get_document_numbering_settings': {
        'domains': ('financial',),
    },
    'get_financial_summary': {
        'domains': ('financial',),
        'is_core': True,
        'aliases': ('خلاصه مالی', 'وضعیت مالی'),
    },
    'get_inventory_status': {
        'domains': ('warehouse',),
        'aliases': ('موجودی', 'انبار', 'stock'),
    },
    'get_inventory_valuation': {
        'domains': ('reports_meta', 'warehouse'),
        'aliases': ('ارزش موجودی', 'ریالی انبار'),
    },
    'get_invoice_details': {
        'domains': ('financial',),
        'is_core': True,
        'aliases': ('جزئیات فاکتور', 'فاکتور'),
    },
    'get_invoices_count': {
        'domains': ('financial',),
        'aliases': ('تعداد فاکتور', 'چند فاکتور'),
    },
    'get_lead_details': {
        'domains': ('crm',),
    },
    'get_lead_funnel_report': {
        'domains': ('crm',),
    },
    'get_loan_facility': {
        'domains': ('financial',),
    },
    'get_opening_balance': {
        'domains': ('financial',),
    },
    'get_person_balance': {
        'domains': ('people',),
        'is_core': True,
        'aliases': ('مانده حساب', 'مانده شخص'),
    },
    'get_person_credit': {
        'domains': ('financial',),
    },
    'get_person_transactions': {
        'domains': ('misc', 'people'),
    },
    'get_pipeline_report': {
        'domains': ('crm',),
    },
    'get_product_attribute': {
        'domains': ('products_write',),
    },
    'get_product_info': {
        'domains': ('products_write',),
        'is_core': True,
        'aliases': ('کالا', 'محصول'),
    },
    'get_product_kardex': {
        'domains': ('warehouse',),
        'aliases': ('کاردکس', 'kardex'),
    },
    'get_project_summary': {
        'domains': ('projects',),
    },
    'get_purchase_report': {
        'domains': ('financial', 'reports_meta'),
        'aliases': ('گزارش خرید', 'خرید'),
    },
    'get_quick_sales_settings': {
        'domains': ('misc',),
    },
    'get_repair_order_details': {
        'domains': ('misc',),
    },
    'get_report': {
        'domains': ('reports_meta',),
        'aliases': ('گزارش یکپارچه', 'get_report'),
    },
    'get_report_template': {
        'domains': ('report_templates',),
    },
    'get_report_template_scope_catalog': {
        'domains': ('report_templates',),
    },
    'get_sales_report': {
        'domains': ('financial', 'reports_meta'),
        'aliases': ('گزارش فروش', 'فروش', 'sales'),
    },
    'get_tax_data_quality': {
        'domains': ('tax',),
    },
    'get_tax_settings': {
        'domains': ('tax',),
        'aliases': ('مالیات', 'مودیان', 'tax'),
    },
    'get_wallet_metrics': {
        'domains': ('financial',),
    },
    'get_wallet_overview': {
        'domains': ('financial',),
        'aliases': ('کیف پول', 'wallet'),
    },
    'get_warehouse_document_details': {
        'domains': ('warehouse',),
    },
    'get_warehouse_report': {
        'domains': ('warehouse',),
    },
    'get_warehouse_stock_summary': {
        'domains': ('warehouse',),
        'aliases': ('خلاصه موجودی', 'انبار'),
    },
    'get_workflow': {
        'domains': ('workflow',),
    },
    'get_workflow_component_schema': {
        'domains': ('workflow',),
    },
    'get_workflow_design_rules': {
        'domains': ('workflow',),
    },
    'get_workflow_execution_debug': {
        'domains': ('workflow',),
    },
    'hscript_fix_script': {
        'domains': ('hscript',),
    },
    'hscript_language_guide': {
        'domains': ('hscript',),
        'aliases': ('راهنمای hscript', 'زبان اسکریپت'),
    },
    'hscript_read_doc': {
        'domains': ('hscript',),
    },
    'hscript_retrieve_docs': {
        'domains': ('hscript',),
    },
    'hscript_run_preview': {
        'domains': ('hscript',),
    },
    'hscript_search_docs': {
        'domains': ('hscript',),
        'aliases': ('hscript', 'اچ اسکریپت', 'اسکریپت'),
    },
    'hscript_validate_script': {
        'domains': ('hscript',),
    },
    'invoke_business_connector': {
        'domains': ('integration',),
        'always_confirm': True,
    },
    'list_accounts': {
        'domains': ('financial',),
        'aliases': ('سرفصل', 'حساب کل', 'coding'),
    },
    'list_announcements': {
        'domains': ('misc',),
    },
    'list_available_reports': {
        'domains': ('reports_meta',),
        'aliases': ('لیست گزارش', 'گزارش\u200cهای موجود'),
    },
    'list_bank_accounts': {
        'domains': ('financial',),
    },
    'list_basalam_dead_letter': {
        'domains': ('integration',),
        'aliases': ('صف خطا', 'dead letter', 'باسلام'),
    },
    'list_basalam_product_conflicts': {
        'domains': ('integration',),
        'aliases': ('تعارض باسلام', 'conflict'),
    },
    'list_basalam_synced_invoices': {
        'domains': ('integration',),
        'aliases': ('سینک باسلام', 'فاکتور باسلام'),
    },
    'list_boms': {
        'domains': ('warehouse',),
    },
    'list_business_notification_logs': {
        'domains': ('misc',),
    },
    'list_business_notification_templates': {
        'domains': ('misc',),
    },
    'list_business_plugins': {
        'domains': ('marketplace',),
        'aliases': ('افزونه فعال', 'پلاگین'),
    },
    'list_business_users': {
        'domains': ('misc',),
    },
    'list_cash_registers': {
        'domains': ('financial',),
    },
    'list_credit_installment_plans': {
        'domains': ('financial',),
    },
    'list_currencies': {
        'domains': ('financial', 'products_write'),
        'aliases': ('ارز', 'ارزها', 'لیست ارزها', 'currency', 'واحد پول'),
    },
    'list_currency_rates': {
        'domains': ('financial',),
    },
    'list_customer_club_ledger': {
        'domains': ('customer_club',),
        'aliases': ('دفتر امتیاز', 'باشگاه'),
    },
    'list_customer_club_tiers': {
        'domains': ('customer_club',),
    },
    'list_distribution_routes': {
        'domains': ('misc',),
    },
    'list_fiscal_years': {
        'domains': ('financial',),
    },
    'list_frequent_descriptions': {
        'domains': ('financial',),
    },
    'list_loan_facilities': {
        'domains': ('financial',),
    },
    'list_marketplace_plugins': {
        'domains': ('marketplace',),
        'aliases': ('بازار افزونه', 'marketplace'),
    },
    'list_my_businesses': {
        'domains': ('misc',),
    },
    'list_payment_gateways': {
        'domains': ('financial',),
        'aliases': ('درگاه پرداخت', 'gateway'),
    },
    'list_person_groups': {
        'domains': ('people',),
    },
    'list_petty_cash': {
        'domains': ('misc',),
    },
    'list_price_list_items': {
        'domains': ('products_write',),
        'aliases': ('قیمت لیست', 'قیمت عمده'),
    },
    'list_price_lists': {
        'domains': ('misc', 'products_write'),
        'aliases': ('لیست قیمت', 'قیمت عمده', 'price list'),
    },
    'list_product_attributes': {
        'domains': ('products_write',),
    },
    'list_queryable_fields': {
        'domains': ('query',),
        'is_core': True,
    },
    'post_warehouse_document': {
        'domains': ('warehouse',),
        'companion_tools': ('get_warehouse_document_details', 'search_warehouse_documents'),
        'intent_write': True,
        'always_confirm': True,
    },
    'list_report_templates': {
        'domains': ('report_templates',),
        'aliases': ('قالب گزارش', 'قالب فاکتور', 'قالب چاپ'),
    },
    'list_session_todos': {
        'domains': ('agent',),
    },
    'list_user_notifications': {
        'domains': ('misc',),
    },
    'list_wallet_transactions': {
        'domains': ('financial',),
        'aliases': ('تراکنش کیف پول', 'wallet'),
    },
    'list_warehouse_locations': {
        'domains': ('warehouse',),
    },
    'list_warehouse_placements': {
        'domains': ('warehouse',),
    },
    'list_warehouses': {
        'domains': ('warehouse',),
        'aliases': ('انبار', 'warehouse'),
    },
    'list_woocommerce_orders': {
        'domains': ('integration',),
        'aliases': ('ووکامرس', 'woocommerce', 'سفارش ووکامرس'),
    },
    'list_woocommerce_products': {
        'domains': ('integration',),
        'aliases': ('محصول ووکامرس', 'woocommerce'),
    },
    'list_workflow_action_catalog': {
        'domains': ('workflow',),
    },
    'list_workflow_builtin_nodes': {
        'domains': ('workflow',),
    },
    'list_workflow_executions': {
        'domains': ('workflow',),
        'aliases': ('اجرای workflow', 'اجرای اتوماسیون'),
    },
    'list_workflow_trigger_catalog': {
        'domains': ('workflow',),
    },
    'list_workflows': {
        'domains': ('workflow',),
        'aliases': ('اتوماسیون', 'گردش کار', 'workflow'),
    },
    'poll_workflow_execution': {
        'domains': ('workflow',),
    },
    'publish_report_template': {
        'domains': ('report_templates',),
        'intent_write': True,
        'always_confirm': True,
    },
    'query_business_data': {
        'domains': ('query',),
        'is_core': True,
        'aliases': ('پرس\u200cوجو', 'query'),
    },
    'read_memory': {
        'domains': ('memory',),
    },
    'recalculate_customer_club_rfm': {
        'domains': ('customer_club',),
        'intent_write': True,
        'always_confirm': True,
    },
    'resolve_currency_rate': {
        'domains': ('financial',),
    },
    'resolve_date_range': {
        'domains': ('query',),
        'is_core': True,
        'aliases': ('بازه تاریخ', 'ماه گذشته', 'تقویم'),
    },
    'search_activities': {
        'domains': ('crm',),
    },
    'search_activity_logs': {
        'domains': ('misc',),
    },
    'search_categories': {
        'domains': ('products_write',),
    },
    'search_checks': {
        'domains': ('financial', 'query'),
    },
    'search_customer_club_rfm_persons': {
        'domains': ('customer_club',),
    },
    'search_deals': {
        'domains': ('crm',),
        'aliases': ('معامله', 'فرصت', 'deal'),
    },
    'search_documents': {
        'domains': ('financial', 'query'),
    },
    'search_expense_income': {
        'domains': ('financial', 'query'),
    },
    'search_invoices': {
        'domains': ('financial', 'query'),
        'is_core': True,
        'aliases': ('فاکتور', 'invoice', 'فروش'),
    },
    'remove_invoice_from_tax_workspace': {
        'domains': ('tax',),
        'companion_tools': ('get_invoice_details', 'search_invoices'),
        'intent_write': True,
    },
    'send_corrective_invoice_to_tax_system': {
        'domains': ('tax',),
        'companion_tools': ('get_invoice_details', 'search_invoices'),
        'intent_write': True,
        'always_confirm': True,
    },
    'send_invoice_to_tax_system': {
        'domains': ('tax',),
        'companion_tools': ('add_invoice_to_tax_workspace', 'get_invoice_details', 'search_invoices'),
        'intent_write': True,
        'always_confirm': True,
    },
    'create_deal': {
        'domains': ('crm',),
        'companion_tools': ('get_deal_details', 'search_deals', 'search_persons'),
        'intent_write': True,
    },
    'update_deal': {
        'domains': ('crm',),
        'companion_tools': ('get_deal_details', 'search_deals'),
        'intent_write': True,
    },
    'delete_deal': {
        'domains': ('crm',),
        'companion_tools': ('get_deal_details', 'search_deals'),
        'intent_write': True,
        'always_confirm': True,
    },
    'replace_deal_lines': {
        'domains': ('crm', 'products_write'),
        'companion_tools': ('get_deal_details', 'search_products'),
        'intent_write': True,
        'always_confirm': True,
    },
    'convert_deal_to_invoice': {
        'domains': ('crm', 'financial'),
        'companion_tools': ('get_deal_details', 'get_invoice_details', 'search_invoices'),
        'intent_write': True,
        'always_confirm': True,
    },
    'create_crm_activity': {
        'domains': ('crm',),
        'companion_tools': ('search_activities', 'search_deals', 'search_leads', 'search_persons'),
        'intent_write': True,
    },
    'update_crm_activity': {
        'domains': ('crm',),
        'companion_tools': ('search_activities',),
        'intent_write': True,
    },
    'delete_crm_activity': {
        'domains': ('crm',),
        'companion_tools': ('search_activities',),
        'intent_write': True,
        'always_confirm': True,
    },
    'list_crm_sequences': {
        'domains': ('crm',),
        'companion_tools': ('get_crm_sequence',),
    },
    'get_crm_sequence': {
        'domains': ('crm',),
        'companion_tools': ('list_crm_sequences', 'update_crm_sequence'),
    },
    'create_crm_sequence': {
        'domains': ('crm',),
        'intent_write': True,
        'always_confirm': True,
    },
    'update_crm_sequence': {
        'domains': ('crm',),
        'companion_tools': ('get_crm_sequence',),
        'intent_write': True,
        'always_confirm': True,
    },
    'delete_crm_sequence': {
        'domains': ('crm',),
        'companion_tools': ('list_crm_sequences',),
        'intent_write': True,
        'always_confirm': True,
    },
    'enroll_crm_sequence': {
        'domains': ('crm',),
        'companion_tools': ('get_crm_sequence', 'get_lead_details', 'get_deal_details'),
        'intent_write': True,
        'always_confirm': True,
    },
    'get_crm_automation_settings': {
        'domains': ('crm',),
        'companion_tools': ('update_crm_automation_settings',),
    },
    'update_crm_automation_settings': {
        'domains': ('crm',),
        'companion_tools': ('get_crm_automation_settings', 'list_crm_sequences'),
        'intent_write': True,
        'always_confirm': True,
    },
    'search_leads': {
        'domains': ('crm',),
        'aliases': ('سرنخ', 'lead'),
    },
    'search_persons': {
        'domains': ('people', 'query'),
        'is_core': True,
        'aliases': ('مشتری', 'شخص', 'تامین'),
    },
    'search_product_instances': {
        'domains': ('products_write',),
    },
    'search_production_documents': {
        'domains': ('warehouse',),
    },
    'search_products': {
        'domains': ('products_write', 'query'),
        'is_core': True,
        'aliases': ('کالا', 'محصول', 'product'),
    },
    'search_projects': {
        'domains': ('projects',),
    },
    'search_receipts_payments': {
        'domains': ('financial', 'query'),
        'aliases': ('دریافت', 'پرداخت', 'receipt', 'payment'),
    },
    'search_repair_orders': {
        'domains': ('misc',),
    },
    'search_tax_workspace': {
        'domains': ('tax',),
        'aliases': ('کارپوشه', 'مودیان'),
    },
    'search_transfers': {
        'domains': ('financial', 'query'),
    },
    'search_warehouse_documents': {
        'domains': ('query', 'warehouse'),
    },
    'search_warranty_codes': {
        'domains': ('misc',),
    },
    'set_default_report_template': {
        'domains': ('report_templates',),
        'intent_write': True,
        'always_confirm': True,
    },
    'spawn_subagent': {
        'domains': ('agent',),
    },
    'test_workflow': {
        'domains': ('workflow',),
        'side_effect': 'execute',
    },
    'update_account': {
        'domains': ('financial',),
        'intent_write': True,
    },
    'update_check': {
        'domains': ('financial',),
        'intent_write': True,
    },
    'update_customer_club_settings': {
        'domains': ('customer_club',),
        'intent_write': True,
        'always_confirm': True,
    },
    'update_expense_income': {
        'domains': ('financial',),
        'aliases': ('ویرایش هزینه', 'ویرایش درآمد', 'اصلاح هزینه'),
        'companion_tools': ('list_accounts', 'list_bank_accounts', 'list_cash_registers', 'list_currencies', 'list_petty_cash', 'search_checks', 'search_expense_income', 'search_persons', 'search_projects'),
        'intent_write': True,
    },
    'update_invoice': {
        'domains': ('financial',),
        'aliases': ('ویرایش فاکتور', 'اصلاح فاکتور'),
        'companion_tools': ('get_invoice_details', 'list_accounts', 'list_bank_accounts', 'list_cash_registers', 'list_currencies', 'list_petty_cash', 'list_warehouses', 'search_checks', 'search_invoices', 'search_persons', 'search_products', 'search_projects'),
        'intent_write': True,
    },
    'update_person': {
        'domains': ('people',),
        'intent_write': True,
    },
    'update_product': {
        'domains': ('products_write',),
        'aliases': ('ویرایش کالا', 'ویرایش محصول', 'اصلاح کالا', 'قیمت کالا'),
        'companion_tools': ('get_current_fiscal_year', 'get_product_info', 'get_tax_settings', 'list_currencies', 'list_price_list_items', 'list_price_lists', 'list_product_attributes', 'list_warehouses', 'search_categories', 'search_persons', 'search_products'),
        'intent_write': True,
    },
    'update_warehouse_document': {
        'domains': ('warehouse',),
        'companion_tools': ('get_warehouse_document_details', 'search_warehouse_documents'),
        'intent_write': True,
    },
    'update_product_attribute': {
        'domains': ('products_write',),
        'intent_write': True,
    },
    'update_receipt_payment': {
        'domains': ('financial',),
        'aliases': ('ویرایش دریافت', 'ویرایش پرداخت', 'اصلاح دریافت'),
        'companion_tools': ('list_bank_accounts', 'list_cash_registers', 'list_currencies', 'list_petty_cash', 'search_checks', 'search_invoices', 'search_persons', 'search_projects', 'search_receipts_payments'),
        'intent_write': True,
    },
    'update_session_todo': {
        'domains': ('agent',),
    },
    'update_transfer': {
        'domains': ('financial',),
        'intent_write': True,
    },
    'update_workflow': {
        'domains': ('workflow',),
        'companion_tools': ('get_workflow', 'get_workflow_design_rules', 'list_workflows', 'validate_workflow_draft'),
        'intent_write': True,
        'always_confirm': True,
    },
    'upsert_memory_entry': {
        'domains': ('memory',),
        'intent_write': True,
    },
    'validate_workflow_draft': {
        'domains': ('workflow',),
    },
    'bulk_upsert_receipts_payments': {
        'domains': ('financial',),
        'intent_write': True,
        'always_confirm': True,
        'companion_tools': ('search_receipts_payments', 'search_persons', 'list_bank_accounts', 'list_cash_registers', 'list_currencies'),
    },
    'bulk_upsert_expense_income': {
        'domains': ('financial',),
        'intent_write': True,
        'always_confirm': True,
        'companion_tools': ('search_expense_income', 'list_accounts', 'list_bank_accounts', 'list_cash_registers', 'list_currencies'),
    },
    'bulk_delete_expense_income': {
        'domains': ('financial',),
        'intent_write': True,
        'always_confirm': True,
        'companion_tools': ('search_expense_income', 'get_document_details'),
    },
    'get_payroll_dashboard': {'domains': ('payroll',)},
    'get_payroll_settings': {'domains': ('payroll',)},
    'update_payroll_settings': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'list_payroll_item_categories': {'domains': ('payroll',)},
    'list_payroll_items': {'domains': ('payroll',)},
    'list_payroll_departments': {'domains': ('payroll',)},
    'list_payroll_employees': {'domains': ('payroll',)},
    'list_payroll_periods': {'domains': ('payroll',)},
    'list_payroll_runs': {'domains': ('payroll',)},
    'get_payroll_run': {'domains': ('payroll',)},
    'get_payroll_department_summary': {'domains': ('payroll',)},
    'get_payroll_item_summary': {'domains': ('payroll',)},
    'get_payroll_employee_summary': {'domains': ('payroll',)},
    'get_payroll_statutory_summary': {'domains': ('payroll',)},
    'get_payroll_period_overview': {'domains': ('payroll',)},
    'create_payroll_item_category': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'update_payroll_item_category': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'delete_payroll_item_category': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'create_payroll_item': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'update_payroll_item': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'delete_payroll_item': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'create_payroll_department': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'update_payroll_department': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'create_payroll_employee': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'update_payroll_employee': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'create_payroll_period': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'close_payroll_period': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'create_payroll_run': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'update_payroll_run': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'delete_payroll_run': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'finalize_payroll_run': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'cancel_payroll_run': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'approve_payroll_run': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'reject_payroll_run': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'copy_payroll_run': {'domains': ('payroll',), 'intent_write': True, 'always_confirm': True},
    'post_payroll_run_to_accounting': {'domains': ('payroll', 'accounting'), 'intent_write': True, 'always_confirm': True},
    'post_payroll_run_payment': {'domains': ('payroll', 'financial'), 'intent_write': True, 'always_confirm': True},
    'bulk_upsert_products': {'domains': ('products', 'inventory'), 'intent_write': True, 'always_confirm': True, 'companion_tools': ('search_products', 'list_warehouses', 'list_categories')},
    'bulk_delete_products': {'domains': ('products',), 'intent_write': True, 'always_confirm': True, 'companion_tools': ('check_product_usage',)},
    'preview_bulk_product_price_update': {'domains': ('products',)},
    'apply_bulk_product_price_update': {'domains': ('products',), 'intent_write': True, 'always_confirm': True, 'companion_tools': ('preview_bulk_product_price_update',)},
    'preview_bulk_product_default_warehouse': {'domains': ('products', 'warehouse')},
    'apply_bulk_product_default_warehouse': {'domains': ('products', 'warehouse'), 'intent_write': True, 'always_confirm': True, 'companion_tools': ('preview_bulk_product_default_warehouse',)},
    'get_warehouse_documents_summary': {'domains': ('warehouse', 'reports')},
    'get_slow_moving_warehouse_items': {'domains': ('warehouse', 'reports')},
    'get_critical_stock_report': {'domains': ('warehouse', 'reports')},
    'get_inter_warehouse_transfers_report': {'domains': ('warehouse', 'reports')},
    'get_warehouse_adjustment_report': {'domains': ('warehouse', 'reports')},
    'get_warehouse_performance_report': {'domains': ('warehouse', 'reports')},
    'get_product_movement_history': {'domains': ('warehouse', 'products', 'reports')},
    'get_inventory_valuation_report': {'domains': ('warehouse', 'reports')},
    'get_pending_warehouse_documents': {'domains': ('warehouse', 'reports')},
    'get_inventory_turnover_report': {'domains': ('warehouse', 'reports')},
    'get_repair_shop_settings': {'domains': ('repair',)},
    'update_repair_shop_settings': {'domains': ('repair',), 'intent_write': True, 'always_confirm': True},
    'list_repair_technicians': {'domains': ('repair',)},
    'create_repair_technician': {'domains': ('repair',), 'intent_write': True, 'always_confirm': True},
    'update_repair_technician': {'domains': ('repair',), 'intent_write': True, 'always_confirm': True},
    'delete_repair_technician': {'domains': ('repair',), 'intent_write': True, 'always_confirm': True},
    'create_repair_order': {'domains': ('repair',), 'intent_write': True, 'always_confirm': True},
    'update_repair_order': {'domains': ('repair',), 'intent_write': True, 'always_confirm': True},
    'cancel_repair_order': {'domains': ('repair',), 'intent_write': True, 'always_confirm': True},
    'assign_repair_technician': {'domains': ('repair',), 'intent_write': True, 'always_confirm': True},
    'update_repair_order_status': {'domains': ('repair',), 'intent_write': True, 'always_confirm': True},
    'add_repair_parts': {'domains': ('repair', 'warehouse', 'products'), 'intent_write': True, 'always_confirm': True},
    'calculate_repair_costs': {'domains': ('repair',), 'intent_write': True, 'always_confirm': True},
    'complete_repair_order': {'domains': ('repair', 'warehouse'), 'intent_write': True, 'always_confirm': True},
    'deliver_repair_order': {'domains': ('repair',), 'intent_write': True, 'always_confirm': True},
    'create_repair_invoice': {'domains': ('repair', 'invoices', 'accounting'), 'intent_write': True, 'always_confirm': True},
    'get_repair_accounting_summary': {'domains': ('repair', 'accounting')},
    'get_repair_history_by_warranty': {'domains': ('repair', 'warranty')},
    'get_warranty_settings': {'domains': ('warranty',)},
    'update_warranty_settings': {'domains': ('warranty',), 'intent_write': True, 'always_confirm': True},
    'generate_warranty_codes': {'domains': ('warranty', 'products'), 'intent_write': True, 'always_confirm': True},
    'list_warranty_codes_by_person': {'domains': ('warranty', 'persons')},
    'delete_warranty_code': {'domains': ('warranty',), 'intent_write': True, 'always_confirm': True},
    'bulk_delete_warranty_codes': {'domains': ('warranty',), 'intent_write': True, 'always_confirm': True},
    'list_production_orders': {'domains': ('production', 'inventory')},
    'get_production_order': {'domains': ('production', 'inventory')},
    'get_production_material_plan': {'domains': ('production', 'inventory')},
    'trace_production_orders_by_lot': {'domains': ('production', 'inventory')},
    'create_production_order': {'domains': ('production', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'update_production_order': {'domains': ('production', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'release_production_order': {'domains': ('production', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'start_production_order': {'domains': ('production', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'complete_production_order': {'domains': ('production', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'cancel_production_order': {'domains': ('production', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'get_production_order_costing': {'domains': ('production', 'accounting')},
    'refresh_production_order_costing': {'domains': ('production', 'accounting'), 'intent_write': True, 'always_confirm': True},
    'update_production_order_lots': {'domains': ('production', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'get_bom': {'domains': ('production', 'inventory')},
    'create_bom': {'domains': ('production', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'update_bom': {'domains': ('production', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'delete_bom': {'domains': ('production', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'explode_bom': {'domains': ('production', 'inventory')},
    'produce_draft_from_bom': {'domains': ('production', 'inventory')},
    'get_distribution_summary': {'domains': ('distribution', 'reports')},
    'list_distribution_territories': {'domains': ('distribution',)},
    'create_distribution_territory': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'update_distribution_territory': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'delete_distribution_territory': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'create_distribution_route': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'update_distribution_route': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'delete_distribution_route': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'list_distribution_route_stops': {'domains': ('distribution',)},
    'upsert_distribution_route_stop': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'delete_distribution_route_stop': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'list_distribution_assignments': {'domains': ('distribution',)},
    'create_distribution_assignment': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'delete_distribution_assignment': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'get_distribution_daily_plan': {'domains': ('distribution', 'reports')},
    'list_distribution_visits': {'domains': ('distribution',)},
    'start_distribution_visit': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'complete_distribution_visit': {'domains': ('distribution', 'invoices', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'cancel_distribution_visit': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'create_distribution_return_request': {'domains': ('distribution', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'list_distribution_return_requests': {'domains': ('distribution',)},
    'resolve_distribution_return_request': {'domains': ('distribution', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'get_distribution_settings': {'domains': ('distribution',)},
    'update_distribution_settings': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'get_distribution_dashboard': {'domains': ('distribution', 'reports')},
    'list_distribution_vans': {'domains': ('distribution', 'inventory')},
    'create_distribution_van': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'update_distribution_van': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'get_distribution_van_stock': {'domains': ('distribution', 'inventory')},
    'load_distribution_van': {'domains': ('distribution', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'unload_distribution_van': {'domains': ('distribution', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'get_my_distribution_van_stock': {'domains': ('distribution', 'inventory')},
    'list_distribution_targets': {'domains': ('distribution', 'reports')},
    'upsert_distribution_target': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'delete_distribution_target': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'preview_distribution_settlement': {'domains': ('distribution', 'financial')},
    'list_distribution_settlements': {'domains': ('distribution', 'financial')},
    'upsert_distribution_settlement': {'domains': ('distribution', 'financial'), 'intent_write': True, 'always_confirm': True},
    'confirm_distribution_settlement': {'domains': ('distribution', 'financial'), 'intent_write': True, 'always_confirm': True},
    'list_distribution_orders': {'domains': ('distribution', 'invoices')},
    'create_distribution_order': {'domains': ('distribution', 'invoices'), 'intent_write': True, 'always_confirm': True},
    'confirm_distribution_order': {'domains': ('distribution', 'invoices'), 'intent_write': True, 'always_confirm': True},
    'update_distribution_order_status': {'domains': ('distribution', 'invoices'), 'intent_write': True, 'always_confirm': True},
    'get_suggested_distribution_order': {'domains': ('distribution', 'invoices')},
    'list_distribution_promotions': {'domains': ('distribution',)},
    'create_distribution_promotion': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'update_distribution_promotion': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'delete_distribution_promotion': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'list_distribution_delivery_trips': {'domains': ('distribution',)},
    'create_distribution_delivery_trip': {'domains': ('distribution', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'start_distribution_delivery_trip': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'complete_distribution_delivery_stop': {'domains': ('distribution', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'list_distribution_load_plans': {'domains': ('distribution',)},
    'create_distribution_load_plan': {'domains': ('distribution', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'confirm_distribution_load_plan': {'domains': ('distribution', 'inventory'), 'intent_write': True, 'always_confirm': True},
    'get_distribution_visit_trail': {'domains': ('distribution',)},
    'get_distribution_person_credit_summary': {'domains': ('distribution', 'financial')},
    'get_distribution_customer_360': {'domains': ('distribution', 'persons', 'crm')},
    'list_distribution_reason_codes': {'domains': ('distribution',)},
    'get_distribution_product_by_barcode': {'domains': ('distribution', 'products')},
    'upsert_distribution_customer_profile': {'domains': ('distribution', 'persons'), 'intent_write': True, 'always_confirm': True},
    'list_distribution_customer_profiles': {'domains': ('distribution', 'persons')},
    'list_distribution_assortments': {'domains': ('distribution', 'products')},
    'create_distribution_assortment': {'domains': ('distribution', 'products'), 'intent_write': True, 'always_confirm': True},
    'update_distribution_assortment': {'domains': ('distribution', 'products'), 'intent_write': True, 'always_confirm': True},
    'delete_distribution_assortment': {'domains': ('distribution', 'products'), 'intent_write': True, 'always_confirm': True},
    'list_distribution_customer_assets': {'domains': ('distribution', 'persons')},
    'create_distribution_customer_asset': {'domains': ('distribution', 'persons'), 'intent_write': True, 'always_confirm': True},
    'update_distribution_customer_asset': {'domains': ('distribution', 'persons'), 'intent_write': True, 'always_confirm': True},
    'get_distribution_scorecard': {'domains': ('distribution', 'reports')},
    'list_distribution_commission_rules': {'domains': ('distribution',)},
    'create_distribution_commission_rule': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'list_distribution_commission_runs': {'domains': ('distribution', 'financial')},
    'create_distribution_commission_run': {'domains': ('distribution', 'financial'), 'intent_write': True, 'always_confirm': True},
    'list_distribution_shelf_audits': {'domains': ('distribution',)},
    'create_distribution_shelf_audit': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'set_distribution_customer_location': {'domains': ('distribution', 'persons'), 'intent_write': True, 'always_confirm': True},
    'update_distribution_visit_location': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'report_distribution_live_location': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'preview_distribution_route_optimization': {'domains': ('distribution',)},
    'apply_distribution_route_optimization': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'get_distribution_team_map': {'domains': ('distribution',)},
    'get_distribution_user_day_trail': {'domains': ('distribution', 'reports')},
    'run_distribution_setup_wizard': {'domains': ('distribution',), 'intent_write': True, 'always_confirm': True},
    'onboard_distribution_outlet': {'domains': ('distribution', 'persons'), 'intent_write': True, 'always_confirm': True},
    'list_distribution_person_open_invoices': {'domains': ('distribution', 'financial', 'persons')},
    'get_distribution_offline_pack': {'domains': ('distribution', 'inventory')},}


def _unique_tuple(*groups) -> Tuple[str, ...]:
    seen: set[str] = set()
    out: list[str] = []
    for group in groups:
        for item in group or ():
            text = str(item).strip()
            if text and text not in seen:
                seen.add(text)
                out.append(text)
    return tuple(out)


def get_manifest_entry(name: str) -> Optional[ToolManifestEntry]:
    raw = TOOL_MANIFEST.get(name)
    if raw is None:
        return None
    domains = tuple(raw.get("domains") or ())
    intent_write = bool(raw.get("intent_write", False))
    always_confirm = bool(raw.get("always_confirm", False))
    capability = str(raw.get("capability") or resolve_tool_capability(name, domains))
    side_effect = raw.get("side_effect") or infer_side_effect(
        name, intent_write=intent_write, always_confirm=always_confirm
    )
    extra = search_meta_for(name)
    policy = permission_policy_for_name(
        name,
        explicit=raw.get("permission_policy"),
    )
    return ToolManifestEntry(
        domains=domains,
        capability=capability,
        namespace=str(raw.get("namespace") or namespace_for_capability(capability)),
        aliases=_unique_tuple(raw.get("aliases"), extra.get("aliases")),
        keywords=_unique_tuple(raw.get("keywords"), extra.get("keywords")),
        examples=_unique_tuple(raw.get("examples"), extra.get("examples")),
        companion_tools=tuple(raw.get("companion_tools") or ()),
        is_core=bool(raw.get("is_core", False)),
        intent_write=intent_write,
        always_confirm=always_confirm,
        side_effect=str(side_effect),
        permission_policy=policy,
        enabled=bool(raw.get("enabled", True)),
        deprecated=bool(raw.get("deprecated", False)),
        replacement=raw.get("replacement"),
        version=str(raw.get("version") or "1"),
        schema_version=str(raw.get("schema_version") or "1"),
    )


def iter_manifest_names() -> Tuple[str, ...]:
    return tuple(TOOL_MANIFEST.keys())
