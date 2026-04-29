-- آخرین فعالیت کاربر (ضربان اپ) — PostgreSQL؛ اجرای دستی روی دیتابیس
ALTER TABLE users
	ADD COLUMN IF NOT EXISTS last_activity_at TIMESTAMP NULL;

CREATE INDEX IF NOT EXISTS ix_users_last_activity_at ON users (last_activity_at);
