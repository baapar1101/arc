"""کاتالوگ Metadata ابزارهای AI — منبع حقیقت Discovery / Intent / Alias.

Handler و JSON Schema در Registry ثبت می‌شوند.
این ماژول طبقه‌بندی پایدار را نگه می‌دارد و هنگام bind روی AIFunction کپی می‌شود.
هر Tool ثبت‌شده باید یک ورودی داشته باشد.
"""
from __future__ import annotations

from typing import Any, Dict, Optional, Tuple

from app.services.ai.ai_tool_spec import ToolManifestEntry, capability_for_domains

TOOL_MANIFEST: Dict[str, Dict[str, Any]] = {
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
        'domains': ('financial',),
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
        'aliases': ('ارز', 'currency', 'واحد پول'),
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
    },
    'validate_workflow_draft': {
        'domains': ('workflow',),
    },}


def get_manifest_entry(name: str) -> Optional[ToolManifestEntry]:
    raw = TOOL_MANIFEST.get(name)
    if raw is None:
        return None
    domains = tuple(raw.get("domains") or ())
    return ToolManifestEntry(
        domains=domains,
        capability=capability_for_domains(domains),
        aliases=tuple(raw.get("aliases") or ()),
        keywords=tuple(raw.get("keywords") or ()),
        examples=tuple(raw.get("examples") or ()),
        is_core=bool(raw.get("is_core", False)),
        companion_tools=tuple(raw.get("companion_tools") or ()),
        intent_write=bool(raw.get("intent_write", False)),
        always_confirm=bool(raw.get("always_confirm", False)),
    )


def iter_manifest_names() -> Tuple[str, ...]:
    return tuple(TOOL_MANIFEST.keys())
