# اصلاح Layout صفحه ورود - LoginPage Layout Fix

## مشکل
CalendarSwitcher و LanguageSwitcher در جای اشتباه (AppBar) قرار داشتند.

## راه‌حل
انتقال CalendarSwitcher و LanguageSwitcher از AppBar به پایین صفحه ورود.

## تغییرات انجام شده

### ✅ حذف AppBar
- AppBar از LoginPage حذف شد
- صفحه ورود حالا بدون AppBar است

### ✅ اضافه کردن کنترل‌ها به پایین صفحه
- CalendarSwitcher و LanguageSwitcher در Row قرار گرفتند
- در مرکز صفحه (MainAxisAlignment.center)
- فاصله 12 پیکسل بین آن‌ها
- قبل از AuthFooter قرار گرفتند

### 🎨 Layout جدید:
```
┌─────────────────────────┐
│     Logo + Title        │
│     Subtitle            │
│     TabBar              │
│     Form Content        │
│     Brand Tagline       │
│                         │
│  [Calendar] [Language]  │ ← جدید
│                         │
│     AuthFooter          │
└─────────────────────────┘
```

## کد اضافه شده:
```dart
// Calendar and Language Switchers
Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    CalendarSwitcher(controller: widget.calendarController),
    const SizedBox(width: 12),
    LanguageSwitcher(controller: widget.localeController),
  ],
),
```

## نتیجه
- ✅ CalendarSwitcher و LanguageSwitcher در پایین صفحه
- ✅ ترتیب منطقی: Calendar → Language
- ✅ طراحی مرکزی و زیبا
- ✅ بدون AppBar اضافی
- ✅ حفظ عملکرد AuthFooter

## تست
- ✅ Flutter analyze بدون خطای critical
- ✅ Layout صحیح و زیبا
- ✅ کنترل‌ها در جای مناسب
