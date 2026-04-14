# 🎨 قابلیت‌های لاگینگ در فرانت‌اند Workflow

## 📅 تاریخ: 2025-12-04
## نسخه: 1.0.0

---

## 🎯 خلاصه

این مستند قابلیت‌های جدیدی که در فرانت‌اند (Flutter) برای استفاده از سیستم لاگینگ و خطایابی بخش اتوماسیون اضافه شده است را شرح می‌دهد.

---

## 📦 فایل‌های جدید/تغییر یافته

### فایل‌های جدید:

1. **`workflow_analytics_dialog.dart`** ⭐
   - دیالوگ نمایش آمار و تحلیل workflow
   - شامل 2 تب: عملکرد و خطاها
   - نمودار دایره‌ای برای خطاها

2. **`workflow_timeline_dialog.dart`** ⭐
   - دیالوگ نمایش Timeline دقیق اجرای workflow
   - فیلتر بر اساس سطح لاگ (info, warning, error, debug)
   - فیلتر بر اساس node
   - نمایش آمار هر node

### فایل‌های تغییر یافته:

1. **`workflow_service.dart`**
   - اضافه کردن `getWorkflowErrorsAnalytics()`
   - اضافه کردن `getWorkflowPerformanceAnalytics()`
   - اضافه کردن `getExecutionTimeline()`

2. **`workflow_execution_history_panel.dart`**
   - اضافه کردن دکمه Analytics به header
   - اضافه کردن دکمه Timeline به جزئیات اجرا

3. **`workflows_page.dart`**
   - اضافه کردن دکمه Analytics به AppBar

---

## 🚀 قابلیت‌های جدید

### 1. دیالوگ Analytics (تحلیل و آمار)

#### 📊 تب عملکرد:

**ویژگی‌ها:**
- نمایش آمار کلی workflows
- انتخاب بازه زمانی (7، 14، 30، 60، 90 روز)
- متریک‌های کلیدی برای هر workflow:
  - 🔵 کل اجراها
  - ✅ اجراهای موفق
  - ❌ اجراهای ناموفق
  - ⏱️ میانگین زمان اجرا
- نرخ موفقیت با نمایش بصری (Progress Bar)
- رنگ‌بندی بر اساس نرخ موفقیت:
  - سبز: بیشتر از 95%
  - نارنجی: 80-95%
  - قرمز: کمتر از 80%

**نحوه دسترسی:**
```dart
// از صفحه workflows
IconButton(
  icon: Icon(Icons.analytics_outlined),
  onPressed: () => showDialog(
    context: context,
    builder: (context) => WorkflowAnalyticsDialog(
      businessId: businessId,
    ),
  ),
)

// یا از history panel
IconButton(
  icon: Icon(Icons.analytics_outlined),
  onPressed: () => showDialog(
    context: context,
    builder: (context) => WorkflowAnalyticsDialog(
      businessId: businessId,
      workflowId: workflowId,
    ),
  ),
)
```

#### 🐛 تب خطاها:

**ویژگی‌ها:**
- خلاصه کلی خطاها:
  - 🔴 تعداد کل خطاها
  - 📂 تعداد انواع خطا
- نمودار دایره‌ای (Pie Chart) توزیع خطاها
- لیست جزئیات خطاها شامل:
  - نوع خطا
  - تعداد رخداد
  - درصد از کل
  - آخرین زمان وقوع
- پیام تبریک در صورت نبود خطا! 🎉

**API استفاده شده:**
```dart
// تحلیل خطاها
final errors = await workflowService.getWorkflowErrorsAnalytics(
  businessId: businessId,
  workflowId: workflowId, // اختیاری
  days: 7,
);

// تحلیل عملکرد
final performance = await workflowService.getWorkflowPerformanceAnalytics(
  businessId: businessId,
  workflowId: workflowId, // اختیاری
  days: 30,
);
```

---

### 2. دیالوگ Timeline (خط زمانی اجرا)

#### 🕐 ویژگی‌های Timeline:

**بخش اطلاعات اجرا:**
- وضعیت اجرا (موفق/ناموفق/در حال اجرا)
- مدت زمان کل
- زمان شروع و پایان
- پیام خطا (در صورت وجود)

**آمار خلاصه:**
- 📋 کل لاگ‌ها
- 🌳 تعداد نودهای اجرا شده
- ❌ تعداد خطاها

**جدول آمار نودها:**
- نام node
- نوع node (trigger, action, condition, loop)
- تعداد اجراها
- تعداد خطاها
- میانگین زمان اجرا (ms)

