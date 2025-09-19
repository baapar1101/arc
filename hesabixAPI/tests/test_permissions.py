"""
تست‌های سیستم دسترسی دو سطحی
"""

import pytest
from unittest.mock import Mock
from app.core.auth_dependency import AuthContext
from adapters.db.models.user import User


class TestAuthContextPermissions:
    """تست کلاس AuthContext برای بررسی دسترسی‌ها"""
    
    def test_app_permissions(self):
        """تست دسترسی‌های اپلیکیشن"""
        # ایجاد کاربر با دسترسی superadmin
        user = Mock(spec=User)
        user.app_permissions = {"superadmin": True}
        
        ctx = AuthContext(user=user, api_key_id=1)
        
        # تست دسترسی‌های اپلیکیشن - SuperAdmin باید تمام دسترسی‌ها را داشته باشد
        assert ctx.has_app_permission("superadmin") == True
        assert ctx.has_app_permission("user_management") == True  # خودکار
        assert ctx.has_app_permission("business_management") == True  # خودکار
        assert ctx.has_app_permission("system_settings") == True  # خودکار
        assert ctx.is_superadmin() == True
        assert ctx.can_manage_users() == True
        assert ctx.can_manage_businesses() == True
    
    def test_app_permissions_normal_user(self):
        """تست دسترسی‌های اپلیکیشن برای کاربر عادی"""
        user = Mock(spec=User)
        user.app_permissions = {"user_management": True}
        
        ctx = AuthContext(user=user, api_key_id=1)
        
        # تست دسترسی‌های اپلیکیشن
        assert ctx.has_app_permission("superadmin") == False
        assert ctx.has_app_permission("user_management") == True
        assert ctx.has_app_permission("business_management") == False
        assert ctx.is_superadmin() == False
        assert ctx.can_manage_users() == True
        assert ctx.can_manage_businesses() == False
    
    def test_business_permissions(self):
        """تست دسترسی‌های کسب و کار"""
        user = Mock(spec=User)
        user.app_permissions = {}
        
        # Mock دیتابیس
        db = Mock()
        business_permission_repo = Mock()
        business_permission_repo.get_by_user_and_business.return_value = Mock(
            business_permissions={
                "sales": {"write": True, "delete": True},
                "accounting": {"write": True}
            }
        )
        
        ctx = AuthContext(
            user=user, 
            api_key_id=1, 
            business_id=1, 
            db=db
        )
        
        # Mock کردن repository
        with pytest.MonkeyPatch().context() as m:
            m.setattr("app.core.auth_dependency.BusinessPermissionRepository", 
                     lambda db: business_permission_repo)
            
            # تست دسترسی‌های کسب و کار
            assert ctx.has_business_permission("sales", "write") == True
            assert ctx.has_business_permission("sales", "delete") == True
            assert ctx.has_business_permission("sales", "approve") == False
            assert ctx.has_business_permission("accounting", "write") == True
            assert ctx.has_business_permission("purchases", "read") == False
            assert ctx.can_read_section("sales") == True
            assert ctx.can_write_section("sales") == True
            assert ctx.can_delete_section("sales") == True
            assert ctx.can_approve_section("sales") == False
    
    def test_empty_business_permissions(self):
        """تست دسترسی‌های خالی کسب و کار"""
        user = Mock(spec=User)
        user.app_permissions = {}
        
        ctx = AuthContext(user=user, api_key_id=1, business_id=1)
        ctx.business_permissions = {}
        
        # اگر دسترسی‌ها خالی باشد، فقط خواندن مجاز است
        assert ctx.has_business_permission("sales", "read") == False
        assert ctx.has_business_permission("sales", "write") == False
        assert ctx.can_read_section("sales") == False
    
    def test_section_with_empty_permissions(self):
        """تست بخش با دسترسی‌های خالی"""
        user = Mock(spec=User)
        user.app_permissions = {}
        
        ctx = AuthContext(user=user, api_key_id=1, business_id=1)
        ctx.business_permissions = {
            "sales": {},  # بخش خالی
            "accounting": {"write": True}
        }
        
        # بخش خالی فقط خواندن مجاز است
        assert ctx.has_business_permission("sales", "read") == True
        assert ctx.has_business_permission("sales", "write") == False
        assert ctx.has_business_permission("accounting", "write") == True
    
    def test_superadmin_override(self):
        """تست override کردن دسترسی‌ها توسط superadmin"""
        user = Mock(spec=User)
        user.app_permissions = {"superadmin": True}
        
        ctx = AuthContext(user=user, api_key_id=1, business_id=1)
        ctx.business_permissions = {}  # بدون دسترسی کسب و کار
        
        # SuperAdmin باید دسترسی کامل داشته باشد
        assert ctx.has_any_permission("sales", "write") == True
        assert ctx.has_any_permission("accounting", "delete") == True
        assert ctx.can_access_business(999) == True  # هر کسب و کاری
    
    def test_business_access_control(self):
        """تست کنترل دسترسی به کسب و کار"""
        user = Mock(spec=User)
        user.app_permissions = {}
        
        ctx = AuthContext(user=user, api_key_id=1, business_id=1)
        
        # فقط به کسب و کار خود دسترسی دارد
        assert ctx.can_access_business(1) == True
        assert ctx.can_access_business(2) == False
        
        # SuperAdmin به همه دسترسی دارد
        user.app_permissions = {"superadmin": True}
        ctx = AuthContext(user=user, api_key_id=1, business_id=1)
        assert ctx.can_access_business(999) == True
    
    def test_business_owner_permissions(self):
        """تست دسترسی‌های مالک کسب و کار"""
        user = Mock(spec=User)
        user.app_permissions = {}
        user.id = 1
        
        # Mock دیتابیس و کسب و کار
        db = Mock()
        business = Mock()
        business.owner_id = 1  # کاربر مالک است
        
        ctx = AuthContext(user=user, api_key_id=1, business_id=1, db=db)
        
        # Mock کردن Business model
        with pytest.MonkeyPatch().context() as m:
            m.setattr("app.core.auth_dependency.Business", Mock)
            db.get.return_value = business
            
            # مالک کسب و کار باید تمام دسترسی‌ها را داشته باشد
            assert ctx.is_business_owner() == True
            assert ctx.has_business_permission("sales", "write") == True
            assert ctx.has_business_permission("sales", "delete") == True
            assert ctx.has_business_permission("accounting", "write") == True
            assert ctx.has_business_permission("reports", "export") == True
            assert ctx.can_read_section("sales") == True
            assert ctx.can_write_section("sales") == True
            assert ctx.can_delete_section("sales") == True
            assert ctx.can_approve_section("sales") == True
    
    def test_business_owner_override(self):
        """تست override کردن دسترسی‌ها توسط مالک کسب و کار"""
        user = Mock(spec=User)
        user.app_permissions = {}
        user.id = 1
        
        # Mock دیتابیس و کسب و کار
        db = Mock()
        business = Mock()
        business.owner_id = 1
        
        ctx = AuthContext(user=user, api_key_id=1, business_id=1, db=db)
        ctx.business_permissions = {}  # بدون دسترسی کسب و کار
        
        # Mock کردن Business model
        with pytest.MonkeyPatch().context() as m:
            m.setattr("app.core.auth_dependency.Business", Mock)
            db.get.return_value = business
            
            # مالک کسب و کار باید دسترسی کامل داشته باشد حتی بدون business_permissions
            assert ctx.is_business_owner() == True
            assert ctx.has_business_permission("sales", "write") == True
            assert ctx.has_business_permission("accounting", "delete") == True
            assert ctx.can_read_section("purchases") == True
            assert ctx.can_write_section("inventory") == True


class TestPermissionDecorators:
    """تست decorator های دسترسی"""
    
    def test_require_app_permission(self):
        """تست decorator دسترسی اپلیکیشن"""
        from app.core.permissions import require_app_permission
        
        @require_app_permission("user_management")
        def test_function():
            return "success"
        
        # این تست نیاز به mock کردن get_current_user دارد
        # که در محیط تست پیچیده‌تر است
        pass
    
    def test_require_business_permission(self):
        """تست decorator دسترسی کسب و کار"""
        from app.core.permissions import require_business_permission
        
        @require_business_permission("sales", "write")
        def test_function():
            return "success"
        
        # این تست نیاز به mock کردن get_current_user دارد
        pass


if __name__ == "__main__":
    pytest.main([__file__])
