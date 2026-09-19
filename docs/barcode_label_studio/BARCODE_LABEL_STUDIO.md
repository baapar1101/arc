# استودیوی طراحی و چاپ برچسب بارکد حسابیکس

> **وضعیت سند:** زنده (Living Document) — پس از هر مرحله طراحی/پیاده‌سازی به‌روز می‌شود.  
> **تاریخ ایجاد:** ۲۰۲۶-۰۸-۰۶  
> **آخرین به‌روزرسانی:** ۲۰۲۶-۰۸-۰۶  
> **کد افزونه:** `barcode_label_studio`  
> **دسته marketplace:** `product_management`

---

## ۰) فهرست پیشرفت کلی

| فاز | عنوان | طراحی | پیاده‌سازی | تست/پذیرش |
|-----|--------|:-----:|:----------:|:---------:|
| — | سناریوی محصول و قواعد کسب‌وکار | ✅ | — | — |
| A | ستون فقرات (مدل، API، رندر PDF، گیت افزونه) | ✅ | ✅ | ❌ |
| B | استودیو WYSIWYG (canvas، DnD، کیبورد، اسکیل) | ✅ | ✅ | ❌ |
| C | اتصال عملیات (کالاها، چاپ گروهی، اکسل، سریال) | ✅ | ✅ | ❌ |
| D | چاپ پیشرفته سیستم و رولی | ✅ | ✅ | ❌ |

**راهنمای علائم:** ✅ انجام شده · 🟡 در حال انجام · ❌ نشده · — موضوعیت ندارد

جزئیات چک‌لیست هر فاز در بخش همان فاز آمده است.

---

## ۱) خلاصه اجرایی

افزونهٔ **طراحی و چاپ برچسب بارکد** یک محصول کامل داخل حسابیکس است که:

1. محیط **استودیوی حرفه‌ای** با موس و کیبورد برای طراحی برچسب دارد.
2. امکان تعریف **چند طرح** برای هر کسب‌وکار، انتخاب **طرح پیش‌فرض**، و **انتخاب طرح موقع چاپ** را می‌دهد.
3. با بخش **کالاها و خدمات** هماهنگ است.
4. خروجی استاندارد همه پلتفرم‌ها **PDF با مختصات میلی‌متر واقعی** است.
5. چاپ مستقیم سیستم/رولی لایهٔ جدا (فاز D) است و شرط تکمیل فازهای A–C نیست.

چاپ سادهٔ فعلی کالاها (Code128/QR، ذخیره PDF) به‌عنوان قابلیت **هستهٔ رایگان** باقی می‌ماند. امکانات استودیو، چندطرح، اکسل سریالی و چاپ پیشرفته پشت لایسنس افزونه قرار می‌گیرند.

---

## ۲) وضعیت فعلی حسابیکس (مبنای کار)

### موجود

| بخش | مسیر/نکته |
|-----|-----------|
| چاپ برچسب ساده کالا | `hesabixUI/.../product_label_print_dialog.dart` — کلاینت PDF، بدون قالب ذخیره‌شونده |
| ورود از کالاها | `products_page.dart` — چاپ بارکد عمومی و برچسب واحد یونیک |
| مدل بارکد کالا | `general_barcodes` + بارکد/سریال `product_instances` |
| الگوی افزونه | `marketplace_plugins_seed.py` + `BusinessPlugin` + `*PluginGate` |
| الگوی قالب چاپ | `report_templates` (draft/publish/default/version) — نزدیک‌ترین آنالوگ |
| الگوی canvas | `workflow_canvas.dart` — InteractiveViewer، zoom، undo، shortcuts |
| اکسل کالا | `product_import_dialog.dart` + API openpyxl |
| پکیج‌ها | `pdf`, `barcode`, `printing`, `desktop_drop`, `file_picker` |

### شکاف‌ها

- هیچ طرح ذخیره‌شونده برای بارکد کالا وجود ندارد.
- استودیوی آزاد با مختصات mm وجود ندارد.
- دیالوگ چاپ سیستم / چاپگر رولی برای لیبل وجود ندارد.
- انواع بارکد محدود به Code128 و QR است.

---

## ۳) سناریوی محصول (کامل)

### ۳.۱ اهداف

