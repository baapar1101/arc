# مدیریت تنظیمات Redis از طریق پنل ادمین

این مستند راهنمای استفاده از بخش مدیریت تنظیمات Redis در پنل ادمین است.

## دسترسی

برای دسترسی به تنظیمات Redis، نیاز به مجوز `system_settings` یا `superadmin` دارید.

## Endpoint ها

### 1. دریافت تنظیمات Redis

**GET** `/api/v1/admin/system-settings/redis`

دریافت تنظیمات فعلی Redis شامل:
- `enabled`: فعال/غیرفعال بودن Redis
- `host`: آدرس سرور Redis
- `port`: پورت Redis
- `db`: شماره دیتابیس Redis (0-15)
- `password`: رمز عبور (برای امنیت نمایش داده نمی‌شود)

**مثال پاسخ:**
```json
{
  "success": true,
  "data": {
    "enabled": true,
    "host": "localhost",
    "port": 6379,
    "db": 0,
    "password": "***"
  }
}
```

### 2. به‌روزرسانی تنظیمات Redis

**PUT** `/api/v1/admin/system-settings/redis`

**Body:**
```json
{
  "enabled": true,
  "host": "localhost",
  "port": 6379,
  "db": 0,
  "password": "your_password_here"
}
```

**نکات مهم:**
- تمام فیلدها اختیاری هستند
- برای حذف password، مقدار خالی `""` ارسال کنید
- تغییرات به صورت خودکار اعمال می‌شوند (نیاز به restart نیست)
- بعد از تغییرات، اتصال Redis به صورت خودکار تست می‌شود

**مثال پاسخ:**
```json
{
  "success": true,
  "message": "REDIS_CONFIGURATION_UPDATED",
  "data": {
    "enabled": true,
    "host": "localhost",
    "port": 6379,
    "db": 0,
    "password": "***",
    "connection_status": "connected"
  }
}
```

### 3. تست اتصال Redis

**POST** `/api/v1/admin/system-settings/redis/test`

تست اتصال به Redis با تنظیمات فعلی و برگرداندن اطلاعات سرور.

**مثال پاسخ موفق:**
```json
{
  "success": true,
  "data": {
    "connected": true,
    "message": "Redis connection successful",
    "redis_version": "7.0.0",
    "used_memory": "2.5M",
    "test_passed": true
  }
}
```

**مثال پاسخ ناموفق:**
```json
{
  "success": true,
  "data": {
    "connected": false,
    "message": "Redis is disabled or connection failed"
  }
}
```

## استفاده در Frontend

### مثال با Flutter/Dart

```dart
// دریافت تنظیمات
Future<Map<String, dynamic>> getRedisSettings() async {
  final res = await apiClient.get('/api/v1/admin/system-settings/redis');
  return res.data['data'];
}

// به‌روزرسانی تنظیمات
Future<Map<String, dynamic>> updateRedisSettings({
  bool? enabled,
  String? host,
  int? port,
  int? db,
  String? password,
}) async {
  final res = await apiClient.put(
    '/api/v1/admin/system-settings/redis',
    data: {
      if (enabled != null) 'enabled': enabled,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (db != null) 'db': db,
      if (password != null) 'password': password,
    },
  );
  return res.data['data'];
}

// تست اتصال
Future<Map<String, dynamic>> testRedisConnection() async {
  final res = await apiClient.post('/api/v1/admin/system-settings/redis/test');
  return res.data['data'];
}
```

## نکات امنیتی

1. **Password**: رمز عبور Redis در پاسخ‌ها نمایش داده نمی‌شود (با `***` نشان داده می‌شود)
2. **HTTPS**: در production حتماً از HTTPS استفاده کنید
3. **Permissions**: فقط کاربران با مجوز `system_settings` یا `superadmin` می‌توانند تنظیمات را تغییر دهند

## عیب‌یابی

### مشکل: اتصال برقرار نمی‌شود

1. بررسی کنید که Redis service در حال اجرا باشد:
   ```bash
   sudo systemctl status redis-server
   ```

2. بررسی firewall:
   ```bash
   sudo ufw allow 6379
   ```

3. تست اتصال از command line:
   ```bash
   redis-cli -h localhost -p 6379 ping
   ```

### مشکل: تغییرات اعمال نمی‌شوند

- از endpoint `/redis/test` برای تست اتصال استفاده کنید
- بررسی لاگ‌های سرور برای خطاهای Redis
- در صورت نیاز، سرویس را restart کنید

## اولویت تنظیمات

تنظیمات Redis به ترتیب اولویت زیر خوانده می‌شوند:

1. **Database (System Settings)**: تنظیمات ذخیره شده در دیتابیس (اولویت اول)
2. **Environment Variables**: تنظیمات در فایل `.env` (fallback)

این به شما امکان می‌دهد تنظیمات را از طریق پنل ادمین تغییر دهید بدون نیاز به تغییر فایل `.env`.


