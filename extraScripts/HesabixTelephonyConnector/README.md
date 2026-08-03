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

- دسترسی root روی سرور تلفن (با یا بدون `sudo`)
- خروجی HTTPS از سرور تلفن به API حسابیکس (پورت ورودی لازم نیست)
- کاربر AMI روی Asterisk (اسکریپت در صورت تمایل می‌سازد)

پیش‌نیازهای نرم‌افزاری (`python3` و …) در صورت نبود، هنگام `install`/`update` خودکار نصب می‌شوند.

### توزیع‌های پشتیبانی‌شده

| خانواده | نمونه‌ها | مدیر بسته |
|---------|----------|-----------|
| Debian | Debian، Ubuntu | `apt-get` |
| RHEL | CentOS، Rocky، Alma، Issabel | `yum` یا `dnf` |

## پیکربندی دستی (.env)

اگر ویزارد را نمی‌خواهید:

```bash
cp /opt/HesabixTelephonyConnector/config.example.env /opt/HesabixTelephonyConnector/.env
nano /opt/HesabixTelephonyConnector/.env
hesabix-pbx restart
hesabix-pbx test
```

مقدار پیش‌فرض `HESABIX_API_URL` برابر `https://hsxn.hesabix.ir` است.

## امنیت

- فقط خروجی HTTPS به حسابیکس لازم است؛ پورت AMI را به اینترنت باز نکنید.
- فایل `.env` با مجوز `600` ذخیره می‌شود.
- اگر توکن لو رفت: در حسابیکس «توکن جدید» بزنید، بعد `hesabix-pbx configure`.
