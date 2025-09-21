# Enhanced Filters System

سیستم فیلتر پیشرفته برای DataTableWidget که امکان استفاده از انواع مختلف فیلتر را فراهم می‌کند.

## ویژگی‌ها

### 🔍 انواع فیلتر

1. **فیلتر متنی** (پیش‌فرض): جستجوی متنی با انواع مختلف
2. **فیلتر بازه زمانی**: انتخاب بازه تاریخ برای ستون‌های تاریخ
3. **فیلتر چندتایی**: انتخاب چندین گزینه با چک باکس

### 🎯 نحوه استفاده

#### 1. ستون تاریخ با فیلتر بازه زمانی

```dart
DateColumn(
  'created_at',
  'تاریخ ایجاد',
  filterType: ColumnFilterType.dateRange,
)
```

#### 2. ستون اولویت با فیلتر چندتایی

```dart
TextColumn(
  'priority',
  'اولویت',
  filterType: ColumnFilterType.multiSelect,
  filterOptions: [
    FilterOption(
      value: 'normal',
      label: 'عادی',
      icon: Icons.circle,
      color: Colors.green,
    ),
    FilterOption(
      value: 'special',
      label: 'ویژه',
      icon: Icons.star,
      color: Colors.orange,
    ),
    FilterOption(
      value: 'urgent',
      label: 'فوری',
      icon: Icons.priority_high,
      color: Colors.red,
    ),
  ],
)
```

#### 3. ستون متنی با فیلتر پیش‌فرض

```dart
TextColumn(
  'name',
  'نام',
  // filterType پیش‌فرض text است
)
```

## ساختار کلاس‌ها

### ColumnFilterType

```dart
enum ColumnFilterType {
  text,           // فیلتر متنی (پیش‌فرض)
  dateRange,      // فیلتر بازه زمانی
  multiSelect,    // فیلتر چندتایی
}
```

### FilterOption

```dart
class FilterOption {
  final String value;        // مقدار برای API
  final String label;        // نمایش در UI
  final String? description; // توضیحات اضافی
  final IconData? icon;      // آیکون
  final Color? color;        // رنگ آیکون/متن
}
```

## رفتار دکمه جستجو

- **ستون تاریخ** → DateRangePicker (از/تا تاریخ)
- **ستون با filterOptions** → CheckboxList با آیتم‌های تعریف شده
- **ستون‌های دیگر** → TextField (فعلی)

## نمایش فیلترهای فعال

- **تاریخ**: "تاریخ: 1403/01/01 - 1403/01/31"
- ☑️ **چندتایی**: "اولویت: عادی، ویژه" (با آیکون‌های رنگی)
- 🔍 **متنی**: "نام: احمد (شامل)"

## ساختار فیلتر در API

### فیلتر متنی
```json
{
  "property": "name",
  "operator": "*",
  "value": "احمد"
}
```

### فیلتر چندتایی
```json
{
  "property": "priority",
  "operator": "in",
  "value": ["normal", "special"]
}
```

### فیلتر بازه زمانی
```json
[
  {
    "property": "created_at",
    "operator": ">=",
    "value": "2024-01-01T00:00:00.000Z"
  },
  {
    "property": "created_at",
    "operator": "<",
    "value": "2024-01-31T00:00:00.000Z"
  }
]
```

## مثال کامل

```dart
DataTableWidget<Map<String, dynamic>>(
  config: DataTableConfig<Map<String, dynamic>>(
    title: 'Enhanced Filters Demo',
    endpoint: '/api/v1/demo/list',
    columns: [
      // ستون تاریخ با فیلتر بازه زمانی
      DateColumn(
        'created_at',
        'تاریخ ایجاد',
        filterType: ColumnFilterType.dateRange,
      ),
      
      // ستون اولویت با فیلتر چندتایی
      TextColumn(
        'priority',
        'اولویت',
        filterType: ColumnFilterType.multiSelect,
        filterOptions: [
          FilterOption(value: 'normal', label: 'عادی'),
          FilterOption(value: 'special', label: 'ویژه'),
          FilterOption(value: 'urgent', label: 'فوری'),
        ],
      ),
      
      // ستون نام با فیلتر متنی (پیش‌فرض)
      TextColumn('name', 'نام'),
    ],
    showColumnSearch: true,
    showActiveFilters: true,
  ),
  fromJson: (json) => json,
  calendarController: calendarController,
)
```

## مزایا

- ✅ **سازگاری کامل**: با سیستم فعلی کاملاً سازگار
- ✅ **انعطاف‌پذیری**: توسعه‌دهنده کنترل کامل دارد
- ✅ **قابلیت استفاده**: UI مناسب برای هر نوع فیلتر
- ✅ **قابلیت توسعه**: آسان برای اضافه کردن انواع جدید
- ✅ **عملکرد**: فیلترها در سمت سرور پردازش می‌شوند

## نکات مهم

1. **فیلتر پیش‌فرض**: اگر `filterType` تعیین نشود، فیلتر متنی استفاده می‌شود
2. **فیلتر چندتایی**: نیاز به `filterOptions` دارد
3. **فیلتر بازه زمانی**: فقط برای ستون‌های تاریخ مناسب است
4. **API**: سرور باید انواع مختلف فیلتر را پشتیبانی کند
