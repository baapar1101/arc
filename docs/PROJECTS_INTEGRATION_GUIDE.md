# 📘 راهنمای یکپارچه‌سازی قابلیت پروژه

## ✅ وضعیت پیاده‌سازی

### Backend (100% تکمیل)
- ✅ مدل و Migration
- ✅ Repository و Service
- ✅ API Endpoints (7 endpoint)
- ✅ یکپارچه‌سازی با سرویس‌های موجود

### Frontend (80% تکمیل)  
- ✅ Models و Services
- ✅ Widget انتخاب پروژه
- ✅ صفحه لیست پروژه‌ها
- ⏳ یکپارچه‌سازی فیلترها (در حال انجام)
- ⏳ یکپارچه‌سازی فرم‌ها (در حال انجام)

---

## 🚀 نحوه یکپارچه‌سازی

### 1️⃣ افزودن فیلتر پروژه به صفحات لیست

#### مرحله 1: افزودن state
```dart
class _YourPageState extends State<YourPage> {
  // ... سایر stateها
  int? _selectedProjectId; // فیلتر پروژه
}
```

#### مرحله 2: import کردن widget
```dart
import 'package:hesabix_ui/widgets/project/project_filter_helper.dart';
```

#### مرحله 3: افزودن widget در بخش فیلترها
```dart
Widget _buildFilters() {
  return Column(
    children: [
      // ... سایر فیلترها
      
      ProjectFilterWidget(
        businessId: widget.businessId,
        apiClient: widget.apiClient,
        selectedProjectId: _selectedProjectId,
        onChanged: (projectId) {
          setState(() {
            _selectedProjectId = projectId;
          });
          _refreshData();
        },
      ),
    ],
  );
}
```

#### مرحله 4: افزودن به additionalFilters
```dart
DataTableConfig _buildTableConfig() {
  final additionalFilters = <dynamic>[];
  
  // ... سایر فیلترها
  
  // فیلتر پروژه
  if (_selectedProjectId != null) {
    additionalFilters.add({
      'property': 'project_id',
      'operator': '=',
      'value': _selectedProjectId,
    });
  }
  
  return DataTableConfig(
    // ...
    additionalFilters: additionalFilters,
  );
}
```

---

### 2️⃣ افزودن انتخاب پروژه به فرم‌های ثبت سند

#### مرحله 1: افزودن state
```dart
class _YourFormState extends State<YourForm> {
  // ... سایر stateها
  int? _selectedProjectId; // پروژه انتخابی
}
```

#### مرحله 2: import کردن widget
```dart
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';
```

#### مرحله 3: افزودن widget در فرم
```dart
Widget build(BuildContext context) {
  return Form(
    child: Column(
      children: [
        // ... سایر فیلدها
        
        // انتخاب پروژه (اختیاری)
        ProjectSelectorWidget(
          businessId: widget.businessId,
          apiClient: widget.apiClient,
          selectedProjectId: _selectedProjectId,
          onChanged: (projectId) {
            setState(() {
              _selectedProjectId = projectId;
            });
          },
          allowNull: true,
          labelText: 'پروژه (اختیاری)',
        ),
        
        // ... ادامه فرم
      ],
    ),
  );
}
```

#### مرحله 4: افزودن به payload
```dart
Future<void> _submitForm() async {
  final payload = {
    // ... سایر فیلدها
    
    'project_id': _selectedProjectId, // اضافه کردن پروژه
    
    // ... ادامه payload
  };
  
  // ارسال به API
  await yourService.create(payload);
}
```

---

## 📄 صفحات نیازمند به‌روزرسانی

### لیست اسناد (فیلتر):
- [ ] `invoices_list_page.dart` - لیست فاکتورها
- [ ] `receipts_payments_list_page.dart` - لیست دریافت/پرداخت
- [ ] `expense_income_list_page.dart` - لیست درآمد/هزینه
- [ ] `documents_page.dart` - لیست کلی اسناد

### فرم‌های ثبت سند (selector):
- [ ] `new_invoice_page.dart` - ثبت فاکتور
- [ ] فرم‌های دریافت/پرداخت
- [ ] فرم‌های درآمد/هزینه

---

## 🔧 اجرای Migration

برای فعال‌سازی در دیتابیس:

```bash
cd hesabixAPI
alembic upgrade head
```

---

## 🧪 تست

### تست Backend:
```bash
# تست API endpoints
curl -X GET "http://localhost:8000/api/v1/businesses/1/projects" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### تست Frontend:
1. ورود به سیستم
2. رفتن به صفحه "پروژه‌ها"
3. افزودن پروژه جدید
4. ثبت فاکتور با پروژه
5. فیلتر فاکتورها بر اساس پروژه

---

## 📚 API Endpoints

| Method | Endpoint | توضیحات |
|--------|----------|---------|
| POST | `/api/v1/businesses/{id}/projects` | ایجاد پروژه |
| GET | `/api/v1/businesses/{id}/projects` | لیست پروژه‌ها |
| GET | `/api/v1/businesses/{id}/projects/active` | پروژه‌های فعال (کمبوباکس) |
| GET | `/api/v1/projects/{id}` | جزئیات پروژه |
| PUT | `/api/v1/projects/{id}` | ویرایش پروژه |
| DELETE | `/api/v1/projects/{id}` | حذف پروژه |
| GET | `/api/v1/projects/{id}/documents` | اسناد پروژه |

---

## 💡 نکات مهم

1. **اختیاری بودن**: پروژه در همه جا اختیاری است و اجباری نیست
2. **فیلتر خودکار**: فیلتر پروژه به صورت خودکار با سایر فیلترها ترکیب می‌شود
3. **اعتبارسنجی**: پروژه باید به همان کسب‌وکار تعلق داشته باشد
4. **وضعیت**: فقط پروژه‌های فعال در کمبوباکس نمایش داده می‌شوند
5. **آمار**: آمار مالی هر پروژه قابل مشاهده است

---

## 🐛 عیب‌یابی

### خطای "PROJECT_NOT_FOUND":
- بررسی کنید پروژه به همان کسب‌وکار تعلق داشته باشد
- بررسی کنید پروژه فعال (is_active=true) باشد

### خطای "CURRENCY_NOT_FOUND":
- ارز پروژه باید معتبر باشد
- می‌توانید بدون ارز هم پروژه ایجاد کنید (null)

### فیلتر کار نمی‌کند:
- بررسی کنید `additionalFilters` به `DataTableConfig` اضافه شده باشد
- بررسی کنید `_refreshData()` بعد از تغییر فیلتر صدا زده شود

---

## 📞 پشتیبانی

در صورت بروز مشکل، موارد زیر را بررسی کنید:
1. Migration اجرا شده باشد
2. Import های لازم انجام شده باشد
3. Widget ها به درستی configure شده باشند
4. API Token معتبر باشد

---

✨ **پیاده‌سازی توسط AI Assistant - دسامبر 2025**