- طراحی برچسب با Drag & Drop، موس، کیبورد، zoom، snap، undo/redo.
- اسکیل واقعی میلی‌متر؛ خروجی قابل اسکن.
- چند طرح per business + پیش‌فرض + انتخاب موقع چاپ.
- اتصال به لیست کالا / واحد یونیک / اکسل / چاپ سریالی و تعدادی.
- پشتیبانی symbology: Code128, Code39, Code93, EAN8, EAN13, CodaBar, DataMatrix, QR.
- چند متن، چند بارکد، چند تصویر در یک برچسب؛ چینش سطر/ستون روی کاغذ.
- سازگاری با چاپگرهای لیزری/رنگی/سوزنی از مسیر PDF+درایور OS؛ رولی در فاز D.

### ۳.۲ غیرهدف‌ها (عمداً خارج)

- جایگزینی کامل موتور قالب فاکتور (`report_templates` عمومی).
- وعدهٔ چاپ مستقیم USB/raw روی وب.
- ادیتور موبایل گوشی کوچک به‌عنوان تجربهٔ اصلی طراحی (اندروید برای چاپ و ویرایش سبک).

### ۳.۳ پرسونا و جریان‌ها

**طراح عملیات:** استودیو → ساخت/ویرایش طرح → Publish → Set default.  
**اپراتور چاپ:** کالاها → انتخاب → طرح (پیش‌فرض یا دستی) → تعداد → پیش‌نمایش → PDF/چاپ.  
**مدیر:** خرید افزونه از بازار، تعیین دسترسی `design` / `print`.

### ۳.۴ معماری اطلاعات UI

```
بازار افزونه‌ها → barcode_label_studio

منو (پس از فعال‌سازی):
  برچسب و بارکد
    ├─ طرح‌های من
    ├─ استودیو (new / :id)
    ├─ چاپ از کالاها (میانبر)
    └─ چاپ از اکسل / سریال

کالاها و خدمات:
  ├─ چاپ با طرح پیش‌فرض
  ├─ چاپ با انتخاب طرح
  └─ از فرم کالا: چاپ این کالا
```

### ۳.۵ استراتژی پلتفرم

| قابلیت | وب | ویندوز | اندروید |
|--------|----|--------|---------|
| استودیو + طرح‌ها + PDF | ✅ | ✅ (بهترین UX) | ✅ (تبلت/landscape) |
| چاپ از کالا / اکسل | ✅ | ✅ | ✅ |
| دیالوگ چاپ سیستم | محدود (مرورگر) | ✅ اولویت | ✅ در حد OS |
| چاپ رولی/خام | ❌ وعده داده نشود | ✅ فاز D | ✅ فاز D |

### ۳.۶ معیار پذیرش محصول کامل

1. ساخت طرح جدید بدون تغییر کد.
2. چند published + یک default پایدار.
3. تعویض طرح موقع چاپ + پیش‌نمایش صحیح.
4. موس + کیبورد + zoom/snap/undo در سطح editor واقعی.
5. مختصات mm و PDF قابل اسکن برای symbologyهای پشتیبانی‌شده.
6. چاپ گروهی از کالا و اکسل با تعداد مشخص.
7. گیت لایسنس روی همه مسیرها.
8. draft / publish / تاریخچه نسخه.

---

## ۴) فاز A — ستون فقرات (طراحی ✅ · پیاده‌سازی ❌)

### ۴.۱ هدف فاز

زیربنای داده، API، گیت افزونه، و **یک موتور رندر PDF واحد از JSON** طوری که preview ≡ چاپ.

### ۴.۲ مدل داده

#### جدول `label_templates`

| ستون | نوع | توضیح |
|------|-----|--------|
| id | PK | |
| business_id | FK businesses | CASCADE |
| name | varchar(160) | |
| description | varchar(512) nullable | |
| status | draft \| published \| archived | index |
| is_default | bool | فقط یکی published per business |
| version | int | bump روی تغییر محتوا |
| schema_version | int | مثلاً 1 |
| design_json | JSON | سند `label_design_v1` |
| sheet_json | JSON | کاغذ مادر، سطر/ستون، حاشیه (ممکن است داخل design هم باشد؛ sheet جدا برای override چاپ) |
| thumbnail_png | bytes/nullable یا file_id | اختیاری |
| created_by | FK users | |
| created_at / updated_at | datetime | |
| published_at | datetime nullable | |

ایندکس یکتا جزئی پیشنهادی: حداکثر یک `is_default=true` برای `(business_id)` بین ردیف‌های `status=published` (در سرویس enforce + در DB در صورت پشتیبانی partial unique).

