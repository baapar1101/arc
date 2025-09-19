# DataTableWidget

یک ویجت جدول قابل استفاده مجدد و قدرتمند برای Flutter که قابلیت‌های پیشرفته جست‌وجو، فیلتر، مرتب‌سازی و صفحه‌بندی را ارائه می‌دهد.

## ویژگی‌ها

### 🔍 جست‌وجو و فیلتر
- **جست‌وجوی کلی**: جست‌وجو در چندین فیلد به صورت همزمان
- **جست‌وجوی ستونی**: جست‌وجو در ستون‌های خاص با انواع مختلف
- **فیلتر بازه زمانی**: فیلتر بر اساس تاریخ
- **فیلترهای فعال**: نمایش و مدیریت فیلترهای اعمال شده

### 📊 انواع ستون‌ها
- **TextColumn**: ستون متنی با قابلیت فرمت‌بندی
- **NumberColumn**: ستون عددی با فرمت‌بندی و پیشوند/پسوند
- **DateColumn**: ستون تاریخ با فرمت‌بندی Jalali/Gregorian
- **ActionColumn**: ستون عملیات با دکمه‌های قابل تنظیم
- **CustomColumn**: ستون سفارشی با builder مخصوص

### 🎨 سفارشی‌سازی
- **تم‌ها**: پشتیبانی کامل از تم‌های Material Design
- **رنگ‌بندی**: قابلیت تنظیم رنگ‌های مختلف
- **فونت‌ها**: تنظیم فونت و اندازه متن
- **حاشیه‌ها**: تنظیم padding و margin

### 📱 پاسخگو
- **اسکرول افقی**: در صورت کمبود فضای افقی
- **صفحه‌بندی**: مدیریت صفحات با گزینه‌های مختلف
- **حالت‌های مختلف**: loading، error، empty state

## نصب و استفاده

### 1. Import کردن
```dart
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
```

### 2. استفاده ساده
```dart
DataTableWidget<Map<String, dynamic>>(
  config: DataTableConfig<Map<String, dynamic>>(
    title: 'لیست کاربران',
    endpoint: '/api/v1/users/list',
    columns: [
      TextColumn('name', 'نام'),
      TextColumn('email', 'ایمیل'),
      DateColumn('created_at', 'تاریخ عضویت'),
    ],
    searchFields: ['name', 'email'],
    filterFields: ['name', 'email', 'created_at'],
  ),
  fromJson: (json) => json,
)
```

### 3. استفاده پیشرفته
```dart
DataTableWidget<Map<String, dynamic>>(
  config: DataTableConfig<Map<String, dynamic>>(
    title: 'لیست فاکتورها',
    subtitle: 'مدیریت فاکتورهای فروش',
    endpoint: '/api/v1/invoices/list',
    columns: [
      TextColumn(
        'invoice_number',
        'شماره فاکتور',
        sortable: true,
        searchable: true,
        width: ColumnWidth.medium,
      ),
      NumberColumn(
        'total_amount',
        'مبلغ کل',
        prefix: 'ریال ',
        decimalPlaces: 0,
        width: ColumnWidth.medium,
      ),
      DateColumn(
        'created_at',
        'تاریخ فاکتور',
        showTime: false,
        width: ColumnWidth.medium,
      ),
      ActionColumn(
        'actions',
        'عملیات',
        actions: [
          DataTableAction(
            icon: Icons.edit,
            label: 'ویرایش',
            onTap: (item) => _editItem(item),
          ),
          DataTableAction(
            icon: Icons.delete,
            label: 'حذف',
            onTap: (item) => _deleteItem(item),
            isDestructive: true,
          ),
        ],
      ),
    ],
    searchFields: ['invoice_number', 'customer_name'],
    filterFields: ['invoice_number', 'customer_name', 'created_at'],
    dateRangeField: 'created_at',
    onRowTap: (item) => _showDetails(item),
    showSearch: true,
    showFilters: true,
    showColumnSearch: true,
    showPagination: true,
    enableSorting: true,
    enableGlobalSearch: true,
    enableDateRangeFilter: true,
    defaultPageSize: 20,
    pageSizeOptions: const [10, 20, 50, 100],
    showRefreshButton: true,
    showClearFiltersButton: true,
    emptyStateMessage: 'هیچ فاکتوری یافت نشد',
    loadingMessage: 'در حال بارگذاری...',
    errorMessage: 'خطا در بارگذاری',
    enableHorizontalScroll: true,
    minTableWidth: 800,
    showBorder: true,
    borderRadius: BorderRadius.circular(8),
    padding: const EdgeInsets.all(16),
  ),
  fromJson: (json) => json,
  calendarController: calendarController,
)
```

## پیکربندی

### DataTableConfig
کلاس اصلی پیکربندی که شامل تمام تنظیمات جدول است:

