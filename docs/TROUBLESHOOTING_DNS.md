# راهنمای حل مشکل DNS برای Flutter

## مشکل
خطای `Failed host lookup: 'pub.flutter-io.cn'` یا `Could not resolve host: pub.dev` هنگام اجرای `flutter pub get`

## علت
DNS server سیستم نمی‌تواند آدرس‌های Flutter Pub را resolve کند.

## راه حل‌ها

### راه حل 1: تنظیم DNS با Google DNS (توصیه می‌شود)

```bash
# تنظیم DNS برای systemd-resolved
sudo mkdir -p /etc/systemd/resolved.conf.d
echo -e '[Resolve]\nDNS=8.8.8.8 8.8.4.4\nFallbackDNS=1.1.1.1' | sudo tee /etc/systemd/resolved.conf.d/dns_servers.conf
sudo systemctl restart systemd-resolved

# تست
nslookup pub.dev
curl -I https://pub.dev
```

### راه حل 2: استفاده از اسکریپت کمکی

```bash
cd /var/www/ark
./fix_dns.sh
```

### راه حل 3: تنظیم موقت DNS

```bash
# فقط برای session فعلی
export DNS_SERVER="8.8.8.8"
sudo resolvectl dns eth0 8.8.8.8 8.8.4.4
```

### راه حل 4: استفاده از Mirror چینی (اگر در چین هستید)

```bash
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
cd /var/www/ark/hesabixUI/hesabix_ui
flutter pub get
```

### راه حل 5: بررسی و تنظیم دستی /etc/resolv.conf

```bash
# بکاپ گرفتن
sudo cp /etc/resolv.conf /etc/resolv.conf.backup

# تغییر موقت
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf

# تست
nslookup pub.dev
```

### راه حل 6: استفاده از Proxy (اگر در شبکه محدود شده‌ای هستید)

```bash
export HTTP_PROXY="http://proxy-server:port"
export HTTPS_PROXY="http://proxy-server:port"
export NO_PROXY="localhost,127.0.0.1"
```

## بررسی وضعیت DNS

```bash
# بررسی DNS servers فعلی
resolvectl status

# تست دسترسی به pub.dev
dig pub.dev
nslookup pub.dev
curl -I https://pub.dev

# تست دسترسی با DNS server خاص
dig @8.8.8.8 pub.dev
host pub.dev 8.8.8.8
```

## نکات مهم

1. پس از تنظیم DNS، حتماً `systemd-resolved` را restart کنید
2. اگر از `/etc/resolv.conf` استفاده می‌کنید، ممکن است بعد از reboot تغییر کند
3. برای تنظیم دائمی، از `systemd-resolved` استفاده کنید
4. اگر مشکل ادامه داشت، فایروال یا proxy شبکه را بررسی کنید

## تست نهایی

پس از تنظیم DNS، دستور زیر را اجرا کنید:

```bash
cd /var/www/ark/hesabixUI/hesabix_ui
flutter pub get
```

اگر موفق بود، می‌توانید build را ادامه دهید:

```bash
cd /var/www/ark
./build_web.sh --clean --mode release --api-base-url https://hsxn.hesabix.ir
```

