# 🐛 گزارش مشکل UI دیزاینر ورک‌فلو

## 📊 خلاصه مشکل

در بخش دیزاینر ورک‌فلو، زمانی که کاربر می‌خواهد از خروجی یک نود قبلی در فیلدهای دیگر استفاده کند (مانند فیلد `message` در اکشن تلگرام)، **Reference Selector** تنها به کاربر اجازه می‌دهد کل نود را انتخاب کند (`$node_id`)، نه یک فیلد خاص (`$node_id.field_name`).

## 🔍 محل مشکل در کد

### فایل: `workflow_node_config_dialog.dart`

**خطوط مشکل‌دار: 857-859**

```dart
trailing: IconButton(
  icon: const Icon(Icons.arrow_forward),
  onPressed: () {
    // ساخت reference
    final reference = '\$${node.id}';  // ❌ مشکل اینجاست
    onSelected(reference);
  },
),
```

### توضیح مشکل:

1. **رفتار فعلی:**
   - زمانی که کاربر دکمه "انتخاب از نودهای قبلی" را می‌زند
   - دیالوگی باز می‌شود که لیست نودهای قبلی را نشان می‌دهد
   - کاربر یک نود را انتخاب می‌کند
   - کد فقط `$node_id` را برمی‌گرداند (کل نود)
   - این مقدار در فیلد ذخیره می‌شود

2. **نتیجه:**
   - برای فیلد `message`، مقدار `$6a6f62bf-1680-4a50-9735-a1acc293d0d0` ذخیره می‌شود
   - این reference به **کل object نود** اشاره می‌کند، نه به یک فیلد خاص
   - نود تریگر `invoice.created` یک object خالی `{}` برمی‌گرداند
   - در نتیجه، پیام ارسالی به تلگرام یک object خالی است

## ✅ راه‌حل پیشنهادی

Reference Selector باید به کاربر اجازه دهد که:
1. نود مورد نظر را انتخاب کند
2. فیلد خاص آن نود را انتخاب کند
3. در نهایت `$node_id.field_name` ذخیره شود

### پیاده‌سازی پیشنهادی:

```dart
// مرحله 1: انتخاب نود
// مرحله 2: نمایش فیلدهای موجود در نود (از config_schema یا trigger_data)
// مرحله 3: انتخاب فیلد خاص
// نتیجه: $node_id.field_name
```

### مثال:

برای نود تریگر "ایجاد فاکتور" که `invoice.created` است، فیلدهای موجود ممکن است شامل:
- `invoice_id`
- `invoice_code`
- `invoice_date`
- `total_amount`
- `customer_name`
- و غیره...

کاربر باید بتواند یکی از این فیلدها را انتخاب کند، مثلاً:
- `$6a6f62bf-1680-4a50-9735-a1acc293d0d0.invoice_code`
- `$6a6f62bf-1680-4a50-9735-a1acc293d0d0.customer_name`

## 🎯 راه‌حل موقت برای کاربر

تا زمانی که این مشکل در UI حل شود، کاربران می‌توانند:

1. **به صورت دستی reference را تایپ کنند:**
   ```
   $node_id.field_name
   ```

2. **یا متن ثابت استفاده کنند:**
   ```
   فاکتور جدیدی ایجاد شد!
   ```

3. **یا ترکیبی از هر دو:**
   ```
   فاکتور شماره $node_id.invoice_code با مبلغ $node_id.total_amount ایجاد شد.
   ```

## 📝 نکات اضافی برای پیاده‌سازی

### 1. دریافت فیلدهای موجود

باید از backend، لیست فیلدهای خروجی هر trigger/action را دریافت کنیم:

```json
{
  "trigger": "invoice.created",
  "output_schema": {
    "invoice_id": {"type": "integer", "description": "شناسه فاکتور"},
    "invoice_code": {"type": "string", "description": "کد فاکتور"},
    "total_amount": {"type": "number", "description": "مبلغ کل"},
    "customer_name": {"type": "string", "description": "نام مشتری"}
  }
}
```

### 2. UI پیشنهادی

**Dialog دو مرحله‌ای:**

**مرحله 1: انتخاب نود**
```
┌─────────────────────────────────┐
│ انتخاب از نودهای قبلی          │
├─────────────────────────────────┤
│ • ایجاد فاکتور (Trigger)       │
│ • محاسبه تخفیف (Action)         │
│ • بررسی موجودی (Condition)      │
└─────────────────────────────────┘
```

**مرحله 2: انتخاب فیلد**
```
┌─────────────────────────────────┐
│ انتخاب فیلد از "ایجاد فاکتور"  │
├─────────────────────────────────┤
│ • invoice_id (شناسه فاکتور)    │
│ • invoice_code (کد فاکتور)     │
│ • total_amount (مبلغ کل)       │
│ • customer_name (نام مشتری)    │
└─────────────────────────────────┘
```

### 3. کد پیشنهادی

```dart
// در ReferenceSelectorDialog

ListTile(
  leading: Icon(node.icon),
  title: Text(node.label),
  subtitle: Text('ID: ${node.id}'),
  onTap: () {
    // بستن این dialog و باز کردن dialog فیلد
    Navigator.of(context).pop();
    _showFieldSelector(context, node, onSelected);
  },
)

// Dialog جدید برای انتخاب فیلد
void _showFieldSelector(
  BuildContext context,
  WorkflowNodeModel node,
  Function(String) onSelected,
) {
  // دریافت لیست فیلدهای موجود از metadata
  final fields = _getNodeOutputFields(node);
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('انتخاب فیلد از "${node.label}"'),
      content: ListView.builder(
        itemCount: fields.length,
        itemBuilder: (context, index) {
          final field = fields[index];
          return ListTile(
            title: Text(field['name']),
            subtitle: Text(field['description']),
            onTap: () {
              final reference = '\$${node.id}.${field['key']}';
              onSelected(reference);
              Navigator.of(context).pop();
            },
          );
        },
      ),
    ),
  );
}
```

## 🚀 اولویت

این مشکل **اولویت بالا** دارد زیرا:
- ✅ باعث می‌شود ورک‌فلوها به درستی کار نکنند
- ✅ کاربران نمی‌توانند به راحتی از داده‌های نودهای قبلی استفاده کنند
- ✅ UX ضعیفی دارد و کاربر باید به صورت دستی reference بنویسد

## 📊 تست

بعد از حل مشکل، باید موارد زیر تست شوند:
1. انتخاب نود از لیست
2. نمایش فیلدهای موجود در نود
3. انتخاب فیلد و ذخیره reference صحیح
4. نمایش پیش‌نمایش reference در فیلد
5. اجرای ورک‌فلو با reference صحیح

---

**تاریخ گزارش:** 2025-12-04
**فایل مشکل‌دار:** `hesabixUI/hesabix_ui/lib/widgets/workflow/workflow_node_config_dialog.dart`
**خطوط مشکل‌دار:** 857-859



