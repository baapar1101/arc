#!/usr/bin/env python3
"""
Script برای اعطای مجوز اپراتور پشتیبانی به کاربران
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from sqlalchemy import text
from adapters.db.session import get_db
from adapters.db.models.user import User


def grant_operator_permission(user_email: str):
    """اعطای مجوز اپراتور پشتیبانی به کاربر"""
    db = next(get_db())
    
    try:
        # پیدا کردن کاربر
        user = db.query(User).filter(User.email == user_email).first()
        if not user:
            print(f"❌ کاربر با ایمیل {user_email} یافت نشد")
            return False
        
        # دریافت مجوزهای موجود
        app_permissions = user.app_permissions or {}
        
        # اضافه کردن مجوز اپراتور
        app_permissions['support_operator'] = True
        
        # به‌روزرسانی مجوزها
        user.app_permissions = app_permissions
        db.commit()
        
        print(f"✅ مجوز اپراتور پشتیبانی به {user_email} اعطا شد")
        return True
        
    except Exception as e:
        db.rollback()
        print(f"❌ خطا در اعطای مجوز: {e}")
        return False
    finally:
        db.close()


def revoke_operator_permission(user_email: str):
    """لغو مجوز اپراتور پشتیبانی از کاربر"""
    db = next(get_db())
    
    try:
        # پیدا کردن کاربر
        user = db.query(User).filter(User.email == user_email).first()
        if not user:
            print(f"❌ کاربر با ایمیل {user_email} یافت نشد")
            return False
        
        # دریافت مجوزهای موجود
        app_permissions = user.app_permissions or {}
        
        # حذف مجوز اپراتور
        app_permissions['support_operator'] = False
        
        # به‌روزرسانی مجوزها
        user.app_permissions = app_permissions
        db.commit()
        
        print(f"✅ مجوز اپراتور پشتیبانی از {user_email} لغو شد")
        return True
        
    except Exception as e:
        db.rollback()
        print(f"❌ خطا در لغو مجوز: {e}")
        return False
    finally:
        db.close()


def list_operators():
    """لیست اپراتورهای پشتیبانی"""
    db = next(get_db())
    
    try:
        operators = db.query(User).filter(
            text("app_permissions->>'support_operator' = 'true'")
        ).all()
        
        if not operators:
            print("هیچ اپراتور پشتیبانی یافت نشد")
            return
        
        print("اپراتورهای پشتیبانی:")
        for operator in operators:
            print(f"- {operator.email} ({operator.first_name} {operator.last_name})")
            
    except Exception as e:
        print(f"❌ خطا در دریافت لیست اپراتورها: {e}")
    finally:
        db.close()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("استفاده:")
        print("  python grant_operator_permission.py grant <email>")
        print("  python grant_operator_permission.py revoke <email>")
        print("  python grant_operator_permission.py list")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "grant":
        if len(sys.argv) < 3:
            print("❌ ایمیل کاربر را وارد کنید")
            sys.exit(1)
        email = sys.argv[2]
        grant_operator_permission(email)
    elif command == "revoke":
        if len(sys.argv) < 3:
            print("❌ ایمیل کاربر را وارد کنید")
            sys.exit(1)
        email = sys.argv[2]
        revoke_operator_permission(email)
    elif command == "list":
        list_operators()
    else:
        print("❌ دستور نامعتبر")
        sys.exit(1)
