# غنی‌سازی Functionهای AI — وضعیت پیاده‌سازی

## فاز ۰ — زیرساخت permission
- `app/services/ai/ai_permission_map.py`: نگاشت `persons.write` → `people.add` و سایر aliasها
- `function_registry.py`: استفاده از `has_any_ai_tool_permission` در فیلتر و اجرا
- `ai_tool_intent.py`: کلیدواژه «اضافه»، دسته `people`، سقف tools → ۴۸

## فاز ۱ — query گسترده
- Entityهای جدید: `category`, `person_group`, `currency`, `product_attribute`
- Tool: `batch_query_business_data` (حداکثر ۸ پرس‌وجو)

## فاز ۲ — گزارش و read اختصاصی
- Tool: `get_report` (sales_by_product, item_movements, debtors, creditors, cash_flow, inventory_valuation, sales)
- Tools: `search_categories`, `list_person_groups`, `list_currencies`

## فاز ۳ — write
- `delete_person`, `create_product`, `update_product`, `create_check`, `create_transfer`
- همه با `requires_approval=True`

## فاز ۴ — batch/report/write تکمیلی
- `batch_query_business_data`, `get_report`, read tools
- write: `delete_person`, `create_product`, `update_product`, `create_check`, `create_transfer`

## فاز ۵ — write/CRM/workflow/export
- `create_expense_income` — سند هزینه/درآمد ساده (`expenses_income.write`)
- `update_invoice`, `delete_invoice` — (`invoices.write`)
- `create_lead` — CRM (`crm.write` → `crm.add`/`crm.edit`)
- `execute_workflow` — (`workflows.write`)
- `export_business_data` — Excel/PDF با `content_base64` (`reports.read`)
- سرویس همگام: `app/services/ai/ai_export_service.py` (بدون وابستگی به routeهای async)

## آمار تقریبی
| مورد | قبل | بعد |
|------|-----|-----|
| Tools | ~۸۰ | **~۹۷** (+۱۷ از فاز ۴–۵) |
| Entities `query_business_data` | ۲۲ | **۲۶** |
| Write tools (با تأیید) | ۴ | **۱۶** |

## فاز ۶ — گزارشات (اجرایی)
- `ai_reports_catalog.py` + `ai_reports_service.py`
- `list_available_reports` — کاتالوگ گزارش‌های مجاز کاربر
- `get_report` — ~۳۵ `report_type` (تراز، دفتر کل، انبار، باسلام، …)
- جزئیات: [`AI_EXECUTION_PHASES.md`](AI_EXECUTION_PHASES.md)

## فاز ۷ — قالب اسناد (اجرایی MVP)
- `list_report_templates`, `get_report_template`, `get_report_template_scope_catalog`
- `set_default_report_template`, `publish_report_template` (با تأیید)

## فاز ۸ — افزونه / باشگاه / باسلام (اجرایی MVP)
- `list_marketplace_plugins`, `list_business_plugins`
- `get_basalam_overview`, `list_basalam_dead_letter`
- `adjust_customer_club_points`, `recalculate_customer_club_rfm`, `update_customer_club_settings`

## آمار به‌روز
| مورد | مقدار |
|------|--------|
| Tools | **~۱۱۲** |
| انواع `get_report` | **۳۵** |
| Write با تأیید | **~۲۲** |

## فاز ۹ (برنامه — اجرا نشده)
- خرید/trial افزونه، sync باسلام، ساخت قالب از چت
- UI دانلود `content_base64` در Flutter

## باقی‌مانده (اختیاری)
- export چک‌ها، حواله انبار write، `update_deal` CRM
