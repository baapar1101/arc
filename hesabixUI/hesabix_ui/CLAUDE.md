# hesabixUI — قواعد کار

اپلیکیشن حسابداری Flutter، رابط فارسی راست‌به‌چپ. برنچ فعال: `feat/m3-alignment`.
هدف جاری: انطباق کامل رابط با Material Design 3 (m3.material.io).

Flutter 3.44.8 · Dart 3.12.2 · ریشهٔ پکیج: `hesabixUI/hesabix_ui/`

---

## قانون طلایی

**`lib/theme/` تنها جایی است که اجازهٔ نوشتن مقدار خام دارد.**
رنگ، شعاع گوشه، اندازهٔ فونت، اندازهٔ آیکون — هیچ‌کدام خارج از این پوشه
به شکل عدد یا `Colors.*` نوشته نمی‌شوند.

هر تغییری در `lib/` باید این را رد کند:

```bash
dart run tool/m3_audit.dart --check
```

اگر خروجی exit 1 داد، تخلف جدید اضافه شده — قبل از ادامه اصلاحش کن.

---

## نگاشت — چه چیزی جای چه چیزی

| به‌جای | بنویس |
|---|---|
| `Colors.green` / `Colors.red` | `context.semantic.success.color` / `context.semantic.debit` |
| `Colors.grey` | `context.colors.onSurfaceVariant` |
| `Colors.white` / `Colors.black` روی سطح | `context.colors.surface` / `context.colors.onSurface` |
| `Color(0xFF…)` | توکن جدید در `lib/theme/tokens/color_schemes.dart` |
| `.withOpacity(x)` | `.withValues(alpha: x)` |
| `colorScheme.surfaceVariant` | `colorScheme.surfaceContainerHighest` |
| `BorderRadius.circular(8)` | `context.shape.smallBorder` |
| `BorderRadius.circular(12)` | `context.shape.mediumBorder` |
| `BorderRadius.circular(16)` | `context.shape.largeBorder` |
| `BoxShadow(...)` | `Material(elevation: AppElevation.level2)` یا `surfaceContainerHigh` |
| `fontSize: 14` | `context.texts.bodyMedium` |
| `EdgeInsets.only(left:/right:)` | `EdgeInsetsDirectional.only(start:/end:)` |
| `Alignment.centerLeft` | `AlignmentDirectional.centerStart` |
| `MediaQuery…size.width < 600` | `context.windowSize.isCompact` |
| `ElevatedButton` | `FilledButton` یا `FilledButton.tonal` |
| `Icon(..., size: 20)` | `AppIconSize.small` |
| `DropdownButtonFormField(value:)` | `initialValue:` |

ایمپورت لازم برای همهٔ `context.*`:

```dart
import '<مسیر نسبی>/theme/tokens/extensions.dart';
```

## انتخاب رنگ معنایی

`context.semantic` این‌ها را دارد — هر نقش چهار توکن (`color`، `onColor`،
`container`، `onContainer`):

- `success` — تأیید شده، ثبت موفق، موجودی سالم
- `warning` — در انتظار، نزدیک به سررسید، موجودی کم
- `info` — یادداشت، راهنما، وضعیت خنثای قابل توجه
- `debit` / `credit` — بدهکار / بستانکار (رنگ تخت، بدون container)
- `tableStripe` / `tableSelection`

خطا و حذف → `context.colors.error` (خودِ M3 دارد، در semantic تکرار نشده).

**برچسب وضعیت** از `container` + `onContainer` استفاده می‌کند، نه `color`.
`color` برای متن و آیکون روی سطح عادی است.

## سلسله‌مراتب دکمه

یک `FilledButton` در هر صفحه — کنش اصلی. بقیه tonal/outlined/text.
`ElevatedButton` فقط روی سطح شلوغ (نقشه، تصویر) توجیه دارد.

---

## راست‌به‌چپ

رابط فارسی است. هر `left`/`right` یک باگ بالقوه است.
آیکون‌های جهت‌دار هم آینه می‌شوند: `Icons.arrow_back` در فارسی به راست
اشاره می‌کند — از `Icons.arrow_back` با `Directionality` خودکار Flutter
استفاده کن، ولی آیکون‌های دستی مثل `chevron_left` را بررسی کن.

---

## آنچه نباید بکنی

- کامیت نکن مگر صریحاً خواسته شود
- `tool/m3_baseline.json` را دستی ویرایش نکن — فقط با `--baseline`
- فایل‌های `third_party/desktop_drop/android/.gradle/` را دست نزن (قفل‌اند)
- بیش از یک قانون audit را در یک کامیت مخلوط نکن
- تغییر رفتاری ندهی؛ این بازسازی صرفاً ظاهری است

---

## دستورهای پرکاربرد

```bash
dart run tool/m3_audit.dart                       # گزارش
dart run tool/m3_audit.dart --rule <id>           # فهرست خط‌به‌خط
dart run tool/m3_audit.dart --check               # دروازه
dart run tool/m3_audit.dart --baseline            # ثبت سقف جدید
flutter analyze lib/theme                         # فقط لایهٔ تم
```

قوانین: `raw_material_color`، `raw_hex_color`، `non_directional_padding`،
`non_directional_alignment` (BLOCKER) · `deprecated_with_opacity`،
`raw_border_radius`، `raw_box_shadow`، `raw_media_query_width`،
`inline_font_size`، `inline_font_family` (MAJOR) · `legacy_elevated_button`،
`raw_icon_size` (MINOR)

استثنای موردی: کامنت `// m3-ignore` در همان خط.
