# اتوماسیون workflow از چت AI — فازهای اجرایی

## اصل طراحی

- **منبع حقیقت:** `TriggerRegistry`, `ActionRegistry`, `WorkflowBuiltinNodeRegistry`
- تریگر/اکشن جدید با `register()` در workflow — **بدون تغییر کد AI**
- پرامپت فقط به ابزارهای کاتالوگ ارجاع می‌دهد، نه لیست ثابت

## فاز ۱ — کشف پویا (پیاده‌سازی شده)

| Tool | نقش |
|------|-----|
| `list_workflow_trigger_catalog` | لیست تریگرها از رجیستری |
| `list_workflow_action_catalog` | لیست اکشن‌ها |
| `list_workflow_builtin_nodes` | condition / loop |
| `get_workflow_component_schema` | schema کامل یک جزء |
| `get_workflow_design_rules` | قوانین گراف |

فایل‌ها: `ai_workflow_catalog_service.py`, `workflow_builtin_node_registry.py`

## فاز ۲ — طراحی و ذخیره (پیاده‌سازی شده)

| Tool | نقش |
|------|-----|
| `validate_workflow_draft` | همان `validate_workflow_data` |
| `create_workflow` | ایجاد (پیش‌نویس) + تأیید کاربر |
| `update_workflow` | ویرایش / فعال‌سازی + تأیید |
| `delete_workflow` | حذف + تأیید |
| `get_workflow` | دریافت گراف کامل |

فایل: `ai_workflow_service.py`

## فاز ۳ — تست و دیباگ از چت (پیاده‌سازی شده)

| Tool | نقش |
|------|-----|
| `test_workflow` | dry_run حتی برای پیش‌نویس (مستقیم engine) |
| `get_workflow_execution_debug` | لاگ و خطاهای نود |
| `execute_workflow` | اجرای واقعی (موجود، workflow فعال) |

## فاز ۴ — بهبودها (پیاده‌سازی شده)

| قابلیت | توضیح |
|--------|--------|
| `test_workflow` + `workflow_data` | تست روی sandbox `[AI] پیش‌نمایش آزمایشی` بدون تغییر اتوماسیون کاربر |
| `wait_for_completion` | poll داخلی تا پایان اجرا + `debug` و `summary` در یک پاسخ |
| `poll_workflow_execution` | polling دستی لاگ (`after_log_id`) |
| `editor_path` | در create/update/get/test برای ارجاع به ادیتور |
| `ai_workflow_agent_policy` | denylist پیش‌فرض ابزار workflow در نود `ai_agent` |

فایل‌ها: `ai_workflow_agent_policy.py`، به‌روزرسانی `ai_workflow_service.py`, `ai_agent_action.py`

## جریان گفتگوی پیشنهادی

1. `get_workflow_design_rules`
2. `list_workflow_trigger_catalog` + انتخاب تریگر
3. `get_workflow_component_schema` برای تریگر و هر اکشن
4. ساخت `workflow_data` → `validate_workflow_draft`
5. `create_workflow` (پیش‌نویس)
6. `test_workflow` → `get_workflow_execution_debug`
7. پس از تأیید: `update_workflow` با `status=فعال`
