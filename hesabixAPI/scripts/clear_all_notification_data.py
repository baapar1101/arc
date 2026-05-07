#!/usr/bin/env python3
"""
پاک‌سازی کامل داده‌های بخش نوتیفیکیشن (اعلان‌ها، outbox، قالب‌های کسب‌وکار، تنظیمات کاربر و …).

جداولی که در دیتابیس فعلی وجود ندارند نادیده گرفته می‌شوند.
پس از حذف قالب‌های سیستمی، در صورت نیاز دوباره seed کنید.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import inspect

from adapters.db.session import SessionLocal
from adapters.db.models.notification import NotificationOutbox, NotificationDeliveryAttempt
from adapters.db.models.announcement import Announcement, UserAnnouncement
from adapters.db.models.notification_config import (
	NotificationTemplate,
	UserNotificationSetting,
	UserInappAlertPreference,
)
from adapters.db.models.business_notification import (
	NotificationEventType,
	BusinessNotificationTemplate,
	NotificationModerationQueue,
	NotificationSendLog,
	NotificationDailyStat,
)


def main() -> None:
	print("=" * 72)
	print("پاک‌سازی تمام داده‌های نوتیفیکیشن در دیتابیس")
	print("=" * 72)

	# ترتیب: وابستگی فرزند → والد؛ بعد از هر جدول commit تا در صورت نبودن جدول بعدی، داده از دست نرود
	steps: list[tuple[str, type]] = [
		("notification_delivery_attempts", NotificationDeliveryAttempt),
		("notification_outbox", NotificationOutbox),
		("user_announcements", UserAnnouncement),
		("announcements", Announcement),
		("notification_moderation_queue", NotificationModerationQueue),
		("notification_send_logs", NotificationSendLog),
		("notification_daily_stats", NotificationDailyStat),
		("business_notification_templates", BusinessNotificationTemplate),
		("notification_event_types", NotificationEventType),
		("notification_templates", NotificationTemplate),
		("user_notification_settings", UserNotificationSetting),
		("user_inapp_alert_preferences", UserInappAlertPreference),
	]

	db = SessionLocal()
	try:
		insp = inspect(db.get_bind())
		for table_name, model in steps:
			if not insp.has_table(table_name):
				print(f"   {table_name}: رد شد (جدول در دیتابیس نیست)")
				continue
			n = db.query(model).delete(synchronize_session=False)
			db.commit()
			print(f"   {table_name}: {n} رکورد حذف شد")

		print("\n✅ پاک‌سازی جداول موجود انجام شد.")
		print(
			"\nدر صورت حذف notification_templates، در صورت نیاز دوباره migration/seed قالب‌ها را اجرا کنید."
		)
	except Exception as e:
		db.rollback()
		print(f"\n❌ خطا: {e}")
		import traceback

		traceback.print_exc()
		sys.exit(1)
	finally:
		db.close()


if __name__ == "__main__":
	main()
