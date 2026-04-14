# گزارش مشکلات بخش Workflow

این گزارش شامل تمام مشکلات شناسایی شده در بخش workflow (فرانت‌اند و بک‌اند) است.

**تاریخ بررسی:** 2025-01-XX  
**وضعیت:** بدون تغییر (فقط بررسی)

---

## 🔴 مشکلات امنیتی (Critical)

### 1. استفاده از `eval()` در workflow_engine.py
**فایل:** `hesabixAPI/app/services/workflow/workflow_engine.py:672`  
**مشکل:** استفاده از `eval()` برای اجرای expression در condition nodes که یک خطر امنیتی جدی است.  
**ریسک:** امکان اجرای کد دلخواه توسط کاربران  
**کد مشکل‌دار:**
```python
result = eval(expression, {"__builtins__": {}}, env)
```
**راه‌حل پیشنهادی:** استفاده از یک expression engine امن مثل `simpleeval` یا `asteval`

---

## ⚠️ مشکلات عملکردی (Performance)

### 2. شمارش ناکارآمد در list_workflow_executions
**فایل:** `hesabixAPI/adapters/api/v1/workflows.py:287`  
**مشکل:** استفاده از `len(list(...))` برای شمارش که تمام رکوردها را از دیتابیس می‌خواند  
**کد مشکل‌دار:**
```python
total_count = len(list(db.execute(stmt).scalars().all()))
```
**راه‌حل پیشنهادی:** استفاده از `func.count()` قبل از offset/limit

### 3. Cache بدون Thread Safety
**فایل:** `hesabixAPI/app/services/workflow/workflow_engine.py:33-34`  
**مشکل:** Cache در سطح کلاس است اما `_cache_lock` مقدار `None` دارد و thread-safe نیست  
**کد مشکل‌دار:**
```python
_result_cache: Dict[str, tuple] = {}  # cache_key -> (result, timestamp)
_cache_lock = None  # برای thread safety
```
**ریسک:** Race condition در محیط multi-threaded  
**راه‌حل پیشنهادی:** استفاده از `threading.Lock()` یا `asyncio.Lock()`

---

## 🐛 مشکلات منطقی (Logic Errors)

### 4. استفاده از مقدار hardcoded فارسی برای status
**فایل:** `hesabixAPI/app/services/workflow/workflow_trigger_service.py:70`  
**مشکل:** استفاده از رشته فارسی hardcoded به جای enum  
**کد مشکل‌دار:**
```python
if execution.status.value == "تکمیل شده":
```
**مشکل:** اگر enum تغییر کند یا زبان تغییر کند، کد کار نمی‌کند  
**راه‌حل پیشنهادی:** استفاده از `WorkflowExecutionStatus.COMPLETED`

### 5. استفاده از raw SQL که database-agnostic نیست
**فایل:** `hesabixAPI/adapters/api/v1/workflows.py:481-488`  
**مشکل:** استفاده از `TIMESTAMPDIFF` که syntax خاص MySQL است  
**کد مشکل‌دار:**
```python
text("TIMESTAMPDIFF(SECOND, workflow_executions.started_at, workflow_executions.completed_at)")
```
**مشکل:** در PostgreSQL یا SQLite کار نمی‌کند  
**راه‌حل پیشنهادی:** استفاده از SQLAlchemy functions یا database-agnostic approach

### 6. عدم اعتبارسنجی ساختار workflow_data قبل از ذخیره
**فایل:** `hesabixAPI/adapters/api/v1/workflows.py:49-51, 185-186`  
**مشکل:** فقط بررسی می‌کند که `workflow_data` وجود دارد، اما ساختار آن را validate نمی‌کند  
**کد مشکل‌دار:**
```python
workflow_data = body.get("workflow_data", {})
if not workflow_data:
    raise ApiError("WORKFLOW_DATA_REQUIRED", "داده‌های workflow الزامی است")
```
**مشکل:** ممکن است workflow_data ساختار نامعتبر داشته باشد  
**راه‌حل پیشنهادی:** اضافه کردن validation برای ساختار JSON

