# UX استودیوی طراحی برچسب — فاز B

> وضعیت طراحی: ✅  
> وضعیت پیاده‌سازی: ❌  
> مخاطب: توسعه‌دهنده Flutter UI

---

## ۱) اهداف تجربه

کاربر باید حس کند در یک **نرم‌افزار طراحی لیبل** کار می‌کند، نه در یک فرم تنظیمات:

- همه چیز با موس قابل انجام است.
- کاربر حرفه‌ای تقریباً بدون موس (کیبورد) کار می‌کند.
- آنچه روی بوم می‌بیند با PDF چاپ‌شده در حد اسکیل mm یکی است.

---

## ۲) صفحه و مسیرها

| مسیر | صفحه |
|------|------|
| `barcode-labels` | لیست طرح‌ها |
| `barcode-labels/studio/new` | استودیو طرح جدید (از preset یا خالی) |
| `barcode-labels/studio/:id` | ویرایش طرح |
| `barcode-labels/print` | چاپ پیشرفته (فاز C) |
| `barcode-labels/print/excel` | اکسل (فاز C) |

Gate: `BarcodeLabelPluginGate` دور shell صفحات.

---

## ۳) آناتومی استودیو

### Header

- فیلد نام طرح (inline edit)
- وضعیت chip: Draft / Published / Archived
- دکمه‌ها: ذخیره · پیش‌نمایش PDF · انتشار · تنظیم به‌عنوان پیش‌فرض (اگر published) · منوی ⋮ (duplicate، archive)
- Undo / Redo
- Zoom controls: − · درصد · + · Fit · 100%

### ستون چپ — Toolbox + Layers

**Toolbox (ایجاد):**
Text · Barcode · QR · DataMatrix · Image · Rectangle · Line

کلیک = ابزار فعال؛ drag روی canvas = ایجاد در نقطه رهاسازی با اندازه پیش‌فرض type.

**Layers:**
لیست از z بالا به پایین؛ drag reorder؛ آیکون چشم/قفل؛ کلیک = select.

### مرکز — Canvas

- پس‌زمینه خاکستری workspace
- کاغذ لیبل سفید با سایه ملایم، ابعاد mm واقعی
- خط‌کش افقی بالا و عمودی چپ (تیک mm)
- Grid نقطه‌ای یا خطی بر اساس `grid_mm`
- Guides قابل کشیدن از خط‌کش
- Safe margin اختیاری (۰.۵ mm داخل لبه) به‌صورت خط‌چین کم‌رنگ

### ستون راست — Inspector

تب‌ها یا سکشن‌ها:

1. **Position** — X Y W H mm، Rotation (اسپینر + فیلد عددی)
2. **Style** — وابسته به type
3. **Data** — Fixed vs Binding + کاتالوگ binding
4. **Arrange** — Align، Distribute، Bring forward/back، Lock

اگر multi-select: فقط خواص مشترک + Align/Distribute.

### Status bar

`X:12.0  Y:4.0  W:46.0  H:6.0 mm | ∠0° | Snap:ON | Grid:1mm | Sel:1 | Zoom:100%`

---

## ۴) حالت‌های ابزار

| ابزار | نشانگر | رفتار |
|-------|--------|--------|
| Select (V) | arrow | select/move/resize |
| Text (T) | I-beam | کلیک-درگ برای باکس متن |
| Barcode (B) | crosshair | درگ باکس بارکد |
| QR (Q) | crosshair | درگ مربع QR |
| Image (I) | crosshair | درگ باکس سپس picker فایل |
| Shape | crosshair | درگ مستطیل/بیضی |
| Pan (Space hold) | hand | جابه‌جایی viewport |

---

## ۵) Selection و Transform

- Bounding box با ۸ handle + rotate handle بالای مرکز
- هنگام move: راهنمای alignment هوشمند (صورتی/آبی) وقتی لبه‌ها تراز می‌شوند
- Snap threshold: ۲ px صفحه (تبدیل به mm در zoom جاری)
- عناصر `locked` قابل select هستند ولی move/resize نمی‌شوند مگر Unlock
- عناصر `visible=false` در layers خاموش؛ روی canvas نیست یا ghost خیلی کم‌رنگ در حالت «show hidden» (اختیاری MVP: فقط hidden کامل)

---

## ۶) داده نمونه روی بوم

سوییچ بالای canvas: **داده نمونه / کالای واقعی**

- پیش‌فرض: payload نمونه ثابت فارسی
- اختیاری: انتخاب یک کالا از جستجو برای preview زنده bindingها
- بارکد روی canvas به‌صورت WYSIWYG تقریبی (پکیج barcode برای preview ویجت) — PDF نهایی منبع حقیقت اسکن

---

## ۷) پیش‌نمایش PDF

- Drawer یا dialog تمام‌صفحه با همان embed الگوی `label_pdf_preview_embed`
- دکمه‌های ذخیره/اشتراک در preview
- اگر validation قرمز وجود دارد: پیش‌نمایش مجاز با بنر هشدار؛ Publish مسدود

---

## ۸) Unsaved changes

- Fingerprint hash از `design_json + sheet_json + name`
- خروج route / بستن: dialog تأیید
- `Ctrl+S` ذخیره و fingerprint را reset می‌کند
- نشانگر «• ذخیره‌نشده» کنار نام

---

## ۹) Sheet settings (پنل جدا یا dialog)

قابل دسترسی از Header «تنظیمات صفحه چاپ»:

- Paper، orientation، margins، columns، rows، gaps
- پیش‌نمایش شماتیک شبکه لیبل روی کاغذ (نه الزماً WYSIWYG کامل در MVP؛ حداقل اعداد + thumbnail ساده)

این تنظیمات در `sheet_json` ذخیره می‌شوند و موقع چاپ override‌پذیرند.

---

## ۱۰) Empty / First-run

ورود به `studio/new`:

1. Dialog انتخاب preset یا «بوم خالی»
2. اگر خالی: اندازه canvas پیش‌فرض ۵۰×۳۰ mm
3. Tooltip اول‌بار (یک‌بار): «از جعبه ابزار بکشید؛ Ctrl+S ذخیره»

---

## ۱۱) دسترس‌پذیری و RTL

- کل shell RTL مطابق حسابیکس
- مختصات منطقی canvas چپ→راست در فضای لیبل (استاندارد چاپ)؛ UI فارسی حول آن
- همه کنترل‌ها `tooltip` و `Semantics` حداقلی
- کنتراست handles روی لیبل تیره/روشن کافی

---

## ۱۲) معیار Done فاز B (پذیرش UX)

- [ ] کاربر می‌تواند فقط با موس یک طرح کامل بسازد و PDF بگیرد
- [ ] کاربر می‌تواند با کیبورد جابه‌جا، duplicate، undo، save کند
- [ ] Zoom و Fit اندازه mm را در PDF تغییر نمی‌دهد
- [ ] Publish بدون رفع خطای EAN نامعتبر ممکن نیست
- [ ] بازگشت با تغییرات ذخیره‌نشده هشدار می‌دهد