#### جدول `label_template_revisions`

| ستون | نوع | توضیح |
|------|-----|--------|
| id | PK | |
| template_id | FK | CASCADE |
| version_no | int | |
| design_json | JSON | snapshot |
| sheet_json | JSON | |
| changelog | varchar nullable | |
| created_by | FK users | |
| created_at | datetime | |

#### تنظیمات کسب‌وکار (اختیاری)

- فیلد/ردیف settings: `default_label_template_id` — یا فقط از `is_default` روی جدول طرح‌ها.

#### دارایی تصویر

- ترجیح فاز A: ارجاع `file_storage_id` از ماژول storage با `module_context=barcode_labels`.
- مسیر سریع: data-URI داخل design برای لوگوهای کوچک (سقف حجم در validation).

### ۴.۳ Schema سند طراحی — `label_design_v1`

```json
{
  "schema_version": 1,
  "canvas": {
    "width_mm": 50,
    "height_mm": 30,
    "grid_mm": 1,
    "snap_to_grid": true,
    "guides_mm": { "vertical": [], "horizontal": [] },
    "dpi": 300
  },
  "elements": [
    {
      "id": "el_1",
      "type": "text",
      "name": "نام کالا",
      "x_mm": 2,
      "y_mm": 2,
      "w_mm": 46,
      "h_mm": 6,
      "rotation_deg": 0,
      "z_index": 1,
      "locked": false,
      "visible": true,
      "props": {
        "content_mode": "binding",
        "text": "",
        "binding": "product.name",
        "font_family": "YekanBakhFaNum",
        "font_size_pt": 9,
        "font_weight": "normal",
        "align": "center",
        "valign": "middle",
        "color": "#000000",
        "rtl": true,
        "wrap": true
      }
    },
    {
      "id": "el_2",
      "type": "barcode",
      "name": "بارکد اصلی",
      "x_mm": 4,
      "y_mm": 10,
      "w_mm": 42,
      "h_mm": 14,
      "rotation_deg": 0,
      "z_index": 2,
      "locked": false,
      "visible": true,
      "props": {
        "symbology": "code128",
        "content_mode": "binding",
        "value": "",
        "binding": "product.general_barcode",
        "show_text": true,
        "text_size_pt": 7,
        "quiet_zone_mm": 1
      }
    }
  ]
}
```

#### انواع المان (`type`)

| type | props کلیدی |
|------|-------------|
| `text` | content_mode fixed\|binding، text، binding، font_*، align، color، rtl، wrap |
| `barcode` | symbology: code128\|code39\|code93\|ean8\|ean13\|codabar، value/binding، show_text، quiet_zone |
| `qr` | ecc L\|M\|Q\|H، value/binding، quiet_zone |
| `datamatrix` | value/binding |
| `image` | source: upload\|product.image\|business.logo، file_id یا data_uri، fit contain\|cover\|fill، opacity |
| `shape` | shape rect\|ellipse\|line، stroke، fill، stroke_width_mm |
| `line` | می‌تواند زیرمجموعه shape باشد |

#### Bindingهای استاندارد فاز A

- `product.name`, `product.code`, `product.price`, `product.sale_price`
- `product.general_barcode` (اولین توکن)، `product.general_barcode[n]`
- `instance.serial`, `instance.barcode`
- `warehouse.name`, `business.name`
- `print.counter`, `print.copy_index`
- `fixed` از طریق content_mode

#### `sheet_json` (چینش روی کاغذ)

```json
{
  "paper": "A4",
  "orientation": "portrait",
  "custom_paper_mm": null,
  "margin_mm": { "top": 5, "right": 5, "bottom": 5, "left": 5 },
  "columns": 3,
  "rows": 8,
  "gap_mm": { "x": 2, "y": 2 },
  "label_from_canvas": true
}
```

### ۴.۴ قرارداد API

Base: `/api/v1/barcode-labels/business/{business_id}`  
همه endpointها پشت `require_barcode_label_plugin_active` + permission.

| Method | Path | توضیح |
|--------|------|--------|
| GET | `/templates` | لیست (فیلتر status) |
| POST | `/templates` | ساخت draft |
| GET | `/templates/{id}` | جزئیات + design |
| PUT | `/templates/{id}` | به‌روزرسانی محتوا (version++) |
| POST | `/templates/{id}/publish` | draft→published |
| POST | `/templates/{id}/archive` | archive |
| POST | `/templates/{id}/duplicate` | کپی |
| POST | `/templates/set-default` | `{ template_id }` فقط published |
| GET | `/templates/default` | resolve پیش‌فرض |
| POST | `/templates/{id}/preview` | PDF یک برچسب با sample payload |
| POST | `/print` | job چاپ → PDF |
| GET | `/presets` | گالری preset سیستمی |
| POST | `/templates/from-preset` | ساخت از preset |

