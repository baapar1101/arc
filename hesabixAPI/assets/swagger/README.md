# 🎨 راهنمای سفارسی‌سازی Swagger UI حسابیکس

این دایرکتوری شامل فایل‌های سفارشی‌سازی Swagger UI برای API حسابیکس است.

## 📁 ساختار فایل‌ها

```
swagger/
├── custom.css          # استایل‌های سفارشی اصلی
├── swagger-rtl.css     # پشتیبانی از راست‌به‌چپ (RTL)
├── dark-mode.css       # حالت تیره (برای /docs-custom)
├── vendor/             # Swagger UI بدون CDN (bundle + CSS + preset)
│   ├── swagger-ui-bundle.js
│   ├── swagger-ui.css
│   ├── swagger-ui-standalone-preset.js
│   └── VERSION.txt
└── README.md           # این فایل
```

## 🚀 نحوه استفاده

### دسترسی به مستندات

پس از اجرای سرور، می‌توانید به دو صفحه مستندات دسترسی داشته باشید:

1. **Swagger UI استاندارد:** `http://localhost:8000/docs`
   - نسخه استاندارد با تنظیمات پیش‌فرض FastAPI

2. **Swagger UI سفارشی:** `http://localhost:8000/docs-custom`
   - نسخه سفارشی با استایل‌های حسابیکس و پشتیبانی کامل RTL

3. **ReDoc:** `http://localhost:8000/redoc`
   - مستندات با استفاده از ReDoc

## 🎨 ویژگی‌های سفارسی‌سازی

### 1. فونت فارسی
- در `custom.css` برای **عدم وابستگی به CDN خارجی**، فونت از طریق `local('Vazirmatn')` و فونت‌های سیستمی (Tahoma و …) پیشنهاد شده است؛ برای ظاهر یکسان همهٔ کاربران می‌توانید فایل‌های woff2 را در `assets` بگذارید و `@font-face` لوکال اضافه کنید.

### 2. فونت انگلیسی/کد
- نام **JetBrains Mono** در استایل کد پیشنهاد شده؛ تنها در صورت نصب روی سیستم کاربر استفاده می‌شود (بدون بارگذاری از اینترنت).

### 3. رنگ‌بندی برند
- رنگ اصلی: `#366092` (آبی حسابیکس)
- رنگ تیره: `#2a4a6f`
- رنگ روشن: `#4a7ab8`

### 4. پشتیبانی RTL
- راست‌چین شدن تمام متن‌های فارسی
- چپ‌چین ماندن کدها، URL ها و JSON ها
- تنظیم صحیح margin و padding برای RTL

### 5. بهبود UI/UX
- دکمه‌های مدرن با سایه و انیمیشن
- Input fields با طراحی حرفه‌ای
- کدها با Syntax Highlighting بهتر
- Scrollbar سفارشی
- Responsive Design برای موبایل

### 6. دسته‌بندی بهتر
- آیکون برای هر دسته
- رنگ‌بندی متفاوت برای متدهای HTTP
- Tag های بهتر با استایل حرفه‌ای

## ⚙️ تنظیمات Swagger UI

تنظیمات زیر در `main.py` اعمال شده‌اند:

```python
swagger_ui_parameters={
    "defaultModelsExpandDepth": -1,     # بسته بودن Models
    "docExpansion": "list",             # نمایش لیستی
    "filter": True,                     # جستجو فعال
    "persistAuthorization": True,       # ذخیره توکن
    "displayRequestDuration": True,     # نمایش زمان
    "tryItOutEnabled": True,            # Try it out فعال
    "syntaxHighlight.theme": "monokai", # تم کد
    "deepLinking": True,                # لینک مستقیم
    "displayOperationId": False,        # بدون Operation ID
}
```

## 🔧 نحوه سفارسی‌سازی بیشتر

### تغییر رنگ اصلی

در فایل `custom.css` متغیرهای CSS را تغییر دهید:

