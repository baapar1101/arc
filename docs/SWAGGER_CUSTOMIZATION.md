# 📚 راهنمای سفارسی‌سازی Swagger UI حسابیکس

## 🎯 خلاصه تغییرات

این سند خلاصه‌ای از تغییرات انجام شده برای بهبود ظاهر و خوانایی Swagger UI در پروژه حسابیکس است.

## ✨ ویژگی‌های جدید

### 1️⃣ **پشتیبانی کامل از زبان فارسی**
- ✅ فونت **Vazirmatn** برای متن‌های فارسی
- ✅ فونت **JetBrains Mono** برای کدها
- ✅ خوانایی بهتر و حروف جدا شده

### 2️⃣ **پشتیبانی RTL (راست به چپ)**
- ✅ راست‌چین شدن تمام توضیحات فارسی
- ✅ چپ‌چین ماندن کدها و URL ها
- ✅ تنظیم صحیح Margin و Padding

### 3️⃣ **رنگ‌بندی برند حسابیکس**
- ✅ رنگ اصلی: `#366092` (آبی حسابیکس)
- ✅ هماهنگی با هویت بصری برند
- ✅ رنگ‌بندی متفاوت برای متدهای HTTP

### 4️⃣ **بهبود UI/UX**
- ✅ دکمه‌های مدرن با سایه و انیمیشن
- ✅ Input fields حرفه‌ای
- ✅ Syntax Highlighting بهتر
- ✅ Scrollbar سفارشی
- ✅ Responsive Design

### 5️⃣ **دسته‌بندی بهتر**
- ✅ آیکون برای هر دسته (Tag)
- ✅ Border رنگی برای تشخیص بهتر
- ✅ Hover effects

## 📂 ساختار فایل‌ها

```
hesabixAPI/
├── app/
│   └── main.py                          # تغییرات اصلی
├── assets/
│   ├── swagger/
│   │   ├── custom.css                   # استایل‌های سفارشی اصلی
│   │   ├── swagger-rtl.css              # پشتیبانی RTL
│   │   └── README.md                    # راهنمای دایرکتوری
│   └── logo-blue.png                    # لوگو (موجود)
└── SWAGGER_CUSTOMIZATION.md             # این فایل
```

## 🚀 نحوه استفاده

### دسترسی به مستندات

پس از اجرای سرور، سه مسیر در دسترس است:

#### 1. Swagger UI استاندارد
```
http://localhost:8000/docs
```
یا
```
https://agent.hesabix.ir/docs
```
- نسخه استاندارد FastAPI
- بدون استایل سفارشی

#### 2. Swagger UI سفارشی (پیشنهادی) ⭐
```
http://localhost:8000/docs-custom
```
یا
```
https://agent.hesabix.ir/docs-custom
```
- **استایل حرفه‌ای حسابیکس**
- **پشتیبانی کامل فارسی و RTL**
- **بهترین تجربه کاربری**

#### 3. ReDoc
```
http://localhost:8000/redoc
```
یا
```
https://agent.hesabix.ir/redoc
```
- مستندات با ReDoc
- مناسب برای چاپ

## 🔧 تغییرات انجام شده

### در `main.py`

#### ✅ Import های جدید
```python
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from fastapi.openapi.docs import get_swagger_ui_html
```

#### ✅ تنظیمات Swagger UI
```python
application = FastAPI(
    # ... سایر تنظیمات
    docs_url=None,  # غیرفعال کردن docs پیش‌فرض
    swagger_ui_parameters={
        "defaultModelsExpandDepth": -1,
        "docExpansion": "list",
        "filter": True,
        "persistAuthorization": True,
        "displayRequestDuration": True,
        "tryItOutEnabled": True,
        "syntaxHighlight.theme": "monokai",
        "deepLinking": True,
        "displayOperationId": False,
    },
)
```

#### ✅ Mount کردن Assets
```python
application.mount("/assets", StaticFiles(directory="assets"), name="assets")
```

#### ✅ Endpoint های سفارشی
- `/docs` - نسخه استاندارد
- `/docs-custom` - نسخه سفارشی با HTML کامل

## 🎨 سفارسی‌سازی بیشتر

### تغییر رنگ اصلی

در `assets/swagger/custom.css`:

```css
:root {
  --hesabix-primary: #YOUR_COLOR;
  --hesabix-primary-dark: #YOUR_DARK_COLOR;
  --hesabix-primary-light: #YOUR_LIGHT_COLOR;
}
```

### تغییر فونت

```css
@font-face {
  font-family: 'YourFont';
  src: url('/assets/fonts/YourFont.woff2') format('woff2');
}

.swagger-ui * {
  font-family: 'YourFont', Tahoma, Arial, sans-serif !important;
}
```

### اضافه کردن لوگوی جدید

1. لوگو را در `assets/` قرار دهید
2. در `custom.css` تغییر دهید:

