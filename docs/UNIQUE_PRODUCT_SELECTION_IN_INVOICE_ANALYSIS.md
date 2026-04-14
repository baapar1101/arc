# بررسی امکان انتخاب کالاهای یونیک در فاکتور فروش و برگشت از خرید

## خلاصه بررسی

این گزارش نتیجه بررسی کامل امکان افزودن قابلیت انتخاب کالاهای یونیک (با ویژگی‌های مشخص) در زمان ایجاد یا ویرایش فاکتور فروش و برگشت از خرید را ارائه می‌دهد. هدف این است که حسابدار بتواند در زمان ثبت فاکتور، کالاهای یونیک خاصی را انتخاب کند و این اطلاعات در حواله خارج که از فاکتور ایجاد می‌شود به انباردار منتقل شود.

---

## 1. ساختار فعلی سیستم

### 1.1 مدل‌های دیتابیس مرتبط

#### Product (کالا)
- فیلد `inventory_mode`: می‌تواند `"bulk"` (فله‌ای) یا `"unique"` (یونیک) باشد
- فیلد `track_serial`: ردیابی سریال نامبر
- فیلد `track_barcode`: ردیابی بارکد

#### ProductInstance (کالای یونیک)
- هر واحد از کالای یونیک به صورت جداگانه ردیابی می‌شود
- شامل:
  - `serial_number`: شماره سریال یکتا
  - `barcode`: بارکد یکتا (اختیاری)
  - `custom_attributes`: ویژگی‌های کالا (JSON) مانند رنگ، سایز، مدل و ...
  - `warehouse_id`: انباری که کالا در آن قرار دارد
  - `status`: وضعیت (available, sold, warranty, defective)
  - `entry_date`: تاریخ ورود به انبار

#### InvoiceItemLine (خط فاکتور)
- شامل:
  - `document_id`: شناسه فاکتور
  - `product_id`: شناسه کالا
  - `quantity`: تعداد
  - `extra_info`: اطلاعات اضافی (JSON) - **این فیلد می‌تواند برای ذخیره اطلاعات instance ها استفاده شود**

#### WarehouseDocumentLine (خط حواله)
- شامل:
  - `instance_ids`: لیست ID کالاهای یونیک (JSON) - **این فیلد برای ذخیره instance های انتخاب شده استفاده می‌شود**

### 1.2 فرآیند فعلی ایجاد حواله از فاکتور

1. **ذخیره فاکتور**: در `InvoiceItemLine` فقط `product_id` و `quantity` ذخیره می‌شود
2. **ایجاد حواله**: از فاکتور با استفاده از تابع `create_from_invoice` در `warehouse_service.py`
3. **بارگذاری خطوط**: خطوط فاکتور از `InvoiceItemLine` با تابع `_load_invoice_lines` بارگذاری می‌شود
4. **انتقال به حواله**: اطلاعات خطوط به `WarehouseDocumentLine` منتقل می‌شود

---

## 2. قابلیت‌های موجود

### 2.1 انتخاب instance ها در حواله

**در حال حاضر:**
- در حواله دستی (Manual Warehouse Document) امکان انتخاب instance های کالای یونیک وجود دارد
- برای حواله **ورود**: از `instance_data` استفاده می‌شود (ایجاد instance جدید)
- برای حواله **خروج**: از `instance_ids` استفاده می‌شود (انتخاب instance موجود)

### 2.2 API موجود برای دریافت instance های در دسترس

**Endpoint:**
```
GET /api/v1/product-instances/business/{business_id}/product/{product_id}/available
```

این API لیست کالاهای یونیک در دسترس را بر اساس:
- `product_id`: شناسه کالا
- `warehouse_id`: شناسه انبار (اختیاری)
- `status`: فقط کالاهای با وضعیت "available"

برمی‌گرداند.

