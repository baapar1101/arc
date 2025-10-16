# Hesabix - سیستم حسابداری جامع

Hesabix یک سیستم حسابداری کامل و مدرن است که شامل یک API قدرتمند (FastAPI + SQLAlchemy) و رابط کاربری زیبا (Flutter) می‌باشد. این سیستم برای مدیریت مالی کسب‌وکارهای کوچک و متوسط طراحی شده است.

## ویژگی‌های اصلی

### 🚀 API Backend (hesabixAPI)
- **FastAPI** - فریمورک مدرن و سریع برای ساخت API
- **SQLAlchemy** - ORM قدرتمند برای مدیریت پایگاه داده
- **MySQL** - پایگاه داده رابطه‌ای قابل اعتماد
- **Alembic** - مدیریت migration های پایگاه داده
- **Pydantic** - اعتبارسنجی و سریالیزاسیون داده‌ها
- **JWT Authentication** - سیستم احراز هویت امن
- **Multi-language Support** - پشتیبانی از چندین زبان (فارسی/انگلیسی)
- **Jalali Calendar** - تقویم شمسی برای کاربران ایرانی

### 📱 Frontend (hesabixUI)
- **Flutter** - فریمورک کراس‌پلتفرم برای موبایل، وب و دسکتاپ
- **Material Design** - رابط کاربری مدرن و زیبا
- **Responsive Design** - سازگار با تمام اندازه‌های صفحه
- **Multi-platform** - اجرا روی Android، iOS، Web و Desktop
- **Persian Font Support** - پشتیبانی کامل از فونت فارسی (Vazirmatn)

## ساختار پروژه

```
hesabix/
├── hesabixAPI/          # Backend API (FastAPI)
│   ├── app/            # کد اصلی اپلیکیشن
│   ├── adapters/       # لایه‌های دسترسی به داده
│   ├── migrations/     # فایل‌های migration پایگاه داده
│   └── tests/          # تست‌های واحد
├── hesabixUI/          # Frontend (Flutter)
│   └── hesabix_ui/     # پروژه Flutter اصلی
├── docs/               # مستندات پروژه
└── scripts/            # اسکریپت‌های کمکی
```

## پیش‌نیازها

### برای Backend (API)
- Python 3.11+
- MySQL 8.0+
- pip (Python package manager)

### برای Frontend (UI)
- Flutter SDK 3.9.2+
- Dart SDK
- Git

### برای Linux Desktop
- GTK+ 3.0 development libraries
- CMake
- Ninja build system
- C++ compiler (clang++ یا gcc)

## نصب و راه‌اندازی

### 1. کلون کردن پروژه

```bash
git clone <repository-url>
cd hesabix
```

### 2. راه‌اندازی Backend (API)

```bash
# ورود به دایرکتوری API
cd hesabixAPI

# ایجاد محیط مجازی
python3 -m venv .venv
source .venv/bin/activate  # در Windows: .venv\Scripts\activate

# نصب وابستگی‌ها
pip install -e .[dev]

# کپی کردن فایل تنظیمات
cp env.example .env

# ویرایش فایل .env و تنظیم اطلاعات پایگاه داده
# DB_USER=root
# DB_PASSWORD=your_password
# DB_HOST=localhost
# DB_PORT=3306
# DB_NAME=hesabixpy

# اجرای migration ها
alembic upgrade head

# اجرای سرور API
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 3. راه‌اندازی Frontend (UI)

```bash
# ورود به دایرکتوری UI
cd hesabixUI/hesabix_ui

# نصب وابستگی‌ها
flutter pub get

# اجرای اپلیکیشن
flutter run
```

## اسکریپت‌های کمکی

پروژه شامل چندین اسکریپت کمکی برای سهولت در استفاده است:

### اجرای API محلی
```bash
./run_local.sh serve    # اجرای سرور API
./run_local.sh migrate  # اجرای migration ها
./run_local.sh test     # اجرای تست‌ها
```

### اجرای Flutter Web
```bash
./run_web.sh                    # اجرای وب اپلیکیشن
./run_web.sh --port 8081        # اجرا روی پورت مشخص
./run_web.sh --mode debug       # اجرا در حالت debug
```

### اجرای Flutter Linux Desktop
```bash
./run_linux.sh                  # اجرای دسکتاپ اپلیکیشن
./run_linux.sh --mode release   # اجرا در حالت release
./run_linux.sh --clean          # پاک کردن build و اجرای مجدد
```

## تنظیمات محیط

### متغیرهای محیطی API (.env)

```env
# تنظیمات عمومی
APP_NAME=Hesabix API
ENVIRONMENT=development
DEBUG=true
API_V1_PREFIX=/api/v1
APP_VERSION=0.1.0

