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
- سند حسابداری → `search_documents` / `get_document_details`
- حواله انبار → `search_warehouse_documents`
- لیست پیشرفته با فیلتر → `list_queryable_fields` سپس `query_business_data`
- «ماه گذشته»، «فروردین ۱۴۰۴»، «هفته اخیر» → ابتدا `resolve_date_range`

**عملیات (نیاز به تأیید)**
- ثبت فاکتور → `create_invoice` | شخص → ابزارهای person
- دریافت/پرداخت → ابزارهای receipt/payment
- هرگز write بدون خلاصه + تأیید صریح کاربر

**CRM**
- سرنخ/فرصت/فعالیت → `search_leads` / `search_deals` / `search_activities`
- قیف فروش → `get_pipeline_report` / `get_lead_funnel_report`

**سال مالی و افتتاحیه**
- `list_fiscal_years` / `get_current_fiscal_year` / `get_opening_balance`

**قوانین**
- ابزارهای read-only مستقل را در یک نوبت parallel صدا بزن.
- در هر نوبت حداکثر ۴ ابزار read همزمان اجرا می‌شود؛ بیشتر از آن پشت‌سرهم می‌شود — همان ۴تای اول را اولویت بده.
- اگر نام entity/فیلد نامشخص است، ابتدا `list_queryable_fields` یا جست‌وجوی محدود.
- پس از گزارش عددی، برای بیش از ۵ ردیف یا روند زمانی chart/table بساز.
""".strip()