**ساختار پاسخ:**
```json
{
  "items": [
    {
      "id": 100,
      "serial_number": "SN-001",
      "barcode": "BC-001",
      "warehouse_id": 1,
      "warehouse_name": "انبار اصلی",
      "custom_attributes": {
        "رنگ": "آبی",
        "سایز": "XL",
        "مدل": "2024"
      },
      "entry_date": "2024-01-15"
    }
  ],
  "total": 50
}
```

**نکته مهم:** `custom_attributes` شامل مقادیر خام است و باید بر اساس `data_type` ویژگی‌های کالا فرمت شود. برای این کار باید:
- ویژگی‌های کالا (ProductAttribute) با `data_type` و `options` بارگذاری شوند
- هر مقدار در `custom_attributes` بر اساس `data_type` مربوطه فرمت شود

### 2.3 پردازش instance ها در حواله

**کد موجود در `warehouse_service.py`:**
- برای حواله خروج (`issue`, `production_out`): از `instance_ids` برای انتخاب instance های موجود استفاده می‌شود
- بررسی می‌شود که instance در دسترس باشد (`status == "available"`)
- instance به‌روزرسانی می‌شود (`status = "sold"`, `warehouse_id = None`)

### 2.4 ویژگی‌های کالا با نوع داده

**ساختار ProductAttribute:**
- `title`: عنوان ویژگی
- `data_type`: نوع داده (text, number, date, select, boolean)
- `options`: گزینه‌های select (فقط برای نوع select) - شامل لیست آیتم‌ها
- `description`: توضیحات

**نوع‌های داده پشتیبانی شده:**
1. **text**: متن ساده
2. **number**: عدد (int, float, Decimal)
3. **date**: تاریخ (فرمت ISO: YYYY-MM-DD)
4. **select**: انتخاب از لیست (مقدار value ذخیره می‌شود، label نمایش داده می‌شود)
5. **boolean**: بله/خیر (true/false)

**در custom_attributes:**
- مقادیر به صورت خام ذخیره می‌شوند
- برای نمایش باید بر اساس `data_type` فرمت شوند
- برای select: باید label را از options پیدا کرد

---

## 3. آنچه باید اضافه شود

### 3.1 در سطح فاکتور

#### الف) ذخیره اطلاعات instance ها در خط فاکتور

**موقعیت ذخیره:**
- در فیلد `extra_info` از `InvoiceItemLine` می‌توانیم کلید جدیدی اضافه کنیم
- پیشنهاد: `selected_instance_ids` - لیست ID های instance های انتخاب شده

**ساختار پیشنهادی:**
```json
{
  "selected_instance_ids": [1, 2, 3],
  "unit_price": 1000,
  "line_discount": 0,
  ...
}
```

#### ب) UI برای انتخاب instance ها

**در فرم ایجاد/ویرایش فاکتور:**
- برای هر خط فاکتور که کالای آن یونیک است (`inventory_mode == "unique"`)
- دکمه/لینک "انتخاب کالای یونیک" نمایش داده شود
- با کلیک، دیالوگی باز شود که:

**1. بارگذاری اطلاعات:**
  - دریافت لیست instance های در دسترس از API
  - دریافت ویژگی‌های کالا (ProductAttribute) با `data_type` و `options`
  - ایجاد map از `data_type` و `options` برای هر ویژگی

**2. نمایش لیست instance ها:**
  - نمایش سریال نامبر، بارکد، انبار
  - **فرمت و نمایش ویژگی‌ها بر اساس data_type:**
    - `text`: نمایش مستقیم
    - `number`: فرمت عددی با جداکننده (مثلاً 1,000)
    - `date`: فرمت تاریخ فارسی (مثلاً 1403/01/15)
    - `select`: پیدا کردن label از `options` و نمایش آن (نه value)
    - `boolean`: نمایش "بله"/"خیر" یا آیکون ✓/✗
  - نمایش ویژگی‌ها در ستون‌های جداگانه یا به صورت برچسب