# پایگاه داده
DB_USER=root
DB_PASSWORD=your_password
DB_HOST=localhost
DB_PORT=3306
DB_NAME=hesabixpy
SQLALCHEMY_ECHO=false

# لاگ‌گیری
LOG_LEVEL=INFO
```

### تنظیمات Flutter

برای تنظیم آدرس API در Flutter، از متغیر محیطی استفاده کنید:

```bash
flutter run --dart-define API_BASE_URL=http://localhost:8000
```

## API Endpoints

### احراز هویت
- `POST /api/v1/auth/login` - ورود کاربر
- `POST /api/v1/auth/register` - ثبت نام کاربر
- `POST /api/v1/auth/refresh` - تمدید توکن

### سلامت سیستم
- `GET /api/v1/health` - بررسی وضعیت API

### کسب‌وکار
- `GET /api/v1/businesses` - لیست کسب‌وکارها
- `POST /api/v1/businesses` - ایجاد کسب‌وکار جدید
- `PUT /api/v1/businesses/{id}` - ویرایش کسب‌وکار

### محصولات
- `GET /api/v1/products` - لیست محصولات
- `POST /api/v1/products` - ایجاد محصول جدید
- `PUT /api/v1/products/{id}` - ویرایش محصول

### فاکتورها و پرداخت‌ها
- `GET /api/v1/receipts` - لیست فاکتورها
- `POST /api/v1/receipts` - ایجاد فاکتور جدید
- `GET /api/v1/payments` - لیست پرداخت‌ها

## ویژگی‌های خاص

### تقویم شمسی
سیستم از تقویم شمسی پشتیبانی کامل می‌کند و تمام تاریخ‌ها به صورت خودکار تبدیل می‌شوند.

### چندزبانه
- پشتیبانی از زبان‌های فارسی و انگلیسی
- امکان اضافه کردن زبان‌های جدید
- ترجمه خودکار رابط کاربری

### امنیت
- احراز هویت JWT
- رمزگذاری رمز عبور با Argon2
- اعتبارسنجی ورودی‌ها
- محافظت در برابر SQL Injection

## توسعه و مشارکت

### اجرای تست‌ها
```bash
# تست‌های Backend
cd hesabixAPI
pytest

# تست‌های Frontend
cd hesabixUI/hesabix_ui
flutter test
```

### کد استایل
```bash
# Backend
black .
ruff check .

# Frontend
flutter analyze
```

### ساخت برای تولید
```bash
# ساخت API
cd hesabixAPI
pip install -e .

# ساخت Flutter
cd hesabixUI/hesabix_ui
flutter build web
flutter build linux
flutter build apk
```

## عیب‌یابی

### مشکلات رایج

1. **خطای اتصال به پایگاه داده**
   - بررسی تنظیمات .env
   - اطمینان از اجرای MySQL
   - بررسی دسترسی‌های کاربر

2. **مشکلات Flutter**
   - اجرای `flutter clean`
   - حذف پوشه build
   - اجرای مجدد `flutter pub get`

3. **مشکلات Linux Desktop**
   - نصب وابستگی‌های مورد نیاز
   - استفاده از اسکریپت `run_linux.sh`

### لاگ‌ها
- API logs: در کنسول سرور نمایش داده می‌شوند
- Flutter logs: با `flutter logs` قابل مشاهده است

## مجوز

این پروژه تحت مجوز [MIT License](LICENSE) منتشر شده است.

## پشتیبانی

برای گزارش باگ یا درخواست ویژگی جدید، لطفاً issue جدیدی در repository ایجاد کنید.

## تیم توسعه

- **Backend**: FastAPI + SQLAlchemy + MySQL
- **Frontend**: Flutter + Material Design
- **DevOps**: Docker + Scripts
- **Documentation**: Markdown + Persian

---

**Hesabix** - سیستم حسابداری مدرن برای کسب‌وکارهای ایرانی 🇮🇷
