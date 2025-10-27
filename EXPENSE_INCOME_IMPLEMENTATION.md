# پیاده‌سازی بخش لیست هزینه و درآمد

## خلاصه پیاده‌سازی

این پیاده‌سازی شامل بخش کاملی برای مدیریت اسناد هزینه و درآمد است که بر اساس الگوی موجود در بخش دریافت و پرداخت طراحی شده است.

## فایل‌های ایجاد شده

### Frontend (Flutter)

#### مدل‌ها
- `lib/models/expense_income_document.dart` - مدل اصلی سند هزینه/درآمد
- `lib/models/account_model.dart` - مدل حساب

#### سرویس‌ها
- `lib/services/expense_income_list_service.dart` - سرویس لیست و عملیات گروهی
- `lib/services/expense_income_service.dart` - سرویس CRUD

#### صفحات
- `lib/pages/business/expense_income_list_page.dart` - صفحه اصلی لیست
- `lib/pages/test/expense_income_test_page.dart` - صفحه تست

#### ویجت‌ها
- `lib/widgets/expense_income/expense_income_form_dialog.dart` - دیالوگ ایجاد/ویرایش
- `lib/widgets/expense_income/expense_income_details_dialog.dart` - دیالوگ مشاهده جزئیات
- `lib/widgets/invoice/account_combobox_widget.dart` - ویجت انتخاب حساب

### Backend (Python)

#### API Endpoints
- `hesabixAPI/adapters/api/v1/expense_income.py` - تمام endpoint های مورد نیاز

#### سرویس‌ها
- `hesabixAPI/app/services/expense_income_service.py` - منطق کسب و کار

## ویژگی‌های پیاده‌سازی شده

### Frontend
- ✅ لیست اسناد با جدول پیشرفته
- ✅ فیلتر بر اساس نوع سند (هزینه/درآمد)
- ✅ فیلتر تاریخ (از/تا)
- ✅ جستجو و صفحه‌بندی
- ✅ انتخاب چندگانه و حذف گروهی
- ✅ خروجی Excel و PDF
- ✅ دیالوگ ایجاد سند جدید
- ✅ دیالوگ ویرایش سند موجود
- ✅ دیالوگ مشاهده جزئیات
- ✅ اعتبارسنجی تعادل حساب‌ها

### Backend
- ✅ API لیست اسناد با فیلتر و صفحه‌بندی
- ✅ API ایجاد سند جدید
- ✅ API ویرایش سند موجود
- ✅ API حذف سند (تکی و گروهی)
- ✅ API مشاهده جزئیات سند
- ✅ API خروجی Excel
- ✅ API خروجی PDF
- ✅ اعتبارسنجی و مدیریت خطا

## ساختار داده

### سند هزینه/درآمد
```json
{
  "id": 1,
  "code": "EI-20250115-12345",
  "document_type": "expense",
  "document_type_name": "هزینه",
  "document_date": "2025-01-15",
  "currency_id": 1,
  "total_amount": 1000000,
  "description": "توضیحات سند",
  "item_lines": [
    {
      "account_id": 123,
      "account_name": "هزینه اداری",
      "amount": 1000000,
      "description": "توضیحات خط"
    }
  ],
  "counterparty_lines": [
    {
      "transaction_type": "bank",
      "amount": 1000000,
      "transaction_date": "2025-01-15T10:00:00",
      "bank_account_id": 456,
      "bank_account_name": "بانک ملی"
    }
  ]
}
```

## نحوه استفاده

### اضافه کردن به منوی اصلی
```dart
// در فایل منوی اصلی
ListTile(
  leading: const Icon(Icons.trending_up),
  title: const Text('هزینه و درآمد'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExpenseIncomeListPage(
          businessId: businessId,
          calendarController: calendarController,
          authStore: authStore,
          apiClient: apiClient,
        ),
      ),
    );
  },
)
```

### تست عملکرد
```dart
// استفاده از صفحه تست
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const ExpenseIncomeTestPage(),
  ),
)
```

## نکات مهم

1. **تعادل حساب‌ها**: سیستم تضمین می‌کند که مجموع حساب‌های هزینه/درآمد با مجموع طرف‌حساب‌ها برابر باشد.

2. **انواع طرف‌حساب**: پشتیبانی از بانک، صندوق، تنخواهگردان، چک و شخص.

3. **کد سند**: فرمت `EI-YYYYMMDD-XXXXX` برای اسناد هزینه/درآمد.

4. **امنیت**: تمام endpoint ها نیاز به احراز هویت و مجوز مناسب دارند.

5. **چندزبانه**: پشتیبانی از تقویم شمسی و میلادی.

## مراحل بعدی

1. **تست کامل**: تست تمام سناریوهای ممکن
2. **بهینه‌سازی**: بهبود عملکرد و UX
3. **مستندسازی**: تکمیل مستندات API
4. **گزارش‌گیری**: اضافه کردن گزارش‌های پیشرفته
5. **یکپارچه‌سازی**: اتصال به سایر بخش‌های سیستم

## مشکلات احتمالی

1. **وابستگی‌ها**: ممکن است نیاز به نصب پکیج‌های اضافی باشد
2. **API**: باید مطمئن شوید که backend در حال اجرا است
3. **دسترسی**: بررسی مجوزهای کاربر برای دسترسی به بخش

## پشتیبانی

برای گزارش مشکلات یا درخواست ویژگی‌های جدید، لطفاً با تیم توسعه تماس بگیرید.