**3. قابلیت‌های دیالوگ:**
  - امکان فیلتر بر اساس انبار
  - امکان جستجو در سریال نامبر و بارکد
  - **امکان فیلتر بر اساس ویژگی‌ها:**
    - برای text: جستجوی متنی
    - برای number: فیلتر بر اساس بازه (min-max)
    - برای date: فیلتر بر اساس بازه تاریخ
    - برای select: انتخاب از dropdown
    - برای boolean: انتخاب بله/خیر/همه
  - امکان انتخاب چند instance (چک‌باکس)
  - اعتبارسنجی: تعداد انتخاب شده = quantity

**4. نمایش اطلاعات:**
  - نمایش خلاصه‌ای از instance های انتخاب شده
  - نمایش ویژگی‌های فرمت شده هر instance

#### ج) اعتبارسنجی

- **تعداد instance های انتخاب شده باید دقیقاً برابر با `quantity` باشد**
  - اگر `quantity = 2` باشد، باید دقیقاً 2 instance انتخاب شود (نه کمتر، نه بیشتر)
  - این اعتبارسنجی هم در زمان ذخیره فاکتور و هم در زمان ایجاد حواله انجام می‌شود
- instance های انتخاب شده باید در دسترس باشند (`status == "available"`)
- instance های انتخاب شده باید در انبار مورد نظر باشند (اگر انبار مشخص شده)
- هر instance فقط یک بار می‌تواند انتخاب شود (بدون تکرار در لیست)

### 3.2 در سطح ایجاد حواله از فاکتور

#### الف) انتقال اطلاعات instance ها

**موقعیت پردازش:**
- در تابع `create_from_invoice` در `warehouse_service.py`
- در بخش پردازش خطوط، باید `selected_instance_ids` از `extra_info` خط فاکتور خوانده شود
- این instance_ids باید به `instance_ids` خط حواله منتقل شود

**کد پیشنهادی:**
```python
# در create_from_invoice
extra = ln.get("extra_info") or {}
selected_instance_ids = extra.get("selected_instance_ids")

if selected_instance_ids and isinstance(selected_instance_ids, list):
    # بررسی اینکه کالا یونیک است
    if product.inventory_mode == "unique":
        # بررسی تعداد - باید دقیقاً برابر quantity باشد
        instance_count = len(selected_instance_ids)
        required_count = int(qty)
        
        if instance_count != required_count:
            raise ApiError("INSTANCE_COUNT_MISMATCH", 
                f"تعداد instance های انتخاب شده ({instance_count}) باید دقیقاً برابر با تعداد کالا ({required_count}) باشد")
        
        # بررسی تکرار در لیست
        if len(selected_instance_ids) != len(set(selected_instance_ids)):
            raise ApiError("DUPLICATE_INSTANCE", 
                f"در لیست instance های انتخاب شده تکرار وجود دارد")
        
        # بررسی دسترس بودن همه instance ها
        for inst_id in selected_instance_ids:
            instance = db.query(ProductInstance).filter(
                and_(
                    ProductInstance.id == int(inst_id),
                    ProductInstance.business_id == business_id,
                    ProductInstance.product_id == int(pid),
                    ProductInstance.status == "available",
                )
            ).first()
            
            if not instance:
                raise ApiError("INSTANCE_NOT_AVAILABLE", 
                    f"کالای یونیک با ID {inst_id} یافت نشد یا در دسترس نیست")
        
        # استفاده از selected_instance_ids به عنوان instance_ids_from_line
        instance_ids_from_line = selected_instance_ids
```

#### ب) حفظ قابلیت موجود

- اگر `selected_instance_ids` در فاکتور نباشد، رفتار فعلی حفظ شود (انتخاب در زمان ایجاد حواله)
- امکان Override: اگر در زمان ایجاد حواله instance_ids جدیدی انتخاب شود، آن‌ها اولویت داشته باشند

### 3.3 در سطح UI ایجاد حواله

#### الف) نمایش اطلاعات از فاکتور

