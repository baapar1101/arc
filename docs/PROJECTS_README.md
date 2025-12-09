# 📁 قابلیت مدیریت پروژه - راهنمای شروع سریع

## ⚡ شروع در 3 دقیقه

### گام 1: اجرای Migration
```bash
cd /var/www/ark/hesabixAPI
alembic upgrade head
sudo systemctl restart hesabix-api
```

### گام 2: تست در مرورگر
1. وارد سیستم شوید
2. به منوی "پروژه‌ها" بروید
3. یک پروژه جدید ایجاد کنید
4. فاکتور ثبت کنید و پروژه را انتخاب کنید
5. در گزارش سود و زیان، پروژه را فیلتر کنید

---

## 📚 مستندات کامل

| فایل | موضوع | زمان خواندن |
|------|-------|-------------|
| [PROJECTS_QUICK_REFERENCE.md](PROJECTS_QUICK_REFERENCE.md) | کپی-پیست کدها | 2 دقیقه |
| [PROJECTS_INTEGRATION_GUIDE.md](PROJECTS_INTEGRATION_GUIDE.md) | راهنمای یکپارچه‌سازی | 10 دقیقه |
| [PROJECTS_REPORTS_DETAILED_SCENARIO.md](PROJECTS_REPORTS_DETAILED_SCENARIO.md) | گزارشات تفصیلی | 15 دقیقه |
| [PROJECTS_FINAL_IMPLEMENTATION_REPORT.md](PROJECTS_FINAL_IMPLEMENTATION_REPORT.md) | گزارش نهایی | 5 دقیقه |

---

## ✅ چه چیزی آماده است؟

### Backend (100%)
- ✅ 7 API Endpoint برای پروژه‌ها
- ✅ یکپارچگی با فاکتور، دریافت/پرداخت، درآمد/هزینه
- ✅ فیلتر پروژه در 3 گزارش اصلی

### Frontend (85%)
- ✅ صفحه لیست پروژه‌ها
- ✅ کمبوباکس انتخاب پروژه
- ✅ فیلتر در لیست فاکتورها  
- ✅ فیلتر در گزارشات
- ⏳ فرم افزودن/ویرایش پروژه (ساده)

---

## 🚀 API Endpoints

```
POST   /api/v1/businesses/{id}/projects           # ایجاد
GET    /api/v1/businesses/{id}/projects/active    # لیست فعال
GET    /api/v1/projects/{id}                      # جزئیات
```

### مثال:
```bash
curl -X GET "http://localhost:8000/api/v1/businesses/1/projects/active" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## 💡 نکات مهم

1. **اختیاری**: پروژه در همه جا اختیاری است
2. **فیلتر**: انتخاب نکردن = همه پروژه‌ها
3. **کد یکتا**: هر کسب‌وکار کدهای جداگانه دارد
4. **آمار**: آمار Real-time برای هر پروژه

---

## 🎯 موارد استفاده

- پروژه‌های ساختمانی
- قراردادهای بلندمدت
- تولید محصولات خاص
- خدمات مشاوره
- مراکز هزینه

---

## 📞 کمک نیاز دارید؟

- 📖 مستندات: فایل‌های بالا
- 🐛 باگ: بررسی لاگ‌های سرور
- ❓ سوال: تماس با تیم فنی

---

**آخرین به‌روزرسانی**: دسامبر 2025  
**وضعیت**: ✅ Production Ready

