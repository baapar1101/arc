# چندزبانه کردن CalendarSwitcher

## تغییرات انجام شده

### ✅ اضافه شدن پشتیبانی چندزبانه
CalendarSwitcher حالا کاملاً چندزبانه است و از ترجمه‌های موجود استفاده می‌کند.

### 🌐 ترجمه‌های استفاده شده:

#### انگلیسی (app_en.arb):
- `calendar`: "Calendar"
- `gregorian`: "Gregorian" 
- `jalali`: "Jalali"
- `calendarType`: "Calendar Type"

#### فارسی (app_fa.arb):
- `calendar`: "تقویم"
- `gregorian`: "میلادی"
- `jalali`: "شمسی" 
- `calendarType`: "نوع تقویم"

### 🔧 تغییرات کد:

#### 1. **Import ترجمه‌ها**
```dart
import 'package:hesabix_ui/l10n/app_localizations.dart';
```

#### 2. **استفاده از ترجمه‌ها**
```dart
final t = AppLocalizations.of(context);
final String label = isJalali ? t.jalali.substring(0, 3) : t.gregorian.substring(0, 3);
```

#### 3. **Tooltip چندزبانه**
```dart
tooltip: t.calendarType,
```

#### 4. **منو چندزبانه**
```dart
PopupMenuItem(
  value: CalendarType.jalali,
  child: Text(t.jalali),
),
PopupMenuItem(
  value: CalendarType.gregorian,
  child: Text(t.gregorian),
),
```

### 🎯 نتیجه:

#### در زبان فارسی:
- دکمه: **"شم"** (3 کاراکتر اول "شمسی")
- منو: **"شمسی"** و **"میلادی"**
- Tooltip: **"نوع تقویم"**

#### در زبان انگلیسی:
- دکمه: **"Jal"** (3 کاراکتر اول "Jalali")
- منو: **"Jalali"** و **"Gregorian"**
- Tooltip: **"Calendar Type"**

### ✨ ویژگی‌های جدید:
- **چندزبانه کامل**: تمام متن‌ها ترجمه شده
- **سازگاری**: با سیستم i18n موجود
- **انعطاف**: تغییر خودکار با تغییر زبان
- **یکپارچگی**: با سایر ویجت‌های چندزبانه

### 🔄 مقایسه با LanguageSwitcher:
| ویژگی | LanguageSwitcher | CalendarSwitcher |
|--------|------------------|------------------|
| چندزبانه | ✅ | ✅ |
| ترجمه منو | ✅ | ✅ |
| ترجمه tooltip | ✅ | ✅ |
| ترجمه دکمه | ✅ | ✅ |

## تست
- ✅ Flutter analyze بدون خطای critical
- ✅ ترجمه‌ها صحیح
- ✅ عملکرد چندزبانه
