# رفع مشکل ایجاد مشتری‌های تکراری "مشتری ناشناس" در فاکتور سریع

## 🔍 مشکل شناسایی شده

### مشکلات اصلی:
1. **عدم تولید کد برای مشتری ناشناس**: در تابع `get_or_create_anonymous_customer`، مشتری جدید مستقیماً با `Person(...)` ایجاد می‌شد بدون اینکه کد تولید شود. این باعث می‌شد:
   - کد مشتری `None` باشد
   - کد با تنظیمات کسب‌وکار مطابقت نداشته باشد
   - چند مشتری با نام یکسان و کد `None` ایجاد شوند

2. **عدم استفاده از `create_person`**: به جای استفاده از تابع `create_person` که کد را به درستی تولید می‌کند و از تنظیمات کسب‌وکار استفاده می‌کند، مستقیماً Person ایجاد می‌شد.

3. **جستجوی ناکافی**: جستجو فقط بر اساس `alias_name` انجام می‌شد و اولویت با مشتری‌هایی که کد دارند در نظر گرفته نمی‌شد.

## ✅ راه‌حل پیاده‌سازی شده

### 1. استفاده از `create_person` برای تولید صحیح کد

**قبل:**
```python
customer = Person(
    business_id=int(business_id),
    alias_name=name_fa,
    person_types=json.dumps([PersonType.CUSTOMER.value]),
)
db.add(customer)
db.flush()
db.commit()
```

**بعد:**
```python
person_data = PersonCreateRequest(
    alias_name=name_fa,
    person_types=[PersonType.CUSTOMER],
    code=None,  # None = تولید خودکار کد
)

result = create_person(db, int(business_id), person_data)
customer_id = result.get("id")
```

### 2. بهبود جستجوی مشتری ناشناس

**قبل:**
```python
customer = db.query(Person).filter(
    and_(
        Person.business_id == int(business_id),
        Person.alias_name == name_fa,
        Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
    )
).first()
```

**بعد:**
```python
# اولویت با مشتری‌هایی که کد دارند
customer = db.query(Person).filter(
    and_(
        Person.business_id == int(business_id),
        Person.alias_name == name_fa,
        Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
        Person.code.isnot(None),  # اولویت با مشتری‌هایی که کد دارند
    )
).first()

# اگر مشتری با کد پیدا نشد، مشتری بدون کد را جستجو کن
if not customer:
    customer = db.query(Person).filter(
        and_(
            Person.business_id == int(business_id),
            Person.alias_name == name_fa,
            Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
        )
    ).first()
```

### 3. Import های جدید

```python
from adapters.api.v1.schema_models.person import PersonCreateRequest
from app.services.person_service import create_person
```

## 📋 تغییرات فایل

### `/var/www/ark/hesabixAPI/app/services/quick_sales_service.py`

1. **افزودن Import ها** (خط 11-13):
   - `PersonCreateRequest` برای ساخت درخواست ایجاد مشتری
   - `create_person` برای استفاده از تابع استاندارد ایجاد مشتری

2. **بهبود جستجو** (خط 187-206):
   - اولویت با مشتری‌هایی که کد دارند
   - اگر پیدا نشد، مشتری بدون کد را جستجو می‌کند

3. **استفاده از `create_person`** (خط 211-236):
   - استفاده از `PersonCreateRequest` برای ساخت درخواست
   - استفاده از `create_person` برای ایجاد مشتری با کد صحیح
   - مدیریت خطاها در صورت عدم موفقیت

## 🎯 مزایای راه‌حل

1. ✅ **تولید صحیح کد**: کد مشتری به صورت خودکار و مطابق با تنظیمات کسب‌وکار تولید می‌شود
2. ✅ **جلوگیری از تکراری**: استفاده از `create_person` که بررسی تکراری بودن کد را انجام می‌دهد
3. ✅ **سازگاری با سیستم**: کد مشتری با سایر مشتری‌ها در سیستم سازگار است
4. ✅ **اولویت‌بندی صحیح**: اولویت با مشتری‌هایی که کد دارند
5. ✅ **مدیریت خطا**: خطاهای مناسب در صورت عدم موفقیت

## 🔄 رفتار جدید

1. **اول**: بررسی مشتری پیش‌فرض از تنظیمات
2. **دوم**: جستجوی مشتری با نام "مشتری ناشناس" که کد دارد
3. **سوم**: جستجوی مشتری با نام "مشتری ناشناس" بدون کد (برای سازگاری با مشتری‌های قدیمی)
4. **چهارم**: ایجاد مشتری جدید با استفاده از `create_person` که کد را به درستی تولید می‌کند

## ⚠️ نکات مهم

- مشتری‌های قدیمی که با کد `None` ایجاد شده‌اند همچنان کار می‌کنند
- مشتری‌های جدید همیشه کد دارند
- کد مشتری مطابق با تنظیمات کسب‌وکار تولید می‌شود (max_code + 1)
- از این به بعد، مشتری‌های تکراری ایجاد نمی‌شوند

## ✅ تست

برای تست این تغییرات:
1. تنظیمات فروش سریع را بررسی کنید
2. یک فاکتور سریع بدون انتخاب مشتری ایجاد کنید
3. بررسی کنید که مشتری ناشناس با کد صحیح ایجاد شده است
4. بررسی کنید که مشتری‌های تکراری ایجاد نمی‌شوند

## 📝 خلاصه

مشکل ایجاد مشتری‌های تکراری "مشتری ناشناس" با کد `None` برطرف شد. حالا:
- ✅ کد مشتری به درستی تولید می‌شود
- ✅ از تابع استاندارد `create_person` استفاده می‌شود
- ✅ جستجو بهبود یافته و اولویت با مشتری‌هایی که کد دارند
- ✅ مشتری‌های تکراری ایجاد نمی‌شوند

