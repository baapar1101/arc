# یکپارچه‌سازی تقویم در بخش بازاریابی

## تغییرات انجام شده

### ✅ اضافه شدن CalendarController به MarketingPage
- CalendarController به constructor اضافه شد
- MarketingPage حالا تقویم انتخابی کاربر را می‌شناسد

### ✅ تنظیم DatePicker بر اساس تقویم انتخابی
DatePicker ها حالا بر اساس تقویم انتخابی کاربر تنظیم می‌شوند:

#### تقویم شمسی:
```dart
locale: const Locale('fa', 'IR')
```

#### تقویم میلادی:
```dart
locale: const Locale('en', 'US')
```

### 🔧 تغییرات کد:

#### 1. **Import CalendarController**
```dart
import '../../core/calendar_controller.dart';
```

#### 2. **Constructor به‌روزرسانی شده**
```dart
class MarketingPage extends StatefulWidget {
  final CalendarController calendarController;
  const MarketingPage({super.key, required this.calendarController});
}
```

#### 3. **DatePicker از تاریخ**
```dart
Future<void> _pickFromDate() async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _fromDate ?? now,
    firstDate: first,
    lastDate: last,
    helpText: t.dateFrom,
    locale: widget.calendarController.isJalali 
        ? const Locale('fa', 'IR') 
        : const Locale('en', 'US'),
  );
}
```

#### 4. **DatePicker تا تاریخ**
```dart
Future<void> _pickToDate() async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _toDate ?? now,
    firstDate: first,
    lastDate: last,
    helpText: t.dateTo,
    locale: widget.calendarController.isJalali 
        ? const Locale('fa', 'IR') 
        : const Locale('en', 'US'),
  );
}
```

#### 5. **به‌روزرسانی main.dart**
```dart
GoRoute(
  path: '/user/profile/marketing',
  name: 'profile_marketing',
  builder: (context, state) => MarketingPage(calendarController: _calendarController!),
),
```

### 🎯 ویژگی‌های جدید:

#### 1. **تطبیق با تقویم انتخابی**
- DatePicker ها بر اساس تقویم انتخابی کاربر نمایش داده می‌شوند
- تقویم شمسی: Locale فارسی
- تقویم میلادی: Locale انگلیسی

#### 2. **یکپارچگی با سیستم تقویم**
- MarketingPage از CalendarController استفاده می‌کند
- تغییر تقویم در سایر صفحات بر روی DatePicker ها تأثیر می‌گذارد

#### 3. **تجربه کاربری بهتر**
- کاربران می‌توانند تاریخ‌ها را با تقویم مورد نظر خود انتخاب کنند
- فیلتر تاریخ بر اساس تقویم انتخابی کار می‌کند

### ✨ نتیجه:
حالا در بخش بازاریابی:
- **فیلتر تاریخ از**: بر اساس تقویم انتخابی
- **فیلتر تاریخ تا**: بر اساس تقویم انتخابی
- **تطبیق خودکار**: با تغییر تقویم در سایر صفحات

### 🔄 نحوه کار:
1. کاربر تقویم مورد نظر را انتخاب می‌کند
2. در بخش بازاریابی، DatePicker ها بر اساس تقویم انتخابی نمایش داده می‌شوند
3. فیلتر تاریخ بر اساس تقویم انتخابی کار می‌کند

## تست
- ✅ Flutter analyze بدون خطای critical
- ✅ CalendarController یکپارچه شده
- ✅ DatePicker ها تطبیق یافته
- ✅ عملکرد صحیح
