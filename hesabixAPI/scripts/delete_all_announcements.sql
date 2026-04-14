-- اسکریپت SQL برای حذف تمام اعلان‌های موجود در دیتابیس
-- استفاده: mysql -u USERNAME -p DATABASE_NAME < scripts/delete_all_announcements.sql

-- نمایش تعداد اعلان‌های موجود قبل از حذف
SELECT 'تعداد اعلان‌های موجود قبل از حذف:' as info;
SELECT COUNT(*) as announcements_count FROM announcements;
SELECT COUNT(*) as user_announcements_count FROM user_announcements;

-- حذف تمام رکوردهای user_announcements (باید قبل از announcements حذف شوند به دلیل foreign key)
DELETE FROM user_announcements;

-- حذف تمام رکوردهای announcements
DELETE FROM announcements;

-- نمایش تعداد اعلان‌های باقی‌مانده بعد از حذف
SELECT 'تعداد اعلان‌های باقی‌مانده بعد از حذف:' as info;
SELECT COUNT(*) as remaining_announcements FROM announcements;
SELECT COUNT(*) as remaining_user_announcements FROM user_announcements;

SELECT '✅ تمام اعلان‌ها حذف شدند!' as result;




