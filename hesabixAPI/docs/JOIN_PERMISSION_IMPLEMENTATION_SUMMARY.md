# خلاصه پیاده‌سازی سیستم دسترسی Join

## تاریخ: 2025-01-20

## مشکل اصلی
کاربران فقط می‌توانستند کسب و کارهای خودشان (که مالک آن‌ها بودند) را در لیست کسب و کارها مشاهده کنند. اگر کاربری عضو کسب و کار دیگری بود، نمی‌توانست آن را در لیست مشاهده کند.

## راه‌حل پیاده‌سازی شده

### 1. تعریف دسترسی `join`
- دسترسی جدید `join: true` برای نشان دادن عضویت کاربر در کسب و کار
- این دسترسی در فیلد `business_permissions` ذخیره می‌شود

### 2. تغییرات در بکند

#### AuthContext (`app/core/auth_dependency.py`)
```python
def is_business_member(self, business_id: int) -> bool:
    """بررسی اینکه آیا کاربر عضو کسب و کار است یا نه (دسترسی join)"""
```

#### BusinessPermissionRepository (`adapters/db/repositories/business_permission_repo.py`)
```python
def get_user_member_businesses(self, user_id: int) -> list[BusinessPermission]:
    """دریافت تمام کسب و کارهایی که کاربر عضو آن‌ها است (دسترسی join)"""
```

#### BusinessService (`app/services/business_service.py`)
```python
def get_user_businesses(db: Session, user_id: int, query_info: Dict[str, Any]) -> Dict[str, Any]:
    """دریافت لیست کسب و کارهای کاربر (مالک + عضو)"""
```

#### API Endpoint (`adapters/api/v1/businesses.py`)
- endpoint `/api/v1/businesses/list` به‌روزرسانی شد
- حالا هم کسب و کارهای مالک و هم کسب و کارهای عضو را نمایش می‌دهد

#### افزودن کاربر (`adapters/api/v1/business_users.py`)
```python
permission_obj = permission_repo.create_or_update(
    user_id=user.id,
    business_id=business_id,
    permissions={'join': True}  # دسترسی join به طور خودکار اضافه می‌شود
)
```

### 3. تغییرات در فرانت‌اند

#### BusinessDashboardService (`hesabixUI/hesabix_ui/lib/services/business_dashboard_service.dart`)
- متد `getUserBusinesses()` به‌روزرسانی شد
- حالا از API جدید استفاده می‌کند که هم مالک و هم عضو را پشتیبانی می‌کند

### 4. نحوه کارکرد

#### مالک کسب و کار
- به طور خودکار عضو محسوب می‌شود
- در لیست با نقش "مالک" نمایش داده می‌شود

#### SuperAdmin
- به طور خودکار عضو همه کسب و کارها محسوب می‌شود

#### کاربران عضو
- باید دسترسی `join: true` داشته باشند
- در لیست با نقش "عضو" نمایش داده می‌شوند
- می‌توانند کسب و کار را در لیست مشاهده کنند

### 5. مثال JSON دسترسی‌ها

```json
{
  "join": true,
  "sales": {
    "read": true,
    "write": false
  },
  "reports": {
    "read": true,
    "export": false
  }
}
```

### 6. تست‌های انجام شده

✅ **تست 1**: افزودن دسترسی join به کاربر موجود
✅ **تست 2**: دریافت لیست کسب و کارهای کاربر (مالک + عضو)
✅ **تست 3**: API endpoint لیست کسب و کارها
✅ **تست 4**: افزودن کاربر جدید به کسب و کار
✅ **تست 5**: نمایش کسب و کار در فرانت‌اند

### 7. فایل‌های تغییر یافته

#### بکند
- `app/core/auth_dependency.py` - اضافه شدن متد `is_business_member`
- `adapters/db/repositories/business_permission_repo.py` - اضافه شدن متد `get_user_member_businesses`
- `app/services/business_service.py` - اضافه شدن متد `get_user_businesses`
- `adapters/api/v1/businesses.py` - به‌روزرسانی endpoint لیست کسب و کارها
- `adapters/api/v1/business_users.py` - اصلاح متد افزودن کاربر

#### فرانت‌اند
- `hesabixUI/hesabix_ui/lib/services/business_dashboard_service.dart` - به‌روزرسانی متد `getUserBusinesses`

#### مستندات
- `docs/JOIN_PERMISSION_SYSTEM.md` - مستندات کامل سیستم
- `migrations/versions/20250120_000002_add_join_permission.py` - Migration

### 8. نتیجه نهایی

🎉 **مشکل حل شد!** حالا کاربران می‌توانند:
- کسب و کارهایی که مالک آن‌ها هستند را مشاهده کنند (نقش: مالک)
- کسب و کارهایی که عضو آن‌ها هستند را مشاهده کنند (نقش: عضو)
- دسترسی `join` به طور خودکار هنگام افزودن کاربر به کسب و کار اضافه می‌شود

### 9. سازگاری
- تمام تغییرات با سیستم قبلی سازگار است
- کاربران موجود نیازی به تغییر ندارند
- API های موجود همچنان کار می‌کنند