#### `POST /print` body

```json
{
  "template_id": 12,
  "source": "products",
  "items": [
    { "product_id": 1, "instance_id": null, "qty": 2, "overrides": {} }
  ],
  "sheet_override": null
}
```

پاسخ: `application/pdf` یا `{ file_token }` مطابق الگوی سایر PDFهای حسابیکس.

### ۴.۵ موتور رندر

- ورودی: `design_json` + `sheet_json` + لیست context آیتم‌ها.
- خروجی: PDF چندصفحه‌ای با کاشی‌کاری لیبل‌ها.
- اعتبارسنجی قبل از رندر: طول EAN، خالی نبودن binding اجباری، المان خارج از canvas، حداقل ارتفاع بارکد.
- کتابخانه پیشنهادی سمت کلاینت فعلی: `pdf` + `barcode`؛ در فاز A تصمیم قطعی:

**تصمیم طراحی فاز A:** رندر **سمت کلاینت** برای preview استودیو و چاپ (هم‌راستا با `ProductLabelPrintDialog` فعلی) + امکان preview سرور اختیاری بعداً. قرارداد JSON واحد است تا بعداً سرور هم همان schema را رندر کند.

فایل‌های هدف پیشنهادی:

```
hesabixAPI/
  adapters/db/models/label_template.py
  adapters/db/models/label_template_revision.py
  migrations/versions/YYYYMMDD_label_templates.py
  adapters/api/v1/barcode_labels.py
  adapters/api/v1/schema_models/barcode_label.py
  app/services/barcode_label_service.py
  app/services/barcode_label_design_validator.py
  app/core/barcode_label_plugin_dependency.py
  adapters/db/seed_data/marketplace_plugins_seed.py  # افزودن seed

hesabixUI/hesabix_ui/lib/
  services/barcode_label_service.dart
  models/barcode_label/
    label_design_v1.dart
    label_template.dart
    label_sheet.dart
  widgets/barcode_label/render/label_pdf_renderer.dart
  widgets/marketplace/barcode_label_plugin_gate.dart
```

### ۴.۶ افزونه marketplace

```text
code: barcode_label_studio
name: طراحی و چاپ برچسب بارکد
category: product_management
trial_days: 14
trial_allowed: true
plans: monthly / yearly / lifetime (مبالغ در پیاده‌سازی نهایی با محصول)
```

Permissions پیشنهادی:

- `barcode_labels.view`
- `barcode_labels.design`
- `barcode_labels.print`

### ۴.۷ Presetهای سیستمی (حداقل)

| کد | اندازه | کاربرد |
|----|--------|--------|
| `shelf_50x30` | ۵۰×۳۰ mm | قفسه |
| `shelf_40x30` | ۴۰×۳۰ mm | فشرده |
| `price_70x40` | ۷۰×۴۰ mm | برچسب قیمت |
| `a4_grid_code128` | canvas ۵۰×۳۰ روی A4 | ورقی چندتایی |

### ۴.۸ چک‌لیست فاز A

#### طراحی

- [x] مدل جداول
- [x] schema `label_design_v1`
- [x] قرارداد API
- [x] تصمیم موتور رندر
- [x] seed افزونه و permissions
- [x] لیست preset

#### پیاده‌سازی

- [x] Migration جداول
- [x] ORM + service + validator
- [x] API router + dependency افزونه
- [x] Seed marketplace
- [x] مدل‌های Dart + service کلاینت
- [x] `LabelPdfRenderer` از JSON
- [x] `BarcodeLabelPluginGate`
- [x] صفحه لیست طرح‌ها (CRUD ساده بدون canvas کامل)
- [x] i18n FA/EN کلیدهای پایه

#### تست/پذیرش

- [ ] ساخت/ویرایش/publish/default از API
- [ ] رندر PDF از preset با داده نمونه قابل اسکن
- [ ] 403 بدون لایسنس

---

## ۵) فاز B — استودیو WYSIWYG (طراحی ✅ · پیاده‌سازی ❌)

