# سیستم دسترسی Join برای عضویت در کسب و کار

## خلاصه تغییرات

این سند توضیح می‌دهد که چگونه سیستم دسترسی `join` برای عضویت کاربران در کسب و کارها پیاده‌سازی شده است.

## مشکل قبلی

قبلاً کاربران فقط می‌توانستند کسب و کارهای خودشان (که مالک آن‌ها بودند) را در لیست کسب و کارها مشاهده کنند. اگر کاربری عضو کسب و کار دیگری بود، نمی‌توانست آن را در لیست مشاهده کند.

## راه‌حل

### 1. تعریف دسترسی `join`

یک دسترسی جدید به نام `join` تعریف شده که نشان‌دهنده عضویت کاربر در کسب و کار است:

```json
{
  "join": true,
  "sales": {
    "read": true,
    "write": false
  }
}
```

### 2. تغییرات در بکند

#### AuthContext
- متد `is_business_member()` اضافه شد
- این متد بررسی می‌کند که آیا کاربر عضو کسب و کار است یا نه

#### BusinessPermissionRepository
- متد `get_user_member_businesses()` اضافه شد
- این متد کسب و کارهایی که کاربر عضو آن‌ها است را برمی‌گرداند

#### BusinessService
- متد `get_user_businesses()` اضافه شد
- این متد هم کسب و کارهای مالک و هم کسب و کارهای عضو را برمی‌گرداند

#### API Endpoint
- endpoint `/api/v1/businesses/list` به‌روزرسانی شد
- حالا هم کسب و کارهای مالک و هم کسب و کارهای عضو را نمایش می‌دهد

### 3. تغییرات در فرانت‌اند

#### BusinessDashboardService
- متد `getUserBusinesses()` به‌روزرسانی شد
- حالا از API جدید استفاده می‌کند که هم مالک و هم عضو را پشتیبانی می‌کند

#### BusinessWithPermission Model
- فیلدهای `isOwner` و `role` قبلاً وجود داشتند
- این فیلدها برای تشخیص نقش کاربر استفاده می‌شوند

## نحوه استفاده

### 1. اضافه کردن کاربر به کسب و کار

```python
from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository

permission_repo = BusinessPermissionRepository(db)
permission_repo.create_or_update(
    user_id=user_id,
    business_id=business_id,
    permissions={'join': True, 'sales': {'read': True}}
)
```

### 2. بررسی عضویت کاربر

```python
from app.core.auth_dependency import AuthContext

auth_ctx = AuthContext(user=user, db=db)
is_member = auth_ctx.is_business_member(business_id)
```

### 3. دریافت لیست کسب و کارهای کاربر

```python
from app.services.business_service import get_user_businesses

result = get_user_businesses(db, user_id, query_info)
# result['items'] شامل هم کسب و کارهای مالک و هم عضو است
```

## اسکریپت‌های کمکی

### 1. تست سیستم
```bash
cd hesabixAPI
python scripts/test_business_membership.py
```

### 2. اضافه کردن دسترسی join به کاربران موجود
```bash
cd hesabixAPI
python scripts/add_join_permissions.py
```

### 3. تست دسترسی join
```bash
cd hesabixAPI
python scripts/test_join_permission.py
```

## Migration

فایل migration `20250120_000002_add_join_permission.py` ایجاد شده که فقط برای مستندسازی است زیرا جدول `business_permissions` قبلاً وجود دارد و JSON field است.

## نکات مهم

1. **مالک کسب و کار**: مالک کسب و کار به طور خودکار عضو محسوب می‌شود
2. **SuperAdmin**: SuperAdmin به طور خودکار عضو همه کسب و کارها محسوب می‌شود
3. **دسترسی join**: این دسترسی باید به صورت دستی برای کاربران عضو اضافه شود
4. **سازگاری**: تغییرات با سیستم قبلی سازگار است

## مثال کامل

```python
# ایجاد کسب و کار
business = create_business(db, business_data, owner_id)

# اضافه کردن کاربر به کسب و کار
permission_repo.create_or_update(
    user_id=member_user_id,
    business_id=business.id,
    permissions={'join': True, 'sales': {'read': True, 'write': False}}
)

# دریافت لیست کسب و کارهای کاربر
result = get_user_businesses(db, member_user_id, query_info)
# حالا کاربر هم کسب و کارهای مالک و هم کسب و کارهای عضو را می‌بیند
```
