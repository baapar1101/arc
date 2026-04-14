# تحلیل انتقال اشخاص از hesabixOld به hesabixpy

## خلاصه اجرایی

این سند تحلیل نحوه انتقال اشخاص (persons/contacts) از دیتابیس قدیمی (`hesabixOld`) به دیتابیس جدید (`hesabixpy`) را ارائه می‌دهد.

## وضعیت فعلی

### دیتابیس قدیمی (hesabixOld)

#### جدول `person`
- **تعداد اشخاص**: 46,646
- **تعداد کسب و کارهای دارای شخص**: 2,597
- **ساختار**:
  - `id`: شناسه یکتا
  - `bid_id`: شناسه کسب و کار (ارجاع به `business.id`)
  - `code`: کد یکتا در کسب و کار (bigint)
  - `nikename`: نام مستعار (varchar(255))
  - `name`: نام (varchar(255))
  - `tel`: تلفن (varchar(12))
  - `mobile`: موبایل (varchar(12))
  - `mobile2`: موبایل دوم (varchar(15))
  - `address`: آدرس (varchar(255))
  - `des`: توضیحات (varchar(255))
  - `company`: نام شرکت (varchar(255))
  - `shenasemeli`: شناسه ملی (varchar(255))
  - `codeeghtesadi`: شناسه اقتصادی (varchar(255))
  - `sabt`: شماره ثبت (varchar(255))
  - `keshvar`: کشور (varchar(255))
  - `ostan`: استان (varchar(255))
  - `shahr`: شهر (varchar(255))
  - `postalcode`: کد پستی (varchar(255))
  - `email`: ایمیل (varchar(255))
  - `website`: وب‌سایت (varchar(255))
  - `fax`: فکس (varchar(255))
  - `birthday`: تاریخ تولد (varchar(255))
  - `payment_id`: شناسه پرداخت (varchar(255))
  - `prelabel_id`: شناسه پیش‌برچسب (int)
  - `tags`: تگ‌ها (longtext)
  - فیلدهای خاص: `plug_noghre_morsa`, `plug_noghre_hakak`, `plug_noghre_tarash`, `employe`, `plug_noghre_ghalam`

**آمار**:
- اشخاص با شرکت: 4,250 (9.1%)
- اشخاص با شناسه ملی: 1,072 (2.3%)
- اشخاص قابل انتقال: 44,754 (96.0%)
- کسب و کارهای قابل انتقال: 2,356

#### جدول `person_type`
- **ساختار**:
  - `id`: شناسه یکتا
  - `label`: برچسب (varchar(255)) - مثل "مشتری", "تامین‌کننده"
  - `code`: کد (varchar(255)) - مثل "customer", "supplier"

**انواع موجود**:
- مشتری (customer)
- بازاریاب (marketer)
- کارمند (emplyee)
- تامین‌کننده (supplier)
- همکار (colleague)
- فروشنده (salesman)

#### جدول `person_person_type`
- **ساختار**:
  - `person_id`: شناسه شخص (ارجاع به `person.id`)
  - `person_type_id`: شناسه نوع شخص (ارجاع به `person_type.id`)

**آمار**:
- کل رکوردها: 21,356
- اشخاص منحصر به فرد با نوع: 19,751
- اشخاص با چندین نوع: 916

**توزیع انواع**:
- مشتری: 14,314 (67.0%)
- تامین‌کننده: 2,705 (12.7%)
- همکار: 2,077 (9.7%)
- کارمند: 1,097 (5.1%)
- فروشنده: 906 (4.2%)
- بازاریاب: 257 (1.2%)

### دیتابیس جدید (hesabixpy)