**فیلترهای پیشرفته:**
- فیلتر بر اساس سطح لاگ:
  - 🔵 Info
  - 🟡 Warning
  - 🔴 Error
  - 🟣 Debug
- فیلتر بر اساس node خاص

**Timeline بصری:**
- نمایش لاگ‌ها به ترتیب زمانی
- آیکون‌های رنگی بر اساس سطح لاگ
- خط ارتباطی بین لاگ‌ها
- نمایش اطلاعات کامل هر لاگ:
  - زمان دقیق (HH:mm:ss.SSS)
  - شناسه node
  - پیام
  - داده‌های اضافی (duration_ms, error_type, ...)

**نحوه دسترسی:**
```dart
// از execution details
IconButton(
  icon: Icon(Icons.timeline),
  onPressed: () => showDialog(
    context: context,
    builder: (context) => WorkflowTimelineDialog(
      businessId: businessId,
      workflowId: workflowId,
      executionId: executionId,
    ),
  ),
)
```

**API استفاده شده:**
```dart
final timeline = await workflowService.getExecutionTimeline(
  businessId: businessId,
  workflowId: workflowId,
  executionId: executionId,
);
```

---

## 🎨 تصاویر و UI Components

### Analytics Dialog:

```
┌────────────────────────────────────────────────────────┐
│ 📊 آمار و تحلیل                                [X]    │
├────────────────────────────────────────────────────────┤
│ [عملکرد] [خطاها]                                       │
├────────────────────────────────────────────────────────┤
│                                                         │
│ بازه زمانی: [7 روز] [14 روز] [30 روز] [60] [90]      │
│                                                         │
│ ┌─────────────────────────────────────────────┐         │
│ │ Workflow: ارسال ایمیل خوشامدگویی          │         │
│ │                                              │         │
│ │ 🔵 کل: 1250  ✅ موفق: 1230  ❌ ناموفق: 20  │         │
│ │ ⏱️ میانگین: 2.34s                          │         │
│ │                                              │         │
│ │ نرخ موفقیت: 98.4%                          │         │
│ │ ████████████████████░░ 98.4%                │         │
│ └─────────────────────────────────────────────┘         │
│                                                         │
└────────────────────────────────────────────────────────┘
```

### Timeline Dialog:

```
┌────────────────────────────────────────────────────────┐
│ ⏱️ Timeline اجرا                           [↻] [X]    │
├────────────────────────────────────────────────────────┤
│ ✅ وضعیت: تکمیل شده                 ⏱️ 2.34s         │
│ ▶️ شروع: 2025/12/04 10:30:00                          │
│ ⏹️ پایان: 2025/12/04 10:30:02                         │
├────────────────────────────────────────────────────────┤
│ [📋 15] [🌳 5] [❌ 0]                                   │
├────────────────────────────────────────────────────────┤
│ فیلتر: [همه سطوح ▼] [همه نودها ▼]                    │
├────────────────────────────────────────────────────────┤
│ ● ─ 10:30:00.123 [trigger_1]                          │
│ │   Workflow started                                  │
│ │   📦 duration_ms: 45.23                            │
│ │                                                     │
│ ● ─ 10:30:00.456 [action_1]                          │
│ │   Action executed successfully                     │
│ │   📦 duration_ms: 234.56                           │
│ │                                                     │
│ ● ─ 10:30:02.789 [workflow]                          │
│     Workflow completed                               │
│     📦 duration_ms: 2340.12                          │
└────────────────────────────────────────────────────────┘
```

---

## 📱 نحوه استفاده

### 1. مشاهده آمار کل workflows:

1. بروید به صفحه **اتوماسیون‌ها**
2. روی آیکون **📊 Analytics** در AppBar کلیک کنید
3. بازه زمانی دلخواه را انتخاب کنید
4. آمار تمام workflows را مشاهده کنید

### 2. مشاهده آمار یک workflow خاص:

1. بروید به **ویرایشگر workflow**
2. در پنل **تاریخچه اجرا** روی **📊 Analytics** کلیک کنید
3. آمار فقط همان workflow نمایش داده می‌شود

### 3. مشاهده Timeline یک اجرا:

1. در پنل **تاریخچه اجرا**
2. روی یک اجرا کلیک کنید
3. در **جزئیات اجرا** روی **⏱️ Timeline** کلیک کنید
4. Timeline کامل با تمام لاگ‌ها نمایش داده می‌شود

---

## 🎯 موارد استفاده (Use Cases)

### Use Case 1: شناسایی workflow های کند

**مشکل:** نمی‌دانیم کدام workflow ها کند هستند

