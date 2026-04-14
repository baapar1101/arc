# نتایج تست اسکریپت Migration

## 📋 خلاصه

✅ **اسکریپت migration با موفقیت ایجاد شد**

## ✅ تست‌های انجام شده

### 1. بررسی ساختار اسکریپت
- ✅ Import ها درست هستند
- ✅ کلاس‌ها و توابع تعریف شده‌اند
- ✅ Argument parser کار می‌کند
- ✅ Help message نمایش داده می‌شود

### 2. تست اتصال PostgreSQL
- ✅ اتصال به PostgreSQL موفق است
- ✅ تعداد جداول: 92 جدول
- ✅ Connection string با quote_plus درست کار می‌کند

### 3. تست اتصال MySQL
- ⚠️ pymysql نصب نیست (نیاز به نصب دارد)
- ⚠️ برای تست کامل نیاز به نصب pymysql داریم

## 📝 نکات مهم

### نیازمندی‌ها:
1. **pymysql** باید نصب شود:
   ```bash
   pip install pymysql
   # یا در virtualenv
   pip install pymysql
   ```

2. **psycopg2-binary** (قبلاً نصب شده است)

### تنظیمات پیش‌فرض:
- **MySQL**: 185.8.172.57:3306/hesabixpy (root/136431)
- **PostgreSQL**: localhost:5432/hesabix (hesabix/@@babaK24055)

## 🚀 نحوه اجرا

### قبل از اجرا:
1. نصب pymysql:
   ```bash
   pip install pymysql
   ```

2. Backup از PostgreSQL:
   ```bash
   pg_dump -U hesabix -d hesabix -h localhost -F c -f backup_before_migration.dump
   ```

### اجرای migration:
```bash
cd /var/www/arc/hesabixAPI
python3 scripts/migrate_mysql_to_postgresql.py
```

### اجرا با تنظیمات سفارشی:
```bash
python3 scripts/migrate_mysql_to_postgresql.py \
    --mysql-host 185.8.172.57 \
    --mysql-user root \
    --mysql-password 136431 \
    --postgres-password '@@babaK24055' \
    --batch-size 1000
```

## ⚠️ هشدارها

1. **Seed Data**: به صورت پیش‌فرض seed data ها از PostgreSQL پاک می‌شوند
2. **Backup**: حتماً قبل از اجرا backup بگیرید
3. **Network**: در صورت قطع ارتباط، checkpoint ذخیره می‌شود
4. **Time**: برای حجم ~0.5GB ممکن است 1-3 ساعت زمان ببرد

## 📊 ویژگی‌های اسکریپت

✅ پاک‌سازی Seed Data  
✅ سیستم Checkpoint/Resume  
✅ تبدیل نوع داده‌ها  
✅ مدیریت Foreign Keys  
✅ پردازش Batch  
✅ Skip کردن alembic_version  
✅ Transaction Safety  
✅ Error Handling  
✅ Progress Reporting  

## 🔄 Checkpoint

اسکریپت وضعیت را در فایل `migration_checkpoint.json` ذخیره می‌کند.

برای شروع از ابتدا:
```bash
python3 scripts/migrate_mysql_to_postgresql.py --clear-checkpoint
```

## 📞 پشتیبانی

در صورت بروز مشکل، فایل checkpoint را بررسی کنید و لاگ‌ها را چک کنید.



