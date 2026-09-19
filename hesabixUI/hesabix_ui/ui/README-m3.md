# بستهٔ انطباق Material 3 — hesabixUI

سه لایه: **اندازه‌گیری** (audit)، **تعریف** (tokens)، **قفل** (lint).
همه نسبت به ریشهٔ پکیج `hesabixUI/hesabix_ui/` هستند.

---

## ۱. نصب

```bash
cd hesabixUI/hesabix_ui
git checkout -b feat/m3-alignment
```

فایل‌ها را در این مسیرها قرار دهید:

```
tool/m3_audit.dart                     ← جدید
lib/theme/app_theme.dart               ← جایگزین
lib/theme/components.dart              ← جایگزین
lib/theme/tokens/color_schemes.dart    ← جایگزین
lib/theme/tokens/extensions.dart       ← جایگزین
lib/theme/tokens/typography.dart       ← جایگزین
lib/pages/dev/theme_showcase_page.dart ← جدید
analysis_options.yaml                  ← ادغام با فایل فعلی
m3_lint/                               ← پکیج جدید کنار hesabix_ui
.github/workflows/m3-audit.yml         ← جدید (در ریشهٔ مخزن)
```

سپس:

```bash
flutter analyze
dart run tool/m3_audit.dart
dart run tool/m3_audit.dart --baseline   # عدد امروز را ثبت کن
```

از این لحظه هیچ تخلف جدیدی نمی‌تواند وارد شود.

---

## ۲. ابزار audit

```bash
dart run tool/m3_audit.dart                          # گزارش کامل
dart run tool/m3_audit.dart --top 15                 # ۱۵ فایل بدتر برای هر قانون
dart run tool/m3_audit.dart --rule raw_material_color # فهرست خط‌به‌خط
dart run tool/m3_audit.dart --baseline                # ثبت وضعیت
dart run tool/m3_audit.dart --check                   # CI؛ اگر بدتر شد exit 1
dart run tool/m3_audit.dart --md                      # جدول Markdown
```

۱۲ قانون در سه سطح شدت. سه‌تای اول کار اصلی شما هستند:

| قانون | شدت | چرا |
|---|---|---|
| `raw_material_color` | BLOCKER | `Colors.*` در دارک‌مود می‌شکند |
| `raw_hex_color` | BLOCKER | توکن باید یک منبع داشته باشد |
| `non_directional_padding` | BLOCKER | `left/right` در فارسی برعکس می‌شود |
| `non_directional_alignment` | BLOCKER | همان مشکل |
| `deprecated_with_opacity` | MAJOR | `.withValues(alpha:)` |
| `raw_border_radius` | MAJOR | مقیاس ۰/۴/۸/۱۲/۱۶/۲۸ |
| `raw_box_shadow` | MAJOR | M3 با لایهٔ سطح ارتفاع می‌سازد |
| `raw_media_query_width` | MAJOR | window size class |
| `inline_font_size` | MAJOR | مقیاس تایپ M3 |
| `inline_font_family` | MAJOR | فونت وابسته به locale |
| `legacy_elevated_button` | MINOR | FilledButton |
| `raw_icon_size` | MINOR | ۱۸/۲۰/۲۴/۴۰/۴۸ |

**استثنای موردی:** کامنت `// m3-ignore` در همان خط.
پوشهٔ `lib/theme/` از قوانین رنگ/شکل/تایپ معاف است — تنها جایی که اجازهٔ
تعریف مقدار خام دارد.

---

## ۳. توکن‌ها — چه چیزی عوض شد

### رنگ (`tokens/color_schemes.dart`)

`AppSemanticColors` اضافه شد. Material 3 فقط `error` را تعریف می‌کند، ولی
نرم‌افزار حسابداری به «موفق»، «هشدار» و «اطلاع» هم نیاز دارد. هر کدام یک
`SemanticRole` کامل دارد — چهار توکنی که M3 برای هر نقش تعریف می‌کند:

```dart
context.semantic.success.color        // متن/آیکون روی سطح
context.semantic.success.onColor
context.semantic.success.container    // پس‌زمینهٔ برچسب وضعیت
context.semantic.success.onContainer

context.semantic.debit                // بدهکار
context.semantic.credit               // بستانکار
context.semantic.tableStripe          // ردیف زبرا
context.semantic.tableSelection
```

این‌ها با `ColorScheme.fromSeed` ساخته می‌شوند، پس در دارک‌مود خودبه‌خود
درست‌اند. قبل از ساخت هم فامشان کمی به سمت رنگ برند می‌چرخد (harmonize)
تا با بقیهٔ رابط هم‌خانواده شوند — همان کاری که `Blend.harmonize` در
material_color_utilities می‌کند، بدون افزودن وابستگی.

اینجا بیشترِ آن ۱٬۸۶۱ مورد `Colors.green` / `Colors.orange` می‌رود.

### شکل (`tokens/extensions.dart`)

`AppRadii` قبلی ۶/۱۰/۱۴ بود — با هیچ مقیاسی نمی‌خواند. حالا:

```dart
context.shape.extraSmall   // 4
context.shape.small        // 8
context.shape.medium       // 12
context.shape.large        // 16
context.shape.extraLarge   // 28
context.shape.full
```

`AppRadii` حذف نشده و به مقیاس درست (۸/۱۲/۱۶) اشاره می‌کند، پس هر ۱٬۱۳۳
محل استفاده بدون تغییر کامپایل می‌شود و ظاهر خودبه‌خود اصلاح می‌شود.
`@Deprecated` گرفته تا در ویرایشگر خط بخورد.

