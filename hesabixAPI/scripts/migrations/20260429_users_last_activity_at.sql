-- آخرین فعالیت کاربر (ضربان اپ)
-- PostgreSQL: ADD COLUMN IF NOT EXISTS فقط از نسخهٔ ۱۱ موجود است؛ برای PG قدیمی‌تر از بلاک شرطی استفاده می‌شود.
DO $$
BEGIN
	IF NOT EXISTS (
		SELECT 1
		FROM information_schema.columns
		WHERE table_schema = current_schema()
			AND table_name = 'users'
			AND column_name = 'last_activity_at'
	) THEN
		ALTER TABLE users ADD COLUMN last_activity_at TIMESTAMP WITHOUT TIME ZONE NULL;
	END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_users_last_activity_at ON users (last_activity_at);
