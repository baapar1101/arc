# راهنمای پیاده‌سازی تقویم شمسی در Hesabix

## ✅ پیاده‌سازی کامل شده

### 🔧 Backend (FastAPI)

#### 1. **Jalali Date Converter** (`/hesabixAPI/app/core/calendar.py`)
- تبدیل تاریخ میلادی به شمسی و بالعکس
- پشتیبانی از سال‌های کبیسه
- نام ماه‌ها و روزهای هفته به فارسی
- فرمت‌های مختلف تاریخ

#### 2. **Calendar Middleware** (`/hesabixAPI/app/core/calendar_middleware.py`)
- تشخیص نوع تقویم از هدر `X-Calendar-Type`
- تنظیم پیش‌فرض بر اساس locale

#### 3. **Response Formatting** (`/hesabixAPI/app/core/responses.py`)
- فرمت‌بندی خودکار تاریخ‌ها در پاسخ‌ها
- اضافه کردن فیلدهای `_raw` برای تاریخ اصلی

### 🎨 Frontend (Flutter)

#### 1. **Jalali Converter** (`/hesabixUI/hesabix_ui/lib/core/jalali_converter.dart`)
- الگوریتم‌های دقیق تبدیل تاریخ
- پشتیبانی کامل از تقویم شمسی
- نام ماه‌ها و روزهای هفته فارسی

#### 2. **Jalali DatePicker** (`/hesabixUI/hesabix_ui/lib/widgets/jalali_date_picker.dart`)
- DatePicker سفارشی برای تقویم شمسی
- UI کامل با نام ماه‌ها و روزهای فارسی
- ناوبری ماه و سال

#### 3. **Calendar Controller** (`/hesabixUI/hesabix_ui/lib/core/calendar_controller.dart`)
- مدیریت حالت تقویم (شمسی/میلادی)
- ذخیره تنظیمات کاربر
- همگام‌سازی با API

#### 4. **Calendar Switcher** (`/hesabixUI/hesabix_ui/lib/widgets/calendar_switcher.dart`)
- ویجت تعویض تقویم
- طراحی مشابه Language Switcher
- پشتیبانی چندزبانه

## 🚀 نحوه استفاده

### در Frontend:

```dart
// نمایش Jalali DatePicker
final picked = await showJalaliDatePicker(
  context: context,
  initialDate: DateTime.now(),
  firstDate: DateTime(2020),
  lastDate: DateTime(2030),
  helpText: 'تاریخ را انتخاب کنید',
);

// تبدیل تاریخ
final jalali = JalaliConverter.gregorianToJalali(DateTime.now());
print(jalali.formatFull()); // "شنبه ۱ فروردین ۱۴۰۳"

// استفاده از CalendarController
final controller = CalendarController();
await controller.load();
controller.setCalendarType(CalendarType.jalali);
```

### در Backend:

```python
# تبدیل تاریخ
jalali_data = CalendarConverter.to_jalali(datetime.now())
# {
#   "year": 1403,
#   "month": 1,
#   "day": 1,
#   "month_name": "فروردین",
#   "weekday_name": "شنبه",
#   "formatted": "1403/01/01 12:00:00"
# }

# فرمت‌بندی بر اساس تقویم
formatted_date = CalendarConverter.format_datetime(
    datetime.now(), 
    CalendarType.jalali
)
```

## 📱 صفحات پیاده‌سازی شده

### 1. **صفحه ورود (LoginPage)**
- Calendar Switcher در AuthFooter
- هماهنگ با Language Switcher

### 2. **داشبورد (HomePage)**
- Calendar Switcher در AppBar
- دسترسی سریع به تعویض تقویم

### 3. **صفحه بازاریابی (MarketingPage)**
- DatePicker های شمسی و میلادی
- فیلتر تاریخ بر اساس تقویم انتخابی

### 4. **پروفایل (ProfileShell)**
- Calendar Switcher در AppBar
- دسترسی در تمام صفحات پروفایل

## 🔄 جریان کار

1. **کاربر تقویم را انتخاب می‌کند**
2. **تنظیمات در SharedPreferences ذخیره می‌شود**
3. **API Client هدر X-Calendar-Type را ارسال می‌کند**
4. **Backend تاریخ‌ها را بر اساس تقویم انتخابی فرمت می‌کند**
5. **Frontend DatePicker مناسب را نمایش می‌دهد**

## 🎯 ویژگی‌های کلیدی

### ✅ **بدون وابستگی خارجی**
- پیاده‌سازی کامل با Flutter native
- الگوریتم‌های دقیق تبدیل تاریخ
- UI سفارشی برای تقویم شمسی

### ✅ **پشتیبانی کامل**
- سال‌های کبیسه شمسی
- نام ماه‌ها و روزهای فارسی
- فرمت‌های مختلف تاریخ

### ✅ **یکپارچگی کامل**
- هماهنگ با سیستم i18n موجود
- ذخیره تنظیمات کاربر
- همگام‌سازی Frontend و Backend

### ✅ **UI/UX بهینه**
- طراحی مشابه Language Switcher
- DatePicker های کاربرپسند
- پشتیبانی چندزبانه

## 🧪 تست

```bash
# تست Frontend
cd hesabixUI/hesabix_ui
flutter analyze
flutter build web

# تست Backend
cd hesabixAPI
python -m pytest tests/
```

## 📚 منابع

- [مستندات Flutter CalendarDelegate](https://docs.flutter.dev/cupertino/showDatePicker)
- [الگوریتم‌های تقویم شمسی](https://fa.wikipedia.org/wiki/تقویم_جلالی)
- [مستندات jdatetime](https://pypi.org/project/jdatetime/)

## 🔧 تنظیمات پیشرفته

### تغییر نام ماه‌ها:
```dart
// در jalali_converter.dart
static const List<String> jalaliMonthNames = [
  'فروردین', 'اردیبهشت', 'خرداد', // ...
];
```

### تغییر فرمت تاریخ:
```dart
// فرمت سفارشی
String customFormat = jalali.format(separator: '-'); // 1403-01-01
```

### اضافه کردن تقویم جدید:
```dart
// در calendar_controller.dart
enum CalendarType { gregorian, jalali, hijri } // اضافه کردن تقویم هجری
```

## 🎉 نتیجه

تقویم شمسی به صورت کامل و دقیق در پروژه Hesabix پیاده‌سازی شده است. کاربران می‌توانند بین تقویم میلادی و شمسی جابجا شوند و تمام تاریخ‌ها بر اساس تقویم انتخابی نمایش داده می‌شوند.
