# پروفایل چاپ مستقیم و سیستم — فاز D

> وضعیت طراحی: ✅ (قرارداد)  
> وضعیت پیاده‌سازی: ✅ (pdf_spooler + پروفایل‌ها؛ ZPL آزمایشی)
> وضعیت اسپایک فنی پکیج رولی: 🟡 ADR ثبت شد؛ تأیید سخت‌افزار باز

---

## ۱) چاپ سیستم از PDF

### رفتار

پس از تولید `Uint8List` PDF توسط `LabelPdfRenderer`:

| پلتفرم | رفتار دکمه «چاپ» |
|--------|------------------|
| Windows | `Printing.layoutPdf(onLayout: ...)` |
| Android | همان |
| iOS/macOS | همان در صورت build |
| Web | دکمه مخفی یا لینک راهنما: باز کردن PDF و Ctrl+P مرورگر |

### نکات

- تعداد کپی OS جدا از qty لیبل داخل PDF است؛ در UI توضیح یک‌خطی.
- قبل از چاپ، همان validation فاز print.

---

## ۲) پروفایل چاپگر رولی

### ذخیره

در settings افزونه per business:

```json
{
  "printer_profiles": [
    {
      "id": "uuid",
      "name": "Zebra فروشگاه",
      "mode": "pdf_spooler",
      "connection": "system_default",
      "host": null,
      "port": null,
      "label_width_mm": 50,
      "label_height_mm": 30,
      "dpi": 203,
      "enabled": true
    }
  ],
  "active_profile_id": null
}
```

`mode` پیشنهادی MVP فاز D1: فقط `pdf_spooler` (ارسال PDF به spooler با اندازه صفحه = اندازه لیبل).  
`mode` آینده پس از اسپایک: `zpl`, `escpos`.

### UI

صفحه `barcode-labels/printers`:

- لیست پروفایل‌ها
- افزودن/ویرایش
- تست چاپ (یک لیبل نمونه)
- بنر روی وب: «پیکربندی چاپگر رولی فقط در نسخه ویندوز/اندروید»

---

## ۳) اسپایک اجباری قبل از raw

قبل از هر dependency جدید در `pubspec.yaml` برای ESC/POS یا ZPL:

1. تست اتصال یک چاپگر واقعی روی Windows
2. تست Android BLE یا LAN
3. ثبت ADR در همین پوشه: `design/adr_roll_printer.md`
4. سپس تیک پیاده‌سازی raw در MASTER

تا آن زمان فقط `pdf_spooler` در محدوده پیاده‌سازی مجاز است.

---

## ۴) معیار Done فاز D

- [x] از ویندوز دکمه چاپ سیستم PDF لیبل را به دیالوگ OS می‌فرستد
- [x] روی وب مسیر PDF بدون شکست کار می‌کند
- [x] (اختیاری) پروفایل pdf_spooler ذخیره و تست می‌شود
- [x] raw ZPL/ESCPOS فقط بعد از ADR تأییدشده (ADR موجود؛ ZPL TCP آزمایشی)
