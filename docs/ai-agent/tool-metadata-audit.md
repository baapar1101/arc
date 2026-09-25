# Tool Metadata Audit (Phase 4)

**تاریخ:** ۱۹ اوت ۲۰۲۶  
**منبع:** parse سورس `AIFunction` + Tool Manifest  
**تعداد:** ۱۸۰  

> Phase 4 improves the quality and trustworthiness of the catalog; it does not improve retrieval yet.

## Completeness

```
total: 180
complete_metadata: 153
missing_permissions: 0
missing_side_effect: 0
missing_domain: 0
missing_capability: 0
missing_description: 0
missing_aliases: 107
missing_examples: 150
missing_search_text: 0
average_quality_score: 78.7
```

Aliases و Examples برای همهٔ ۱۸۰ اجباری نیستند. اجباری: domain, capability, side_effect, search_text, permission (یا سیاست صریح).

Description کوتاهِ قبلی بیشتر false-negative پارسر بود (`CREATE_INVOICE_DESCRIPTION` و مشابه). پارسر حالا ثابت‌های `*_DESCRIPTION` را resolve می‌کند. چهار توضیح واقعاً کوتاه (`delete_check`, `delete_workflow`, `get_bom_details`, `get_check_details`) بازنویسی هدفمند شدند.

Quality < 70 (عمدتاً بدون alias/example دم‌بلند، نه بدون permission):

`delete_expense_income, delete_product_attribute, delete_receipt_payment, delete_transfer, get_business_credit_settings, get_document_details, get_opening_balance, get_person_credit, get_product_attribute, get_project_summary, get_repair_order_details, get_warehouse_document_details, list_announcements, list_boms, list_cash_registers, list_credit_installment_plans, list_customer_club_tiers, list_fiscal_years, list_petty_cash, search_activity_logs, search_customer_club_rfm_persons, search_expense_income, search_projects, search_transfers, search_warranty_codes, update_product_attribute, validate_workflow_draft`

## Permission policies (۲۲ مورد خالی قبلی)

| Tool | Policy / Permission | دلیل |
|------|---------------------|------|
| query_business_data | handler | Permission per entity در handler |
| batch_query_business_data | handler | همان fan-in |
| list_queryable_fields | handler | کاتالوگ فیلد همان entityها |
| read_memory | self_scoped | حافظهٔ خود کاربر |
| upsert_memory_entry | self_scoped | mutation حافظهٔ خود کاربر |
| delete_memory_entry | self_scoped | حذف حافظهٔ خود کاربر |
| create_session_plan | agent_internal | state گفت‌وگو |
| list_session_todos | agent_internal | state گفت‌وگو |
| update_session_todo | agent_internal | state گفت‌وگو |
| spawn_subagent | agent_internal | orchestration |
| await_subagent | agent_internal | orchestration |
| cancel_subagent | agent_internal | orchestration |
| resolve_date_range | user_context | تبدیل تقویم، دادهٔ کسب‌وکار نیست |
| list_my_businesses | user_context | عضویت کاربر |
| list_announcements | user_context | اعلان سامانه برای کاربر |
| list_user_notifications | user_context | نوتیف کاربر |
| get_business_info | user_context | پروفایل کسب‌وکار نشست |
| get_wallet_overview | wallet.view | دادهٔ مالی پلتفرم |
| list_wallet_transactions | wallet.view | دادهٔ مالی پلتفرم |
| get_wallet_metrics | wallet.view | دادهٔ مالی پلتفرم |
| list_frequent_descriptions | invoices.read | شرح اسناد/فاکتور |
| invoke_business_connector | settings.view | HTTP خارجی / execute |

## Side effects

```
{'write': 28, 'none': 138, 'delete': 10, 'execute': 3, 'export': 1}
```

- `upsert_memory_entry`: write (دیگر none نیست)
- `test_workflow`: execute (اجرای sandbox؛ خطرناک‌تر از read)
- `invoke_business_connector`: execute (prefix invoke_)
- `export_business_data`: export

