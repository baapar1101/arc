# قرارداد API — Barcode Label Studio

> وضعیت طراحی: ✅ کامل (فاز A)  
> وضعیت پیاده‌سازی: ❌  
> Base path: `/api/v1/barcode-labels/business/{business_id}`  
> احراز هویت: Bearer مثل بقیه API  
> گیت: لایسنس فعال `barcode_label_studio` + permission مربوطه

---

## خطاهای مشترک

| HTTP | معنی |
|------|------|
| 401 | بدون احراز |
| 403 | بدون لایسنس افزونه یا بدون permission |
| 404 | طرح/منبع پیدا نشد |
| 409 | تعارض (مثلاً set-default روی draft) |
| 422 | validation schema / symbology / binding |

بدنه خطا مطابق الگوی استاندارد حسابیکس (`detail` / کد خطا در صورت وجود).

---

## Permissions

| کد | استفاده |
|----|---------|
| `barcode_labels.view` | لیست و مشاهده طرح‌های published |
| `barcode_labels.design` | CRUD، publish، archive، duplicate، از preset |
| `barcode_labels.print` | preview، print job، اکسل/سریال |

کاربر `design` به‌صورت ضمنی view دارد مگر جدا enforce شود — در پیاده‌سازی: design ⊃ view، print جدا.

---

## Templates

### `GET /templates`

Query:

- `status`: `draft|published|archived|all` (پیش‌فرض برای writer: all، برای print-only: published)
- `q`: جستجوی نام

Response `200`:

```json
{
  "items": [
    {
      "id": 1,
      "name": "قفسه ۵۰×۳۰",
      "description": null,
      "status": "published",
      "is_default": true,
      "version": 3,
      "schema_version": 1,
      "canvas_width_mm": 50,
      "canvas_height_mm": 30,
      "updated_at": "2026-08-06T00:00:00Z",
      "published_at": "2026-08-06T00:00:00Z"
    }
  ]
}
```

`design_json` در لیست نمی‌آید (حجم).

### `POST /templates`

Body:

```json
{
  "name": "طرح جدید",
  "description": null,
  "design_json": { "schema_version": 1, "canvas": {}, "elements": [] },
  "sheet_json": { "paper": "A4", "orientation": "portrait", "columns": 3, "rows": 8 }
}
```

Response `201`: آبجکت کامل مثل `GET /templates/{id}`.

### `GET /templates/{id}`

شامل `design_json`, `sheet_json`, متادیتا.

### `PUT /templates/{id}`

به‌روزرسانی name/description/design/sheet.  
`version` در سرور +۱ می‌شود و یک revision ذخیره می‌شود.  
اگر `published` باشد: یا اجازه ویرایش مستقیم با version bump (ساده) یا اجبار به draft — **تصمیم قفل‌شده طراحی:** ویرایش published مجاز است و version bump می‌شود (مثل گزارش‌ساز عملیاتی)؛ status همان published می‌ماند مگر کاربر archive کند.

### `POST /templates/{id}/publish`

`draft → published`. Validation سخت schema + خطاهای قرمز استودیو.

### `POST /templates/{id}/archive`

`→ archived`. اگر default بود، default برداشته می‌شود.

### `POST /templates/{id}/duplicate`

کپی با نام `«کپی {name}»`، status=`draft`، `is_default=false`.

### `POST /templates/set-default`

```json
{ "template_id": 12 }
```

فقط `published`. بقیه `is_default` همان business صفر می‌شوند.

### `GET /templates/default`

`200` آبجکت خلاصه یا `404` اگر نباشد.

### `GET /templates/{id}/revisions`

لیست تاریخچه نسخه (بدون الزام restore در MVP؛ restore فاز بعدی).

---

## Presets

### `GET /presets`

```json
{
  "items": [
    {
      "code": "shelf_50x30",
      "name": "قفسه ۵۰×۳۰",
      "width_mm": 50,
      "height_mm": 30,
      "thumbnail_url": null
    }
  ]
}
```

### `POST /templates/from-preset`

```json
{ "preset_code": "shelf_50x30", "name": null }
```

ساخت draft از preset.

---

## Preview & Print

### `POST /templates/{id}/preview`

```json
{
  "sample": {
    "product": {
      "name": "نمونه کالا",
      "code": "P-100",
      "price": 150000,
      "sale_price": 135000,
      "general_barcode": "1234567890123"
    },
    "instance": { "serial": "SN001", "barcode": "INST-001" },
    "warehouse": { "name": "انبار مرکزی" },
    "business": { "name": "فروشگاه نمونه" },
    "print": { "counter": 1, "copy_index": 1 }
  },
  "sheet_override": null
}
```

Response: `application/pdf` (یک صفحه نمونه یا یک لیبل روی sheet).

### `POST /print`

```json
{
  "template_id": 12,
  "source": "products",
  "items": [
    {
      "product_id": 10,
      "instance_id": null,
      "qty": 3,
      "overrides": {
        "product.general_barcode": "CUSTOM"
      }
    }
  ],
  "sheet_override": null,
  "max_labels": 10000
}
```

`source`: `products | instances | excel_rows | serial_range`

برای `serial_range` به‌جای items:

```json
{
  "template_id": 12,
  "source": "serial_range",
  "serial": {
    "prefix": "A",
    "start": 1,
    "end": 100,
    "pad": 5,
    "suffix": "",
    "qty_each": 1,
    "binding_target": "fixed_as_barcode"
  }
}
```

Response: PDF یا الگوی download token حسابیکس.

سقف: اگر مجموع qty > `max_labels` (پیش‌فرض ۱۰۰۰۰) → `422`.

---

## Excel helpers

### `GET /print/excel-template`

دانلود xlsx قالب (FA headers).

### `POST /print/excel/dry-run`

multipart file → گزارش ردیف‌های معتبر/نامعتبر و تعداد برچسب برآوردی.

### `POST /print/excel`

multipart + `template_id` → PDF (یا job async اگر حجم بالا — MVP همزمان با سقف).

---

## Plugin / health

نیازی به endpoint جدا نیست؛ `GET /marketplace/business/{id}/plugins` وضعیت را می‌دهد.  
Dependency سرور روی همه مسیرهای بالا اجباری است.

---

## Sheet JSON schema (فشرده)

```json
{
  "paper": "A4",
  "orientation": "portrait",
  "custom_paper_mm": { "width": null, "height": null },
  "margin_mm": { "top": 5, "right": 5, "bottom": 5, "left": 5 },
  "columns": 3,
  "rows": 8,
  "gap_mm": { "x": 2, "y": 2 },
  "label_from_canvas": true
}
```

`paper`: `A4 | A5 | Letter | custom`
