# Hesabix Help

راهنمای جامع و آموزش حسابیکس با درخت دسته‌بندی، دسترسی رایگان / ویژه اعضا / پولی، ویدئو و خرید فوری ووکامرس.

## آدرس‌ها

- هاب: `/help/`
- مطلب: `/help/{بخش}/{مطلب}/`
- جستجو: `/help/search/?q=...`

## REST API (مسیر A — برای AI خارجی)

Endpoint استاندارد وردپرس:

```
https://hesabix.ir/wp-json/wp/v2/help
```

### احراز هویت

1. کاربر با قابلیت `edit_pages` / `publish_pages` (مثلاً `supportAI` یا Administrator)
2. پروفایل کاربر → **Application Passwords** → ساخت رمز برنامه
3. درخواست‌ها با HTTP Basic Auth: `USERNAME:APPLICATION_PASSWORD`

### خواندن

```http
GET /wp-json/wp/v2/help
GET /wp-json/wp/v2/help/{id}?context=edit
```

پاسخ شامل `meta` و آبجکت کمکی `hhelp` است.

### ایجاد

```http
POST /wp-json/wp/v2/help
Content-Type: application/json

{
  "title": "عنوان",
  "content": "<p>متن</p>",
  "status": "draft",
  "parent": 727,
  "menu_order": 3,
  "meta": {
    "_hhelp_access": "free",
    "_hhelp_product_id": 0,
    "_hhelp_icon": "",
    "_hhelp_featured": false,
    "_hhelp_video_type": "aparat",
    "_hhelp_video_id": "xxxxx",
    "_hhelp_video_duration": "4:20"
  }
}
```

### ویرایش

```http
POST /wp-json/wp/v2/help/{id}
```

همان فیلدها؛ فقط فیلدهای ارسالی به‌روز می‌شوند.

### متاها

| کلید | مقادیر |
|------|--------|
| `_hhelp_access` | `free` \| `members` \| `paid` |
| `_hhelp_product_id` | ID محصول ووکامرس |
| `_hhelp_icon` | slug آیکون |
| `_hhelp_featured` | boolean |
| `_hhelp_video_type` | `none` \| `aparat` \| `youtube` \| `embed` |
| `_hhelp_video_id` | شناسه یا URL |
| `_hhelp_video_duration` | مثلاً `4:20` |

برای `content` خام در خواندن از `?context=edit` استفاده کنید.

## دسترسی محتوا

- `free` — عمومی
- `members` — کاربران واردشده
- `paid` — پس از خرید محصول ووکامرس مرتبط

محصول می‌تواند meta `_hhelp_grant_ids` داشته باشد: شناسه‌ها با ویرگول، `children_of:ID` یا `all`.

## حساب کاربری

تب «آموزش‌های من» در My Account: `/my-account/help-library/`

## قالب

Override در تم: `wp-content/themes/hesabix2/help/*.php` و `help/partials/`