### ۵.۱ هدف فاز

محیط استودیوی حرفه‌ای با موس، کیبورد، مقیاس mm، DnD، لایه‌ها، inspector، پیش‌نمایش PDF.

### ۵.۲ چیدمان صفحه استودیو

مسیر: `barcode-labels/studio/new` و `barcode-labels/studio/:template_id`

```
┌ Header: نام | ذخیره | پیش‌نمایش PDF | انتشار | پیش‌فرض | Undo/Redo | Zoom% | بستن
├──────┬──────────────────────────────┬─────────────┐
│Tool  │ Ruler H                      │ Inspector   │
│box   ├──────────────────────────────┤ Properties  │
│+Layer│ RulerV │   CANVAS            │ Binding     │
│s     │        │   (InteractiveViewer│ Align       │
│      │        │    + grid + guides) │ Lock        │
└──────┴──────────────────────────────┴─────────────┘
└ Status: X/Y/W/H mm | angle | snap | selection count
```

مرجع تعاملی: `workflow_canvas.dart` + تاریخچه command مانند `workflow_history.dart`.

### ۵.۳ سیستم مختصات و اسکیل

| مفهوم | قاعده |
|--------|--------|
| منبع حقیقت | mm در `design_json` |
| نمایش | `px = mm * (dpi/25.4) * zoom` با dpi منطقی UI جدا از dpi چاپ (مثلاً UI 96 منطقی، چاپ 300) |
| Zoom | 0.25 … 4.0 ؛ Ctrl+Wheel ؛ Ctrl+0 fit ؛ Ctrl+1 صددرصد |
| Grid | 1 / 2 / 5 mm |
| Snap | grid، لبه المان‌ها، راهنماها، مرکز canvas |
| Pan | Space+drag، mid-button، InteractiveViewer |

**قانون طلایی:** هیچ layout چاپی نباید از مختصات پیکسل UI مشتق شود؛ همیشه mm → PDF.

### ۵.۴ تعامل موس

- Drag از toolbox → ایجاد المان در نقطه drop
- Select / multi-select (Ctrl) / marquee
- Move، resize با 8 handle؛ Shift = حفظ نسبت
- Rotate handle (زاویه با Shift قفل ۱۵°)
- Double-click متن → ویرایش inline
- Context menu: کپی، duplicate، قفل، ترتیب لایه، حذف، تبدیل به binding
- Drop فایل تصویر روی canvas

### ۵.۵ میانبرهای کیبورد

| کلید | عمل |
|------|-----|
| Ctrl+Z / Ctrl+Y یا Ctrl+Shift+Z | Undo / Redo (حداقل ۵۰ فرمان) |
| Ctrl+S | ذخیره |
| Ctrl+C / X / V / D | کپی / برش / چسباندن / duplicate |
| Delete | حذف |
| Ctrl+A | انتخاب همه |
| Arrows | ۱ mm |
| Shift+Arrows | ۵ mm |
| Ctrl+Arrows | یک قدم grid |
| Ctrl+] `[` | لایه |
| Ctrl+L | قفل |
| Esc | لغو / deselect |
| V T B Q I | ابزارها |
| Ctrl+P | پیش‌نمایش PDF |

Focus: canvas با `Focus`/`CallbackShortcuts`؛ وقتی Inspector text field فوکوس دارد، فلش‌ها برای متن کار کنند نه جابه‌جایی المان.

### ۵.۶ Command pattern (Undo)

فرمان‌های atomic:

- `AddElement`, `RemoveElements`, `MoveElements`, `ResizeElement`, `RotateElement`
- `UpdateElementProps`, `ReorderZ`, `ToggleLock`, `ToggleVisible`
- `UpdateCanvas`, `UpdateSheet`

هر فرمان: `apply` / `revert` روی `LabelDesignDocument`.

### ۵.۷ Inspector و Toolbox

**Toolbox:** Text, Barcode, QR, DataMatrix, Image, Rect, Line + presets سریع.  
**Layers:** لیست z-order، چشم، قفل، rename.  
**Inspector:** بسته به type — فونت، symbology، binding picker از کاتالوگ فیلدها، رنگ، fit تصویر.

### ۵.۸ اعتبارسنجی زنده در استودیو

- هشدار زرد: quiet zone کم، فونت خیلی کوچک، بارکد فشرده
- خطای قرمز: EAN نامعتبر در حالت fixed، المان خارج بوم، تداخل اجباری برای publish
- Publish فقط وقتی خطاهای قرمز صفر باشند

