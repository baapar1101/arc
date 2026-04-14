# سیستم مدیریت دسترسی‌ها

این سیستم برای مدیریت دسترسی‌های کاربران در سطح کسب و کار طراحی شده است.

## ویژگی‌ها

- **دسترسی‌های جزئی**: پشتیبانی از دسترسی‌های بسیار جزئی برای هر بخش
- **مدیریت خودکار**: فیلتر کردن منو و دکمه‌ها بر اساس دسترسی‌ها
- **کامپوننت‌های آماده**: ویجت‌های آماده برای بررسی دسترسی‌ها
- **امنیت کامل**: بررسی دسترسی‌ها در هر سطح

## دسترسی‌های موجود

### اشخاص (People)
- `people`: add, view, edit, delete
- `people_receipts`: add, view, edit, delete, draft
- `people_payments`: add, view, edit, delete, draft

### کالا و خدمات (Products & Services)
- `products`: add, view, edit, delete
- `price_lists`: add, view, edit, delete
- `categories`: add, view, edit, delete
- `product_attributes`: add, view, edit, delete

### بانکداری (Banking)
- `bank_accounts`: add, view, edit, delete
- `cash`: add, view, edit, delete
- `petty_cash`: add, view, edit, delete
- `checks`: add, view, edit, delete, collect, transfer, return
- `wallet`: view, charge
- `transfers`: add, view, edit, delete, draft

### فاکتورها و هزینه‌ها (Invoices & Expenses)
- `invoices`: add, view, edit, delete, draft
- `expenses_income`: add, view, edit, delete, draft

### حسابداری (Accounting)
- `accounting_documents`: add, view, edit, delete, draft
- `chart_of_accounts`: add, view, edit, delete
- `opening_balance`: view, edit

### انبارداری (Warehouse)
- `warehouses`: add, view, edit, delete
- `warehouse_transfers`: add, view, edit, delete, draft

### تنظیمات (Settings)
- `settings`: business, print, history, users
- `storage`: view, delete
- `sms`: history, templates
- `marketplace`: view, buy, invoices

## نحوه استفاده

### 1. بررسی دسترسی در AuthStore

```dart
final authStore = Provider.of<AuthStore>(context);

// بررسی دسترسی کلی
if (authStore.canReadSection('people')) {
  // نمایش لیست اشخاص
}

// بررسی دسترسی خاص
if (authStore.hasBusinessPermission('people', 'add')) {
  // نمایش دکمه اضافه کردن
}

// بررسی دسترسی‌های خاص
if (authStore.canCollectChecks()) {
  // نمایش دکمه وصول چک
}
```

### 2. استفاده از کامپوننت‌های آماده

#### PermissionButton
```dart
PermissionButton(
  section: 'people',
  action: 'add',
  authStore: authStore,
  child: IconButton(
    onPressed: () => _addPerson(),
    icon: const Icon(Icons.add),
    tooltip: 'اضافه کردن شخص',
  ),
)
```

#### PermissionWidget
```dart
PermissionWidget(
  section: 'settings',
  action: 'view',
  authStore: authStore,
  child: Card(
    child: ListTile(
      title: Text('تنظیمات'),
      onTap: () => _openSettings(),
    ),
  ),
)
```

#### AccessDeniedPage
```dart
if (!authStore.canReadSection('people')) {
  return AccessDeniedPage(
    message: 'شما دسترسی لازم برای مشاهده لیست اشخاص را ندارید',
  );
}
```


### 3. فیلتر کردن منو

منوی کسب و کار به صورت خودکار بر اساس دسترسی‌های کاربر فیلتر می‌شود:

```dart
// در BusinessShell
final menuItems = _getFilteredMenuItems(allMenuItems);
```

### 4. API Endpoint

```dart
// دریافت اطلاعات کسب و کار و دسترسی‌ها
final businessData = await businessService.getBusinessWithPermissions(businessId);
await authStore.setCurrentBusiness(businessData);
```

## مثال کامل

```dart
class PersonsPage extends StatelessWidget {
  final int businessId;
  final AuthStore authStore;

  const PersonsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  Widget build(BuildContext context) {
    // بررسی دسترسی خواندن
    if (!authStore.canReadSection('people')) {
      return AccessDeniedPage(
        message: 'شما دسترسی لازم برای مشاهده لیست اشخاص را ندارید',
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('لیست اشخاص'),
        actions: [
          // دکمه اضافه کردن فقط در صورت داشتن دسترسی
          PermissionButton(
            section: 'people',
            action: 'add',
            authStore: authStore,
            child: IconButton(
              onPressed: () => _addPerson(),
              icon: const Icon(Icons.add),
              tooltip: 'اضافه کردن شخص',
            ),
          ),
        ],
      ),
      body: PersonsList(),
    );
  }
}
```

## نکات مهم

1. **امنیت**: همیشه دسترسی‌ها را در سمت سرور نیز بررسی کنید
2. **عملکرد**: دسترسی‌ها در AuthStore کش می‌شوند
3. **به‌روزرسانی**: دسترسی‌ها هنگام تغییر کسب و کار به‌روزرسانی می‌شوند
4. **مالک کسب و کار**: مالک کسب و کار تمام دسترسی‌ها را دارد