- اگر در خط فاکتور `selected_instance_ids` وجود داشته باشد، در دیالوگ ایجاد حواله:
  - لیست instance های انتخاب شده را نمایش دهد
  - امکان ویرایش/تغییر را داشته باشد
  - اگر تغییر داد، به‌روزرسانی در حواله اعمال شود (نه در فاکتور)

#### ب) انتخاب دستی در حواله (قابلیت موجود)

- قابلیت موجود برای انتخاب دستی instance ها در زمان ایجاد حواله حفظ شود
- اگر در فاکتور انتخاب شده بود، به عنوان پیش‌فرض نمایش داده شود

---

## 4. جزئیات پیاده‌سازی پیشنهادی

### 4.1 Backend Changes

#### الف) مدل InvoiceItemLine
**هیچ تغییری نیاز نیست** - `extra_info` (JSON) برای ذخیره `selected_instance_ids` کافی است

#### ب) سرویس invoice_service.py
**تابع `create_invoice`:**
- اعتبارسنجی `selected_instance_ids` در `extra_info` هر خط
- بررسی اینکه تعداد instance ها با quantity برابر باشد
- بررسی اینکه instance ها در دسترس باشند

**تابع `update_invoice`:**
- اعتبارسنجی مشابه در زمان به‌روزرسانی

#### ج) سرویس warehouse_service.py
**تابع `create_from_invoice`:**
- خواندن `selected_instance_ids` از `extra_info` خط فاکتور
- انتقال به `instance_ids_from_line` برای پردازش
- حفظ منطق موجود برای پردازش instance ها

**تابع `_load_invoice_lines`:**
- احتمالاً تغییری نیاز نیست - `extra_info` خود به خود بارگذاری می‌شود

#### د) API جدید (اختیاری)
- Endpoint برای اعتبارسنجی instance های انتخاب شده قبل از ذخیره فاکتور
- Endpoint برای دریافت اطلاعات کامل instance های انتخاب شده (برای نمایش در UI)

### 4.2 Frontend Changes

#### الف) فرم فاکتور (new_invoice_page.dart / edit_invoice_page.dart)

**برای هر خط فاکتور:**
- بررسی اینکه آیا کالا یونیک است (`inventory_mode == "unique"`)
- اگر یونیک است:
  - دکمه "انتخاب کالای یونیک" نمایش داده شود
  - با کلیک، دیالوگ انتخاب باز شود
  - پس از انتخاب، `selected_instance_ids` در `extra_info` خط ذخیره شود

**دیالوگ انتخاب:**
- استفاده از API موجود: `GET /product-instances/.../available`
- فیلتر بر اساس انبار (اگر در فاکتور مشخص شده)
- نمایش اطلاعات هر instance (serial, barcode, custom_attributes)
- امکان انتخاب چندتایی (چک‌باکس)
- اعتبارسنجی: تعداد انتخاب شده = quantity

#### ب) فرم حواله (warehouse_document_form_dialog.dart)

**هنگام بارگذاری از فاکتور:**
- خواندن `selected_instance_ids` از `extra_info` خط فاکتور
- بارگذاری اطلاعات کامل instance ها از API
- نمایش به عنوان پیش‌فرض
- امکان ویرایش/تغییر

---

## 5. سناریوی کاربری

### سناریو کامل:

1. **ورود کالا به انبار (حواله ورود)**
   - 50 یخچال با مشخصات مختلف وارد انبار می‌شود
   - برای هر یخچال یک `ProductInstance` ایجاد می‌شود با:
     - serial_number (مثلاً 100, 101, 102, ...)
     - custom_attributes: `{"color": "آبی", "model": "A123", ...}`

