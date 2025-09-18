# قابلیت انتخاب نوع تقویم - Calendar Type Selection Feature

## خلاصه
این قابلیت امکان انتخاب نوع تقویم (میلادی یا شمسی) را در کل برنامه فراهم می‌کند. کاربران می‌توانند از طریق ویجت مخصوص، نوع تقویم مورد نظر خود را انتخاب کنند و تمام تاریخ‌ها در برنامه بر اساس انتخاب آن‌ها نمایش داده می‌شود.

## ویژگی‌های پیاده‌سازی شده

### Backend (FastAPI)
- ✅ **Middleware تقویم**: پردازش هدر `X-Calendar-Type` در درخواست‌ها
- ✅ **تبدیل تاریخ**: تبدیل خودکار تاریخ‌ها بین میلادی و شمسی
- ✅ **Response Formatting**: فرمت‌بندی پاسخ‌ها بر اساس نوع تقویم انتخابی
- ✅ **کتابخانه jdatetime**: استفاده از کتابخانه jdatetime برای تبدیل تاریخ‌ها

### Frontend (Flutter)
- ✅ **CalendarController**: مدیریت نوع تقویم انتخابی کاربر
- ✅ **CalendarSwitcher Widget**: ویجت تغییر نوع تقویم در AppBar
- ✅ **ApiClient Integration**: ارسال هدر `X-Calendar-Type` در درخواست‌ها
- ✅ **ترجمه‌ها**: ترجمه‌های فارسی و انگلیسی برای قابلیت تقویم

## نحوه استفاده

### برای کاربران
1. در صفحه اصلی برنامه، کنار دکمه تغییر زبان، دکمه انتخاب نوع تقویم را مشاهده کنید
2. روی دکمه کلیک کنید و نوع تقویم مورد نظر (میلادی یا شمسی) را انتخاب کنید
3. تمام تاریخ‌ها در برنامه بر اساس انتخاب شما نمایش داده می‌شوند

### برای توسعه‌دهندگان

#### Backend
```python
# استفاده از CalendarConverter
from app.core.calendar import CalendarConverter

# تبدیل تاریخ میلادی به شمسی
jalali_date = CalendarConverter.to_jalali(datetime.now())

# تبدیل تاریخ میلادی به فرمت استاندارد
gregorian_date = CalendarConverter.to_gregorian(datetime.now())

# فرمت‌بندی بر اساس نوع تقویم
formatted_date = CalendarConverter.format_datetime(datetime.now(), "jalali")
```

#### Frontend
```dart
// استفاده از CalendarController
final calendarController = CalendarController.load();

// تغییر نوع تقویم
await calendarController.setCalendarType(CalendarType.jalali);

// بررسی نوع تقویم فعلی
if (calendarController.isJalali) {
  // منطق برای تقویم شمسی
}
```

## فایل‌های تغییر یافته

### Backend
- `app/core/calendar.py` - ابزارهای تبدیل تاریخ
- `app/core/calendar_middleware.py` - middleware پردازش هدر تقویم
- `app/core/responses.py` - فرمت‌بندی پاسخ‌ها
- `app/main.py` - اضافه کردن middleware
- `adapters/api/v1/auth.py` - استفاده از فرمت‌بندی تقویم
- `pyproject.toml` - اضافه کردن jdatetime

### Frontend
- `lib/core/calendar_controller.dart` - مدیریت نوع تقویم
- `lib/widgets/calendar_switcher.dart` - ویجت تغییر تقویم
- `lib/core/api_client.dart` - ارسال هدر تقویم
- `lib/main.dart` - یکپارچه‌سازی CalendarController
- `lib/pages/home_page.dart` - اضافه کردن CalendarSwitcher
- `lib/l10n/app_*.arb` - ترجمه‌های مربوط به تقویم

## تست کردن

### Backend
```bash
cd hesabixAPI
pip install jdatetime
python3 -c "import jdatetime; print('jdatetime imported successfully')"
```

### Frontend
```bash
cd hesabixUI/hesabix_ui
flutter analyze
flutter run
```

## نکات مهم

1. **پیش‌فرض**: تقویم شمسی به عنوان پیش‌فرض برای کاربران فارسی تنظیم شده است
2. **ذخیره‌سازی**: انتخاب کاربر در SharedPreferences ذخیره می‌شود
3. **هماهنگی**: تغییر نوع تقویم به صورت سراسری در کل برنامه اعمال می‌شود
4. **سازگاری**: تمام تاریخ‌ها همچنان به صورت UTC میلادی در دیتابیس ذخیره می‌شوند

## مراحل بعدی (اختیاری)

برای تکمیل کامل قابلیت، می‌توانید موارد زیر را اضافه کنید:

1. **CalendarDelegate**: پیاده‌سازی CalendarDelegate برای تقویم شمسی
2. **Date Picker**: استفاده از Date Picker شمسی در فرم‌ها
3. **Time Picker**: پیاده‌سازی Time Picker شمسی
4. **Localization**: اضافه کردن نام ماه‌ها و روزهای هفته شمسی

## پشتیبانی

در صورت بروز مشکل، لطفاً موارد زیر را بررسی کنید:

1. نصب صحیح کتابخانه jdatetime در Backend
2. اجرای `flutter pub get` در Frontend
3. بررسی تنظیمات SharedPreferences
4. بررسی هدرهای ارسالی در درخواست‌های API
