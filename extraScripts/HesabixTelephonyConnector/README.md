# Hesabix Telephony Connector

عامل سبک برای اتصال **Issabel / Asterisk** به حسابیکس.

مخزن: [extraScripts/HesabixTelephonyConnector](https://source.hesabix.ir/hesabix/arc/src/branch/master/extraScripts/HesabixTelephonyConnector)

## نصب یک‌خطی (پیشنهادی)

روی سرور Issabel/Asterisk:

```bash
curl -fsSL https://source.hesabix.ir/hesabix/arc/raw/branch/master/extraScripts/HesabixTelephonyConnector/install.sh | sudo bash
```

اسکریپت:
1. کانکتور را از مخزن حسابیکس می‌گیرد
2. دستور `hesabix-pbx` را در سیستم نصب می‌کند
3. ویزارد پیکربندی (API / توکن / AMI) را اجرا می‌کند
4. سرویس systemd را فعال می‌کند

قبل از نصب، در حسابیکس: افزونه را فعال کنید → مرکز تلفن بسازید → توکن را کپی کنید.

## دستورات روزمره

```bash
hesabix-pbx status      # وضعیت سرویس و پیکربندی
hesabix-pbx test        # تست AMI + اتصال به حسابیکس
hesabix-pbx update      # به‌روزرسانی از مخزن
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

- Python 3.9+
- دسترسی root روی سرور تلفن
- کاربر AMI روی Asterisk (اسکریپت در صورت تمایل می‌سازد)
- خروجی HTTPS از سرور تلفن به API حسابیکس (پورت ورودی لازم نیست)

## پیکربندی دستی (.env)

اگر ویزارد را نمی‌خواهید:

```bash
cp /opt/HesabixTelephonyConnector/config.example.env /opt/HesabixTelephonyConnector/.env
nano /opt/HesabixTelephonyConnector/.env
hesabix-pbx restart
hesabix-pbx test
```

## امنیت

- فقط خروجی HTTPS به حسابیکس لازم است؛ پورت AMI را به اینترنت باز نکنید.
- فایل `.env` با مجوز `600` ذخیره می‌شود.
- اگر توکن لو رفت: در حسابیکس «توکن جدید» بزنید، بعد `hesabix-pbx configure`.
