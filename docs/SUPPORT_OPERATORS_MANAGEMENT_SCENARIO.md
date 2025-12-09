# سناریوی پیاده‌سازی: مدیریت اپراتورهای پشتیبانی

## 📋 خلاصه اجرایی

این سند سناریوی کامل پیاده‌سازی بخش مدیریت App-Level Permissions (با تمرکز روی اپراتورهای پشتیبانی) را شامل می‌شود.

---

## 🎯 اهداف

1. **مدیریت مرکزی:** ایجاد یک پنل مدیریتی برای تخصیص و لغو permissions در سطح اپلیکیشن
2. **امنیت:** فقط SuperAdmin بتواند App Permissions را مدیریت کند
3. **ساده و کاربرپسند:** UI ساده و واضح برای مدیریت نقش‌ها
4. **قابل توسعه:** طراحی به گونه‌ای که بتوان permissions جدید اضافه کرد

---

## 🏗️ معماری کلی

```
┌─────────────────────────────────────────────────────────────┐
│                   SuperAdmin Panel (UI)                     │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  User Management                                       │ │
│  │  ┌──────────────────────────────────────────────────┐ │ │
│  │  │  • List Users                                    │ │ │
│  │  │  • View User Details                            │ │ │
│  │  │  • Manage App Permissions ← NEW!               │ │ │
│  │  │    - Support Operator                           │ │ │
│  │  │    - System Settings                            │ │ │
│  │  │    - User Management                            │ │ │
│  │  │    - Business Management                        │ │ │
│  │  └──────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                          ↕ API Calls
┌─────────────────────────────────────────────────────────────┐
│                      Backend API                            │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  /api/v1/admin/users/{user_id}/app-permissions         │ │
│  │    • GET: دریافت permissions کاربر                    │ │
│  │    • PUT: به‌روزرسانی permissions کاربر ← NEW!        │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  /api/v1/admin/operators ← NEW!                        │ │
│  │    • GET: لیست اپراتورهای پشتیبانی                    │ │
│  │    • POST: اضافه کردن اپراتور                         │ │
│  │    • DELETE: حذف اپراتور                              │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## 📍 فاز 1: Backend API (اولویت بالا)

### 1.1 ایجاد Endpoint های جدید

**فایل:** `hesabixAPI/adapters/api/v1/admin/users_permissions.py` (جدید)

```python
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from typing import Dict, Any, List
from pydantic import BaseModel, Field

from adapters.db.session import get_db
from adapters.db.models.user import User
from adapters.db.repositories.user_repo import UserRepository
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_app_permission
from app.core.responses import success_response

router = APIRouter(
    prefix="/admin/users",
    tags=["مدیریت کاربران", "مدیریت سیستم"]
)


# ========== Schemas ==========

class AppPermissionsResponse(BaseModel):
    """پاسخ دریافت App Permissions"""
    user_id: int
    email: str
    app_permissions: Dict[str, bool] = Field(default_factory=dict)
    
    class Config:
        from_attributes = True


class UpdateAppPermissionsRequest(BaseModel):
    """درخواست به‌روزرسانی App Permissions"""
    permissions: Dict[str, bool] = Field(
        ..., 
        description="دسترسی‌های سطح اپلیکیشن (مثال: {'support_operator': true, 'system_settings': false})"
    )
    
    class Config:
        json_schema_extra = {
            "example": {
                "permissions": {
                    "support_operator": True,
                    "system_settings": False,
                    "user_management": False,
                    "business_management": False
                }
            }
        }


class OperatorSummary(BaseModel):
    """خلاصه اطلاعات اپراتور"""
    id: int
    email: str
    first_name: str | None
    last_name: str | None
    full_name: str | None
    telegram_chat_id: str | None
    is_active: bool
    created_at: str
    
    class Config:
        from_attributes = True


# ========== Endpoints ==========

