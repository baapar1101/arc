# رفع مشکل اتصال Proxy به سرور اصلی

## مشکل

لاگ‌ها نشان می‌دهند که سرور proxy نمی‌تواند به سرور اصلی (`hsxn.hesabix.ir`) متصل شود:

```
[ERROR] ❌ Failed to forward webhook - DETAILED ERROR
"error":"Could not connect to server. Check firewall and network settings."
"curl_errno":7
```

خطای `curl_errno: 7` (CURLE_COULDNT_CONNECT) به معنای این است که:
- فایروال سرور اصلی، IP سرور proxy را block کرده است
- یا مشکل شبکه بین دو سرور وجود دارد

## راه‌حل‌ها

### 1. تست اتصال

ابتدا از اسکریپت تست استفاده کنید:

```bash
cd /var/www/ark/telegram_proxy
php test_connection.php
```

این اسکریپت بررسی می‌کند که:
- DNS resolution کار می‌کند
- اتصال TCP برقرار می‌شود
- درخواست HTTP/HTTPS موفق است

### 2. پیدا کردن IP سرور Proxy

برای پیدا کردن IP سرور proxy:

```bash
# از داخل سرور proxy
curl -s ifconfig.me
# یا
hostname -I
```

یا از لاگ‌های proxy می‌توانید IP را ببینید.

### 3. Whitelist کردن IP در فایروال سرور اصلی

#### اگر از UFW استفاده می‌کنید:

```bash
# روی سرور اصلی
sudo ufw allow from <PROXY_IP> to any port 443
sudo ufw allow from <PROXY_IP> to any port 80
```

#### اگر از iptables استفاده می‌کنید:

```bash
# روی سرور اصلی
sudo iptables -A INPUT -p tcp -s <PROXY_IP> --dport 443 -j ACCEPT
sudo iptables -A INPUT -p tcp -s <PROXY_IP> --dport 80 -j ACCEPT
sudo iptables-save
```

#### اگر از Cloudflare یا CDN استفاده می‌کنید:

- بررسی کنید که IP سرور proxy در whitelist قرار دارد
- یا از "IP Access Rules" در Cloudflare استفاده کنید

### 4. بررسی تنظیمات Nginx/Apache

مطمئن شوید که nginx/apache روی سرور اصلی، درخواست‌ها را از IP proxy می‌پذیرد.

برای nginx، بررسی کنید که در `nginx.conf` یا فایل site شما محدودیتی وجود ندارد:

```nginx
# اگر چنین محدودیتی دارید، آن را حذف یا تغییر دهید:
# deny all;
# allow 192.168.1.0/24;
```

### 5. استفاده از IP مستقیم (موقت)

اگر مشکل DNS وجود دارد، می‌توانید موقتاً از IP مستقیم استفاده کنید:

1. IP سرور اصلی را پیدا کنید:
   ```bash
   nslookup hsxn.hesabix.ir
   ```

2. در `telegram_proxy/config.php`، `internal_webhook_url` را به IP تغییر دهید:
   ```php
   'internal_webhook_url' => 'https://<IP>/api/v1/integrations/telegram/webhook/...'
   ```

**توجه:** این راه‌حل موقت است و برای SSL certificate مشکل ایجاد می‌کند. بهتر است مشکل فایروال را حل کنید.

### 6. بررسی SSL Certificate

اگر مشکل SSL وجود دارد:

```bash
# تست SSL از سرور proxy
openssl s_client -connect hsxn.hesabix.ir:443 -showcerts
```

مطمئن شوید که:
- Certificate معتبر است
- Certificate برای domain صحیح است
- Certificate منقضی نشده است

### 7. بررسی لاگ‌های سرور اصلی

بررسی کنید که آیا درخواست‌ها به سرور اصلی می‌رسند یا نه:

```bash
# لاگ‌های nginx
sudo tail -f /var/log/nginx/access.log | grep telegram

# لاگ‌های apache
sudo tail -f /var/log/apache2/access.log | grep telegram
```

اگر درخواست‌ها در لاگ نیستند، یعنی فایروال یا nginx آن‌ها را block کرده است.

## چک‌لیست

- [ ] IP سرور proxy را پیدا کردید
- [ ] IP را در فایروال سرور اصلی whitelist کردید
- [ ] اتصال TCP را تست کردید (`test_connection.php`)
- [ ] تنظیمات nginx/apache را بررسی کردید
- [ ] SSL certificate معتبر است
- [ ] لاگ‌های سرور اصلی را بررسی کردید

## تست نهایی

بعد از اعمال تغییرات:

1. اسکریپت تست را اجرا کنید:
   ```bash
   php telegram_proxy/test_connection.php
   ```

2. یک پیام به ربات تلگرام بفرستید

3. لاگ‌های proxy را بررسی کنید:
   ```bash
   tail -f telegram_proxy/proxy_*.log
   ```

4. لاگ‌های سرور اصلی را بررسی کنید تا ببینید درخواست‌ها دریافت می‌شوند

## دریافت کمک

اگر مشکل حل نشد:

1. خروجی `test_connection.php` را ذخیره کنید
2. لاگ‌های کامل proxy را ذخیره کنید
3. خروجی `iptables -L` یا `ufw status` را ذخیره کنید
4. این اطلاعات را به تیم پشتیبانی ارسال کنید