### 7. عدم بررسی duplicate node IDs در frontend
**فایل:** `hesabixUI/hesabix_ui/lib/pages/business/workflow_visual_editor_page.dart`  
**مشکل:** هنگام افزودن node جدید، بررسی نمی‌شود که ID تکراری نباشد  
**ریسک:** تداخل در اجرای workflow  
**راه‌حل پیشنهادی:** بررسی duplicate ID قبل از افزودن node

---

## 🔧 مشکلات کدنویسی (Code Quality)

### 8. عدم مدیریت صحیح Transaction در error cases
**فایل:** `hesabixAPI/app/services/workflow/workflow_engine.py`  
**مشکل:** در برخی موارد خطا، transaction rollback نمی‌شود  
**مثال:** در خط 142-192، اگر exception رخ دهد، ممکن است execution record ذخیره شود اما workflow کامل نشود

### 9. عدم validation برای empty workflow_data
**فایل:** `hesabixUI/hesabix_ui/lib/pages/business/workflow_visual_editor_page.dart:587`  
**مشکل:** هنگام ذخیره، بررسی نمی‌شود که workflow_data خالی نباشد  
**کد:**
```dart
'workflow_data': _editorState.toBackendFormat(),
```
**راه‌حل پیشنهادی:** بررسی قبل از ارسال به API

### 10. استفاده از localization string به جای enum value
**فایل:** `hesabixUI/hesabix_ui/lib/pages/business/workflow_visual_editor_page.dart:586`  
**مشکل:** status با مقدار localization string تنظیم می‌شود  
**کد مشکل‌دار:**
```dart
'status': _workflow?['status'] ?? AppLocalizations.of(context).workflowDraft,
```
**مشکل:** باید از enum value استفاده شود نه string ترجمه شده  
**راه‌حل پیشنهادی:** استفاده از enum value (مثل "پیش‌نویس")

### 11. Hardcoded status values در frontend
**فایل:** `hesabixUI/hesabix_ui/lib/pages/business/workflows_page.dart:44-48`  
**مشکل:** mapping status با مقادیر hardcoded فارسی  
**کد مشکل‌دار:**
```dart
static const Map<String, String> _statusApiValues = {
  'active': 'فعال',
  'inactive': 'غیرفعال',
  'draft': 'پیش‌نویس',
};
```
**مشکل:** اگر backend enum تغییر کند، frontend کار نمی‌کند  
**راه‌حل پیشنهادی:** استفاده از enum مشترک یا API برای دریافت status values

---

## 📝 مشکلات UX/UI

### 12. عدم نمایش loading state در برخی عملیات
**فایل:** `hesabixUI/hesabix_ui/lib/pages/business/workflow_visual_editor_page.dart`  
**مشکل:** در عملیات async مثل `_loadTemplate` و `_saveAsTemplate` loading indicator نمایش داده نمی‌شود

### 13. عدم retry logic برای failed requests
**فایل:** `hesabixUI/hesabix_ui/lib/services/workflow_service.dart`  
**مشکل:** در صورت خطای شبکه، retry نمی‌شود  
**راه‌حل پیشنهادی:** اضافه کردن retry logic با exponential backoff

### 14. عدم نمایش خطای دقیق در برخی موارد
**فایل:** `hesabixUI/hesabix_ui/lib/pages/business/workflows_page.dart:536-541`  
**مشکل:** در `_runWorkflow`، خطای دقیق نمایش داده نمی‌شود  
**کد:**
```dart
SnackBarHelper.showError(context, message: AppLocalizations.of(context).workflowErrorExecuting);
```
**راه‌حل پیشنهادی:** نمایش پیام خطای دقیق از API

---

## 🔄 مشکلات همگام‌سازی (Synchronization)

### 15. عدم بررسی concurrent modifications
**فایل:** `hesabixAPI/adapters/api/v1/workflows.py:174-197`  
**مشکل:** در `update_workflow`، بررسی نمی‌شود که workflow توسط کاربر دیگری تغییر نکرده باشد  
**ریسک:** Overwrite کردن تغییرات همزمان  
**راه‌حل پیشنهادی:** استفاده از optimistic locking با `updated_at` یا version field

