# راه‌اندازی Redis برای Cache

این مستند راهنمای نصب و پیکربندی Redis برای استفاده به عنوان cache layer در Hesabix API است.

## نصب Redis

### Ubuntu/Debian
```bash
sudo apt update
sudo apt install redis-server -y
sudo systemctl enable redis-server
sudo systemctl start redis-server
```

### بررسی نصب
```bash
redis-cli ping
# باید پاسخ PONG برگرداند
```

## پیکربندی Redis

### تنظیمات پیشنهادی برای Production

ویرایش فایل `/etc/redis/redis.conf`:

```conf
# حداکثر حافظه (مثال: 512MB)
maxmemory 512mb

# سیاست حذف کلیدها هنگام پر شدن حافظه
maxmemory-policy allkeys-lru

# ذخیره‌سازی persistence (اختیاری)
save 900 1
save 300 10
save 60 10000

# امنیت
requirepass your_secure_password_here
```

بعد از تغییرات:
```bash
sudo systemctl restart redis-server
```

## پیکربندی در Hesabix API

افزودن به فایل `.env`:

```env
# Redis Cache
REDIS_ENABLED=true
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=your_secure_password_here
```

## تست اتصال

```python
from app.core.cache import get_redis_client

client = get_redis_client()
if client:
    print("Redis connected successfully!")
    client.set("test", "value", ex=60)
    print(client.get("test"))
else:
    print("Redis connection failed")
```

## Monitoring

### بررسی وضعیت Redis
```bash
redis-cli info stats
redis-cli info memory
```

### مشاهده کلیدهای cache
```bash
redis-cli
> KEYS api_key:*
> KEYS system:*
```

### پاک کردن cache
```bash
redis-cli FLUSHDB  # پاک کردن تمام cache
redis-cli DEL api_key:xxx  # پاک کردن یک کلید خاص
```

## Performance Tips

1. **Memory Management**: تنظیم `maxmemory` و `maxmemory-policy` مناسب
2. **Persistence**: برای cache معمولاً نیاز به persistence نیست (می‌توانید disable کنید)
3. **Connection Pooling**: Redis client به صورت خودکار connection pooling دارد
4. **Monitoring**: استفاده از `redis-cli --latency` برای بررسی latency

## Troubleshooting

### مشکل: Redis connection failed
- بررسی کنید که Redis service در حال اجرا باشد: `sudo systemctl status redis-server`
- بررسی firewall: `sudo ufw allow 6379`
- بررسی password در `.env`

### مشکل: Memory full
- افزایش `maxmemory` در `redis.conf`
- تغییر `maxmemory-policy` به `allkeys-lru`


