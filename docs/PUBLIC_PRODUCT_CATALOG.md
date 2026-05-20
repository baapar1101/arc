# API عمومی کاتالوگ کالا (شبکهٔ انتشار)

این APIها **بدون احراز هویت** Hesabix در دسترس‌اند؛ روی IP نرخ‌سنجی (rate limit) دارند.

## مسیرها

| روش | مسیر | توضیح |
|------|------|--------|
| GET | `/api/v1/public/catalog/products` | لیست با `search`, `business_id`, `category_id`, `province`, `city`, `skip`, `take` |
| GET | `/api/v1/public/catalog/products/{catalog_public_uuid}` | جزئیات یک کالای منتشرشده (`catalog_public_uuid` باید UUID معتبر باشد) |
| GET | `/api/v1/public/catalog/products/{catalog_public_uuid}/image` | تصویر کالا (`size=small|medium|original`) |
| GET | `/api/v1/public/catalog/feed.json` | فید سبک برای همگام‌سازی |
| POST | `/api/v1/public/catalog/contact-messages` | ارسال پیام تماس؛ **الزام کپچا** (`captcha_id`, `captcha_code` همراه با `POST /api/v1/auth/captcha` برای دریافت تصویر) |

## خطاها

پاسخ‌های خطای این ماژول (به‌جز خطاهای داخلی نادر) معمولاً به شکل:

`{ "success": false, "error": { "code": "...", "message": "..." } }`

هستند (کد HTTP متناظر: 400، 404، 422، 429).

## تنظیمات

- روی هر **کالا/خدمت**: فیلد `is_public_catalog` در ثبت/ویرایش؛ سرور در صورت نیاز `catalog_public_uuid` تولید می‌کند. فقط کالاهایی که UUID دارند در لیست عمومی می‌آیند.
- روی **کسب‌وکار**:
  - `public_catalog_show_contact` — نمایش `phone` / `mobile` در بلوک `supplier`.
  - `public_catalog_show_base_sales_price` — اگر `false` باشد، فیلد `base_sales_price` در خروجی عمومی `null` است.

## آدرس تصویر و سایت جانبی

فیلدهای `image_url` / `thumbnail_url` در JSON به صورت **مسیر نسبی** برگردانده می‌شوند؛ کلاینت باید با پایهٔ URL همان API (مثلاً `https://api.example.com`) ترکیبشان کند.

## مهاجرت

`alembic upgrade head` برای اعمال به‌ترتیب:

- `20260620_000001_product_public_catalog`
- `20260621_000001_public_catalog_price_flag`
