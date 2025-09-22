# اسکریپت‌های Linux برای Hesabix

این فایل شامل اسکریپت‌های مفید برای اجرا و build کردن اپلیکیشن Flutter در Linux است.

## اسکریپت‌های موجود

### 1. `run_linux.sh` - اجرای اپلیکیشن در Linux

اسکریپت اصلی برای اجرای اپلیکیشن Flutter در Linux Desktop.

**استفاده:**
```bash
./run_linux.sh [options]
```

**گزینه‌ها:**
- `--project PATH`: مسیر پروژه Flutter (اختیاری)
- `--mode MODE`: نوع اجرا (debug/profile/release) - پیش‌فرض: debug
- `--build-dir DIR`: مسیر build directory - پیش‌فرض: build/linux
- `--clean`: پاک کردن build directory قبل از اجرا
- `--install-deps`: نصب وابستگی‌ها قبل از اجرا
- `--api-base-url URL`: آدرس پایه API
- `--help`: نمایش راهنما

**نمونه‌های استفاده:**
```bash
# اجرای ساده
./run_linux.sh

# اجرا در حالت release
./run_linux.sh --mode release

# اجرا با پاک کردن build directory
./run_linux.sh --clean --mode debug

# اجرا با نصب وابستگی‌ها
./run_linux.sh --install-deps

# اجرا با API base URL
./run_linux.sh --api-base-url http://localhost:8000
```

### 2. `build_linux.sh` - Build کردن اپلیکیشن برای Linux

اسکریپت برای ایجاد executable مستقل از اپلیکیشن Flutter.

**استفاده:**
```bash
./build_linux.sh [options]
```

**گزینه‌ها:**
- `--project PATH`: مسیر پروژه Flutter (اختیاری)
- `--mode MODE`: نوع build (debug/profile/release) - پیش‌فرض: release
- `--build-dir DIR`: مسیر build directory - پیش‌فرض: build/linux
- `--output-dir DIR`: مسیر خروجی نهایی - پیش‌فرض: build/linux_release
- `--clean`: پاک کردن build directory قبل از build
- `--install-deps`: نصب وابستگی‌ها قبل از build
- `--api-base-url URL`: آدرس پایه API
- `--archive`: ایجاد فایل tar.gz از خروجی
- `--help`: نمایش راهنما

**نمونه‌های استفاده:**
```bash
# Build ساده
./build_linux.sh

# Build در حالت debug
./build_linux.sh --mode debug

# Build با ایجاد archive
./build_linux.sh --archive

# Build کامل با پاک کردن و نصب وابستگی‌ها
./build_linux.sh --clean --install-deps --archive
```

## وابستگی‌های مورد نیاز

قبل از استفاده از این اسکریپت‌ها، مطمئن شوید که وابستگی‌های زیر نصب شده‌اند:

### Ubuntu/Debian:
```bash
sudo apt update
sudo apt install libgtk-3-dev cmake ninja-build
```

### Fedora/RHEL:
```bash
sudo dnf install gtk3-devel cmake ninja-build
```

### Arch Linux:
```bash
sudo pacman -S gtk3 cmake ninja
```

## نصب Flutter

اگر Flutter نصب نیست، می‌توانید از snap استفاده کنید:

```bash
sudo snap install flutter --classic
```

یا از سایت رسمی Flutter دانلود کنید:
https://flutter.dev/docs/get-started/install/linux

## ویژگی‌های جدید

### نصب خودکار وابستگی‌ها
اسکریپت‌ها به‌طور خودکار وابستگی‌های مورد نیاز را تشخیص داده و نصب می‌کنند:
- GTK+3 development libraries
- CMake
- Ninja build system
- Clang C++ compiler
- Build essential tools

### رفع مشکلات platform-specific
- مشکلات مربوط به `dart:html` (که فقط در web platform موجود است) به‌طور خودکار رفع می‌شوند
- توابع download برای Linux desktop به‌روزرسانی می‌شوند
- فایل‌های اصلی پس از اجرا بازیابی می‌شوند

### پشتیبانی از توزیع‌های مختلف
- Ubuntu/Debian (apt)
- Fedora/RHEL (dnf)
- Arch Linux (pacman)

## نکات مهم

1. **مسیر پروژه**: اسکریپت‌ها به‌طور خودکار پروژه Flutter را در `hesabixUI/hesabix_ui` پیدا می‌کنند.

2. **Mirror تنظیمات**: اسکریپت‌ها از mirror چینی برای حل مشکل دسترسی به pub.dev استفاده می‌کنند.

3. **Build Directory**: فایل‌های build شده در `build/linux` ذخیره می‌شوند.

4. **خروجی نهایی**: فایل‌های قابل اجرا در `build/linux_release` (یا مسیر مشخص شده) قرار می‌گیرند.

5. **اجرای فایل نهایی**: پس از build، می‌توانید فایل `hesabix_ui` را در مسیر خروجی اجرا کنید.

6. **بازیابی خودکار**: فایل‌های اصلی پس از اجرا یا build به حالت اولیه بازمی‌گردند.

## عیب‌یابی

### خطای "Flutter یافت نشد"
- مطمئن شوید Flutter نصب شده است
- مسیر Flutter را به PATH اضافه کنید
- از snap استفاده کنید: `sudo snap install flutter --classic`

### خطای "GTK+3 development libraries یافت نشد"
- وابستگی‌های GTK را نصب کنید (به بخش وابستگی‌ها مراجعه کنید)

### خطای "CMake یافت نشد"
- CMake را نصب کنید: `sudo apt install cmake` (Ubuntu/Debian)

### خطای build
- از `--clean` استفاده کنید تا build directory پاک شود
- از `--install-deps` استفاده کنید تا وابستگی‌ها نصب شوند

### خطای "dart:html is not available"
- این خطا به‌طور خودکار توسط اسکریپت رفع می‌شود
- اگر همچنان رخ داد، از `--clean` استفاده کنید

### خطای "deprecated-literal-operator"
- این خطا مربوط به flutter_secure_storage_linux است
- اسکریپت به‌طور خودکار compiler flags را تنظیم می‌کند

### خطای "Could not find compiler"
- اسکریپت به‌طور خودکار clang و build-essential را نصب می‌کند
- اگر همچنان رخ داد، دستی نصب کنید: `sudo apt install clang build-essential`
