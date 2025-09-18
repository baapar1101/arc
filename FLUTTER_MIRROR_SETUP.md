# راهنمای تنظیم Flutter Mirror برای دسترسی بهتر به پکیج‌ها

## مشکل
در برخی مناطق، دسترسی مستقیم به `pub.dev` ممکن است محدود یا کند باشد.

## راه‌حل
استفاده از mirror سایت‌های چینی برای دسترسی بهتر به پکیج‌های Flutter.

## تنظیم سریع

### 1. اجرای اسکریپت خودکار
```bash
cd /home/babak/hesabix
./setup_flutter_mirror.sh
```

### 2. تنظیم دستی
```bash
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
```

## Mirror سایت‌های پشتیبانی شده

### 1. China Flutter User Group
- **URL**: `https://pub.flutter-io.cn`
- **Storage**: `https://storage.flutter-io.cn`
- **پشتیبانی**: [Issue Tracker](https://github.com/flutter-io/flutter-io.cn)

### 2. Shanghai Jiao Tong University
- **URL**: `https://mirror.sjtu.edu.cn/dart-pub`
- **Storage**: `https://mirror.sjtu.edu.cn`

### 3. Tsinghua University TUNA
- **URL**: `https://mirrors.tuna.tsinghua.edu.cn/dart-pub`
- **Storage**: `https://mirrors.tuna.tsinghua.edu.cn/flutter`

## تنظیم دائمی

### برای Bash/Zsh:
```bash
echo 'export PUB_HOSTED_URL="https://pub.flutter-io.cn"' >> ~/.bashrc
echo 'export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"' >> ~/.bashrc
source ~/.bashrc
```

### برای Windows PowerShell:
```powershell
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
```

## تست تنظیمات

### 1. بررسی متغیرهای محیطی
```bash
echo $PUB_HOSTED_URL
echo $FLUTTER_STORAGE_BASE_URL
```

### 2. تست دسترسی به پکیج‌ها
```bash
cd hesabixUI/hesabix_ui
flutter pub get
```

### 3. تست نصب پکیج جدید
```bash
flutter pub add package_name
```

## بازگشت به تنظیمات پیش‌فرض

### حذف متغیرهای محیطی
```bash
unset PUB_HOSTED_URL
unset FLUTTER_STORAGE_BASE_URL
```

### یا تنظیم به pub.dev اصلی
```bash
export PUB_HOSTED_URL="https://pub.dev"
export FLUTTER_STORAGE_BASE_URL="https://storage.googleapis.com"
```

## مزایای استفاده از Mirror

1. **سرعت بالاتر**: دانلود سریع‌تر پکیج‌ها
2. **دسترسی بهتر**: حل مشکل محدودیت‌های جغرافیایی
3. **پایداری**: کاهش احتمال قطع ارتباط
4. **سازگاری**: کاملاً سازگار با Flutter اصلی

## نکات مهم

- Mirror سایت‌ها توسط جامعه Flutter چین پشتیبانی می‌شوند
- همیشه از mirror های معتبر استفاده کنید
- در صورت بروز مشکل، به Issue Tracker مربوطه مراجعه کنید
- تنظیمات فقط برای session فعلی اعمال می‌شود مگر اینکه دائمی شوند

## منابع

- [مستندات رسمی Flutter](https://docs.flutter.dev/community/china)
- [China Flutter User Group](https://flutter-io.cn)
- [Shanghai Jiao Tong University Mirror](https://mirror.sjtu.edu.cn)
- [Tsinghua University TUNA Mirror](https://mirrors.tuna.tsinghua.edu.cn)