#### جدول `persons`
- **تعداد اشخاص فعلی**: 122
- **ساختار**:
  - `id`: شناسه یکتا
  - `business_id`: شناسه کسب و کار (ارجاع به `businesses.id`)
  - `code`: کد یکتا در هر کسب و کار (integer)
  - `alias_name`: نام مستعار (varchar(255)) - **الزامی**
  - `first_name`: نام (varchar(100))
  - `last_name`: نام خانوادگی (varchar(100))
  - `person_types`: لیست انواع شخص به صورت JSON (text) - **الزامی**
  - `company_name`: نام شرکت (varchar(255))
  - `payment_id`: شناسه پرداخت (varchar(100))
  - `national_id`: شناسه ملی (varchar(20))
  - `registration_number`: شماره ثبت (varchar(50))
  - `economic_id`: شناسه اقتصادی (varchar(50))
  - `country`: کشور (varchar(100))
  - `province`: استان (varchar(100))
  - `city`: شهرستان (varchar(100))
  - `address`: آدرس (text)
  - `postal_code`: کد پستی (varchar(20))
  - `phone`: تلفن (varchar(20))
  - `mobile`: موبایل (varchar(20))
  - `fax`: فکس (varchar(20))
  - `email`: ایمیل (varchar(255))
  - `website`: وب‌سایت (varchar(255))
  - `share_count`: تعداد سهام (integer)
  - `commission_sale_percent`: درصد پورسانت از فروش (decimal(5,2))
  - `commission_sales_return_percent`: درصد پورسانت از برگشت از فروش (decimal(5,2))
  - `commission_sales_amount`: مبلغ فروش مبنا برای پورسانت (decimal(12,2))
  - `commission_sales_return_amount`: مبلغ برگشت از فروش مبنا برای پورسانت (decimal(12,2))
  - `commission_exclude_discounts`: عدم محاسبه تخفیف در پورسانت (boolean)
  - `commission_exclude_additions_deductions`: عدم محاسبه اضافات و کسورات فاکتور در پورسانت (boolean)
  - `commission_post_in_invoice_document`: ثبت پورسانت در سند حسابداری فاکتور (boolean)
  - `credit_limit`: سقف اعتبار شخص (decimal(14,2))
  - `credit_check_enabled`: فعال بودن بررسی اعتبار (boolean)
  - `created_at`: تاریخ ایجاد (datetime)
  - `updated_at`: تاریخ به‌روزرسانی (datetime)

**نکته مهم**: `person_types` به صورت JSON array نگهداری می‌شود، مثل: `["مشتری", "تامین‌کننده"]`

## استراتژی انتقال

### تبدیل فیلدها

| فیلد قدیمی | فیلد جدید | تبدیل |
|------------|-----------|-------|
| `id` | - | نگه‌داری در mapping table (اختیاری) |
| `bid_id` | `business_id` | نگاشت از business_id_mapping |
| `code` | `code` | تبدیل bigint به integer (با بررسی محدوده) |
| `nikename` | `alias_name` | مستقیم (الزامی) |
| `name` | `first_name`, `last_name` | تقسیم نام به نام و نام خانوادگی |
| `company` | `company_name` | مستقیم |
| `shenasemeli` | `national_id` | مستقیم |
| `codeeghtesadi` | `economic_id` | مستقیم |
| `sabt` | `registration_number` | مستقیم |
| `keshvar` | `country` | مستقیم |
| `ostan` | `province` | مستقیم |
| `shahr` | `city` | مستقیم |
| `address` | `address` | مستقیم |
| `postalcode` | `postal_code` | مستقیم |
| `tel` | `phone` | مستقیم |
| `mobile` | `mobile` | مستقیم |
| `mobile2` | - | حذف (یا در توضیحات) |
| `fax` | `fax` | مستقیم |
| `email` | `email` | مستقیم |
| `website` | `website` | مستقیم |
| `birthday` | - | حذف (یا در توضیحات) |
| `payment_id` | `payment_id` | مستقیم |
| `des` | - | حذف (یا در توضیحات) |
| `tags` | - | حذف (یا در جدول جداگانه) |
| `person_person_type` | `person_types` | تبدیل به JSON array |

### تبدیل name به first_name و last_name

**الگوریتم**:
```python
def split_name(name: str | None) -> Tuple[str | None, str | None]:
	"""
	تبدیل name به first_name و last_name
	
	Args:
		name: نام کامل (مثل "علی زیوری" یا "صادق احمدیان")
	
	Returns:
		(first_name, last_name)
	"""
	if not name or not name.strip():
		return (None, None)
	
	name = name.strip()
	parts = name.split()
	
	if len(parts) == 0:
		return (None, None)
	elif len(parts) == 1:
		return (parts[0], None)
	else:
		# اولین کلمه = نام، بقیه = نام خانوادگی
		first_name = parts[0]
		last_name = ' '.join(parts[1:])
		return (first_name, last_name)
```