```dart
DataTableConfig<T>(
  // الزامی
  endpoint: String,                    // آدرس API
  columns: List<DataTableColumn>,      // تعریف ستون‌ها
  
  // اختیاری
  title: String?,                      // عنوان جدول
  subtitle: String?,                   // زیرعنوان
  searchFields: List<String>,          // فیلدهای جست‌وجوی کلی
  filterFields: List<String>,          // فیلدهای قابل فیلتر
  dateRangeField: String?,             // فیلد فیلتر بازه زمانی
  
  // UI
  showSearch: bool,                    // نمایش جست‌وجو
  showFilters: bool,                   // نمایش فیلترها
  showColumnSearch: bool,              // نمایش جست‌وجوی ستونی
  showPagination: bool,                // نمایش صفحه‌بندی
  showActiveFilters: bool,             // نمایش فیلترهای فعال
  
  // عملکرد
  enableSorting: bool,                 // فعال‌سازی مرتب‌سازی
  enableGlobalSearch: bool,            // فعال‌سازی جست‌وجوی کلی
  enableDateRangeFilter: bool,         // فعال‌سازی فیلتر بازه زمانی
  
  // صفحه‌بندی
  defaultPageSize: int,                // اندازه پیش‌فرض صفحه
  pageSizeOptions: List<int>,          // گزینه‌های اندازه صفحه
  
  // رویدادها
  onRowTap: Function(T)?,              // کلیک روی سطر
  onRowDoubleTap: Function(T)?,        // دابل کلیک روی سطر
  
  // پیام‌ها
  emptyStateMessage: String?,          // پیام حالت خالی
  loadingMessage: String?,             // پیام بارگذاری
  errorMessage: String?,               // پیام خطا
  
  // ظاهر
  enableHorizontalScroll: bool,        // اسکرول افقی
  minTableWidth: double?,              // حداقل عرض جدول
  showBorder: bool,                    // نمایش حاشیه
  borderRadius: BorderRadius?,         // شعاع حاشیه
  padding: EdgeInsets?,                // فاصله داخلی
  margin: EdgeInsets?,                 // فاصله خارجی
  backgroundColor: Color?,             // رنگ پس‌زمینه
  headerBackgroundColor: Color?,       // رنگ پس‌زمینه هدر
  rowBackgroundColor: Color?,          // رنگ پس‌زمینه سطرها
  alternateRowBackgroundColor: Color?, // رنگ پس‌زمینه سطرهای متناوب
  borderColor: Color?,                 // رنگ حاشیه
  borderWidth: double?,                // ضخامت حاشیه
  boxShadow: List<BoxShadow>?,         // سایه
)
```

### انواع ستون‌ها

#### TextColumn
```dart
TextColumn(
  'field_name',           // نام فیلد
  'نمایش نام',            // برچسب
  sortable: true,         // قابل مرتب‌سازی
  searchable: true,       // قابل جست‌وجو
  width: ColumnWidth.medium, // عرض ستون
  formatter: (item) => item['field_name']?.toString() ?? '', // فرمت‌کننده
  textAlign: TextAlign.start, // تراز متن
  maxLines: 1,            // حداکثر خطوط
  overflow: true,         // نمایش ... در صورت اضافه
)
```

#### NumberColumn
```dart
NumberColumn(
  'amount',
  'مبلغ',
  prefix: 'ریال ',
  suffix: '',
  decimalPlaces: 2,
  textAlign: TextAlign.end,
)
```

#### DateColumn
```dart
DateColumn(
  'created_at',
  'تاریخ ایجاد',
  showTime: false,
  dateFormat: 'yyyy/MM/dd',
  textAlign: TextAlign.center,
)
```

#### ActionColumn
```dart
ActionColumn(
  'actions',
  'عملیات',
  actions: [
    DataTableAction(
      icon: Icons.edit,
      label: 'ویرایش',
      onTap: (item) => _editItem(item),
    ),
    DataTableAction(
      icon: Icons.delete,
      label: 'حذف',
      onTap: (item) => _deleteItem(item),
      isDestructive: true,
    ),
  ],
)
```

## API Integration

### QueryInfo Structure
ویجت از ساختار QueryInfo برای ارتباط با API استفاده می‌کند:

```dart
class QueryInfo {
  String? search;                    // عبارت جست‌وجو
  List<String>? searchFields;        // فیلدهای جست‌وجو
  List<FilterItem>? filters;         // فیلترها
  String? sortBy;                    // فیلد مرتب‌سازی
  bool sortDesc;                     // ترتیب نزولی
  int take;                          // تعداد رکورد
  int skip;                          // تعداد رد شده
}
```

### FilterItem Structure
```dart
class FilterItem {
  String property;                   // نام فیلد
  String operator;                   // عملگر (>=, <, *, =, etc.)
  dynamic value;                     // مقدار
}
```

### Response Structure
API باید پاسخ را در این فرمت برگرداند:

```json
{
  "data": {
    "items": [...],
    "total": 100,
    "page": 1,
    "limit": 20,
    "total_pages": 5
  }
}
```

## مثال‌های استفاده

### 1. لیست کاربران
```dart
ReferralDataTableExample(calendarController: calendarController)
```

### 2. لیست فاکتورها
```dart
InvoiceDataTableExample(calendarController: calendarController)
```

### 3. لیست سفارشی
```dart
DataTableWidget<CustomModel>(
  config: DataTableConfig<CustomModel>(
    // پیکربندی...
  ),
  fromJson: (json) => CustomModel.fromJson(json),
  calendarController: calendarController,
)
```

## نکات مهم

1. **CalendarController**: برای فیلترهای تاریخ نیاز است
2. **fromJson**: تابع تبدیل JSON به مدل مورد نظر
3. **API Endpoint**: باید QueryInfo را پشتیبانی کند
4. **Localization**: نیاز به کلیدهای ترجمه مناسب
5. **Theme**: از تم فعلی برنامه استفاده می‌کند

## عیب‌یابی

### مشکلات رایج
1. **خطای API**: بررسی endpoint و ساختار QueryInfo
2. **خطای ترجمه**: بررسی کلیدهای localization
3. **خطای مدل**: بررسی تابع fromJson
4. **خطای UI**: بررسی تنظیمات DataTableConfig

### لاگ‌ها
ویجت لاگ‌های مفیدی برای عیب‌یابی ارائه می‌دهد که در console قابل مشاهده است.