## Short descriptions

پس از resolve ثابت‌ها و بازنویسی چهار مورد ضعیف: **missing_description = 0** (آستانه ۱۶ کاراکتر). Descriptionها کورکورانه بازنویسی نشدند.

## Collisions (عمدی fan-in)

| خانواده | Toolها | تمایز |
|----------|--------|--------|
| فاکتور | search_invoices, get_invoice_details, query_business_data(entity=invoice), get_report | اختصاصی فاکتور در برابر fan-in |
| گزارش فروش | get_sales_report, get_report(report_type=…) | capability reports.sales در برابر reports.overview |
| شخص | search_persons, get_customer_info, query_business_data(entity=person) | لیست در برابر کارت مشتری |

## Machine-readable rows

هر ردیف: name, capability, namespace, side_effect, permission_status, policy, score, aliases_count, examples_count

```
adjust_customer_club_points	customer_club.loyalty	customer_club	write	assigned	required	75	0	0
await_subagent	agent.subagent	agent	none	explicit_empty	agent_internal	75	0	0
batch_query_business_data	query.entity	query	none	explicit_empty	handler	75	0	0
cancel_subagent	agent.subagent	agent	none	explicit_empty	agent_internal	75	0	0
create_account	financial.account	financial	write	assigned	required	75	0	0
create_check	financial.check	financial	write	assigned	required	85	3	0
create_expense_income	financial.expense	financial	write	assigned	required	85	6	0
create_invoice	financial.invoice	financial	write	assigned	required	95	3	2
create_lead	crm.lead	crm	write	assigned	required	75	0	0
create_person	people.person	people	write	assigned	required	95	3	1
create_product	inventory.product	inventory	write	assigned	required	95	6	1
create_product_attribute	inventory.product	inventory	write	assigned	required	75	0	0
create_receipt_payment	financial.payment	financial	write	assigned	required	85	6	0
create_session_plan	agent.plan	agent	none	explicit_empty	agent_internal	75	0	0
create_transfer	financial.transfer	financial	write	assigned	required	85	2	0
create_warehouse_document	inventory.warehouse	inventory	write	assigned	required	85	4	0
create_workflow	automation.workflow	automation	write	assigned	required	95	3	1
delete_account	financial.account	financial	delete	assigned	required	75	0	0
delete_check	financial.check	financial	delete	assigned	required	75	0	0
delete_expense_income	financial.expense	financial	delete	assigned	required	65	0	0
delete_invoice	financial.invoice	financial	delete	assigned	required	95	2	1
delete_memory_entry	agent.memory	agent	delete	explicit_empty	self_scoped	95	2	1
delete_person	people.person	people	delete	assigned	required	95	2	1
delete_product_attribute	inventory.product	inventory	delete	assigned	required	65	0	0
delete_receipt_payment	financial.payment	financial	delete	assigned	required	65	0	0
delete_transfer	financial.transfer	financial	delete	assigned	required	65	0	0
delete_workflow	automation.workflow	automation	delete	assigned	required	75	0	0
execute_workflow	automation.workflow	automation	execute	assigned	required	95	2	1
export_business_data	reports.export	reports	export	assigned	required	95	3	1
get_account	financial.account	financial	none	assigned	required	85	2	0
get_basalam_overview	integration.basalam	integration	none	assigned	required	95	3	1
get_bom_details	inventory.bom	inventory	none	assigned	required	75	0	0
get_business_credit_settings	financial.credit	financial	none	assigned	required	65	0	0
get_business_dashboard	reports.overview	reports	none	assigned	required	75	0	0
get_business_info	platform.settings	platform	none	explicit_empty	user_context	75	0	0
get_cash_flow	reports.cashflow	reports	none	assigned	required	85	3	0
get_check_details	financial.check	financial	none	assigned	required	75	0	0
get_creditors_report	reports.payables	reports	none	assigned	required	95	4	1
get_crm_summary	crm.summary	crm	none	assigned	required	85	2	0
get_current_fiscal_year	financial.fiscal	financial	none	assigned	required	75	2	0
get_customer_club_rfm_summary	customer_club.loyalty	customer_club	none	assigned	required	75	2	0
get_customer_club_settings	customer_club.loyalty	customer_club	none	assigned	required	85	3	0
get_customer_info	people.person	people	none	assigned	required	75	0	0
get_deal_details	crm.deal	crm	none	assigned	required	75	0	0
get_debtors_report	reports.receivables	reports	none	assigned	required	95	4	1
get_document_details	financial.document	financial	none	assigned	required	65	0	0
get_document_numbering_settings	platform.settings	platform	none	assigned	required	75	0	0
get_financial_summary	reports.financial	reports	none	assigned	required	85	2	0
get_inventory_status	inventory.stock	inventory	none	assigned	required	95	4	1
get_inventory_valuation	reports.inventory	reports	none	assigned	required	85	2	0
get_invoice_details	financial.invoice	financial	none	assigned	required	95	3	2
get_invoices_count	financial.invoice	financial	none	assigned	required	85	2	0
get_lead_details	crm.lead	crm	none	assigned	required	75	0	0
get_lead_funnel_report	reports.crm	reports	none	assigned	required	75	0	0
get_loan_facility	financial.loan	financial	none	assigned	required	75	0	0
get_opening_balance	financial.account	financial	none	assigned	required	65	0	0
get_person_balance	people.person	people	none	assigned	required	75	0	0
get_person_credit	financial.credit	financial	none	assigned	required	65	0	0
get_person_transactions	financial.payment	financial	none	assigned	required	75	0	0
get_pipeline_report	reports.crm	reports	none	assigned	required	75	0	0
get_product_attribute	inventory.product	inventory	none	assigned	required	65	0	0
get_product_info	inventory.product	inventory	none	assigned	required	85	2	0
get_product_kardex	inventory.stock	inventory	none	assigned	required	95	3	1
get_project_summary	misc.general	misc	none	assigned	required	65	0	0
get_purchase_report	reports.purchases	reports	none	assigned	required	95	3	1
get_quick_sales_settings	platform.settings	platform	none	assigned	required	75	0	0
get_repair_order_details	misc.general	misc	none	assigned	required	65	0	0
get_report	reports.overview	reports	none	assigned	required	95	3	2
get_report_template	reports.templates	reports	none	assigned	required	75	0	0
get_report_template_scope_catalog	reports.templates	reports	none	assigned	required	75	0	0
get_sales_report	reports.sales	reports	none	assigned	required	100	5	2
get_tax_data_quality	tax.moadian	tax	none	assigned	required	75	0	0
get_tax_settings	tax.moadian	tax	none	assigned	required	85	3	0
get_wallet_metrics	financial.wallet	financial	none	assigned	required	75	0	0
get_wallet_overview	financial.wallet	financial	none	assigned	required	95	3	1
get_warehouse_document_details	inventory.warehouse	inventory	none	assigned	required	65	0	0
get_warehouse_report	reports.inventory	reports	none	assigned	required	75	0	0
get_warehouse_stock_summary	inventory.stock	inventory	none	assigned	required	75	2	0
get_workflow	automation.workflow	automation	none	assigned	required	75	0	0
get_workflow_component_schema	automation.workflow	automation	none	assigned	required	75	0	0
get_workflow_design_rules	automation.workflow	automation	none	assigned	required	75	0	0
get_workflow_execution_debug	automation.workflow	automation	none	assigned	required	75	0	0
hscript_fix_script	platform.hscript	platform	none	assigned	required	75	0	0
hscript_language_guide	platform.hscript	platform	none	assigned	required	85	2	0
hscript_read_doc	platform.hscript	platform	none	assigned	required	75	0	0
hscript_retrieve_docs	platform.hscript	platform	none	assigned	required	75	0	0
hscript_run_preview	platform.hscript	platform	none	assigned	required	75	0	0
hscript_search_docs	platform.hscript	platform	none	assigned	required	85	3	0
hscript_validate_script	platform.hscript	platform	none	assigned	required	75	0	0
invoke_business_connector	integration.connector	integration	execute	assigned	required	95	2	1
list_accounts	financial.account	financial	none	assigned	required	95	3	1
list_announcements	platform.notifications	platform	none	explicit_empty	user_context	65	0	0
list_available_reports	reports.overview	reports	none	assigned	required	85	2	0
list_bank_accounts	financial.account	financial	none	assigned	required	75	0	0
list_basalam_dead_letter	integration.basalam	integration	none	assigned	required	85	3	0
list_basalam_product_conflicts	integration.basalam	integration	none	assigned	required	75	2	0
list_basalam_synced_invoices	integration.basalam	integration	none	assigned	required	75	2	0
list_boms	inventory.bom	inventory	none	assigned	required	65	0	0
list_business_notification_logs	platform.notifications	platform	none	assigned	required	75	0	0
list_business_notification_templates	platform.notifications	platform	none	assigned	required	75	0	0
list_business_plugins	platform.marketplace	platform	none	assigned	required	85	2	0
list_business_users	platform.settings	platform	none	assigned	required	75	0	0
list_cash_registers	financial.account	financial	none	assigned	required	65	0	0
list_credit_installment_plans	financial.credit	financial	none	assigned	required	65	0	0
list_currencies	financial.currency	financial	none	assigned	required	85	3	0
list_currency_rates	financial.currency	financial	none	assigned	required	75	0	0
list_customer_club_ledger	customer_club.loyalty	customer_club	none	assigned	required	75	2	0
list_customer_club_tiers	customer_club.loyalty	customer_club	none	assigned	required	65	0	0
list_distribution_routes	misc.general	misc	none	assigned	required	75	0	0
list_fiscal_years	financial.fiscal	financial	none	assigned	required	65	0	0
list_frequent_descriptions	financial.document	financial	none	assigned	required	75	0	0
list_loan_facilities	financial.loan	financial	none	assigned	required	75	0	0
list_marketplace_plugins	platform.marketplace	platform	none	assigned	required	85	2	0
list_my_businesses	platform.settings	platform	none	explicit_empty	user_context	75	0	0
list_payment_gateways	financial.payment	financial	none	assigned	required	85	2	0
list_person_groups	people.person	people	none	assigned	required	75	0	0
list_petty_cash	financial.account	financial	none	assigned	required	65	0	0
list_price_list_items	inventory.product	inventory	none	assigned	required	85	2	0
list_price_lists	inventory.product	inventory	none	assigned	required	85	3	0
list_product_attributes	inventory.product	inventory	none	assigned	required	75	0	0
list_queryable_fields	query.meta	query	none	explicit_empty	handler	75	0	0
list_report_templates	reports.templates	reports	none	assigned	required	85	3	0
list_session_todos	agent.plan	agent	none	explicit_empty	agent_internal	75	0	0
list_user_notifications	platform.notifications	platform	none	explicit_empty	user_context	75	0	0
list_wallet_transactions	financial.wallet	financial	none	assigned	required	75	2	0
list_warehouse_locations	inventory.warehouse	inventory	none	assigned	required	75	0	0
list_warehouse_placements	inventory.warehouse	inventory	none	assigned	required	75	0	0
list_warehouses	inventory.warehouse	inventory	none	assigned	required	75	2	0
list_woocommerce_orders	integration.woocommerce	integration	none	assigned	required	85	3	0
list_woocommerce_products	integration.woocommerce	integration	none	assigned	required	85	2	0
list_workflow_action_catalog	automation.workflow	automation	none	assigned	required	75	0	0
list_workflow_builtin_nodes	automation.workflow	automation	none	assigned	required	75	0	0
list_workflow_executions	automation.workflow	automation	none	assigned	required	75	2	0
list_workflow_trigger_catalog	automation.workflow	automation	none	assigned	required	75	0	0
list_workflows	automation.workflow	automation	none	assigned	required	85	5	1
poll_workflow_execution	automation.workflow	automation	none	assigned	required	75	0	0
publish_report_template	reports.templates	reports	write	assigned	required	75	0	0
query_business_data	query.entity	query	none	explicit_empty	handler	95	2	1
read_memory	agent.memory	agent	none	explicit_empty	self_scoped	95	2	1
recalculate_customer_club_rfm	customer_club.loyalty	customer_club	write	assigned	required	75	0	0
resolve_currency_rate	financial.currency	financial	none	assigned	required	75	0	0
resolve_date_range	query.meta	query	none	explicit_empty	user_context	85	3	0
search_activities	crm.activity	crm	none	assigned	required	75	0	0
search_activity_logs	platform.audit	platform	none	assigned	required	65	0	0
search_categories	inventory.product	inventory	none	assigned	required	75	0	0
search_checks	financial.check	financial	none	assigned	required	75	0	0
search_customer_club_rfm_persons	customer_club.loyalty	customer_club	none	assigned	required	65	0	0
search_deals	crm.deal	crm	none	assigned	required	85	3	0
search_documents	financial.document	financial	none	assigned	required	75	0	0
search_expense_income	financial.expense	financial	none	assigned	required	65	0	0
search_invoices	financial.invoice	financial	none	assigned	required	100	6	2
search_leads	crm.lead	crm	none	assigned	required	95	3	1
search_persons	people.person	people	none	assigned	required	95	5	2
search_product_instances	inventory.stock	inventory	none	assigned	required	75	0	0
search_production_documents	inventory.production	inventory	none	assigned	required	75	0	0
search_products	inventory.product	inventory	none	assigned	required	95	4	1
search_projects	misc.general	misc	none	assigned	required	65	0	0
search_receipts_payments	financial.payment	financial	none	assigned	required	85	4	0
search_repair_orders	misc.general	misc	none	assigned	required	75	0	0
search_tax_workspace	tax.moadian	tax	none	assigned	required	75	2	0
search_transfers	financial.transfer	financial	none	assigned	required	65	0	0
search_warehouse_documents	inventory.warehouse	inventory	none	assigned	required	75	0	0
search_warranty_codes	misc.general	misc	none	assigned	required	65	0	0
set_default_report_template	reports.templates	reports	write	assigned	required	75	0	0
spawn_subagent	agent.subagent	agent	none	explicit_empty	agent_internal	75	0	0
test_workflow	automation.workflow	automation	execute	assigned	required	75	0	0
update_account	financial.account	financial	write	assigned	required	75	0	0
update_check	financial.check	financial	write	assigned	required	75	0	0
update_customer_club_settings	customer_club.loyalty	customer_club	write	assigned	required	75	0	0
update_expense_income	financial.expense	financial	write	assigned	required	85	3	0
update_invoice	financial.invoice	financial	write	assigned	required	95	2	1
update_person	people.person	people	write	assigned	required	75	0	0
update_product	inventory.product	inventory	write	assigned	required	85	4	0
update_product_attribute	inventory.product	inventory	write	assigned	required	65	0	0
update_receipt_payment	financial.payment	financial	write	assigned	required	85	3	0
update_session_todo	agent.plan	agent	none	explicit_empty	agent_internal	75	0	0
update_transfer	financial.transfer	financial	write	assigned	required	75	0	0
update_workflow	automation.workflow	automation	write	assigned	required	75	0	0
upsert_memory_entry	agent.memory	agent	write	explicit_empty	self_scoped	95	2	1
validate_workflow_draft	automation.workflow	automation	none	assigned	required	65	0	0
```