**نکته**: اگر `name` خالی باشد، از `nikename` استفاده می‌شود.

### تبدیل person_types

**چالش**: 
- در قدیمی: جدول `person_person_type` با چندین رکورد برای هر شخص
- در جدید: فیلد `person_types` به صورت JSON array

**راه‌حل**:
1. برای هر شخص، تمام `person_type_id` را از `person_person_type` بخوان
2. `label` هر نوع را از `person_type` بگیر
3. تبدیل به JSON array: `["مشتری", "تامین‌کننده"]`
4. اگر شخصی نوع نداشت، پیش‌فرض: `["مشتری"]`

**الگوریتم**:
```python
def get_person_types(old_person_id: int, person_type_mapping: Dict[int, str]) -> List[str]:
	"""
	دریافت انواع شخص از دیتابیس قدیمی
	
	Args:
		old_person_id: شناسه شخص قدیمی
		person_type_mapping: mapping {person_type_id: label}
	
	Returns:
		لیست انواع شخص (مثل ["مشتری", "تامین‌کننده"])
	"""
	query = text("""
		SELECT person_type_id
		FROM hesabixOld.person_person_type
		WHERE person_id = :person_id
	""")
	results = old_db.execute(query, {"person_id": old_person_id}).fetchall()
	
	types = []
	for row in results:
		type_label = person_type_mapping.get(row.person_type_id)
		if type_label:
			types.append(type_label)
	
	# اگر نوعی نداشت، پیش‌فرض مشتری
	if not types:
		types = ["مشتری"]
	
	return types

def convert_person_types_to_json(types: List[str]) -> str:
	"""تبدیل لیست انواع به JSON"""
	return json.dumps(types, ensure_ascii=False)
```

**Mapping انواع**:
- مشتری (customer) → "مشتری"
- بازاریاب (marketer) → "بازاریاب"
- کارمند (emplyee) → "کارمند"
- تامین‌کننده (supplier) → "تامین‌کننده"
- همکار (colleague) → "همکار"
- فروشنده (salesman) → "فروشنده"

### تبدیل code

**چالش**: 
- در قدیمی: `code` به صورت `bigint`
- در جدید: `code` به صورت `integer` (محدود به 2147483647)

**راه‌حل**:
```python
def convert_code(code: int | None) -> int | None:
	"""تبدیل code از bigint به integer"""
	if code is None:
		return None
	
	# محدود کردن به محدوده integer
	if code > 2147483647:
		return None  # یا استفاده از code جدید
	
	return int(code)
```

### تبدیل alias_name

**الگوریتم**:
```python
def get_alias_name(nikename: str | None, name: str | None) -> str:
	"""
	دریافت alias_name از nikename یا name
	
	Args:
		nikename: نام مستعار
		name: نام کامل
	
	Returns:
		alias_name (الزامی)
	"""
	if nikename and nikename.strip():
		return nikename.strip()
	elif name and name.strip():
		return name.strip()
	else:
		# اگر هیچکدام نبود، از "شخص بدون نام" استفاده می‌کنیم
		return "شخص بدون نام"
```

## الگوریتم انتقال

### مرحله 1: آماده‌سازی

1. **ایجاد business_id_mapping**: از انتقال کسب و کارها
2. **ایجاد person_type_mapping**: mapping بین `person_type.id` و `person_type.label`

### مرحله 2: فیلتر اشخاص برای انتقال

**شرایط انتقال**:
1. شخص باید `bid_id` داشته باشد
2. `bid_id` باید در `business_id_mapping` وجود داشته باشد
3. شخص نباید در دیتابیس جدید وجود داشته باشد (بر اساس business_id و code)

**SQL برای انتخاب**:
```sql
SELECT p.*
FROM hesabixOld.person p
INNER JOIN business_id_mapping m ON p.bid_id = m.old_business_id
WHERE NOT EXISTS (
	SELECT 1 FROM hesabixpy.persons new
	WHERE new.business_id = m.new_business_id
	  AND new.code = p.code
)
ORDER BY p.bid_id, p.id;
```

