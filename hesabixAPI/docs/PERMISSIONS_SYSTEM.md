# سیستم دسترسی دو سطحی

این سیستم دسترسی‌ها را در دو سطح جداگانه مدیریت می‌کند:

## 1. دسترسی‌های اپلیکیشن (App-Level Permissions)

در `users.app_permissions` ذخیره می‌شود و شامل:

### دسترسی‌های موجود:
- `superadmin`: دسترسی کامل به سیستم
- `support_operator`: دسترسی به پنل اپراتور پشتیبانی و مدیریت تیکت‌ها
- `user_management`: مدیریت کاربران در سطح اپلیکیشن
- `business_management`: مدیریت کسب و کارها
- `system_settings`: دسترسی به تنظیمات سیستم

### مثال JSON:
```json
{
  "superadmin": true,
  "user_management": true,
  "business_management": true
}
```

## 2. دسترسی‌های کسب و کار (Business-Level Permissions)

در `business_permissions.business_permissions` ذخیره می‌شود و شامل:

### بخش‌های موجود:
- `sales`: فروش
- `purchases`: خرید
- `accounting`: حسابداری
- `inventory`: موجودی
- `reports`: گزارش‌ها
- `settings`: تنظیمات کسب و کار
- `marketing`: بازاریابی

### عملیات‌های موجود:
- `read`: خواندن
- `write`: نوشتن
- `delete`: حذف
- `approve`: تأیید
- `export`: صادرات
- `manage_users`: مدیریت کاربران (فقط در settings)

### مثال JSON:
```json
{
  "sales": {
    "write": true,
    "delete": true,
    "approve": true
  },
  "accounting": {
    "write": true
  },
  "reports": {
    "export": true
  },
  "settings": {
    "manage_users": true
  }
}
```

## نحوه استفاده

### 1. بررسی دسترسی در AuthContext:

```python
# دسترسی‌های اپلیکیشن
ctx.has_app_permission("superadmin")
ctx.is_superadmin()
ctx.can_manage_users()
ctx.can_manage_businesses()

# دسترسی‌های کسب و کار
ctx.has_business_permission("sales", "write")
ctx.can_read_section("sales")
ctx.can_write_section("sales")
ctx.can_delete_section("sales")
ctx.can_approve_section("sales")
ctx.can_export_section("reports")
ctx.can_manage_business_users()

# ترکیب دسترسی‌ها
ctx.has_any_permission("sales", "write")  # app یا business
ctx.can_access_business(business_id)
```

### 2. استفاده از Decorator ها:

```python
from app.core.permissions import (
    require_superadmin,
    require_user_management,
    require_sales_write,
    require_business_access
)

# دسترسی اپلیکیشن
@require_superadmin()
def admin_function():
    pass

@require_user_management()
def manage_users():
    pass

# دسترسی کسب و کار
@require_business_access("business_id")
@require_sales_write()
def create_sale(business_id: int):
    pass
```

### 3. بررسی دسترسی در API:

```python
@router.post("/business/{business_id}/sales")
def create_sale(
    business_id: int,
    ctx: AuthContext = Depends(get_current_user)
):
    # بررسی دسترسی به کسب و کار
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "No access to this business")
    
    # بررسی دسترسی نوشتن فروش
    if not ctx.has_business_permission("sales", "write"):
        raise ApiError("FORBIDDEN", "No permission to create sales")
    
    # ایجاد فروش
    pass
```

## قوانین دسترسی

### 1. SuperAdmin:
- **دسترسی خودکار**: تمام دسترسی‌های اپلیکیشن را خودکار دارد
- **دسترسی کامل**: به تمام بخش‌های سیستم دسترسی دارد
- **دسترسی کسب و کار**: می‌تواند به هر کسب و کاری دسترسی داشته باشد
- **تمام عملیات**: تمام عملیات را می‌تواند انجام دهد

### 2. مالک کسب و کار:
- **دسترسی اپلیکیشن**: فقط دسترسی‌های مشخص شده در `app_permissions`
- **دسترسی خودکار کسب و کار**: تمام دسترسی‌های کسب و کار خود را خودکار دارد
- **دسترسی کامل**: تمام عملیات در کسب و کار خود را می‌تواند انجام دهد
- **مدیریت کاربران**: می‌تواند کاربران کسب و کار خود را مدیریت کند

### 3. کاربران عادی:
- **دسترسی اپلیکیشن**: فقط دسترسی‌های مشخص شده در `app_permissions`
- **دسترسی کسب و کار**: دسترسی‌های مشخص شده در `business_permissions`
- **دسترسی محدود**: فقط به کسب و کارهای خود دسترسی دارند
- **قوانین بخش**: اگر بخش در دسترسی‌ها وجود دارد اما خالی است، فقط خواندن مجاز است

### 3. ذخیره‌سازی بهینه:
- فقط دسترسی‌های موجود ذخیره می‌شود
- `false` یا `null` ذخیره نمی‌شود
- کاهش حجم داده و بهبود عملکرد

## مثال‌های عملی

### کاربر مدیر فروش:
```json
{
  "app_permissions": {},
  "business_permissions": {
    "sales": {
      "write": true,
      "delete": true,
      "approve": true
    },
    "inventory": {
      "write": true
    }
  }
}
```

### کاربر کارمند حسابداری:
```json
{
  "app_permissions": {},
  "business_permissions": {
    "accounting": {
      "write": true
    },
    "reports": {
      "export": true
    }
  }
}
```

### SuperAdmin:
```json
{
  "app_permissions": {
    "superadmin": true
  },
  "business_permissions": {}  // دسترسی کامل به همه
}

// نتایج:
// - has_app_permission("user_management") → True (خودکار)
// - has_app_permission("business_management") → True (خودکار)
// - has_business_permission("sales", "write") → True (برای هر کسب و کار)
// - is_superadmin() → True
// - is_business_owner() → False (مگر اینکه مالک کسب و کار باشد)
```

### مالک کسب و کار:
```json
{
  "app_permissions": {},
  "business_permissions": {
    "sales": {"write": true, "delete": true}
  }
}

// نتایج:
// - has_app_permission("user_management") → False
// - has_business_permission("sales", "write") → True (از JSON)
// - has_business_permission("accounting", "write") → True (خودکار - مالک)
// - has_business_permission("reports", "export") → True (خودکار - مالک)
// - is_business_owner() → True
```

## توسعه سیستم

### اضافه کردن بخش جدید:
```python
# فقط در business_permissions اضافه می‌شود
{
  "new_section": {
    "write": true,
    "approve": true
  }
}
```

### اضافه کردن عملیات جدید:
```python
# در هر بخش قابل اضافه کردن
{
  "sales": {
    "write": true,
    "new_action": true
  }
}
```

### اضافه کردن دسترسی اپلیکیشن جدید:
```python
# در app_permissions اضافه می‌شود
{
  "new_app_permission": true
}
```
