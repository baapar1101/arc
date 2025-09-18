# یکپارچه‌سازی CalendarSwitcher با AuthFooter

## مشکل
CalendarSwitcher و LanguageSwitcher دو بار تکرار شده بودند - یک بار در Row جداگانه و یک بار در AuthFooter.

## راه‌حل
انتقال CalendarSwitcher به AuthFooter و حذف Row اضافی.

## تغییرات انجام شده

### ✅ AuthFooter (`lib/widgets/auth_footer.dart`)
- اضافه شدن CalendarController به constructor
- اضافه شدن CalendarSwitcher به children
- ترتیب جدید: Calendar → Theme → Language

### ✅ LoginPage (`lib/pages/login_page.dart`)
- حذف Row اضافی برای CalendarSwitcher و LanguageSwitcher
- ارسال CalendarController به AuthFooter
- حذف import های اضافی

## Layout جدید AuthFooter:
```
┌─────────────────────────────────┐
│  [تقویم] [تم] [زبان]            │ ← در سمت راست
└─────────────────────────────────┘
```

## ترتیب کنترل‌ها در AuthFooter:
1. **CalendarSwitcher** - انتخاب نوع تقویم
2. **ThemeModeSwitcher** - انتخاب تم (اختیاری)
3. **LanguageSwitcher** - انتخاب زبان

## کد AuthFooter:
```dart
Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    CalendarSwitcher(controller: calendarController),
    const SizedBox(width: 8),
    if (themeController != null) ...[
      ThemeModeSwitcher(controller: themeController!),
      const SizedBox(width: 8),
    ],
    LanguageSwitcher(controller: localeController),
  ],
),
```

## نتیجه
- ✅ حذف تکرار کنترل‌ها
- ✅ یکپارچه‌سازی در AuthFooter
- ✅ ترتیب منطقی و زیبا
- ✅ کد تمیز و منظم
- ✅ حفظ عملکرد تمام کنترل‌ها

## تست
- ✅ Flutter analyze بدون خطای critical
- ✅ حذف تکرار
- ✅ Layout یکپارچه