### ۵.۹ ساختار فایل UI پیشنهادی

```
lib/pages/business/barcode_labels/
  label_templates_page.dart
  label_studio_page.dart
  label_print_page.dart

lib/widgets/barcode_label/studio/
  label_studio_shell.dart
  label_canvas.dart
  label_canvas_painter.dart
  label_element_widget.dart
  label_toolbox.dart
  label_layers_panel.dart
  label_inspector.dart
  label_rulers.dart
  label_studio_shortcuts.dart
  label_studio_history.dart

lib/models/barcode_label/studio/
  label_studio_state.dart
  label_studio_commands.dart
```

### ۵.۱۰ چک‌لیست فاز B

#### طراحی

- [x] چیدمان استودیو
- [x] قواعد اسکیل/zoom/snap
- [x] موس و کیبورد
- [x] Undo command list
- [x] ساختار فایل‌ها
- [x] قوانین validation استودیو

#### پیاده‌سازی

- [x] Shell استودیو + route + منو
- [x] Canvas + grid + zoom/pan (InteractiveViewer، مختصات mm)
- [x] Toolbox + ایجاد المان‌ها (کلیک ابزار)
- [x] Selection + drag move + snap به grid
- [x] Resize handles / rotate handle
- [x] Inspector + binding picker + symbology
- [x] Layers panel
- [x] Shortcuts پایه + Undo/Redo (Ctrl+Z/Y)
- [x] History undo/redo
- [x] Preview PDF از همان renderer فاز A
- [x] ذخیره / publish از استودیو
- [x] نشانگر تغییرات ذخیره‌نشده (dirty)
- [x] Unsaved changes guard روی خروج route
- [x] خط‌کش mm

#### تست/پذیرش

- [ ] ساخت طرح ۵۰×۳۰ با متن+بارکد+لوگو و چاپ قابل اسکن
- [ ] Undo پس از ۱۰ عمل متوالی درست برمی‌گردد
- [ ] Zoom fit و ۱۰۰٪ مختصات mm را خراب نمی‌کند

---

## ۶) فاز C — اتصال عملیات (طراحی ✅ · پیاده‌سازی ❌)

### ۶.۱ هدف فاز

مصرف واقعی طرح‌ها از کالاها، تعدادی/گروهی، اکسل، سریال؛ جایگزینی تدریجی flow چاپ پیشرفته پشت گیت افزونه.

### ۶.۲ نقاط ورود کالاها

در `products_page.dart` (و فرم کالا):

| ورود | رفتار با افزونه فعال | بدون افزونه |
|------|----------------------|-------------|
| چاپ بارکد عمومی | دیالوگ پیشرفته با انتخاب طرح | دیالوگ ساده فعلی |
| چاپ واحد یونیک | همان | ساده فعلی |
| چاپ از فرم کالا | دیالوگ برای همان کالا | ساده/مخفی پیشرفته |

دیالوگ پیشرفته (`LabelPrintJobDialog`):

1. انتخاب طرح (پیش‌فرض از قبل selected)
2. Thumbnail + نام طرح
3. جدول آیتم‌ها: نام، کد، بارکد، qty
4. Override موقت sheet (اختیاری)
5. پیش‌نمایش صفحه اول
6. خروجی PDF / اشتراک / (فاز D) چاپ

### ۶.۳ منابع داده چاپ

| source | توضیح |
|--------|--------|
| `products` | کالاهای انتخاب‌شده؛ general barcode |
| `instances` | واحدهای یونیک |
| `excel` | ردیف فایل |
| `serial_range` | از–تا + prefix/suffix |

### ۶.۴ اکسل

قالب ستون‌ها (حداقلی):

| ستون | اجباری | توضیح |
|------|--------|--------|
| code | خیر* | match کالا |
| barcode | خیر* | مقدار بارکد |
| name | خیر | override نام |
| qty | بله | تعداد چاپ |
| price | خیر | |
| serial | خیر | |
| custom_1..n | خیر | برای bindingهای سفارشی بعدی |

\* حداقل یکی از code یا barcode لازم است مگر حالت «داده خام».

Flow: دانلود قالب → انتخاب فایل → dry-run → تأیید → ساخت job → PDF.  
Shell مشترک: `excel_import_dialog_shell.dart`.

### ۶.۵ چاپ سریالی