2. **ایجاد فاکتور فروش**
   - حسابدار یک فاکتور فروش برای 2 یخچال ایجاد می‌کند
   - در فرم فاکتور، برای خط مربوط به یخچال:
     - دکمه "انتخاب کالای یونیک" را کلیک می‌کند
     - دیالوگی باز می‌شود که لیست 50 یخچال موجود را نشان می‌دهد
     - حسابدار یخچال با serial_number 100 (رنگ آبی) و 101 (رنگ قرمز) را انتخاب می‌کند
     - این انتخاب در `extra_info.selected_instance_ids` ذخیره می‌شود

3. **ایجاد حواله خارج از فاکتور**
   - حسابدار حواله خارج را از فاکتور ایجاد می‌کند
   - در دیالوگ ایجاد حواله:
     - به طور خودکار instance های انتخاب شده (100 و 101) نمایش داده می‌شوند
     - انباردار می‌بیند که باید یخچال با سریال 100 (رنگ آبی) و 101 (رنگ قرمز) را ارسال کند
     - می‌تواند در صورت نیاز تغییر دهد (این تغییر فقط در حواله اعمال می‌شود، نه فاکتور)

4. **پست حواله**
   - با پست حواله:
     - instance های 100 و 101 از انبار خارج می‌شوند
     - status آن‌ها به "sold" تغییر می‌کند

---

## 6. مزایا و نکات

### مزایا:
- ✅ حسابدار می‌تواند در زمان ثبت فاکتور مشخص کند که دقیقاً کدام یخچال باید ارسال شود
- ✅ نیاز به انتخاب مجدد در زمان ایجاد حواله کاهش می‌یابد
- ✅ اطلاعات دقیق‌تر و سریع‌تر به انباردار منتقل می‌شود
- ✅ از ساختار موجود استفاده می‌کند (نیاز به تغییر schema نیست)

### نکات مهم:
- ⚠️ این قابلیت فقط برای فاکتور فروش (`INVOICE_SALES`) و برگشت از خرید (`INVOICE_PURCHASE_RETURN`) معنا دارد (چون حواله خارج ایجاد می‌کنند)
- ⚠️ برای فاکتور خرید و برگشت از فروش نیازی به این قابلیت نیست (حواله ورود دارند که در زمان ایجاد حواله instance ها ایجاد می‌شوند)
- ⚠️ اگر instance انتخاب شده قبل از ایجاد حواله فروخته/رزرو شود، باید خطا داده شود
- ⚠️ انتخاب در فاکتور اختیاری است - اگر انتخاب نشود، می‌توان در زمان ایجاد حواله انتخاب کرد

### نکته مهم درباره چند کالا در یک ردیف:

**✅ بله، می‌توان چند کالای یونیک را برای یک ردیف فاکتور انتخاب کرد!**

مثال: اگر در یک ردیف فاکتور `quantity = 2` باشد (مثلاً 2 یخچال)، می‌توان **2 instance مختلف** را انتخاب کرد:
- `selected_instance_ids: [100, 101]` - یخچال با سریال 100 و 101

**قوانین اعتبارسنجی:**
1. تعداد instance های انتخاب شده **باید دقیقاً برابر** با `quantity` ردیف باشد
   - اگر `quantity = 2` باشد، باید دقیقاً 2 instance انتخاب شود
   - کمتر از quantity: خطا - باید همه کالاها را انتخاب کنید
   - بیشتر از quantity: خطا - نمی‌توانید بیشتر از quantity انتخاب کنید

2. هر instance فقط می‌تواند یک بار انتخاب شود (در یک فاکتور)

3. ساختار داده:
   ```json
   {
     "product_id": 5,
     "quantity": 2,
     "extra_info": {
       "selected_instance_ids": [100, 101],  // لیست ID های instance ها
       "unit_price": 1000,
       ...
     }
   }
   ```

4. در حواله، این instance_ids به صورت خودکار منتقل می‌شوند:
   - هر instance در حواله خروج پردازش می‌شود
   - status آن‌ها به "sold" تغییر می‌کند
   - warehouse_id آن‌ها null می‌شود