### مرحله 3: پردازش هر شخص

**مراحل**:
1. نگاشت `bid_id` → `business_id`
2. تبدیل `code` (bigint به integer)
3. تبدیل `nikename`/`name` → `alias_name`
4. تقسیم `name` → `first_name` و `last_name`
5. تبدیل `person_person_type` → `person_types` (JSON)
6. تبدیل سایر فیلدها
7. درج در دیتابیس جدید

### مرحله 4: مدیریت موارد خاص

**سناریو 1: code خارج از محدوده integer**
- عمل: `code = NULL` یا استفاده از code جدید
- لاگ: ثبت در لاگ

**سناریو 2: alias_name خالی**
- عمل: استفاده از "شخص بدون نام"
- لاگ: ثبت در لاگ

**سناریو 3: person_types خالی**
- عمل: پیش‌فرض `["مشتری"]`
- لاگ: ثبت در لاگ

**سناریو 4: کد تکراری**
- عمل: skip کردن با reason "duplicate_code"
- لاگ: ثبت در لاگ

## آمار و ارقام

### توزیع داده‌ها

- **کل اشخاص**: 46,646
- **اشخاص قابل انتقال**: 44,754 (96.0%)
- **کسب و کارهای قابل انتقال**: 2,356
- **اشخاص با شرکت**: 4,250 (9.1%)
- **اشخاص با شناسه ملی**: 1,072 (2.3%)
- **اشخاص با نوع**: 19,751 (42.3%)
- **اشخاص با چندین نوع**: 916 (2.0%)

### توزیع انواع شخص

- مشتری: 14,314 (67.0%)
- تامین‌کننده: 2,705 (12.7%)
- همکار: 2,077 (9.7%)
- کارمند: 1,097 (5.1%)
- فروشنده: 906 (4.2%)
- بازاریاب: 257 (1.2%)

### قابل انتقال

- **کسب و کارهای منتقل شده**: 3,812
- **کسب و کارهای دارای شخص که منتقل شده‌اند**: 2,356
- **اشخاص قابل انتقال**: 44,754
- **اشخاص با code خارج از محدوده integer**: 0 (همه code ها در محدوده هستند)

## نکات مهم

1. **حجم متوسط داده**: 44,754 شخص - نیاز به پردازش batch به batch
2. **person_types**: باید از جدول `person_person_type` به JSON array تبدیل شود
3. **alias_name**: الزامی است - باید از `nikename` یا `name` استفاده شود
4. **code**: باید از bigint به integer تبدیل شود (با بررسی محدوده)
5. **name splitting**: باید به `first_name` و `last_name` تقسیم شود

## ریسک‌ها و راه‌حل‌ها

### ریسک 1: code خارج از محدوده integer
**راه‌حل**: بررسی محدوده و استفاده از NULL یا code جدید
**وضعیت**: همه code ها در محدوده integer هستند (max: 21,252)

### ریسک 2: alias_name خالی
**راه‌حل**: استفاده از پیش‌فرض "شخص بدون نام"

### ریسک 3: person_types خالی
**راه‌حل**: استفاده از پیش‌فرض `["مشتری"]`

### ریسک 4: کدهای تکراری
**راه‌حل**: بررسی unique constraint قبل از درج

### ریسک 5: اشخاص با چندین نوع
**راه‌حل**: تبدیل همه انواع به JSON array

## نتیجه‌گیری

انتقال اشخاص نیاز به:
- ✅ نگاشت business_id
- ✅ تبدیل code (bigint به integer)
- ✅ تبدیل nikename/name به alias_name
- ✅ تقسیم name به first_name و last_name
- ✅ تبدیل person_person_type به person_types (JSON)
- ✅ پردازش batch به batch

**تخمین زمان**: با batch size 500، حدود 90 batch نیاز است که می‌تواند 10-20 دقیقه طول بکشد.

**آمار دقیق قابل انتقال**:
- اشخاص: 44,754
- کسب و کارهای دارای شخص: 2,356
- اشخاص با نوع: 19,751
- اشخاص با چندین نوع: 916

