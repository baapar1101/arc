# مدیریت سرویس Hesabix API با systemd

سرویس Hesabix API به صورت خودکار با systemd مدیریت می‌شود و با راه‌اندازی مجدد سیستم به صورت خودکار اجرا می‌شود.

## دستورات مدیریتی

### مشاهده وضعیت سرویس
```bash
systemctl status hesabix-api.service
```

### شروع سرویس
```bash
systemctl start hesabix-api.service
```

### توقف سرویس
```bash
systemctl stop hesabix-api.service
```

### راه‌اندازی مجدد سرویس
```bash
systemctl restart hesabix-api.service
```

### مشاهده لاگ‌های سرویس
```bash
# مشاهده لاگ‌های اخیر
journalctl -u hesabix-api.service -n 50

# مشاهده لاگ‌های زنده (real-time)
journalctl -u hesabix-api.service -f

# مشاهده لاگ‌های از یک زمان خاص
journalctl -u hesabix-api.service --since "1 hour ago"
```

### فعال/غیرفعال کردن اجرای خودکار
```bash
# فعال کردن اجرای خودکار
systemctl enable hesabix-api.service

# غیرفعال کردن اجرای خودکار
systemctl disable hesabix-api.service
```

## تنظیمات سرویس

فایل سرویس در مسیر زیر قرار دارد:
```
/etc/systemd/system/hesabix-api.service
```

### تغییر تعداد Workers

برای تغییر تعداد worker ها، فایل سرویس را ویرایش کنید:
```bash
sudo nano /etc/systemd/system/hesabix-api.service
```

سپس خط `ExecStart` را ویرایش کنید:
```ini
ExecStart=/var/www/ark/hesabixAPI/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
```

بعد از تغییر، سرویس را reload کنید:
```bash
sudo systemctl daemon-reload
sudo systemctl restart hesabix-api.service
```

## بررسی عملکرد

### تست Health Endpoint
```bash
curl http://localhost:8000/api/v1/health
```

### مشاهده پروسه‌های در حال اجرا
```bash
ps aux | grep uvicorn
```

## نکات مهم

1. سرویس به صورت خودکار با راه‌اندازی مجدد سیستم اجرا می‌شود
2. در صورت crash، سرویس به صورت خودکار restart می‌شود (با تأخیر 10 ثانیه)
3. لاگ‌ها در systemd journal ذخیره می‌شوند و با `journalctl` قابل مشاهده هستند
4. سرویس با 4 worker اجرا می‌شود که می‌تواند برای بار بالا مناسب باشد