- prefix + start + end + pad length + suffix
- qty per value
- پیش‌نمایش ۱۰ مقدار اول
- محدودیت سقف تعداد برچسب در یک job (مثلاً ۱۰٬۰۰۰) با پیام واضح

### ۶.۶ همگام‌سازی با موجودی ساده هسته

- هسته: `ProductLabelPrintDialog` بدون طرح می‌ماند.
- افزونه: مسیر جدید؛ دکمه/منوی «چاپ پیشرفته برچسب» واضح برچسب‌گذاری شود تا کاربر سردرگم نشود.
- اگر default تعریف نشده: اجبار به انتخاب طرح یا پیشنهاد ساخت از preset.

### ۶.۷ چک‌لیست فاز C

#### طراحی

- [x] نقاط ورود کالا
- [x] دیالوگ job چاپ
- [x] اکسل و سریال
- [x] سیاست هم‌زیستی با چاپ ساده

#### پیاده‌سازی

- [x] `LabelPrintJobDialog` + اتصال renderer
- [x] اتصال `products_page` bulk actions (منوی چاپ حرفه‌ای)
- [ ] چاپ از فرم کالا (اختیاری باقی‌مانده)
- [x] صفحه/دیالوگ اکسل
- [x] صفحه/دیالوگ سریال
- [x] resolve default template در UI
- [x] پیام‌ها و empty states وقتی طرحی نیست

#### تست/پذیرش

- [ ] چاپ ۲۰ کالا با qty متفاوت روی A4
- [ ] اکسل dry-run خطاها را نشان می‌دهد
- [ ] بدون افزونه مسیر ساده Intact بماند

---

## ۷) فاز D — چاپ پیشرفته (طراحی ✅ · پیاده‌سازی ✅)

### ۷.۱ اهداف

1. چاپ سیستم از PDF لیبل (`Printing.layoutPdf`)
2. پروفایل چاپگر رولی / حرارتی / Zebra (native)
3. دکمه چاپ با طرح در فرم تک‌کالا

### ۷.۲ چاپ سیستم

- ویندوز/اندروید: دیالوگ OS
- وب: ذخیره PDF + راهنما

### ۷.۳ پروفایل رولی (native-only)

مسیر پایدار: `pdf_spooler` با صفحه به اندازه بوم.  
ZPL آزمایشی (TCP بدون پکیج جدید) طبق `design/adr_roll_printer.md`.

### ۷.۴ چک‌لیست فاز D

#### طراحی

- [x] قرارداد چاپ سیستم
- [x] مدل پروفایل رولی

#### پیاده‌سازی

- [x] دکمه Print با `layoutPdf` روی ویندوز/اندروید (و راهنمای وب)
- [x] اسپایک پکیج رولی و ADR (`adr_roll_printer.md` — بدون dependency جدید)
- [x] CRUD پروفایل چاپگر (`barcode-labels/printers` + API settings)
- [x] ارسال job به پروفایل (pdf_spooler کامل؛ ZPL TCP آزمایشی)
- [x] دکمه چاپ با طرح داخل فرم تک‌کالا
- [x] مستند کاربر: محدودیت پلتفرم‌ها (hint وب در UI)

#### تست/پذیرش

- [ ] چاپ ورقی از ویندوز روی لیزری واقعی
- [ ] (اختیاری) یک چاپگر رولی نمونه

---

## ۸) توالی پیاده‌سازی پیشنهادی

```
A1 seed+migration+API CRUD
A2 validator + Dart models
A3 LabelPdfRenderer + preset render
A4 لیست طرح‌ها + set-default + gate
B1 studio shell + canvas mm
B2 elements DnD + inspector
B3 shortcuts + undo
B4 preview/publish integration
C1 print job dialog + products hooks
C2 excel + serial
D1 system print
D2 roll printer profiles + product form button
```

هر زیرمرحله پس از اتمام، چک‌لیست همین سند تیک می‌خورد و در بخش ۹ ثبت می‌شود.

---

## ۹) گزارش پیشرفت اجرا (لاگ)

