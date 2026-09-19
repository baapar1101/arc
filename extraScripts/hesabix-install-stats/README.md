# Hesabix Install Stats (WordPress)

افزونهٔ مرکزی برای دریافت و گزارش آمار نصب/به‌روزرسانی سرورهای Hesabix.  
**فقط روی سایت رسمی `hesabix.ir` نصب و فعال شود** (نه روی سرور مشتری).

## نصب روی hesabix.ir

1. پوشهٔ `hesabix-install-stats` را در `wp-content/plugins/` کپی کنید.
2. از **افزونه‌ها** آن را فعال کنید (جداول `wp_hesabix_install_instances` و `wp_hesabix_install_events` ساخته می‌شوند).
3. منوی **آمار نصب** در پیشخوان ظاهر می‌شود.
4. در **تنظیمات** توکن ingest را با مقدار استفاده‌شده در اسکریپت‌ها هم‌تراز نگه دارید (پیش‌فرض: `hesabix-stats-ingest-v1`).

## Endpoint

| مسیر | روش | توضیح |
|------|-----|--------|
| `/wp-json/hesabix-stats/v1/event` | POST | دریافت رویداد |
| `/wp-json/hesabix-stats/v1/health` | GET | سلامت سرویس |

هدر لازم:

```http
Content-Type: application/json
X-Hesabix-Stats-Token: hesabix-stats-ingest-v1
```

### نمونهٔ بدنه

```json
{
  "schema_version": 1,
  "install_id": "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx",
  "event": "install",
  "api_domain": "api.example.com",
  "ui_domain": "app.example.com",
  "reported_ip": "1.2.3.4",
  "ram_mb": 8192,
  "cpu_cores": 4,
  "disk_free_gb": 40,
  "arch": "x86_64",
  "os_id": "ubuntu",
  "os_version": "24.04",
  "branch": "main",
  "git_commit": "abc123def456",
  "app_version": "",
  "uvicorn_workers": 9,
  "ssl_api": true,
  "ssl_ui": true,
  "install_pgadmin": false,
  "install_voice": false,
  "pip_mirror": "hesabix",
  "flutter_mirror": "hesabix",
  "script": "deploy",
  "hostname": "srv1"
}
```

`event` مجاز: `install` | `update` | `heartbeat`

## فرستنده در مخزن اصلی

- `scripts/hesabix_telemetry.sh`
- فراخوانی از `deploy.sh` (پس از نصب موفق) و `update.sh` (پس از به‌روزرسانی موفق)
- خاموش کردن: `HESABIX_TELEMETRY=0`
- شناسه پایدار: `INSTALL_ID` در `/opt/hesabix/.deploy_env`

## گزارش‌های پیش‌بینی‌شده در پنل

- کل نمونه‌ها / فعال ۷ و ۳۰ روز / ساکت ۹۰+ روز
- نصب و آپدیت روزانه–ماهانه
- توزیع OS، معماری، RAM، CPU
- شاخه Git و نسخه
- آینه pip / Flutter
- نرخ SSL و گزینه‌های pgAdmin / Voice
- لیست نمونه‌ها با جستجو و فیلتر
- **دامنه‌ها** (API/UI جدا، فیلتر نقش، لینک باز کردن، جفت دامنه، CSV)
- جزئیات + تاریخچه رویداد هر نمونه
- خروجی CSV

## امنیت

- Rate limit بر اساس IP (۳۰ درخواست / دقیقه برای `/event`)
- اعتبارسنجی `install_id` (UUID)، دامنه، و schema
- بدون ذخیرهٔ رمز دیتابیس، JWT، یا دادهٔ کسب‌وکار
- توکن ingest قابل چرخش از پنل (پس از چرخش، سرورها باید `HESABIX_STATS_TOKEN` بگیرند)

## نیازمندی‌ها

- وردپرس 5.8+
- PHP 7.4+
- قابلیت `manage_options` برای مشاهده گزارش‌ها
