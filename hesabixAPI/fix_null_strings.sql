-- تصحیح مقادیر '[null]' به NULL در جدول users
UPDATE users SET last_name = NULL WHERE last_name = '[null]';

-- همچنین برای سایر ستون‌های ممکن
UPDATE users SET first_name = NULL WHERE first_name = '[null]';