**مثال کامل:**
- ردیف فاکتور: یخچال، quantity = 3
- انتخاب شده: instance های با ID های [100, 101, 102]
- در حواله: هر 3 instance پردازش و از انبار خارج می‌شوند

---

## 7. فرمت‌بندی ویژگی‌ها بر اساس data_type

### 7.1 تابع فرمت‌بندی ویژگی‌ها

برای نمایش صحیح ویژگی‌های هر instance، باید تابعی ایجاد شود که بر اساس `data_type` ویژگی، مقدار را فرمت کند:

**مثال کد پیشنهادی (Dart/Flutter):**

```dart
String formatAttributeValue(
  Map<String, dynamic> attribute,
  dynamic value,
) {
  if (value == null) return '-';
  
  final dataType = attribute['data_type']?.toString() ?? 'text';
  
  switch (dataType) {
    case 'text':
      return value.toString();
    
    case 'number':
      final numValue = num.tryParse(value.toString());
      if (numValue == null) return value.toString();
      // فرمت با جداکننده هزارگان
      return NumberFormat('#,###').format(numValue);
    
    case 'date':
      if (value is String) {
        final date = DateTime.tryParse(value);
        if (date != null) {
          // فرمت تاریخ فارسی
          return formatPersianDate(date);
        }
      }
      return value.toString();
    
    case 'boolean':
      final boolValue = value == true || 
                       value.toString().toLowerCase() == 'true' ||
                       value == 1 ||
                       value.toString() == '1';
      return boolValue ? 'بله' : 'خیر';
    
    case 'select':
      // پیدا کردن label از options
      final options = attribute['options'];
      if (options != null) {
        if (options is Map && options['items'] != null) {
          final items = options['items'] as List?;
          if (items != null) {
            final item = items.firstWhere(
              (e) => e['value'] == value.toString(),
              orElse: () => null,
            );
            if (item != null && item['label'] != null) {
              return item['label'].toString();
            }
          }
        } else if (options is List) {
          final item = options.firstWhere(
            (e) => e['value'] == value.toString(),
            orElse: () => null,
          );
          if (item != null && item['label'] != null) {
            return item['label'].toString();
          }
        }
      }
      return value.toString(); // fallback
    
    default:
      return value.toString();
  }
}
```

### 7.2 مثال عملی

**ویژگی کالا:**
- عنوان: "رنگ"
- data_type: "select"
- options: `{"items": [{"value": "blue", "label": "آبی"}, {"value": "red", "label": "قرمز"}]}`

**مقدار در custom_attributes:**
```json
{
  "رنگ": "blue"
}
```

**نمایش در UI:**
- باید "آبی" نمایش داده شود (نه "blue")
- برای این کار باید از تابع `formatAttributeValue` استفاده کرد که label را پیدا می‌کند

### 7.3 بارگذاری ویژگی‌های کالا

**در زمان بارگذاری instance ها:**
1. دریافت لیست ویژگی‌های کالا از API:
   ```
   GET /api/v1/product-attributes/business/{business_id}?product_id={product_id}
   ```
2. ایجاد Map از ویژگی‌ها بر اساس `title`:
   ```dart
   Map<String, Map<String, dynamic>> attributesMap = {};
   for (var attr in attributes) {
     attributesMap[attr['title']] = attr;
   }
   ```
3. هنگام نمایش هر instance:
   ```dart
   for (var entry in instance['custom_attributes'].entries) {
     final attrTitle = entry.key;
     final attrValue = entry.value;
     final attribute = attributesMap[attrTitle];
     
     if (attribute != null) {
       final formattedValue = formatAttributeValue(attribute, attrValue);
       // نمایش formattedValue
     }
   }
   ```

---

## 8. فایل‌های کلیدی برای تغییر

### Backend:
1. `hesabixAPI/app/services/invoice_service.py`
   - تابع `create_invoice`: اعتبارسنجی `selected_instance_ids`
   - تابع `update_invoice`: اعتبارسنجی `selected_instance_ids`

