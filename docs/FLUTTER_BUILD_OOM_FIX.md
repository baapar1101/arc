# راهنمای حل مشکل OOM (Out of Memory) در Build Flutter Web

## مشکل

خطای `exit code -9` در هنگام build کردن Flutter Web معمولاً به معنای OOM (Out of Memory) است. این خطا زمانی رخ می‌دهد که:
- سیستم حافظه کافی ندارد
- `optimization-level 4` حافظه بسیار زیادی مصرف می‌کند
- Swap file وجود ندارد یا کافی نیست

## راه‌حل‌های اعمال شده

### 1. کاهش Optimization Level

در فایل `build_web.sh`، `optimization-level` از 4 به 2 کاهش یافته است:
- **قبل**: `--optimization-level 4` (نیاز به حافظه بسیار زیاد)
- **بعد**: `--optimization-level 2` (متعادل و کافی برای production)

این تغییر باعث کاهش مصرف حافظه می‌شود در حالی که هنوز بهینه‌سازی کافی برای production را فراهم می‌کند.

### 2. اضافه کردن بررسی حافظه

قبل از build، وضعیت حافظه سیستم بررسی می‌شود تا کاربر از وضعیت سیستم مطلع شود.

### 3. اسکریپت تنظیم Swap

اسکریپت `check_and_setup_swap.sh` برای ایجاد و فعال‌سازی swap file ایجاد شده است.

## استفاده

### راه‌حل سریع (توصیه می‌شود)

```bash
# فقط build را دوباره اجرا کنید
cd /var/www/ark
./build_web.sh
```

### راه‌حل کامل (در صورت نیاز)

اگر هنوز مشکل دارید، swap file را تنظیم کنید:

```bash
# ایجاد swap file به اندازه 4GB (پیش‌فرض)
sudo /var/www/ark/check_and_setup_swap.sh

# یا با اندازه دلخواه (مثلاً 8GB)
sudo /var/www/ark/check_and_setup_swap.sh 8
```

سپس build را دوباره اجرا کنید:

```bash
cd /var/www/ark
./build_web.sh
```

## بررسی وضعیت

### بررسی حافظه:
```bash
free -h
```

### بررسی swap:
```bash
swapon --show
```

### بررسی فضای دیسک:
```bash
df -h
```

## نکات مهم

1. **Optimization Level 2 کافی است**: برای اکثر پروژه‌ها، level 2 بهینه‌سازی کافی را فراهم می‌کند و نیازی به level 4 نیست.

2. **Swap File**: اگر سیستم شما RAM کمی دارد (کمتر از 8GB)، حتماً swap file را تنظیم کنید.

3. **پاک کردن Cache**: در صورت نیاز، می‌توانید cache را پاک کنید:
   ```bash
   cd /var/www/ark/hesabixUI/hesabix_ui
   flutter clean
   flutter pub get
   ```

4. **Build با Profile Mode**: برای تست، می‌توانید از profile mode استفاده کنید که حافظه کمتری مصرف می‌کند:
   ```bash
   ./build_web.sh --mode profile
   ```

## تغییرات در build_web.sh

- کاهش `optimization-level` از 4 به 2
- اضافه شدن بررسی حافظه قبل از build
- اضافه شدن تنظیمات محیطی برای dart compile js

## نتیجه

با این تغییرات، build باید بدون خطای OOM انجام شود. اگر هنوز مشکل دارید:
1. Swap file را تنظیم کنید
2. حافظه سیستم را بررسی کنید
3. از profile mode برای تست استفاده کنید