**راه‌حل:**
1. از دکمه Analytics استفاده کنید
2. تب عملکرد را باز کنید
3. workflows را بر اساس "میانگین زمان" مرتب کنید
4. workflow های با زمان بالا را شناسایی کنید

### Use Case 2: پیدا کردن علت خطای مکرر

**مشکل:** یک workflow مدام خطا می‌دهد

**راه‌حل:**
1. از دکمه Analytics استفاده کنید
2. تب خطاها را باز کنید
3. نوع خطاهای رایج را شناسایی کنید
4. روی یک اجرای ناموفق کلیک کنید
5. از Timeline جزئیات دقیق خطا را ببینید

### Use Case 3: بررسی عملکرد یک node خاص

**مشکل:** می‌خواهیم بدانیم یک node چقدر زمان می‌برد

**راه‌حل:**
1. یک اجرا را انتخاب کنید
2. Timeline را باز کنید
3. در جدول "آمار نودها" میانگین زمان هر node را ببینید
4. یا Timeline را فیلتر کنید روی آن node

### Use Case 4: Debugging خطای خاص

**مشکل:** یک اجرا با خطای عجیبی fail شده

**راه‌حل:**
1. اجرای ناموفق را انتخاب کنید
2. Timeline را باز کنید
3. فیلتر را روی "Error" بگذارید
4. لاگ خطا را ببینید که شامل:
   - error_type
   - error_message
   - stack_trace
   - correlation_id

---

## 🔧 تنظیمات و سفارشی‌سازی

### تغییر بازه زمانی پیش‌فرض:

```dart
// در WorkflowAnalyticsDialog
int _performanceDays = 30; // تغییر به مقدار دلخواه
int _errorsDays = 7;
```

### تغییر رنگ‌های نرخ موفقیت:

```dart
Color _getSuccessRateColor(double rate) {
  if (rate >= 95) return Colors.green;    // تغییر به دلخواه
  if (rate >= 80) return Colors.orange;   // تغییر به دلخواه
  return Colors.red;
}
```

### اضافه کردن فیلترهای بیشتر:

```dart
// در Timeline Dialog
DropdownButton<String>(
  items: [
    DropdownMenuItem(value: 'all', child: Text('همه سطوح')),
    DropdownMenuItem(value: 'custom', child: Text('سفارشی')), // ✅ جدید
  ],
  // ...
)
```

---

## 📊 وابستگی‌ها

این ویجت‌ها به package های زیر وابسته هستند:

```yaml
dependencies:
  flutter:
    sdk: flutter
  intl: ^0.18.0          # برای فرمت تاریخ
  fl_chart: ^0.66.0      # برای نمودار دایره‌ای (Pie Chart)
```

**توجه:** باید `fl_chart` را به `pubspec.yaml` اضافه کنید:

```bash
flutter pub add fl_chart
```

---

## 🐛 مشکلات شناخته شده

1. **نمودار دایره‌ای:**
   - اگر تعداد انواع خطا بیش از 8 باشد، رنگ‌ها تکرار می‌شوند
   - **راه‌حل:** محدود کردن به 8 خطای برتر

2. **Performance:**
   - برای workflows با تعداد execution بسیار زیاد، ممکن است لود کردن کند باشد
   - **راه‌حل:** استفاده از pagination در API

3. **تاریخ:**
   - فرمت تاریخ به locale دستگاه بستگی دارد
   - **راه‌حل:** استفاده از CalendarController برای فرمت یکسان

---

## 🚀 ویژگی‌های آینده (Roadmap)

### v1.1.0:
- [ ] Export Timeline به JSON
- [ ] Share Timeline به تلگرام/ایمیل
- [ ] فیلتر پیشرفته بر اساس تاریخ
- [ ] جستجو در لاگ‌ها

### v1.2.0:
- [ ] Real-time monitoring با WebSocket
- [ ] نوتیفیکیشن در زمان خطا
- [ ] نمودار خطی برای روند عملکرد
- [ ] مقایسه چند workflow

### v2.0.0:
- [ ] Dashboard اختصاصی monitoring
- [ ] هشدارهای هوشمند
- [ ] پیش‌بینی خطا با ML
- [ ] Anomaly detection

---

## 📞 پشتیبانی

برای مشکلات یا سوالات:
- 📧 ایمیل: dev@hesabix.ir
- 📱 تلگرام: @hesabix_support

---

## 👥 مشارکت‌کنندگان

- **طراحی UI/UX:** Hesabix Design Team
- **پیاده‌سازی Flutter:** Hesabix Frontend Team
- **بررسی و تست:** QA Team

---

**تاریخ:** 2025-12-04  
**نسخه:** 1.0.0  
**وضعیت:** ✅ Production Ready


