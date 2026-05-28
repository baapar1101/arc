# فازهای اجرایی غنی‌سازی AI (۶–۸)

این سند **برنامهٔ اجرا** و وضعیت پیاده‌سازی فازهای بعد از فاز ۰–۵ است. جزئیات تحلیل شکاف: [`AI_CAPABILITY_GAP_SCENARIO_V2.md`](AI_CAPABILITY_GAP_SCENARIO_V2.md).

---

## نمای کلی

| فاز | عنوان | وضعیت | ابزارهای جدید |
|-----|--------|--------|----------------|
| **۶** | گزارشات یکپارچه | ✅ پیاده‌سازی شده | `list_available_reports` + گسترش `get_report` (~۳۵ نوع) |
| **۷** | قالب اسناد / چاپ | ✅ پیاده‌سازی شده (MVP) | ۵ tool (۳ read، ۲ write با تأیید) |
| **۸** | افزونه‌ها و باشگاه و باسلام | ✅ پیاده‌سازی شده (MVP) | ۸ tool |
| **۹** | یکپارچه‌سازی write (اختیاری) | 📋 برنامه | sync باسلام، خرید افزونه، … |
| **۱۰** | جست‌وجوی پیشرفته QueryInfo | ✅ | `list_queryable_fields` + `filters[]` در query |
| **۱۱** | toolهای search اختصاصی + OpenAPI | ✅ | `search_invoices/persons/products/...` + مستندات `/docs` |
| **۱۲** | OpenAPI یکپارچه endpointها | ✅ | `QueryInfo` / `DocumentListQuery` در Body + `GET /query-schema/{entity}` |

**تعداد تقریبی tools:** ~۹۸ → **~۱۱۳**

جزئیات: [`AI_ADVANCED_SEARCH_SCENARIO.md`](AI_ADVANCED_SEARCH_SCENARIO.md)

## فاز ۱۲ — OpenAPI یکپارچه + query-schema

| # | تحویل | فایل |
|---|--------|------|
| ۱۲.۱ | مدل‌های `DocumentListQuery`, `InvoiceListQuery`, `KardexListQuery`, `WarehouseDocListQuery` | `adapters/api/v1/schemas.py` |
| ۱۲.۲ | helper مشترک Body و تبدیل به dict سرویس | `adapters/api/v1/list_query_common.py` |
| ۱۲.۳ | endpoint `GET /api/v1/query-schema/{entity}` | `adapters/api/v1/query_schema.py` |
| ۱۲.۴ | پچ OpenAPI برای requestBody لیست‌ها | `app/openapi_list_query_patch.py`, `main.py` `custom_openapi` |
| ۱۲.۵ | endpointهای به‌روز: persons, checks, documents, invoices/search, receipts, transfers, expense, kardex, bank/cash/petty, warehouse/search | همان ماژول‌های API |

---

## فاز ۱۱ — toolهای search + مستندات OpenAPI

- `ai_tool_query_params.py` — schema مشترک `filters[]` برای همه toolهای لیست
- به‌روزرسانی: `search_invoices`, `search_persons`, `search_products`, `search_receipts_payments`
- extension tools: چک، انتقال، هزینه/درآمد، سند، حواله انبار — با `entity` در `_build_list_query`
- **OpenAPI:** بخش «جستجو و فیلتر پیشرفته» در ابتدای `/docs` + Components `FilterItem` / `QueryInfo`
- فایل مرجع: `app/openapi_query_filter_docs.py`

---

## فاز ۶ — گزارشات

### هدف
پوشش ~۸۰٪ سوالات «گزارش بده» بدون tool جدا برای هر صفحه UI.

### تحویل‌ها
| # | مورد | فایل |
|---|------|------|
| ۶.۱ | کاتالوگ گزارش + permission | `ai_reports_catalog.py` |
| ۶.۲ | اجرای گزارش | `ai_reports_service.py` → `execute_ai_report` |
| ۶.۳ | `list_available_reports` | `ai_function_extensions_phase6.py` |
| ۶.۴ | `get_report` از سرویس مشترک | `ai_function_extensions_phase4.py` |
| ۶.۵ | intent + alias | `ai_tool_intent.py`, `ai_permission_map.py` |

### انواع `report_type` (نمونه)
- **financial:** debtors, creditors, cash_flow, people_transactions, bank_accounts_turnover, cash_petty_turnover
- **sales:** sales_by_product, daily_sales, monthly_sales, top_customers, …
- **warehouse:** inventory_stock, inventory_kardex, slow_moving_items, critical_stock, …
- **accounting:** trial_balance, general_ledger*, journal_ledger, pnl_period, accounts_review
- **integration:** basalam_overview, basalam_dead_letter, distribution_dashboard**

\* `general_ledger` نیاز به `account_ids` یا `account_id`  
\** `distribution_dashboard` نیاز به `from_date`, `to_date`

### جریان پیشنهادی برای مدل
1. `list_available_reports` (اختیاری: `category`)
2. `get_report` با `report_type` + بازه تاریخ

---

## فاز ۷ — قالب اسناد

### هدف
لیست/جزئیات قالب؛ تنظیم پیش‌فرض و انتشار با تأیید کاربر.

### Tools
| Tool | نوع | permission |
|------|-----|------------|
| `list_report_templates` | read | report_templates.view |
| `get_report_template` | read | report_templates.view |
| `get_report_template_scope_catalog` | read | report_templates.view |
| `set_default_report_template` | write + تأیید | report_templates.write |
| `publish_report_template` | write + تأیید | report_templates.write |

### خارج از scope فعلی
- `create_report_template` / ویرایش HTML builder از چت
- `preview_report_template` با PDF base64

---

## فاز ۸ — افزونه‌ها، باشگاه، باسلام

### Tools
| Tool | نوع |
|------|-----|
| `list_marketplace_plugins` | read |
| `list_business_plugins` | read |
| `get_basalam_overview` | read |
| `list_basalam_dead_letter` | read |
| `adjust_customer_club_points` | write + تأیید |
| `recalculate_customer_club_rfm` | write + تأیید |
| `update_customer_club_settings` | write + تأیید |

### فاز ۹ (پیشنهادی — هنوز اجرا نشده)
- `purchase_marketplace_plugin`, `start_plugin_trial`
- `trigger_basalam_sync` (enum operation)
- `resolve_basalam_product_conflict`
- `get_woocommerce_overview` / bridge health
- `create_report_template` + `preview_report_template`

---

## چک‌لیست merge هر فاز

- [ ] `function_registry.py` — `register_phaseN`
- [ ] `ai_permission_map.py`
- [ ] `ai_write_guard.py` + `ai_tool_intent.py`
- [ ] `ai_tool_keys.py` + `ai_chat_l10n.dart`
- [ ] `python3 -m py_compile` روی ماژول‌های جدید
- [ ] به‌روزرسانی این سند و `AI_FUNCTION_ENRICHMENT_PHASES.md`
