# Hesabix Telephony Connector

عامل سبک برای اتصال **Issabel / Asterisk** به حسابیکس.

## نیازمندی‌ها

- Python 3.9+
- دسترسی AMI روی Asterisk
- توکن Connector از تنظیمات مرکز تماس در حسابیکس

## نصب سریع

```bash
cd /opt
git clone <repo-or-copy> HesabixTelephonyConnector
cd HesabixTelephonyConnector
cp config.example.env .env
# مقادیر را پر کنید
python3 app/main.py
```

## systemd

فایل نمونه: `systemd/hesabix-telephony-connector.service`

## امنیت

- فقط خروجی HTTPS به حسابیکس لازم است؛ پورت ورودی باز نکنید.
- توکن را rotate کنید اگر لو رفت.
