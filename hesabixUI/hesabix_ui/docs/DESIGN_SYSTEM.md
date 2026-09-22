# دیزاین‌سیستم hesabixUI

پیاده‌سازی دیزاین‌سیستم پنل ادمین «هُما» روی اپ Flutter، در قالب توکن‌های Material 3.

مرجع: پروژهٔ HTML/Tailwind پنل ادمین (`tailwind.config.js` + `assets/css/main.css`)
محل پیاده‌سازی: `lib/theme/` — طبق قانون طلایی `CLAUDE.md` تنها جای مجاز مقادیر خام.

---

## چرا این روش کار می‌کند

کل `lib/` (۸۰۶ فایل) رنگ و اندازه را از `context.colors` / `context.texts` /
`context.shape` / `context.semantic` می‌گیرد، نه از مقدار خام. بنابراین بازنویسی
**لایهٔ توکن** ظاهر همهٔ صفحات را هم‌زمان عوض می‌کند؛ نیازی به ویرایش تک‌تک
صفحات نبود.

---

## ۱. پالت رنگ

توکن‌های خام در `lib/theme/tokens/color_schemes.dart` → `AppColorTokens`.

| گروه | مقادیر | نقش |
|---|---|---|
| `ink` | `950 #070B12` · `900 #0B111D` · `850 #0E1626` · `800 #131C2E` · `700 #1A2438` · `600 #243149` | لایه‌های سطح، از پس‌زمینهٔ صفحه تا لبه |
| `brand` | `300 #6EE7B7` · `400 #34D399` · `500 #10B981` · `600 #059669` · `700 #047857` | لهجهٔ اصلی، کنش اصلی، موفقیت |
| `aqua` | `300 #67E8F9` · `400 #22D3EE` · `500 #06B6D4` | نقش دوم، اطلاع، نمودار |
| `amber` | `300 #FCD34D` · `500 #F59E0B` · `700 #B45309` | هشدار، «در انتظار» |
| `rose` | `300 #FDA4AF` · `400 #FB7185` · `600 #E11D48` | خطا، حذف، بدهکار |
| `slate` | `200 #E2E8F0` … `600 #475569` | متن و متن کم‌رنگ |

### نگاشت به ColorScheme متریال (حالت تیره — منطبق بر مرجع)

| نقش M3 | مقدار | معادل در CSS مرجع |
|---|---|---|
| `surface` | `ink-950` | `body { background }` |
| `surfaceContainerLow` | `ink-900` | `bg-ink-900/85` (نوار بالا) |
| `surfaceContainer` | `ink-850` | `.glass-card` |
| `surfaceContainerHigh` | `ink-800` | `bg-ink-800/60` (ورودی، `.icon-btn`) |
| `surfaceContainerHighest` | `ink-700` | اسکرول‌بار، لبهٔ روشن |
| `onSurface` | `slate-200` | `body { color }` |
| `onSurfaceVariant` | `slate-400` | `.nav-item` غیرفعال، متن کم‌رنگ |
| `primary` / `onPrimary` | `brand-500` / `ink-950` | دکمهٔ اصلی (متن تیره روی سبز) |
| `onPrimaryContainer` | `brand-300` | `.nav-item.active` |
| `outline` / `outlineVariant` | `ink-600` / `ink-700` | `border-white/10` / `border-white/[0.06]` |

**حالت روشن** در مرجع وجود ندارد؛ نسخه‌ای هم‌هویت ساخته شد (`lightScheme`) تا
حالت روشن اپ کاربردی بماند: زمینهٔ `slate-50` و برند `brand-600` برای تضاد کافی.

### رنگ سفارشی کاربر
`schemeFromSeed` اگر بذر برابر `brand-500` باشد پالت صریح بالا را برمی‌گرداند؛
در غیر این صورت به تولید تونال M3 برمی‌گردد. یعنی «تنظیمات ظاهر» و انتخاب رنگ
دلخواه کاربر همچنان کار می‌کند.

---

## ۲. رنگ معنایی

`context.semantic` — هر نقش چهار توکن (`color` / `onColor` / `container` / `onContainer`):

| نقش | تیره | روشن |
|---|---|---|
| `success` | `brand-400` | `brand-600` |
| `warning` | `amber-500` | `amber-700` |
| `info` | `aqua-400` | `aqua-700` |
| `debit` | `rose-400` | `rose-600` |
| `credit` | `brand-400` | `brand-600` |

**برچسب وضعیت** از `container` + `onContainer` استفاده می‌کند، نه `color`.

---

## ۳. تایپوگرافی

`lib/theme/tokens/typography.dart` — منطبق بر مقیاس Tailwind مرجع.

