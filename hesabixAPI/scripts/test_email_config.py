#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
اسکریپت تست تنظیمات ایمیل از دیتابیس
این اسکریپت تمام تنظیمات ایمیل را از دیتابیس می‌خواند و اتصال SMTP را تست می‌کند.
"""

import sys
import os
from pathlib import Path

# اضافه کردن مسیر پروژه به sys.path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from sqlalchemy.orm import Session
from adapters.db.session import get_db
from adapters.db.models.email_config import EmailConfig
import smtplib
import socket
import traceback


def print_section(title: str):
    """چاپ عنوان بخش"""
    print("\n" + "=" * 70)
    print(f"  {title}")
    print("=" * 70)


def print_config(config, index: int = None):
    """چاپ اطلاعات یک پیکربندی"""
    prefix = f"[{index}] " if index is not None else ""
    print(f"\n{prefix}📧 پیکربندی: {config.name}")
    print(f"   ID: {config.id}")
    print(f"   میزبان SMTP: {config.smtp_host}")
    print(f"   پورت: {config.smtp_port}")
    print(f"   نام کاربری: {config.smtp_username}")
    print(f"   ایمیل فرستنده: {config.from_email}")
    print(f"   نام فرستنده: {config.from_name}")
    print(f"   استفاده از TLS: {'✓' if config.use_tls else '✗'}")
    print(f"   استفاده از SSL: {'✓' if config.use_ssl else '✗'}")
    print(f"   فعال: {'✓' if config.is_active else '✗'}")
    print(f"   پیش‌فرض: {'✓' if config.is_default else '✗'}")
    print(f"   تاریخ ایجاد: {config.created_at}")
    print(f"   تاریخ به‌روزرسانی: {config.updated_at}")


def safe_str(obj):
    """Safely convert object to string"""
    try:
        if isinstance(obj, bytes):
            return obj.decode('utf-8', errors='replace')
        return str(obj)
    except (UnicodeEncodeError, UnicodeDecodeError):
        try:
            return repr(obj)
        except Exception:
            return "Unable to convert to string"


def test_connection(config):
    """تست اتصال برای یک پیکربندی"""
    print(f"\n🔍 در حال تست اتصال به {config.smtp_host}:{config.smtp_port}...")
    print(f"   نام کاربری: {config.smtp_username}")
    print(f"   رمز عبور: {'*' * len(config.smtp_password)} (طول: {len(config.smtp_password)})")
    
    # بررسی نوع و محتوای رمز عبور
    password_type = type(config.smtp_password).__name__
    password_repr = repr(config.smtp_password)
    print(f"   نوع رمز عبور: {password_type}")
    print(f"   نمایش رمز عبور (repr): {password_repr[:100]}")
    
    try:
        # تست DNS resolution
        try:
            socket.gethostbyname(config.smtp_host)
            print("   ✓ DNS resolution موفق")
        except socket.gaierror as dns_error:
            print(f"   ❌ خطا در DNS: {dns_error}")
            return False
        
        # تست دسترسی به پورت
        try:
            test_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            test_socket.settimeout(5)
            result = test_socket.connect_ex((config.smtp_host, config.smtp_port))
            test_socket.close()
            
            if result != 0:
                print(f"   ❌ پورت {config.smtp_port} در دسترس نیست (کد: {result})")
                return False
            else:
                print(f"   ✓ پورت {config.smtp_port} در دسترس است")
        except Exception as socket_error:
            print(f"   ⚠️  خطا در تست پورت: {socket_error}")
        
        # تست اتصال SMTP
        print(f"   در حال اتصال به SMTP...")
        try:
            if config.use_ssl:
                server = smtplib.SMTP_SSL(config.smtp_host, config.smtp_port, timeout=10)
            else:
                server = smtplib.SMTP(config.smtp_host, config.smtp_port, timeout=10)
                if config.use_tls:
                    server.starttls()
            
            print(f"   در حال احراز هویت...")
            # تست login با مدیریت encoding
            try:
                server.login(config.smtp_username, config.smtp_password)
                server.quit()
                print("✅ اتصال موفق!")
                return True
            except Exception as login_error:
                error_type = type(login_error).__name__
                try:
                    error_msg = str(login_error)
                    print(f"   ❌ خطا در احراز هویت ({error_type}): {error_msg}")
                except UnicodeEncodeError as enc_err:
                    print(f"   ❌ خطا در احراز هویت ({error_type})")
                    print(f"   مشکل encoding در پیام خطا: {enc_err}")
                    print(f"   موقعیت کاراکتر مشکل‌دار: {enc_err.start}-{enc_err.end}")
                    try:
                        safe_msg = safe_str(login_error)
                        print(f"   پیام خطا (safe): {safe_msg}")
                    except Exception as e:
                        print(f"   خطا در safe encoding: {e}")
                return False
                
        except Exception as smtp_error:
            error_type = type(smtp_error).__name__
            try:
                error_msg = str(smtp_error)
                print(f"   ❌ خطا در اتصال SMTP ({error_type}): {error_msg}")
            except UnicodeEncodeError as enc_err:
                print(f"   ❌ خطا در اتصال SMTP ({error_type})")
                print(f"   مشکل encoding در پیام خطا: {enc_err}")
                print(f"   موقعیت کاراکتر مشکل‌دار: {enc_err.start}-{enc_err.end}")
                try:
                    safe_msg = safe_str(smtp_error)
                    print(f"   پیام خطا (safe): {safe_msg}")
                except Exception as e:
                    print(f"   خطا در safe encoding: {e}")
            return False
        
    except Exception as e:
        error_type = type(e).__name__
        print(f"❌ خطا در تست اتصال ({error_type})")
        try:
            error_msg = str(e)
            print(f"   پیام خطا: {error_msg}")
        except UnicodeEncodeError as enc_err:
            print(f"   مشکل encoding در پیام خطا: {enc_err}")
            print(f"   موقعیت کاراکتر مشکل‌دار: {enc_err.start}-{enc_err.end}")
            try:
                safe_msg = safe_str(e)
                print(f"   پیام خطا (safe): {safe_msg}")
            except Exception as e2:
                print(f"   خطا در safe encoding: {e2}")
        print(f"\n📊 Traceback:")
        try:
            traceback.print_exc()
        except UnicodeEncodeError as enc_err:
            print(f"   خطا در نمایش traceback (encoding): {enc_err}")
            import sys
            exc_type, exc_value, exc_traceback = sys.exc_info()
            print(f"   نوع خطا: {exc_type.__name__}")
            try:
                print(f"   مقدار خطا: {safe_str(exc_value)}")
            except Exception:
                print(f"   مقدار خطا: {repr(exc_value)}")
        return False


def main():
    print_section("تست تنظیمات ایمیل از دیتابیس")
    
    # اتصال به دیتابیس
    db: Session = next(get_db())
    
    try:
        # دریافت تمام پیکربندی‌ها مستقیماً از دیتابیس
        print("\n📥 در حال دریافت پیکربندی‌های ایمیل از دیتابیس...")
        configs = db.query(EmailConfig).order_by(EmailConfig.created_at.desc()).all()
        
        if not configs:
            print("\n⚠️  هیچ پیکربندی ایمیلی در دیتابیس یافت نشد!")
            return 1
        
        print(f"\n✅ {len(configs)} پیکربندی ایمیل یافت شد.")
        
        # نمایش تمام پیکربندی‌ها
        print_section("فهرست پیکربندی‌ها")
        for idx, config in enumerate(configs, 1):
            print_config(config, idx)
        
        # تست اتصال برای هر پیکربندی
        print_section("نتایج تست اتصال")
        
        success_count = 0
        failed_count = 0
        
        for idx, config in enumerate(configs, 1):
            print(f"\n{'─' * 70}")
            print(f"تست پیکربندی [{idx}]: {config.name}")
            print(f"{'─' * 70}")
            
            if test_connection(config):
                success_count += 1
            else:
                failed_count += 1
        
        # خلاصه نتایج
        print_section("خلاصه نتایج")
        print(f"\n✅ اتصال موفق: {success_count}")
        print(f"❌ اتصال ناموفق: {failed_count}")
        print(f"📊 کل پیکربندی‌ها: {len(configs)}")
        
        return 0 if success_count > 0 else 1
        
    except Exception as e:
        print(f"\n❌ خطا در اجرای اسکریپت: {e}")
        traceback.print_exc()
        return 1
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