| تاریخ | رویداد | نتیجه |
|-------|--------|--------|
| ۲۰۲۶-۰۸-۰۶ | نگارش سناریوی کامل در سند اصلی | سناریو ✅ |
| ۲۰۲۶-۰۸-۰۶ | طراحی فاز A–D + فایل‌های design/* | طراحی ✅ |
| ۲۰۲۶-۰۸-۰۶ | پیاده‌سازی A: migration، ORM، API، seed، gate، لیست طرح‌ها، renderer | A عمدتاً ✅ |
| ۲۰۲۶-۰۸-۰۶ | تکمیل B: undo/redo، resize/rotate، rulers، exit guard | B ✅ |
| ۲۰۲۶-۰۸-۰۶ | تکمیل C: LabelPrintJobDialog، اتصال کالاها، اکسل، سریال | C ✅ |
| ۲۰۲۶-۰۸-۰۶ | تکمیل D1: Printing.layoutPdf + hint وب | D جزئی 🟡 (رولی مانده) |
| ۲۰۲۶-۰۸-۰۶ | تکمیل D2: پروفایل رولی/Zebra، roll PDF، دکمه فرم کالا | D ✅ |

---

## ۱۰) تصمیم‌های قفل‌شده

1. افزونه marketplace با کد `barcode_label_studio` — نه قابلیت رایگان هسته برای استودیو.
2. چاپ ساده فعلی کالا باقی می‌ماند.
3. مختصات طراحی و چاپ: **میلی‌متر**.
4. یک schema نسخه دار: `label_design_v1`.
5. چند طرح + یک default + انتخاب موقع چاپ.
6. استودیو روی وب/ویندوز/اندروید؛ چاپ رولی فقط native.
7. رندر فاز A–C: کلاینت PDF از JSON (هم‌خوان با کدبیس فعلی لیبل).
8. الگوی UX canvas نزدیک workflow editor؛ الگوی lifecycle نزدیک report templates.

---

## ۱۱) تصمیم‌های باز (باید قبل/حین پیاده‌سازی بسته شوند)

| # | موضوع | گزینه‌ها | وضعیت |
|---|--------|----------|--------|
| 1 | قیمت پلن‌های افزونه | هم‌تراز HScript / Warranty | باز — محصول |
| 2 | سقف المان/تصویر/برچسب در یک job | پیشنهاد: ۵۰ المان، ۲MB/تصویر، ۱۰k برچسب | پیشنهاد شده |
| 3 | گروه المان (Group) | فاز B یا بعد | بعد از MVP استودیو |
| 4 | رندر سرور WeasyPrint علاوه بر کلاینت | اختیاری آینده | باز |
| 5 | پکیج چاپ رولی نهایی | ADR ثبت شد؛ تأیید سخت‌افزار باز | 🟡 ADR |

---

## ۱۲) ارجاعات کدبیس

- `hesabixUI/hesabix_ui/lib/widgets/product/product_label_print_dialog.dart`
- `hesabixUI/hesabix_ui/lib/pages/business/products_page.dart`
- `hesabixUI/hesabix_ui/lib/widgets/workflow/workflow_canvas.dart`
- `hesabixUI/hesabix_ui/lib/pages/business/report_template_studio_page.dart`
- `hesabixAPI/adapters/db/models/report_template.py`
- `hesabixAPI/adapters/db/seed_data/marketplace_plugins_seed.py`
- `hesabixAPI/app/services/warehouse_postal_label_service.py`

---

## ۱۳) فایل‌های مرتبط این پوشه

| فایل | نقش | وضعیت |
|------|-----|--------|
| `BARCODE_LABEL_STUDIO.md` | سند اصلی زنده (همین فایل) | ✅ |
| `README.md` | فهرست ورود سریع | ✅ |
| `design/label_design_v1.schema.json` | JSON Schema رسمی سند طراحی | ✅ طراحی |
| `design/api_contract.md` | قرارداد API فاز A | ✅ طراحی |
| `design/studio_ux.md` | UX استودیو فاز B | ✅ طراحی |
| `design/print_job_ux.md` | UX چاپ/اکسل/سریال فاز C | ✅ طراحی |
| `design/phase_d_printing.md` | چاپ سیستم و رولی فاز D | ✅ طراحی |
| `design/adr_roll_printer.md` | ADR اسپایک چاپگر رولی | ✅ |

---

## ۱۴) قدم بعدی پیشنهادی

1. اجرای migrationهای `20260806_000001` و `20260806_000002` و فعال‌سازی trial افزونه
2. Smoke تست: preset → استودیو → publish → پروفایل رولی → چاپ از کالاها / فرم کالا
3. (اختیاری) تست سخت‌افزاری Zebra LAN برای تأیید کامل ZPL

پس از هر تست/تکمیل، چک‌لیست و لاگ همین سند را به‌روز کنید.