### 16. عدم بررسی workflow status قبل از execute
**فایل:** `hesabixUI/hesabix_ui/lib/pages/business/workflows_page.dart:525-542`  
**مشکل:** در `_runWorkflow`، بررسی نمی‌شود که workflow فعال است یا نه  
**راه‌حل پیشنهادی:** بررسی status قبل از اجرا

---

## 📊 مشکلات داده (Data Issues)

### 17. عدم پاکسازی cache منقضی شده به صورت دوره‌ای
**فایل:** `hesabixAPI/app/services/workflow/workflow_engine.py:506-520`  
**مشکل:** `_cleanup_cache` فقط زمانی فراخوانی می‌شود که cache بیش از 1000 entry داشته باشد  
**مشکل:** cache entries منقضی شده ممکن است برای مدت طولانی باقی بمانند  
**راه‌حل پیشنهادی:** اجرای periodic cleanup task

### 18. عدم محدودیت برای اندازه workflow_data
**فایل:** `hesabixAPI/adapters/api/v1/workflows.py:49`  
**مشکل:** هیچ محدودیتی برای اندازه `workflow_data` وجود ندارد  
**ریسک:** ممکن است workflow_data بسیار بزرگ شود و باعث مشکل در دیتابیس شود  
**راه‌حل پیشنهادی:** اضافه کردن validation برای حداکثر اندازه

---

## 🧪 مشکلات Testing

### 19. عدم unit test برای workflow engine
**مشکل:** هیچ test file برای `workflow_engine.py` وجود ندارد  
**ریسک:** تغییرات ممکن است bugs جدید ایجاد کنند

### 20. عدم integration test برای workflow execution
**مشکل:** هیچ test برای end-to-end workflow execution وجود ندارد

---

## 📚 مشکلات مستندسازی

### 21. عدم مستندسازی API endpoints
**مشکل:** برخی endpoints دارای description کافی نیستند  
**مثال:** `get_workflow_errors_analytics` و `get_workflow_performance_analytics`

### 22. عدم مستندسازی error codes
**مشکل:** error codes استفاده شده در API مستندسازی نشده‌اند  
**مثال:** `WORKFLOW_NAME_REQUIRED`, `WORKFLOW_DATA_REQUIRED`

---

## 🔍 مشکلات دیگر

### 23. عدم پشتیبانی از workflow versioning
**مشکل:** هیچ سیستم versioning برای workflowها وجود ندارد  
**ریسک:** نمی‌توان تغییرات workflow را track کرد

### 24. عدم پشتیبانی از workflow templates در backend
**مشکل:** templates فقط در frontend (SharedPreferences) ذخیره می‌شوند  
**ریسک:** templates بین دستگاه‌ها sync نمی‌شوند

### 25. عدم محدودیت برای تعداد nodeها در یک workflow
**مشکل:** هیچ محدودیتی برای تعداد nodeها وجود ندارد  
**ریسک:** ممکن است workflow بسیار پیچیده شود و performance مشکل پیدا کند

---

## 📋 خلاصه

| دسته | تعداد مشکلات |
|------|-------------|
| امنیتی (Critical) | 1 |
| عملکردی | 2 |
| منطقی | 4 |
| کدنویسی | 4 |
| UX/UI | 3 |
| همگام‌سازی | 2 |
| داده | 2 |
| Testing | 2 |
| مستندسازی | 2 |
| دیگر | 3 |
| **جمع کل** | **25** |

---

## اولویت‌بندی

### اولویت بالا (باید فوراً رفع شود):
1. مشکل #1: استفاده از `eval()` (امنیتی)
2. مشکل #4: hardcoded status values
3. مشکل #6: عدم validation workflow_data

### اولویت متوسط:
4. مشکل #2: شمارش ناکارآمد
5. مشکل #3: Cache thread safety
6. مشکل #5: Raw SQL database-specific
7. مشکل #15: Concurrent modifications

### اولویت پایین:
8. مشکلات UX/UI
9. مشکلات Testing
10. مشکلات مستندسازی

---

**نکته:** این گزارش فقط مشکلات را شناسایی کرده و هیچ تغییری در کد ایجاد نکرده است.




