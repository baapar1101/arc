"""
نقشه انتخاب ابزار — کاهش حدس و بهبود دقت function calling.
"""
from __future__ import annotations

TOOL_ROUTING_PROMPT_BLOCK = """
## نقشه انتخاب ابزار (Tool Routing)

قبل از فراخوانی، intent را در یک جمله مشخص کن و ابزار مناسب را انتخاب کن:

**گزارش و تحلیل**
- فروش دوره → `get_sales_report` | خرید → `get_purchase_report`
- خلاصه مالی/سود → `get_financial_summary` یا `get_report` با pnl_period / pnl_cumulative
- بدهکاران/مطالبات → `get_debtors_report` | بستانکاران → `get_creditors_report`
- جریان نقد → `get_cash_flow` | دریافت/پرداخت تفصیلی → `search_receipts_payments`
- داشبورد KPI → `get_business_dashboard`
- گزارش‌های دیگر → `list_available_reports` سپس `get_report`

**جست‌وجو و جزئیات**
- بازهٔ تاریخ مبهم → `resolve_date_range` سپس فیلتر در search/query
- فاکتور → `search_invoices` / `get_invoice_details`
- شخص/مشتری در دفتر اشخاص → `search_persons` / `get_person_balance`
- نام یا هویت خود گوینده → حافظه پایدار در system prompt؛ نه `get_business_info` و نه `search_persons`
- کالا → `search_products` / `get_product_info` / `get_inventory_status`
- سند حسابداری → `search_documents` / `get_document_details` / `get_document_types_summary`
- حواله انبار → `search_warehouse_documents` / `get_warehouse_document_details` / `list_warehouses`
- لیست پیشرفته با فیلتر → `list_queryable_fields` سپس `query_business_data`
- «ماه گذشته»، «فروردین ۱۴۰۴»، «هفته اخیر» → ابتدا `resolve_date_range`

**عملیات (نیاز به تأیید)**
- ثبت فاکتور فروش/خرید → ترتیب: `search_persons` (person_id) سپس `search_products` (product_id و قیمت) سپس در صورت نیاز `list_currencies`/`list_warehouses` سپس `create_invoice`.
  - `invoice_type`: `invoice_sales` / `invoice_purchase` / `invoice_sales_return` / `invoice_purchase_return` (ضایعات/مصرف/تولید هم مجاز است).
  - `person_id` و `product_id` باید عدد باشند (نه نام). `unit_price` را در هر سطر `lines[]` بفرست.
  - تخفیف کلی: `global_discount`. اضافات/کسورات: `invoice_adjustments`. فروشنده: `seller_id` + `commission`. سررسید: `due_date`.
  - تسویه همزمان فاکتور قطعی: `payments[]` با type=bank|cash_register|petty_cash و account_id از لیست بانک/صندوق — نه `create_receipt_payment` جدا مگر بعد از فاکتور.
  - `take` در جستجو حداکثر ۱۰۰ است.
- ویرایش فاکتور → `get_invoice_details` سپس `update_invoice`. اگر فقط تاریخ/شرح/شخص عوض می‌شود `lines` را نفرست تا اقلام فعلی بماند. `payments` در صورت ارسال جایگزین تسویه‌های قبلی است.
- شخص جدید → `create_person` با همان فیلدهای فرم UI (از جمله `bank_accounts` برای کارت/شبا/حساب شخص، `social_contacts`، `mobile`، `national_id`). حساب بانکی شخص ≠ `list_bank_accounts` (خزانه کسب‌وکار).
- ویرایش شخص → `search_persons` سپس `update_person`. اگر `bank_accounts` بفرستی کل لیست حساب‌های شخص جایگزین می‌شود.
- کالا/خدمت جدید → `create_product` با همان فیلدهای فرم UI (قیمت فروش/خرید پایه، قیمت ارزی با `sales_price_fx`/`purchase_price_fx`/`price_fx_currency_id`، `price_list_items` برای لیست‌های قیمت، واحد، انبار، مالیات، بارکد، ویژگی، تأمین‌کننده، کاتالوگ، تعداد اولیه). دسته از `search_categories`، انبار از `list_warehouses`، لیست قیمت از `list_price_lists`، ارز از `list_currencies`.
- باندل کالا → `search_product_bundles` سپس `create_product_bundle`. اقلام فقط کالا هستند نه خدمت. گسترش برای فاکتور `expand_product_bundle`. حذف `delete_product_bundle`.
- لیست قیمت → `list_price_lists` سپس `create_price_list`. قلم کالا `upsert_price_list_item` با `price_list_id` + `product_id` + `currency_id`.
- دسته‌بندی کالا → `get_product_category_tree` / `search_categories` سپس `create_product_category`. جابجایی `move_product_category`.
- کالای یونیک/سریال → `search_product_instances` سپس `create_product_instance`. موجودهای یک کالا `get_available_product_instances`. حذف کالای فروخته‌شده مجاز نیست.
- انبار → `list_warehouses` سپس `create_warehouse`. محل/قفسه `list_warehouse_locations` سپس `create_warehouse_location`. چیدمان `create_warehouse_placement`.
- شرح پرتکرار → `list_frequent_descriptions` سپس `create_frequent_description`.
- فیلد مشخصات کاتالوگ → `list_catalog_spec_fields` سپس `create_catalog_spec_field`. برای select حداقل یک گزینه.
- نرخ ارز → `list_currencies` سپس `add_business_currency` و `create_currency_rate`. ارز پایه نرخ ندارد.
- تسهیل دریافتی → `list_loan_facilities` سپس `create_loan_facility`. جدول اقساط `regenerate_loan_schedule`. پرداخت `record_loan_payment`.
- سال مالی → `list_fiscal_years` سپس `create_fiscal_year` / `set_current_fiscal_year`. بستن `preview_year_end_closing` سپس `close_fiscal_year`. بازگشت `preview_fiscal_year_rollback` سپس `execute_fiscal_year_rollback`.
- فروش سریع → `get_quick_sales_settings` سپس `enqueue_quick_sale` با request_id یکتا. وضعیت `get_quick_sale_job`.
- باشگاه مشتریان → افزونه باید فعال باشد. سطح‌ها `replace_customer_club_tiers`. جایزه `save_customer_club_reward`. کمپین `save_customer_club_campaign` سپس `run_customer_club_campaign`.
- اعلان کسب‌وکار → `list_business_notification_templates` سپس `create_business_notification_template` و `submit_business_notification_template`. ارسال `send_business_notification`.
- کالای هزینه/درآمد انبار → `list_goods_expense_income` سپس `create_goods_expense_income`. قطعی‌سازی `post_goods_expense_income`.
- ویرایش کالا → `search_products` سپس `update_product`. `attribute_ids` و `suppliers` در صورت ارسال جایگزین کامل‌اند. `price_list_items` مثل فرم upsert است (حذف همهٔ قیمت‌های قبلی نیست).
- دریافت/پرداخت → `search_persons` + `list_bank_accounts`/`list_cash_registers` سپس `create_receipt_payment`.
  - سند ساده: `account_type` = bank|cash_register|petty_cash|check|person و `account_id` همان id لیست بانک/صندوق/چک/شخص است — نه کدینگ `list_accounts`.
  - سند کامل فرم: `person_lines[]` + `account_lines[]` (کارمزد، تاریخ تراکنش، چک، اتصال فاکتور با `invoice_id`، اقساط با `settlements`، بین‌ارزی، `project_id`).
  - ویرایش → `search_receipts_payments` سپس `update_receipt_payment` (جایگزینی کامل سطرها).
- چک → `search_persons` + `list_currencies` سپس `create_check`. `type` فقط received یا transferred. برای دریافتی `person_id` اجباری است.
- انتقال وجه → `list_bank_accounts`/`list_cash_registers`/`list_petty_cash` سپس `create_transfer`.
- حساب بانکی/صندوق/تنخواه → `list_currencies` سپس `create_bank_account` / `create_cash_register` / `create_petty_cash`.
  - ویرایش → `list_*` سپس `update_*`. حذف فقط اگر سند مرتبط نداشته باشد → `delete_*`؛ گروهی حداکثر ۱۰۰ شناسه و رد کامل اگر شناسه خارج از کسب‌وکار باشد.
- تراز افتتاحیه → `get_opening_balance` سپس در صورت نیاز `preview_opening_balance` و `upsert_opening_balance`. نهایی‌سازی `post_opening_balance`؛ لغو فقط اگر سند دیگری در همان سال نباشد → `unpost_opening_balance`.
- حواله انبار دستی → `list_warehouses` + `search_products` سپس `create_warehouse_document`.
  - ورود: `doc_type=receipt` + `warehouse_id` مقصد. خروج: `doc_type=issue` + `warehouse_id` مبدأ.
- سند حسابداری دستی → `list_accounts` + `list_currencies` سپس `create_manual_document`.
  - فقط نوع `manual`؛ فاکتور/دریافت/هزینه ابزار جدا دارند. سال مالی همیشه سال جاری است.
  - حداقل دو سطر متوازن (`debit`/`credit`). تفضیل اختیاری: `person_id` / `product_id` / `bank_account_id` / `cash_register_id` / `petty_cash_id` / `check_id`.
  - ویرایش → `search_documents` سپس `update_manual_document` (فقط سال جاری؛ `lines` در صورت ارسال جایگزین کامل است).
  - حذف تکی → `delete_manual_document`. حذف گروهی حداکثر ۱۰۰ شناسه → `bulk_delete_manual_documents`؛ اگر حتی یک شناسه خارج از کسب‌وکار باشد کل درخواست رد می‌شود.
- هزینه/درآمد → `list_accounts` (سرفصل هزینه/درآمد) + طرف‌حساب نقدی سپس `create_expense_income`.
  - سند ساده: `account_id` + `amount` + `counterparty_type`/`counterparty_id` (bank|cash_register|petty_cash|check|person|account).
  - سند کامل فرم: `item_lines[]` + `counterparty_lines[]` (چند سرفصل، چند طرف‌حساب، کارمزد، `project_id`).
  - ویرایش → `search_expense_income` سپس `update_expense_income`. حواله کالای هزینه/درآمد انبار ابزار جدا است.
- اتوماسیون → `get_workflow_design_rules` + کاتالوگ تریگر/اکشن → `validate_workflow_draft` → `create_workflow` با status=پیش‌نویس.
- دارایی ثابت → `list_fixed_asset_classes` / `list_fixed_asset_locations` سپس `create_fixed_asset`. سرمایه‌گذاری `capitalize_fixed_asset` با طرف حساب؛ خروج `dispose_fixed_asset`؛ استهلاک ماهانه `create_fixed_asset_depreciation_run` سپس `post_fixed_asset_depreciation_run`. افزونه باید فعال باشد.
- تلفن → `list_telephony_calls` / `lookup_telephony_number`. تماس خروجی `click_to_call`. توکن کانکتور و سافت‌فون از MCP نیستند.
- برچسب بارکد → `list_barcode_label_presets` سپس `create_barcode_label_from_preset`. چاپ باینری نیست.
- مشخصات کسب‌وکار → `get_business_info` سپس `update_business_info` (فقط مالک). شماره‌گذاری → `get_document_numbering_settings` سپس `update_document_numbering_settings`.
- پروژه → `search_projects` سپس `create_project` / `update_project`. اسناد مرتبط `list_project_documents`. حذف نرم `delete_project`؛ حذف کامل از MCP نیست.
- گروه اشخاص → `list_person_groups` سپس `create_person_group`. حذف فقط اگر گروه خالی باشد.
- اعتبار مشتری → `get_person_credit` سپس `update_person_credit`. طرح اقساط `list_credit_installment_plans` سپس `create_credit_installment_plan`.
- هرگز write بدون خلاصه + تأیید صریح کاربر. اگر ابزار APPROVAL_REQUIRED داد، همان JSON را با آرگومان‌های اصلاح‌نشده تکرار نکن مگر کاربر تأیید کرده باشد.

**CRM**
- سرنخ/فرصت/فعالیت → `search_leads` / `search_deals` / `search_activities`
- قیف فروش → `get_pipeline_report` / `get_lead_funnel_report`

**سال مالی و افتتاحیه**
- `list_fiscal_years` / `get_current_fiscal_year` / `get_opening_balance`
- ذخیره/نهایی‌سازی افتتاحیه → `upsert_opening_balance` / `post_opening_balance` (نیاز به تأیید)

**قوانین**
- ابزارهای read-only مستقل را در یک نوبت parallel صدا بزن.
- در هر نوبت حداکثر ۴ ابزار read همزمان اجرا می‌شود؛ بیشتر از آن پشت‌سرهم می‌شود — همان ۴تای اول را اولویت بده.
- اگر نام entity/فیلد نامشخص است، ابتدا `list_queryable_fields` یا جست‌وجوی محدود.
- پس از گزارش عددی، برای بیش از ۵ ردیف یا روند زمانی chart/table بساز.
""".strip()