### ارتفاع

```dart
AppElevation.level0 … level5              // 0, 1, 3, 6, 8, 12
scheme.surfaceAtElevation(elevation)      // لایهٔ رنگ متناظر
```

به‌جای ۸۹ مورد `BoxShadow` دستی، از `Material(elevation:)` یا مستقیماً
از `surfaceContainer*` استفاده کنید.

### حرکت

```dart
AppMotion.emphasized              // منحنی اصلی M3
AppMotion.emphasizedDecelerate    // ورود
AppMotion.emphasizedAccelerate    // خروج
context.motion.short              // 150ms
context.motion.medium             // 300ms
context.motion.long               // 450ms
```

### چیدمان تطبیقی

```dart
switch (context.windowSize) {
  WindowSizeClass.compact  => bottomNavigationBar: NavigationBar(...),
  WindowSizeClass.medium ||
  WindowSizeClass.expanded => NavigationRail(...),
  _                        => NavigationDrawer(...),
}
```

جایگزین ۴۳ بررسی پراکندهٔ عرض. کمکی‌ها: `usesBottomNav`، `usesRail`،
`usesPermanentDrawer`، `columns`، `margin`.

### تایپ

مقیاس قبلی با ضرب در ۰٫۹ ساخته می‌شد. مشکل: `YekanBakhFaNum` ارتفاع x
بزرگ‌تری از Roboto دارد، پس ضرب یکسان روی هر ۱۵ نقش، line-height را در
تیترها باز و در بدنه تنگ می‌کند. حالا دو جدول صریح فارسی/انگلیسی با
`fontSize`، `height`، `letterSpacing` و `fontWeight` مستقل وجود دارد.

**ارتفاع خط فارسی عمداً بازتر است** (۱٫۵۸ در برابر ۱٫۵۰) چون حروف فارسی
زیرنویس و اعراب دارند.

---

## ۴. قفل کردن با lint

### الف) افزونهٔ ویرایشگر — خط قرمز زیر کد

```yaml
# pubspec.yaml
dev_dependencies:
  custom_lint: ^0.7.0
  m3_lint:
    path: ../../m3_lint
```

```bash
flutter pub get
dart run custom_lint
```

چهار قانون: `avoid_raw_colors`، `avoid_raw_hex_color`،
`prefer_directional_insets`، `prefer_filled_button`.

> نسخهٔ `custom_lint_builder` باید با نسخهٔ `analyzer` در Flutter SDK شما
> بخواند. اگر `pub get` تعارض داد، `^0.7.0` را با نسخهٔ سازگار عوض کنید.
> این تنها بخش شکنندهٔ بسته است — بقیه وابستگی خارجی ندارند.

### ب) دروازهٔ CI — سخت‌گیرتر و بدون شکنندگی

`.github/workflows/m3-audit.yml` روی هر PR اجرا می‌شود و اگر تخلف جدید
اضافه شده باشد PR را رد می‌کند. جدول وضعیت را هم در خلاصهٔ اجرا می‌نویسد.

### ج) قلاب پیش از commit

```bash
cat > .git/hooks/pre-commit <<'HOOK'
#!/bin/sh
cd hesabixUI/hesabix_ui && dart run tool/m3_audit.dart --check
HOOK
chmod +x .git/hooks/pre-commit
```

---

## ۵. صفحهٔ مرجع تم

مسیر را فقط در debug ثبت کنید:

```dart
import 'package:flutter/foundation.dart';
// در جدول مسیرها:
if (kDebugMode) '/dev/theme': (_) => const ThemeShowcasePage(),
```

پنج زبانه: رنگ، تایپ، شکل و ارتفاع، دکمه، اجزا. **قبل و بعد از هر تغییر
در `lib/theme/` آن را در light/dark و fa/en باز کنید.** بدون این، رگرسیون
بصری را کاربر پیدا می‌کند نه شما.

---

## ۶. ترتیب کار پیشنهادی

| هفته | کار | معیار |
|---|---|---|
| ۱ | نصب بسته، baseline، صفحهٔ مرجع | `flutter analyze` تمیز |
| ۲ | `withOpacity` (۲۷۸) — تماماً مکانیکی | `deprecated_with_opacity` صفر |
| ۳–۴ | رنگ در `widgets/workflow/` و `pages/admin/` | `raw_material_color` زیر ۸۰۰ |
| ۵ | RTL: EdgeInsets و Alignment (۱۸۶) | هر دو قانون BLOCKER صفر |
| ۶ | ناوبری تطبیقی — نیازمند جدا کردن routing از `main.dart` | `raw_media_query_width` صفر |
| ۷+ | `data_table_widget.dart` و داشبورد | `raw_material_color` صفر |

بعد از هر مرحله `--baseline` را دوباره بزنید تا سقف پایین بیاید.

---

## ۷. نکات نسخه

سه چیز به Flutter نسبتاً جدید نیاز دارند. اگر `flutter analyze` گیر داد،
هر کدام یک خط است و حذفش بی‌ضرر:

- `FadeForwardsPageTransitionsBuilder` در `app_theme.dart` — گذار صفحهٔ M3
- `year2023: false` در `appProgressTheme` — نشانگر پیشرفت نسل جدید
- `Card.outlined` / `Card.filled` در صفحهٔ مرجع

---

## هشدار

روی برنچ `master` تغییری نده تا `--baseline` ثبت شده باشد؛ وگرنه معیار
سنجش را از دست می‌دهی. اولین دستور بعد از نصب همیشه `--baseline` است.
