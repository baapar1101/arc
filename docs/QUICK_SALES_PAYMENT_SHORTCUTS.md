# میانبرهای دکمه‌های پرداخت فروش سریع

## رفتار

دکمه‌های پرداخت همچنان در بخش پرداخت فروش سریع تعریف می‌شوند. هر دکمه در دو محیط، پروفایل مستقل دارد:

- برنامه ویندوز؛
- رابط وب.

برای هر محیط، ترتیب انتخاب میانبر مؤثر چنین است:

```text
personal override > business default > no shortcut
```

میانبرها هنگام بارگذاری دکمه‌ها یک‌بار از API دریافت و در حافظه نگهداری می‌شوند. فشردن کلید درخواست دیتابیس یا API ایجاد نمی‌کند.

## محل تنظیمات و دسترسی

پیش‌فرض‌های کسب‌وکار در صفحه «تنظیمات فروش سریع»، بخش «میانبرهای پیش‌فرض پرداخت» مدیریت می‌شوند. دکمه مدیریت پیش‌فرض‌ها داخل نوار پرداخت نمایش داده نمی‌شود.

مجوز مستقل زیر در جدول کاربران و دسترسی‌ها قرار دارد:

```text
quick_sales.manage_default_payment_shortcuts
```

مالک و superadmin به‌صورت ضمنی مجازند. کاربری که فقط این مجوز را دارد می‌تواند وارد صفحه تنظیمات فروش سریع شود، ولی سایر تنظیمات آن صفحه برای او نمایش داده نمی‌شود.

تنظیم شخصی از منوی هر دکمه پرداخت و گزینه «میانبرهای شخصی» انجام می‌شود. کاربر برای ویندوز و وب می‌تواند یکی از این سه حالت را انتخاب کند:

- استفاده از پیش‌فرض کسب‌وکار؛
- میانبر شخصی من؛
- بدون میانبر برای من.

## ذخیره‌سازی

پیش‌فرض ویندوز در `quick_sales_payment_buttons.shortcut` و پیش‌فرض وب در `quick_sales_payment_buttons.web_shortcut` نگهداری می‌شود. ستون وب با migration زیر اضافه شده است:

```text
20261015_000001_quick_sales_web_shortcut
```

تنظیم شخصی در JSON جدول `user_ui_preferences` و به تفکیک کسب‌وکار و پلتفرم ذخیره می‌شود:

```json
{
  "quick_sales_payment_shortcuts": {
    "4952": {
      "windows": {
        "17": "F12",
        "22": "__DISABLED__"
      },
      "web": {
        "17": "ALT+1"
      }
    }
  }
}
```

`__DISABLED__` یعنی میانبر همان دکمه فقط برای آن کاربر و آن محیط غیرفعال است. پیش‌فرض مالک برای کاربران کپی نمی‌شود؛ در نتیجه تغییر بعدی پیش‌فرض برای کاربرانی که override ندارند فوراً اعمال می‌شود.

## API

فهرست دکمه‌ها:

```http
GET /api/v1/businesses/{business_id}/quick-sales/payment-buttons
```

هر دکمه `shortcut_profiles` دارد:

```json
{
  "shortcut_profiles": {
    "windows": {
      "default_shortcut": "F1",
      "user_shortcut": "F8",
      "effective_shortcut": "F8",
      "shortcut_source": "user",
      "shortcut_conflict": false,
      "user_shortcut_disabled": false
    },
    "web": {
      "default_shortcut": "ALT+1",
      "user_shortcut": null,
      "effective_shortcut": "ALT+1",
      "shortcut_source": "business",
      "shortcut_conflict": false,
      "user_shortcut_disabled": false
    }
  }
}
```

فیلدهای سطح اول میانبر برای سازگاری با کلاینت قدیمی، نماینده پروفایل ویندوز هستند.

تنظیم شخصی:

```http
PUT /api/v1/businesses/{business_id}/quick-sales/payment-buttons/{button_key}/shortcut
```

رابط جدید هر دو پروفایل را در یک درخواست و یک تراکنش ذخیره می‌کند:

```json
{
  "platforms": {
    "windows": {"mode": "inherit", "shortcut": null},
    "web": {"mode": "custom", "shortcut": "ALT+1"}
  }
}
```

برای سازگاری، ارسال یک `platform` نیز پشتیبانی می‌شود. نام پلتفرم یکی از `windows` و `web` و `mode` یکی از `inherit`، `custom` و `disabled` است.

فهرست و ذخیره یکجای پیش‌فرض‌ها:

```http
GET /api/v1/businesses/{business_id}/quick-sales/payment-buttons/default-shortcuts
PUT /api/v1/businesses/{business_id}/quick-sales/payment-buttons/default-shortcuts
```

```json
{
  "shortcuts": [
    {
      "button_id": 17,
      "shortcuts": {"windows": "F1", "web": "ALT+1"}
    }
  ]
}
```

تمام ردیف‌ها پیش از تغییر دیتابیس اعتبارسنجی می‌شوند. تکراری‌بودن میانبر به‌صورت مستقل در هر پلتفرم بررسی می‌شود.

## کلیدهای مجاز

در ویندوز:

- `F1` تا `F12`؛
- ترکیب `CTRL`، `ALT` یا `SHIFT` با حرف، عدد یا کلید تابع.

در وب:

- ترکیبی شامل `CTRL` یا `ALT` و یک حرف یا عدد، مانند `ALT+1` یا `CTRL+ALT+R`؛
- کلیدهای تابع به‌تنهایی پذیرفته نمی‌شوند؛
- ترکیب‌های رزروشده مرورگر مانند `CTRL+L`، `CTRL+R` و `CTRL+P` پذیرفته نمی‌شوند.

هنگامی که فوکوس داخل فیلد متنی است، میانبر وب اجرا نمی‌شود. در هر محیط، نگاشت نهایی فقط از `effective_shortcut` ساخته می‌شود و یک کلید هم‌زمان دو پرداخت را فعال نمی‌کند.
