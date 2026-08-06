# Hesabix Telephony Connector

عامل سبک برای اتصال **Issabel / Asterisk** به حسابیکس.

مخزن: [extraScripts/HesabixTelephonyConnector](https://source.hesabix.ir/hesabix/arc/src/branch/master/extraScripts/HesabixTelephonyConnector)

## نصب یک‌خطی (پیشنهادی)

روی سرور Issabel/Asterisk با root:

```bash
# اگر sudo دارید (مثلاً Ubuntu):
curl -fsSL https://source.hesabix.ir/hesabix/arc/raw/branch/master/extraScripts/HesabixTelephonyConnector/install.sh | sudo bash

# اگر sudo ندارید (مثلاً Debian یا Issabel با ورود root):
curl -fsSL https://source.hesabix.ir/hesabix/arc/raw/branch/master/extraScripts/HesabixTelephonyConnector/install.sh | bash
```

آدرس API پیش‌فرض `https://hsxn.hesabix.ir` است. برای تغییر از همان لحظهٔ نصب:

```bash
curl -fsSL https://source.hesabix.ir/hesabix/arc/raw/branch/master/extraScripts/HesabixTelephonyConnector/install.sh \
  | HESABIX_API_URL=https://my-api.example.com bash
```

اسکریپت:
1. توزیع را تشخیص می‌دهد (Debian/Ubuntu با apt، Issabel/CentOS/RHEL با yum یا dnf)
2. پیش‌نیازها را نصب می‌کند (`python3`, `rsync`, `curl`, `git`)
3. کانکتور را از مخزن حسابیکس می‌گیرد
4. دستور `hesabix-pbx` را در سیستم نصب می‌کند
5. ویزارد پیکربندی (API / توکن / AMI) را اجرا می‌کند — آدرس API قابل تغییر است
6. سرویس systemd را فعال می‌کند

قبل از نصب، در حسابیکس: افزونه را فعال کنید → مرکز تلفن بسازید → توکن را کپی کنید.

## دستورات روزمره

```bash
hesabix-pbx status      # وضعیت سرویس، سیستم‌عامل و پیکربندی
hesabix-pbx test        # تست AMI + اتصال به حسابیکس
hesabix-pbx update      # به‌روزرسانی از مخزن (+ تلاش برای نصب Softphone deps)
hesabix-pbx softphone-setup  # نصب خودکار Softphone Relay
hesabix-pbx restart     # ری‌استارت
hesabix-pbx stop
hesabix-pbx start
hesabix-pbx configure   # تغییر توکن / AMI / آدرس API
hesabix-pbx logs        # آخرین لاگ‌ها
hesabix-pbx follow      # لاگ زنده
hesabix-pbx uninstall   # حذف سرویس
hesabix-pbx help
```

## نیازمندی‌ها

- دسترسی root روی سرور تلفن (با یا بدون `sudo`)
- خروجی HTTPS از سرور تلفن به API حسابیکس (پورت ورودی لازم نیست)
- کاربر AMI روی Asterisk (اسکریپت در صورت تمایل می‌سازد)

پیش‌نیازهای نرم‌افزاری (`python3` و …) در صورت نبود، هنگام `install`/`update` خودکار نصب می‌شوند.

### توزیع‌های پشتیبانی‌شده

| خانواده | نمونه‌ها | مدیر بسته |
|---------|----------|-----------|
| Debian | Debian، Ubuntu | `apt-get` |
| RHEL | CentOS، Rocky، Alma، Issabel | `yum` یا `dnf` |

## پیکربندی (ویزارد)

```bash
hesabix-pbx configure
```

از شما فقط می‌پرسد:
1. آدرس API (پیش‌فرض `https://hsxn.hesabix.ir`)
2. **کلید API** از حسابیکس: پروفایل ← کلیدهای API
3. انتخاب کسب‌وکار از لیست
4. انتخاب یا ایجاد مرکز تلفن (توکن Connector خودکار گرفته می‌شود)
5. تنظیمات AMI محلی

دیگر نیازی به وارد کردن دستی Business ID / PBX ID نیست.

مقدار پیش‌فرض `HESABIX_API_URL` برابر `https://hsxn.hesabix.ir` است.

## Softphone Media Relay

از نسخهٔ دارای Softphone، Connector علاوه بر AMI یک **تونل رسانه خروجی (WSS)** به حسابیکس و یک **AudioSocket محلی** (`127.0.0.1:9092`) دارد.

### نصب خودکار (پیشنهادی)

روی سرور PBX با root:

```bash
hesabix-pbx update
hesabix-pbx softphone-setup
```

`softphone-setup` این کارها را خودش انجام می‌دهد:
1. نصب `websocket-client` (pip)
2. افزودن کلیدهای Softphone به `.env` (`MEDIA_TUNNEL_ENABLED`, `AUDIOSOCKET_*`)
3. ری‌استارت سرویس
4. بررسی آمادگی

از نسخهٔ `1.3.0` به بعد، خودِ `hesabix-pbx update` هم تلاش می‌کند `websocket-client` را نصب کند.

### نصب دستی (در صورت نیاز)

```bash
pip3 install -r /opt/HesabixTelephonyConnector/requirements-softphone.txt
# یا:
pip3 install websocket-client
```

متغیرهای `.env`:

```bash
AUDIOSOCKET_HOST=127.0.0.1
AUDIOSOCKET_PORT=9092
MEDIA_TUNNEL_ENABLED=1
```

نمونه دیال‌پلن: `dialplan/hesabix-softphone-relay.conf.sample`

در حسابیکس: نگاشت کاربر↔داخلی را روی `endpoint_mode=relay` بگذارید، سپس از صفحه Softphone «آنلاین شدن» را بزنید.

**امنیت:** همچنان هیچ پورت ورودی روی PBX لازم نیست؛ فقط خروجی HTTPS/WSS به API حسابیکس.