```css
.swagger-ui .topbar .topbar-wrapper::before {
  background-image: url('/assets/your-new-logo.png');
}
```

## 📊 مقایسه Before/After

| ویژگی | قبل ❌ | بعد ✅ |
|-------|--------|--------|
| **فونت فارسی** | نامناسب، حروف به هم چسبیده | Vazirmatn، خوانا و زیبا |
| **جهت متن** | چپ‌چین (LTR) | راست‌چین (RTL) |
| **رنگ‌بندی** | سبز استاندارد Swagger | آبی حسابیکس (#366092) |
| **لوگو** | ❌ ندارد | ✅ لوگو حسابیکس در Topbar |
| **دکمه‌ها** | ساده | مدرن با سایه و انیمیشن |
| **جستجو** | غیرفعال | ✅ فعال |
| **Try It Out** | بدون زیباسازی | طراحی حرفه‌ای |
| **Responsive** | محدود | ✅ کاملاً Responsive |

## 🧪 تست و عیب‌یابی

### چک کردن CSS ها

```bash
# بررسی وجود فایل‌ها
ls -la assets/swagger/

# خروجی باید شامل این موارد باشد:
# - custom.css
# - swagger-rtl.css
# - README.md
```

### تست در مرورگر

1. به `http://localhost:8000/docs-custom` بروید
2. Developer Tools را باز کنید (F12)
3. در Console بررسی کنید که خطایی وجود نداشته باشد
4. در Network Tab بررسی کنید که CSS ها لود شده باشند

### مشکلات رایج

#### مشکل: CSS ها لود نمی‌شوند
**علت:** مسیر assets درست mount نشده
**راه‌حل:**
```python
# در main.py بررسی کنید:
application.mount("/assets", StaticFiles(directory="assets"), name="assets")
```

#### مشکل: فونت فارسی نمایش داده نمی‌شود
**علت:** اتصال اینترنت یا مشکل CDN
**راه‌حل:** فونت را به صورت local در `assets/fonts/` قرار دهید

#### مشکل: تغییرات نمایش داده نمی‌شوند
**راه‌حل:**
```bash
# پاک کردن cache مرورگر
Ctrl + Shift + R  # Windows/Linux
Cmd + Shift + R   # Mac

# یا استفاده از Incognito Mode
```

## 🔄 به‌روزرسانی

برای به‌روزرسانی Swagger UI به نسخه جدید:

```html
<!-- در endpoint /docs-custom تغییر دهید: -->
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.x.x/swagger-ui.css">
<script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.x.x/swagger-ui-bundle.js"></script>
```

## 📦 Production Deployment

### 1. Minify کردن CSS

```bash
# نصب ابزار minify
npm install -g clean-css-cli

# minify کردن فایل‌ها
cleancss -o assets/swagger/custom.min.css assets/swagger/custom.css
cleancss -o assets/swagger/swagger-rtl.min.css assets/swagger/swagger-rtl.css
```

### 2. استفاده از CDN

برای بهبود performance در production، می‌توانید CSS های خود را روی CDN قرار دهید:

```html
<link rel="stylesheet" href="https://your-cdn.com/swagger/custom.min.css">
<link rel="stylesheet" href="https://your-cdn.com/swagger/swagger-rtl.min.css">
```

### 3. تنظیمات Caching

در Nginx یا Apache:

```nginx
# Nginx
location /assets/swagger/ {
    expires 30d;
    add_header Cache-Control "public, immutable";
}
```

## 📝 چک‌لیست Deploy

- [ ] فایل‌های CSS ایجاد شده‌اند
- [ ] `main.py` به‌روزرسانی شده
- [ ] دایرکتوری `assets/swagger/` وجود دارد
- [ ] سرور restart شده
- [ ] `/docs-custom` در مرورگر تست شده
- [ ] Cache مرورگر پاک شده
- [ ] در Production تست شده
- [ ] CSS ها minify شده‌اند (اختیاری)

## 🤝 مشارکت

اگر پیشنهاد بهبود یا ایده جدیدی دارید:

1. Issue جدید در GitLab/GitHub ایجاد کنید
2. تغییرات را در branch جدید commit کنید
3. Pull/Merge Request ارسال کنید

## 📚 منابع

- [Swagger UI Customization](https://swagger.io/docs/open-source-tools/swagger-ui/customization/custom-layout/)
- [FastAPI Custom Docs](https://fastapi.tiangolo.com/advanced/extending-openapi/)
- [Vazirmatn Font](https://github.com/rastikerdar/vazirmatn)
- [CSS RTL Best Practices](https://rtlstyling.com/)

## 🆘 پشتیبانی

برای سوالات یا مشکلات:
- **ایمیل:** support@hesabix.ir
- **تیکت:** در سیستم پشتیبانی حسابیکس

---

**✨ نسخه:** 1.0.0  
**📅 تاریخ:** دسامبر 2025  
**👥 تیم:** حسابیکس  
**📄 لایسنس:** GNU GPLv3


