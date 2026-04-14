#!/usr/bin/env python3
"""
اسکریپت بررسی کسب و کارهای یک کاربر در دیتابیس hesabixOld
"""

import sys
import os
import argparse

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker


def check_user_businesses(email: str, db_name: str = "hesabixOld",
                          db_user: str = "root", db_password: str = "136431",
                          db_host: str = "localhost", db_port: int = 3306):
    """بررسی کسب و کارهای یک کاربر"""
    
    # اتصال به دیتابیس
    dsn = f"mysql+pymysql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"
    engine = create_engine(
        dsn, 
        echo=False, 
        pool_pre_ping=True,
        connect_args={
            "connect_timeout": 60,
            "read_timeout": 300,
            "write_timeout": 300,
            "charset": "utf8mb4"
        }
    )
    db = sessionmaker(bind=engine)()
    
    try:
        # پیدا کردن کاربر با ایمیل
        query = text("""
            SELECT id, email, full_name, mobile, active
            FROM user
            WHERE email = :email
            LIMIT 1
        """)
        
        user_result = db.execute(query, {"email": email}).fetchone()
        
        if not user_result:
            print(f"❌ کاربری با ایمیل {email} یافت نشد.")
            return
        
        user_id = user_result[0]
        user_email = user_result[1]
        user_full_name = user_result[2] or "نامشخص"
        user_mobile = user_result[3] or "نامشخص"
        user_active = "فعال" if user_result[4] == 1 else "غیرفعال"
        
        print(f"{'='*60}")
        print(f"اطلاعات کاربر:")
        print(f"{'='*60}")
        print(f"شناسه: {user_id}")
        print(f"ایمیل: {user_email}")
        print(f"نام: {user_full_name}")
        print(f"موبایل: {user_mobile}")
        print(f"وضعیت: {user_active}")
        print(f"{'='*60}\n")
        
        # کسب و کارهایی که کاربر مالک آن‌ها است
        query = text("""
            SELECT 
                b.id,
                b.name,
                b.legal_name,
                b.type,
                b.field,
                b.mobile,
                b.tel,
                b.address
            FROM business b
            WHERE b.owner_id = :user_id
            ORDER BY b.id ASC
        """)
        
        owned_businesses = db.execute(query, {"user_id": user_id}).fetchall()
        
        print(f"{'='*60}")
        print(f"کسب و کارهایی که کاربر مالک آن‌ها است ({len(owned_businesses)} مورد):")
        print(f"{'='*60}")
        
        if owned_businesses:
            for idx, business in enumerate(owned_businesses, 1):
                print(f"\n{idx}. شناسه: {business[0]}")
                print(f"   نام: {business[1]}")
                if business[2]:
                    print(f"   نام قانونی: {business[2]}")
                print(f"   نوع: {business[3] or 'نامشخص'}")
                print(f"   زمینه: {business[4] or 'نامشخص'}")
                if business[5]:
                    print(f"   موبایل: {business[5]}")
                if business[6]:
                    print(f"   تلفن: {business[6]}")
                if business[7]:
                    print(f"   آدرس: {business[7]}")
        else:
            print("   هیچ کسب و کاری یافت نشد.")
        
        print(f"\n{'='*60}")
        
        # کسب و کارهایی که کاربر عضو آن‌ها است (نه مالک)
        query = text("""
            SELECT 
                b.id,
                b.name,
                b.legal_name,
                b.type,
                b.field,
                b.mobile,
                b.tel,
                b.address,
                p.owner as is_owner,
                p.settings,
                p.person,
                p.commodity,
                p.sell,
                p.buy
            FROM permission p
            INNER JOIN business b ON p.bid_id = b.id
            WHERE p.user_id = :user_id
            ORDER BY b.id ASC
        """)
        
        member_businesses = db.execute(query, {"user_id": user_id}).fetchall()
        
        # فیلتر کردن فقط کسب و کارهایی که کاربر مالک نیست (owner = 0)
        member_only_businesses = [b for b in member_businesses if b[8] == 0]
        
        print(f"کسب و کارهایی که کاربر عضو آن‌ها است ({len(member_only_businesses)} مورد):")
        print(f"{'='*60}")
        
        if member_only_businesses:
            for idx, business in enumerate(member_only_businesses, 1):
                print(f"\n{idx}. شناسه: {business[0]}")
                print(f"   نام: {business[1]}")
                if business[2]:
                    print(f"   نام قانونی: {business[2]}")
                print(f"   نوع: {business[3] or 'نامشخص'}")
                print(f"   زمینه: {business[4] or 'نامشخص'}")
                if business[5]:
                    print(f"   موبایل: {business[5]}")
                if business[6]:
                    print(f"   تلفن: {business[6]}")
                if business[7]:
                    print(f"   آدرس: {business[7]}")
                
                # نمایش برخی دسترسی‌ها
                permissions = []
                if business[9] == 1:
                    permissions.append("تنظیمات")
                if business[10] == 1:
                    permissions.append("اشخاص")
                if business[11] == 1:
                    permissions.append("کالا")
                if business[12] == 1:
                    permissions.append("فروش")
                if business[13] == 1:
                    permissions.append("خرید")
                
                if permissions:
                    print(f"   دسترسی‌ها: {', '.join(permissions)}")
        else:
            print("   هیچ کسب و کاری یافت نشد.")
        
        print(f"\n{'='*60}")
        print(f"خلاصه:")
        print(f"{'='*60}")
        print(f"تعداد کسب و کارهای مالک: {len(owned_businesses)}")
        print(f"تعداد کسب و کارهای عضو: {len(member_only_businesses)}")
        print(f"جمع کل: {len(owned_businesses) + len(member_only_businesses)}")
        print(f"{'='*60}")
        
    except Exception as e:
        print(f"❌ خطا: {str(e)}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()


def main():
    parser = argparse.ArgumentParser(description="بررسی کسب و کارهای یک کاربر")
    parser.add_argument("--email", required=True, help="ایمیل کاربر")
    parser.add_argument("--db", default="hesabixOld", help="نام دیتابیس")
    parser.add_argument("--db-user", default="root", help="نام کاربری دیتابیس")
    parser.add_argument("--db-password", default="136431", help="رمز عبور دیتابیس")
    parser.add_argument("--db-host", default="localhost", help="آدرس دیتابیس")
    parser.add_argument("--db-port", type=int, default=3306, help="پورت دیتابیس")
    
    args = parser.parse_args()
    
    check_user_businesses(
        email=args.email,
        db_name=args.db,
        db_user=args.db_user,
        db_password=args.db_password,
        db_host=args.db_host,
        db_port=args.db_port
    )


if __name__ == "__main__":
    main()

