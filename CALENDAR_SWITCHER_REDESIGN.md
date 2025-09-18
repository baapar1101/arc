# بازطراحی CalendarSwitcher - تقلید از LanguageSwitcher

## تغییرات انجام شده

### ✅ طراحی جدید CalendarSwitcher
CalendarSwitcher حالا دقیقاً شبیه LanguageSwitcher طراحی شده است:

#### قبل (طراحی پیچیده):
- Container با padding و decoration
- Row با آیکون و متن و فلش
- طراحی بزرگ و پیچیده

#### بعد (طراحی ساده):
- CircleAvatar ساده
- متن کوتاه (شم/میل)
- طراحی یکپارچه با LanguageSwitcher

### 🎨 ویژگی‌های جدید:

#### 1. **CircleAvatar**
```dart
CircleAvatar(
  radius: 14,
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
  foregroundColor: Theme.of(context).colorScheme.onSurface,
  child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
)
```

#### 2. **متن کوتاه**
- شمسی → **شم**
- میلادی → **میل**

#### 3. **PopupMenu ساده**
- بدون آیکون اضافی
- فقط متن ساده
- طراحی یکپارچه

### 🔄 مقایسه با LanguageSwitcher:

| ویژگی | LanguageSwitcher | CalendarSwitcher |
|--------|------------------|------------------|
| شکل | CircleAvatar | CircleAvatar |
| اندازه | radius: 14 | radius: 14 |
| رنگ | surfaceContainerHighest | surfaceContainerHighest |
| متن | فا/EN | شم/میل |
| فونت | 12px, w600 | 12px, w600 |
| منو | PopupMenu ساده | PopupMenu ساده |

### ✨ مزایای طراحی جدید:
- **یکپارچگی**: شبیه LanguageSwitcher
- **سادگی**: طراحی تمیز و ساده
- **فضا**: کمتر فضا اشغال می‌کند
- **خوانایی**: متن کوتاه و واضح
- **سازگاری**: با تم و رنگ‌بندی برنامه

### 🎯 نتیجه:
CalendarSwitcher حالا دقیقاً شبیه LanguageSwitcher است و در AuthFooter به صورت یکپارچه نمایش داده می‌شود.

## تست
- ✅ Flutter analyze بدون خطای critical
- ✅ طراحی یکپارچه
- ✅ عملکرد صحیح