2. `hesabixAPI/app/services/warehouse_service.py`
   - تابع `create_from_invoice`: خواندن و انتقال `selected_instance_ids`

3. `hesabixAPI/adapters/api/v1/warehouse_docs.py`
   - تابع `_load_invoice_lines`: احتمالاً تغییری نیاز نیست

### Frontend:
1. `hesabixUI/hesabix_ui/lib/pages/business/new_invoice_page.dart`
   - افزودن UI برای انتخاب instance ها
   - بارگذاری ویژگی‌های کالا با data_type
   - فرمت‌بندی ویژگی‌ها برای نمایش

2. `hesabixUI/hesabix_ui/lib/pages/business/edit_invoice_page.dart`
   - افزودن UI برای انتخاب/ویرایش instance ها
   - نمایش instance های انتخاب شده با ویژگی‌های فرمت شده

3. `hesabixUI/hesabix_ui/lib/widgets/warehouse/warehouse_document_form_dialog.dart`
   - نمایش و پردازش `selected_instance_ids` از فاکتور
   - نمایش ویژگی‌های فرمت شده در حواله

4. `hesabixUI/hesabix_ui/lib/models/invoice_line_item.dart`
   - افزودن فیلد `selectedInstanceIds` (اختیاری)

5. **تابع کمکی جدید برای فرمت ویژگی‌ها:**
   - ایجاد تابع `formatAttributeValue(attribute, value)` که بر اساس `data_type` فرمت می‌کند
   - تابع `getAttributeLabel(attribute, value)` برای select ها که label را برمی‌گرداند
   - تابع `formatDate(value)` برای فرمت تاریخ به فارسی

---

## 9. سوالات و تصمیمات باقی‌مانده

### سوالات:
1. **آیا انتخاب instance در فاکتور اجباری است؟**
   - پیشنهاد: اختیاری - اگر انتخاب نشود، در زمان ایجاد حواله می‌توان انتخاب کرد

2. **آیا امکان تغییر instance ها در فاکتور بعد از ایجاد حواله وجود دارد؟**
   - پیشنهاد: خیر - اگر حواله ایجاد شده باشد، تغییر در فاکتور فقط برای حواله‌های جدید اعمال می‌شود

3. **آیا امکان نمایش لیست instance های انتخاب شده در فاکتور وجود دارد؟**
   - پیشنهاد: بله - به صورت خلاصه (مثلاً تعداد و سریال‌ها)

4. **آیا برای برگشت از خرید هم همین قابلیت نیاز است؟**
   - پیشنهاد: بله - چون برگشت از خرید هم حواله خارج ایجاد می‌کند

### تصمیمات پیشنهادی:
- ✅ انتخاب در فاکتور اختیاری باشد
- ✅ امکان نمایش/ویرایش لیست انتخاب شده در فاکتور باشد
- ✅ در زمان ایجاد حواله، امکان Override باشد
- ✅ اعتبارسنجی در زمان ذخیره فاکتور انجام شود

---

## 10. نتیجه‌گیری

این قابلیت قابل پیاده‌سازی است و از ساختار موجود سیستم پشتیبانی می‌کند:

- ✅ ساختار دیتابیس کافی است (`extra_info` JSON در `InvoiceItemLine`)
- ✅ API های لازم برای دریافت instance های در دسترس وجود دارد
- ✅ منطق پردازش instance ها در حواله موجود است
- ✅ نیاز به تغییر schema دیتابیس نیست

**مراحل پیاده‌سازی:**
1. Backend: اعتبارسنجی و انتقال `selected_instance_ids`
2. Frontend: UI برای انتخاب instance ها در فرم فاکتور
3. Frontend: نمایش اطلاعات در فرم حواله
4. تست: سناریو کامل از فاکتور تا حواله

---

**تاریخ بررسی:** 2024
**بررسی کننده:** AI Assistant
**وضعیت:** آماده برای پیاده‌سازی

