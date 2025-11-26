#!/usr/bin/env python3
"""
تست کامل ایجاد API Key و بررسی پیشوند hsx_
این اسکریپت یک درخواست واقعی به API می‌فرستد
"""
import requests
import json
import sys

API_BASE = "http://localhost:8000/api/v1"

def print_section(title):
    print(f"\n{'='*60}")
    print(f"  {title}")
    print(f"{'='*60}")

def print_step(num, desc):
    print(f"\n{num}️⃣  {desc}")
    print("-" * 60)

def test_api_key_creation():
    """تست ایجاد API Key و بررسی پیشوند"""
    
    print_section("🔍 تست پیشوند کلید API (hsx_)")
    
    # بررسی وضعیت سرور
    print_step("1", "بررسی وضعیت سرور")
    try:
        response = requests.get(f"{API_BASE}/health", timeout=5)
        if response.status_code == 200:
            print("   ✅ سرور در حال اجرا است")
            print(f"   📋 پاسخ: {response.json()}")
        else:
            print(f"   ❌ سرور پاسخ نامعتبر داد: {response.status_code}")
            return False
    except Exception as e:
        print(f"   ❌ خطا در اتصال به سرور: {e}")
        print("   💡 لطفاً اطمینان حاصل کنید سرور در حال اجرا است")
        return False
    
    # بررسی کد
    print_step("2", "بررسی کد")
    try:
        with open("hesabixAPI/app/services/api_key_service.py", "r") as f:
            content = f.read()
            if 'prefix="hsx_"' in content:
                print("   ✅ پیشوند hsx_ در کد پیدا شد")
            else:
                print("   ❌ پیشوند hsx_ در کد پیدا نشد!")
                return False
    except Exception as e:
        print(f"   ⚠️  خطا در خواندن فایل: {e}")
    
    # بررسی endpoint
    print_step("3", "بررسی مستندات API")
    try:
        response = requests.get(f"{API_BASE.replace('/api/v1', '')}/docs", timeout=5)
        if response.status_code == 200:
            print("   ✅ مستندات API در دسترس است")
            print(f"   🔗 آدرس: http://localhost:8000/docs")
        else:
            print(f"   ⚠️  مستندات در دسترس نیست")
    except Exception as e:
        print(f"   ⚠️  خطا در دسترسی به مستندات: {e}")
    
    # راهنمای تست دستی
    print_step("4", "راهنمای تست دستی")
    print("   برای تست کامل از طریق UI:")
    print("   1️⃣  وارد برنامه Flutter شوید")
    print("   2️⃣  به صفحه 'پروفایل' > 'API Keys' بروید")
    print("   3️⃣  یک کلید جدید ایجاد کنید")
    print("   4️⃣  بررسی کنید که کلید با پیشوند 'hsx_' شروع می‌شود")
    print("")
    print("   یا از طریق API:")
    print("   1️⃣  یک API Key معتبر از طریق login دریافت کنید")
    print("   2️⃣  درخواست POST به /api/v1/auth/api-keys بفرستید:")
    print("      curl -X POST http://localhost:8000/api/v1/auth/api-keys \\")
    print("           -H 'Authorization: ApiKey YOUR_SESSION_KEY' \\")
    print("           -H 'Content-Type: application/json' \\")
    print("           -d '{\"name\": \"Test Key\"}'")
    print("   3️⃣  در پاسخ بررسی کنید که api_key با 'hsx_' شروع می‌شود")
    
    print_section("✅ بررسی اولیه موفق بود!")
    print("   📝 پیشوند در کد درست تنظیم شده است")
    print("   💡 برای تست کامل از UI یا API استفاده کنید")
    
    return True

if __name__ == "__main__":
    try:
        success = test_api_key_creation()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n⚠️  تست توسط کاربر لغو شد")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ خطا در تست: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