```css
:root {
  --hesabix-primary: #366092;        /* رنگ اصلی */
  --hesabix-primary-dark: #2a4a6f;   /* رنگ تیره */
  --hesabix-primary-light: #4a7ab8;  /* رنگ روشن */
}
```

### اضافه کردن لوگو سفارشی

لوگوی خود را در `/assets/` قرار دهید و در `custom.css` مسیر را تغییر دهید:

```css
.swagger-ui .topbar .topbar-wrapper::before {
  background-image: url('/assets/your-logo.png');
}
```

### تغییر فونت

می‌توانید فونت دلخواه خود را اضافه کنید:

```css
@font-face {
  font-family: 'YourFont';
  src: url('/assets/fonts/YourFont.woff2') format('woff2');
}

.swagger-ui * {
  font-family: 'YourFont', Tahoma, Arial, sans-serif !important;
}
```

## 📊 مقایسه قبل و بعد

### قبل (Swagger UI پیش‌فرض):
❌ فونت نامناسب برای فارسی  
❌ چپ‌چین بودن متن  
❌ رنگ‌بندی استاندارد  
❌ بدون لوگو و برندینگ  

### بعد (Swagger UI سفارشی):
✅ فونت Vazirmatn برای فارسی  
✅ راست‌چین با پشتیبانی کامل RTL  
✅ رنگ‌بندی برند حسابیکس  
✅ لوگو و هویت بصری  
✅ UI/UX بهبود یافته  

## 🐛 عیب‌یابی

### مشکل: فونت فارسی نمایش داده نمی‌شود
**راه‌حل:** 
- اتصال اینترنت را بررسی کنید (فونت از CDN لود می‌شود)
- یا فونت را به صورت local در `/assets/fonts/` قرار دهید

### مشکل: CSS ها اعمال نمی‌شوند
**راه‌حل:**
- Cache مرورگر را پاک کنید (Ctrl+Shift+R)
- مسیر `/assets/swagger/` را بررسی کنید
- مجوز دسترسی فایل‌ها را چک کنید

### مشکل: صفحه `/docs-custom` خطای 404 می‌دهد
**راه‌حل:**
- مطمئن شوید که سرور را restart کرده‌اید
- `main.py` را بررسی کنید که endpoint اضافه شده باشد

## 🔒 امنیت

- تمام فایل‌های CSS استاتیک هستند و خطر امنیتی ندارند
- فونت‌ها از CDN معتبر jsdelivr لود می‌شوند
- لوگو از همان سرور serve می‌شود

## 📝 یادداشت‌ها

### کش مرورگر
برای مشاهده تغییرات، همیشه cache مرورگر را پاک کنید یا از Incognito Mode استفاده کنید.

### توسعه محلی
برای توسعه و تست سریع‌تر:
```bash
# Watch mode برای CSS (اختیاری)
npm install -g live-server
live-server --watch=assets/swagger/
```

### Production
در production مطمئن شوید:
- فایل‌های CSS را minify کنید
- از CDN برای serve کردن فایل‌های استاتیک استفاده کنید
- از caching مناسب استفاده کنید

## 🤝 مشارکت

برای پیشنهاد بهبود یا گزارش باگ:
1. Issue جدید ایجاد کنید
2. تغییرات خود را در branch جدید commit کنید
3. Pull Request ارسال کنید

## 📚 منابع مفید

- [Swagger UI Documentation](https://swagger.io/docs/open-source-tools/swagger-ui/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/advanced/extending-openapi/)
- [OpenAPI Specification](https://spec.openapis.org/oas/latest.html)
- [Vazirmatn Font](https://github.com/rastikerdar/vazirmatn)

## 📄 لایسنس

این سفارسی‌سازی‌ها تحت لایسنس GNU GPLv3 منتشر شده‌اند.

---

**نسخه:** 1.0.0  
**آخرین به‌روزرسانی:** دسامبر 2025  
**نگهدارنده:** تیم حسابیکس