@router.get(
    "/{user_id}/app-permissions",
    summary="دریافت App Permissions کاربر",
    description="دریافت دسترسی‌های سطح اپلیکیشن یک کاربر. نیاز به مجوز SuperAdmin دارد.",
    response_model=AppPermissionsResponse
)
@require_app_permission("superadmin")
async def get_user_app_permissions(
    user_id: int,
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """دریافت App Permissions کاربر"""
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")
    
    return success_response(
        data={
            "user_id": user.id,
            "email": user.email,
            "app_permissions": user.app_permissions or {}
        },
        request=request
    )


@router.put(
    "/{user_id}/app-permissions",
    summary="به‌روزرسانی App Permissions کاربر",
    description="به‌روزرسانی دسترسی‌های سطح اپلیکیشن یک کاربر. فقط SuperAdmin.",
)
@require_app_permission("superadmin")
async def update_user_app_permissions(
    user_id: int,
    permissions_request: UpdateAppPermissionsRequest,
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """به‌روزرسانی App Permissions کاربر"""
    
    # بررسی وجود کاربر
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")
    
    # جلوگیری از تغییر permissions خودش
    if user.id == ctx.get_user_id():
        raise HTTPException(
            status_code=403, 
            detail="شما نمی‌توانید دسترسی‌های خود را تغییر دهید"
        )
    
    # فیلتر کردن فقط permissions معتبر
    valid_permissions = {
        "superadmin",
        "support_operator", 
        "system_settings",
        "user_management",
        "business_management"
    }
    
    # فقط permissions که true هستند را نگه می‌داریم
    new_permissions = {
        k: v for k, v in permissions_request.permissions.items()
        if k in valid_permissions and v is True
    }
    
    # به‌روزرسانی
    user.app_permissions = new_permissions
    db.commit()
    db.refresh(user)
    
    return success_response(
        data={
            "user_id": user.id,
            "email": user.email,
            "app_permissions": user.app_permissions or {}
        },
        request=request,
        message="دسترسی‌ها با موفقیت به‌روزرسانی شد"
    )


# ========== Operator Management Endpoints ==========

@router.get(
    "/operators",
    summary="لیست اپراتورهای پشتیبانی",
    description="دریافت لیست تمام اپراتورهای پشتیبانی فعال",
    response_model=List[OperatorSummary]
)
@require_app_permission("superadmin")
async def list_support_operators(
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """لیست اپراتورهای پشتیبانی"""
    user_repo = UserRepository(db)
    operators = user_repo.get_support_operators()
    
    operators_data = []
    for op in operators:
        full_name = None
        if op.first_name or op.last_name:
            parts = [p for p in [op.first_name, op.last_name] if p]
            full_name = " ".join(parts) if parts else None
        
        operators_data.append({
            "id": op.id,
            "email": op.email,
            "first_name": op.first_name,
            "last_name": op.last_name,
            "full_name": full_name,
            "telegram_chat_id": op.telegram_chat_id,
            "is_active": op.is_active,
            "created_at": op.created_at.isoformat()
        })
    
    return success_response(
        data={"items": operators_data, "total": len(operators_data)},
        request=request
    )


@router.post(
    "/operators/{user_id}",
    summary="اضافه کردن اپراتور پشتیبانی",
    description="افزودن مجوز اپراتور پشتیبانی به یک کاربر"
)
@require_app_permission("superadmin")
async def add_support_operator(
    user_id: int,
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """اضافه کردن اپراتور پشتیبانی"""
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")
    
    # اضافه کردن permission
    permissions = user.app_permissions or {}
    permissions['support_operator'] = True
    user.app_permissions = permissions
    
    db.commit()
    db.refresh(user)
    
    return success_response(
        data={"user_id": user.id, "email": user.email},
        request=request,
        message="کاربر به عنوان اپراتور پشتیبانی اضافه شد"
    )


@router.delete(
    "/operators/{user_id}",
    summary="حذف اپراتور پشتیبانی",
    description="لغو مجوز اپراتور پشتیبانی از یک کاربر"
)
@require_app_permission("superadmin")
async def remove_support_operator(
    user_id: int,
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """حذف اپراتور پشتیبانی"""
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")
    
    # حذف permission
    if user.app_permissions and 'support_operator' in user.app_permissions:
        permissions = user.app_permissions.copy()
        del permissions['support_operator']
        user.app_permissions = permissions if permissions else {}
        
        db.commit()
        db.refresh(user)
    
    return success_response(
        data={"user_id": user.id, "email": user.email},
        request=request,
        message="مجوز اپراتور پشتیبانی لغو شد"
    )
```

### 1.2 ثبت Router جدید

**فایل:** `hesabixAPI/app/main.py`

```python
# اضافه کردن import
from adapters.api.v1.admin import users_permissions

# در تابع create_app():
app.include_router(
    users_permissions.router,
    prefix="/api/v1",
)
```

### 1.3 تست API

```bash
# دریافت App Permissions کاربر
curl -X GET "http://localhost:8000/api/v1/admin/users/1/app-permissions" \
  -H "Authorization: Bearer YOUR_TOKEN"

# به‌روزرسانی App Permissions
curl -X PUT "http://localhost:8000/api/v1/admin/users/1/app-permissions" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "permissions": {
      "support_operator": true,
      "system_settings": false
    }
  }'

# لیست اپراتورها
curl -X GET "http://localhost:8000/api/v1/admin/users/operators" \
  -H "Authorization: Bearer YOUR_TOKEN"

# اضافه کردن اپراتور
curl -X POST "http://localhost:8000/api/v1/admin/users/operators/1" \
  -H "Authorization: Bearer YOUR_TOKEN"

# حذف اپراتور
curl -X DELETE "http://localhost:8000/api/v1/admin/users/operators/1" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## 📍 فاز 2: Frontend UI (اولویت متوسط)

### 2.1 سرویس API در Flutter

**فایل:** `hesabixUI/hesabix_ui/lib/services/admin_users_service.dart` (جدید)

```dart
import '../core/api_client.dart';

class AdminUsersService {
  final ApiClient _api;
  AdminUsersService(this._api);

  /// دریافت App Permissions کاربر
  Future<Map<String, dynamic>> getUserAppPermissions(int userId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/users/$userId/app-permissions'
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// به‌روزرسانی App Permissions کاربر
  Future<Map<String, dynamic>> updateUserAppPermissions(
    int userId,
    Map<String, bool> permissions
  ) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/users/$userId/app-permissions',
      data: {'permissions': permissions}
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// لیست اپراتورهای پشتیبانی
  Future<List<Map<String, dynamic>>> listSupportOperators() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/users/operators'
    );
    final data = res.data?['data'] as Map? ?? {};
    final items = data['items'] as List? ?? [];
    return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  /// اضافه کردن اپراتور
  Future<void> addSupportOperator(int userId) async {
    await _api.post(
      '/api/v1/admin/users/operators/$userId',
    );
  }

  /// حذف اپراتور
  Future<void> removeSupportOperator(int userId) async {
    await _api.delete(
      '/api/v1/admin/users/operators/$userId',
    );
  }
}
```

### 2.2 صفحه مدیریت دسترسی‌ها

**فایل:** `hesabixUI/hesabix_ui/lib/pages/admin/user_app_permissions_page.dart` (جدید)

```dart
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/admin_users_service.dart';

class UserAppPermissionsPage extends StatefulWidget {
  final int userId;
  final String userEmail;

  const UserAppPermissionsPage({
    super.key,
    required this.userId,
    required this.userEmail,
  });

  @override
  State<UserAppPermissionsPage> createState() => _UserAppPermissionsPageState();
}

class _UserAppPermissionsPageState extends State<UserAppPermissionsPage> {
  final _service = AdminUsersService(ApiClient());
  bool _isLoading = true;
  Map<String, bool> _permissions = {};

  final Map<String, String> _permissionLabels = {
    'support_operator': 'اپراتور پشتیبانی',
    'system_settings': 'تنظیمات سیستم',
    'user_management': 'مدیریت کاربران',
    'business_management': 'مدیریت کسب‌وکارها',
  };

  final Map<String, String> _permissionDescriptions = {
    'support_operator': 'دسترسی به پنل پشتیبانی و مدیریت تیکت‌ها',
    'system_settings': 'دسترسی به تنظیمات سیستم',
    'user_management': 'مدیریت کاربران در سطح اپلیکیشن',
    'business_management': 'مدیریت کسب‌وکارها',
  };

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    setState(() => _isLoading = true);
    
    try {
      final data = await _service.getUserAppPermissions(widget.userId);
      final appPerms = data['app_permissions'] as Map? ?? {};
      
      // Initialize all permissions
      final permissions = <String, bool>{};
      for (var key in _permissionLabels.keys) {
        permissions[key] = appPerms[key] == true;
      }
      
      setState(() {
        _permissions = permissions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در بارگذاری دسترسی‌ها: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _savePermissions() async {
    try {
      await _service.updateUserAppPermissions(widget.userId, _permissions);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('دسترسی‌ها با موفقیت ذخیره شد'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در ذخیره دسترسی‌ها: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت دسترسی‌ها'),
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _savePermissions,
            icon: const Icon(Icons.save, color: Colors.white),
            label: const Text('ذخیره', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Info Card
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(widget.userEmail[0].toUpperCase()),
                      ),
                      title: Text(widget.userEmail),
                      subtitle: const Text('مدیریت دسترسی‌های سطح اپلیکیشن'),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Permissions List
                  const Text(
                    'دسترسی‌های سطح اپلیکیشن',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  ..._permissionLabels.entries.map((entry) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: SwitchListTile(
                        title: Text(entry.value),
                        subtitle: Text(_permissionDescriptions[entry.key] ?? ''),
                        value: _permissions[entry.key] ?? false,
                        onChanged: (value) {
                          setState(() {
                            _permissions[entry.key] = value;
                          });
                        },
                        secondary: Icon(
                          _getIconForPermission(entry.key),
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }

  IconData _getIconForPermission(String permission) {
    switch (permission) {
      case 'support_operator':
        return Icons.support_agent;
      case 'system_settings':
        return Icons.settings;
      case 'user_management':
        return Icons.people;
      case 'business_management':
        return Icons.business;
      default:
        return Icons.check_circle;
    }
  }
}
```

### 2.3 صفحه لیست اپراتورها

**فایل:** `hesabixUI/hesabix_ui/lib/pages/admin/support_operators_page.dart` (جدید)

```dart
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/admin_users_service.dart';

class SupportOperatorsPage extends StatefulWidget {
  const SupportOperatorsPage({super.key});

  @override
  State<SupportOperatorsPage> createState() => _SupportOperatorsPageState();
}

class _SupportOperatorsPageState extends State<SupportOperatorsPage> {
  final _service = AdminUsersService(ApiClient());
  bool _isLoading = true;
  List<Map<String, dynamic>> _operators = [];

  @override
  void initState() {
    super.initState();
    _loadOperators();
  }

  Future<void> _loadOperators() async {
    setState(() => _isLoading = true);
    
    try {
      final operators = await _service.listSupportOperators();
      setState(() {
        _operators = operators;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در بارگذاری لیست اپراتورها: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeOperator(int userId, String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف اپراتور'),
        content: Text('آیا مطمئن هستید که می‌خواهید دسترسی اپراتور را از $email لغو کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _service.removeSupportOperator(userId);
        await _loadOperators();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('دسترسی اپراتور با موفقیت لغو شد'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطا در حذف اپراتور: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اپراتورهای پشتیبانی'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOperators,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _operators.isEmpty
              ? const Center(
                  child: Text('هیچ اپراتور پشتیبانی یافت نشد'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _operators.length,
                  itemBuilder: (context, index) {
                    final operator = _operators[index];
                    final fullName = operator['full_name'] as String?;
                    final email = operator['email'] as String;
                    final telegramId = operator['telegram_chat_id'] as String?;
                    final isActive = operator['is_active'] as bool? ?? false;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isActive
                              ? Colors.green
                              : Colors.grey,
                          child: Icon(
                            Icons.support_agent,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(fullName ?? email),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (fullName != null) Text(email),
                            if (telegramId != null)
                              Row(
                                children: [
                                  const Icon(Icons.telegram, size: 16, color: Colors.blue),
                                  const SizedBox(width: 4),
                                  Text('متصل به تلگرام'),
                                ],
                              ),
                            if (!isActive)
                              const Text(
                                'غیرفعال',
                                style: TextStyle(color: Colors.red),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeOperator(
                            operator['id'] as int,
                            email,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
```

### 2.4 افزودن به منوی تنظیمات

**فایل:** `hesabixUI/hesabix_ui/lib/pages/system_settings/services/settings_categorization_service.dart`

```dart
// در بخش items دسته 'users_businesses' (خط 154)، اضافه کنید:

SettingsItem(
  id: 'support_operators',
  title: 'settingsSupportOperators',
  description: 'settingsSupportOperatorsDescription',
  icon: Icons.support_agent_outlined,
  color: const Color(0xFFE91E63),
  route: '/user/profile/system-settings/support-operators',
  categoryId: 'users_businesses',
  order: 3,
),
```

### 2.5 افزودن Route ها

**فایل:** `hesabixUI/hesabix_ui/lib/main.dart`

```dart
// در بخش system-settings routes
GoRoute(
  path: 'support-operators',
  name: 'system_settings_support_operators',
  builder: (context, state) {
    return const SupportOperatorsPage();
  },
),
```

---

## 📍 فاز 3: اضافه کردن به صفحه لیست کاربران (اولویت پایین)

در صفحه لیست کاربران (`/api/v1/users`) می‌توانید یک دکمه "مدیریت دسترسی‌ها" اضافه کنید که به صفحه `UserAppPermissionsPage` هدایت کند.

---

## 🔒 نکات امنیتی

1. **فقط SuperAdmin:** تمام endpoint ها باید با `@require_app_permission("superadmin")` محافظت شوند
2. **جلوگیری از خودکاری:** کاربر نباید بتواند permissions خودش را تغییر دهد
3. **Audit Log:** تغییرات permissions باید در activity_logs ثبت شوند
4. **Validation:** فقط permissions معتبر باید پذیرفته شوند

---

## 📊 اولویت‌بندی پیاده‌سازی

### اولویت 1 (ضروری - همین حالا):
1. ✅ Backend API endpoints برای مدیریت App Permissions
2. ✅ تست کامل API ها

### اولویت 2 (مهم - هفته آینده):
3. ✅ UI صفحه مدیریت دسترسی‌ها
4. ✅ UI صفحه لیست اپراتورها
5. ✅ اتصال به منوی تنظیمات

### اولویت 3 (خوب است داشته باشیم - ماه آینده):
6. ⬜ Audit logging برای تغییرات
7. ⬜ یکپارچه‌سازی با صفحه لیست کاربران
8. ⬜ فیلتر و جستجو در لیست اپراتورها

---

## ✅ Checklist پیاده‌سازی

### Backend:
- [ ] ایجاد فایل `users_permissions.py`
- [ ] اضافه کردن Schemas (Pydantic models)
- [ ] پیاده‌سازی endpoint های CRUD
- [ ] ثبت router در `main.py`
- [ ] تست با Postman/curl
- [ ] نوشتن Unit Tests

### Frontend:
- [ ] ایجاد `admin_users_service.dart`
- [ ] پیاده‌سازی `UserAppPermissionsPage`
- [ ] پیاده‌سازی `SupportOperatorsPage`
- [ ] افزودن به `settings_categorization_service.dart`
- [ ] افزودن routes
- [ ] افزودن translations
- [ ] تست در محیط توسعه

### Documentation:
- [ ] به‌روزرسانی `PERMISSIONS_SYSTEM.md`
- [ ] نوشتن مستندات API
- [ ] نوشتن راهنمای کاربر

---

## 🚀 نحوه استفاده بعد از پیاده‌سازی

### برای SuperAdmin:

1. **افزودن اپراتور:**
   - وارد System Settings > Support Operators شوید
   - روی "افزودن اپراتور" کلیک کنید
   - کاربر مورد نظر را انتخاب کنید

2. **مدیریت دسترسی‌ها:**
   - وارد System Settings > User Management شوید
   - روی کاربر مورد نظر کلیک کنید
   - "مدیریت دسترسی‌ها" را انتخاب کنید
   - دسترسی‌های مورد نظر را فعال/غیرفعال کنید
   - ذخیره کنید

3. **حذف اپراتور:**
   - وارد System Settings > Support Operators شوید
   - روی دکمه حذف کنار نام اپراتور کلیک کنید
   - تأیید کنید

---

## 📞 پشتیبانی و سوالات

در صورت بروز مشکل یا سوال:
- مستندات API: `/docs` (Swagger UI)
- لاگ‌های سیستم: `journalctl -u hesabix-api -f`
- لاگ‌های اپلیکیشن: فایل‌های log در `hesabixAPI/logs/`

---

**نکته مهم:** این سناریو قابل توسعه است و می‌توان permissions دیگری نیز به همین روش اضافه کرد.