| نقش | اندازه | وزن | معادل مرجع |
|---|---|---|---|
| `displayLarge` | 48 | 800 | `text-5xl` |
| `displaySmall` | 30 | 700 | `lg:text-3xl` |
| `headlineLarge` | 27 | 700 | `text-[1.7rem]` |
| `headlineMedium` | 24 | 700 | `text-2xl` |
| `headlineSmall` | 20 | 700 | `text-xl` |
| `titleLarge` | 18 | 700 | `text-lg` |
| `titleMedium` | 16 | 600 | `text-base` |
| `titleSmall` | 14 | 600 | `text-sm` |
| `bodyLarge` / `bodyMedium` / `bodySmall` | 14 / 13 / 12 | 400 | `text-sm` / `text-xs` |
| `labelLarge` / `labelMedium` / `labelSmall` | 13 / 11 / 10 | 600 | `.chip` و برچسب‌ها |

**فونت**: مرجع از `Vazirmatn FD` استفاده می‌کند. اپ روی `YekanBakhFaNum` ماند —
چون هفت وزن (۱۰۰ تا ۹۰۰) در `pubspec.yaml` ثبت شده در حالی که Vazirmatn فقط
Regular و Bold دارد، و دیزاین مرجع به وزن‌های ۵۰۰/۶۰۰/۸۰۰ متکی است.
رنگ متن بدنه از سفید خالص به `onSurface` (یعنی `slate-200`) تغییر کرد — دقیقاً
مثل مرجع، که تضاد را نرم‌تر و متن طولانی فارسی را خواناتر می‌کند.

---

## ۴. شکل و فاصله

`context.shape` — منطبق بر `rounded-*` تِیل‌ویند:

| توکن | مقدار | معادل |
|---|---|---|
| `extraSmall` | 6 | `rounded-md` |
| `small` | 8 | `rounded-lg` |
| `medium` | 12 | `rounded-xl` |
| `large` | 16 | `rounded-2xl` — کارت |
| `extraLarge` | 24 | دیالوگ |
| `full` | 999 | `rounded-full` — چیپ، دکمه |

---

## ۵. سطوح شیشه‌ای و درخشش

M3 برای «شیشه» توکن ندارد، پس افزونهٔ `AppSurfaces` اضافه شد.
دسترسی: `context.surfaces`.

| توکن | معادل CSS |
|---|---|
| `glassFill` | `bg-ink-850/70` |
| `glassBorder` | `border-white/[0.06]` |
| `glassBorderAccent` | `border-brand-500/25` (hover) |
| `cardShadow` | `shadow-card` |
| `liftShadow` | `shadow-lift` (hover) |
| `glow` | `shadow-glow` — هالهٔ زمردی |
| `brandGradient` | `from-brand-500 to-brand-600` |
| `brandWashGradient` | `.nav-item.active` |

میان‌بر آماده:

```dart
Container(
  decoration: context.surfaces.glassCard(context.shape.largeBorder),
  child: ...,
)
```

---

## ۶. حرکت

`AppMotion.spring` = `Cubic(0.22, 1.0, 0.36, 1.0)` — همان
`cubic-bezier(.22,1,.36,1)` مرجع که در همهٔ ترنزیشن‌های پنل ادمین استفاده شده.

---

## ۷. کامپوننت‌ها

`lib/theme/components.dart` — تم هر ویجت متریال با معادل مرجعش:

| ویجت | تنظیم | معادل |
|---|---|---|
| `Card` | شعاع ۱۶، لبهٔ `white/6%`، بدون سایهٔ متریال | `.glass-card` |
| `FilledButton` | زمردی تخت، متن تیره، هاله در hover | دکمهٔ گرادیانی + `shadow-glow` |
| `IconButton` | مربع ۴۰، گوشهٔ ۱۲، لبه و آیکون زمردی در hover | `.icon-btn` |
| `Chip` | قرص کامل، `labelMedium` (۱۱px/۶۰۰) | `.chip` |
| `NavigationRail` / `Drawer` / `Bar` | اندیکاتور `primary @15%`، گوشهٔ ۱۲، متن `brand-300` | `.nav-item.active` |
| `InputDecoration` | زمینهٔ `ink-800/60`، لبهٔ زمردی در فوکوس | `input:focus` |
| `DataTable` | سربرگ کم‌رنگ، hover در ۲.۵٪، انتخاب زمردی | `.order-row:hover` |

---

## ۸. اعتبارسنجی

```bash
dart run tool/m3_audit.dart --check
flutter analyze lib/theme
```

آخرین اجرا: ممیزی قبول (۱۰ تخلف کمتر از baseline)، لایهٔ تم بدون خطا.
