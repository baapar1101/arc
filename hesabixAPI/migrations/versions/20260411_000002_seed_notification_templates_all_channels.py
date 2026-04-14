"""seed global notification_templates for all channels and core event_keys

Revision ID: 20260411_000002_seed_notification_templates_all_channels
Revises: 20260411_000001_add_invoice_warehouse_release_mode
Create Date: 2026-04-11

قالب‌های پیش‌فرض سیستمی (جدول notification_templates) برای کانال‌های
telegram, bale, sms, email, inapp و رویدادهای اصلی ارسال نوتیفیکیشن.
در صورت وجود ردیف با همان (event_key, channel, locale)، متن به‌روز می‌شود.
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260411_000002_seed_notification_templates_all_channels"
down_revision = "20260411_000001_add_invoice_warehouse_release_mode"
branch_labels = None
depends_on = None

# کانال‌های استاندارد NotificationService
CHANNELS = ("telegram", "bale", "sms", "email", "inapp")

# رویدادهایی که در کد با locale ارسال نمی‌شوند → locale NULL
EVENT_KEYS_DEFAULT_LOCALE = (
	"auth.password_reset",
	"workflow.error",
	"wallet.insufficient_funds_notification",
	"system.test",
	"support.ticket_created",
	"support.user_reply",
	"support.ticket_status_changed",
	"support.ticket_assigned",
	"support.operator_reply",
	"support.tickets_bulk_assigned",
	"support.tickets_bulk_status_changed",
	"business.deleted",
	"business.restored",
)


def _templates_for_event(event_key: str) -> dict[str, dict[str, str | None]]:
	"""برای هر event_key: کانال → {subject, body}"""
	# متن‌ها کوتاه برای SMS؛ بله/تلگرام بدون مارکداون پیچیده برای اجتناب از خطای parse
	if event_key == "auth.password_reset":
		return {
			"telegram": {
				"subject": "بازیابی رمز عبور",
				"body": "درخواست بازیابی رمز عبور ثبت شد.\nتوکن/لینک: {{ token }}\nاگر شما درخواست نداده‌اید، این پیام را نادیده بگیرید.",
			},
			"bale": {
				"subject": "بازیابی رمز عبور",
				"body": "بازیابی رمز عبور\nتوکن: {{ token }}\nدر صورت عدم درخواست شما، نادیده بگیرید.",
			},
			"sms": {
				"subject": "بازیابی رمز",
				"body": "حسابیکس: بازیابی رمز. توکن {{ token }}",
			},
			"email": {
				"subject": "بازیابی کلمه عبور — حسابیکس",
				"body": "سلام،\n\nبرای تنظیم مجدد رمز عبور از اطلاعات زیر استفاده کنید:\n\n{{ token }}\n\nاگر این درخواست از طرف شما نبوده، این ایمیل را نادیده بگیرید.",
			},
			"inapp": {
				"subject": "بازیابی رمز عبور",
				"body": "درخواست بازیابی رمز عبور ثبت شد. از لینک یا توکن ارسال‌شده در پیام‌های دیگر استفاده کنید.\n\nتوکن: {{ token }}",
			},
		}
	if event_key == "workflow.error":
		_body = (
			"خطا در workflow «{{ workflow_name }}»\n"
			"شناسه اجرا: {{ execution_id }}\n"
			"پیام: {{ error_message }}\n"
			"جزئیات در پنل لاگ‌های workflow."
		)
		return {ch: {"subject": "خطا در اجرای workflow", "body": _body} for ch in CHANNELS}
	if event_key == "wallet.insufficient_funds_notification":
		return {
			ch: {"subject": "{{ subject }}", "body": "{{ message }}"}
			for ch in CHANNELS
		}
	if event_key == "system.test":
		return {
			ch: {"subject": "{{ subject }}", "body": "{{ message }}"}
			for ch in CHANNELS
		}
	if event_key == "support.ticket_created":
		return {
			"telegram": {"subject": "{{ subject }}", "body": "{{ message }}\nدسته: {{ category }} — اولویت: {{ priority }}"},
			"bale": {"subject": "{{ subject }}", "body": "{{ message }}\nدسته: {{ category }} — اولویت: {{ priority }}"},
			"sms": {"subject": "تیکت جدید", "body": "تیکت #{{ ticket_id }}: {{ ticket_title }}. {{ user_name }}"},
			"email": {"subject": "{{ subject }}", "body": "{{ message }}\n\nدسته: {{ category }}\nاولویت: {{ priority }}"},
			"inapp": {"subject": "{{ subject }}", "body": "{{ message }}"},
		}
	if event_key == "support.user_reply":
		return {
			"telegram": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"bale": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"sms": {"subject": "پاسخ تیکت", "body": "تیکت #{{ ticket_id }}: پاسخ از {{ user_name }}"},
			"email": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"inapp": {"subject": "{{ subject }}", "body": "{{ message }}"},
		}
	if event_key == "support.ticket_status_changed":
		return {
			"telegram": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"bale": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"sms": {"subject": "وضعیت تیکت", "body": "تیکت #{{ ticket_id }}: {{ old_status }} → {{ new_status }}"},
			"email": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"inapp": {"subject": "{{ subject }}", "body": "{{ message }}"},
		}
	if event_key == "support.ticket_assigned":
		return {
			"telegram": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"bale": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"sms": {"subject": "تخصیص تیکت", "body": "تیکت #{{ ticket_id }} به شما: {{ ticket_title }}"},
			"email": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"inapp": {"subject": "{{ subject }}", "body": "{{ message }}"},
		}
	if event_key == "support.operator_reply":
		return {
			"telegram": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"bale": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"sms": {"subject": "پاسخ پشتیبانی", "body": "تیکت #{{ ticket_id }}: {{ operator_name }}"},
			"email": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"inapp": {"subject": "{{ subject }}", "body": "{{ message }}"},
		}
	if event_key == "support.tickets_bulk_assigned":
		return {
			"telegram": {"subject": "{{ subject }}", "body": "{{ message }}\nتعداد: {{ ticket_count }}"},
			"bale": {"subject": "{{ subject }}", "body": "{{ message }}\nتعداد: {{ ticket_count }}"},
			"sms": {"subject": "تیکت‌ها", "body": "{{ ticket_count }} تیکت به شما تخصیص داده شد."},
			"email": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"inapp": {"subject": "{{ subject }}", "body": "{{ message }}"},
		}
	if event_key == "support.tickets_bulk_status_changed":
		return {
			"telegram": {"subject": "{{ subject }}", "body": "{{ message }}\nوضعیت جدید: {{ new_status }}"},
			"bale": {"subject": "{{ subject }}", "body": "{{ message }}\nوضعیت: {{ new_status }}"},
			"sms": {"subject": "تیکت‌ها", "body": "{{ ticket_count }} تیکت → {{ new_status }}"},
			"email": {"subject": "{{ subject }}", "body": "{{ message }}"},
			"inapp": {"subject": "{{ subject }}", "body": "{{ message }}"},
		}
	if event_key == "business.deleted":
		return {
			"telegram": {
				"subject": "حذف کسب‌وکار",
				"body": "کسب‌وکار «{{ business_name }}» حذف نرم شد.\nمهلت بازیابی تا: {{ restore_deadline }}",
			},
			"bale": {
				"subject": "حذف کسب‌وکار",
				"body": "«{{ business_name }}» حذف شد. بازیابی تا {{ restore_deadline }} ({{ restore_days }} روز).",
			},
			"sms": {
				"subject": "حذف کسب‌وکار",
				"body": "{{ business_name }} حذف شد. مهلت بازگردانی {{ restore_days }} روز.",
			},
			"email": {
				"subject": "حذف نرم کسب‌وکار {{ business_name }}",
				"body": "کسب‌وکار شما با شناسه {{ business_id }} حذف نرم شد.\nتاریخ حذف: {{ deletion_date }}\nمهلت بازیابی: {{ restore_deadline }} (حدود {{ restore_days }} روز).\nدر این مدت می‌توانید از بخش بازیابی اقدام کنید.",
			},
			"inapp": {
				"subject": "کسب‌وکار حذف شد",
				"body": "«{{ business_name }}» حذف نرم شد. تا تاریخ {{ restore_deadline }} قابل بازیابی است.",
			},
		}
	if event_key == "business.restored":
		return {
			"telegram": {"subject": "بازیابی کسب‌وکار", "body": "کسب‌وکار «{{ business_name }}» با موفقیت بازیابی شد."},
			"bale": {"subject": "بازیابی کسب‌وکار", "body": "«{{ business_name }}» دوباره فعال شد."},
			"sms": {"subject": "بازیابی", "body": "کسب‌وکار {{ business_name }} بازیابی شد."},
			"email": {
				"subject": "بازیابی کسب‌وکار {{ business_name }}",
				"body": "کسب‌وکار با شناسه {{ business_id }} ({{ business_name }}) با موفقیت بازیابی شد.",
			},
			"inapp": {"subject": "بازیابی کسب‌وکار", "body": "«{{ business_name }}» دوباره در دسترس است."},
		}
	return {}


def _auth_otp_templates() -> list[dict]:
	"""ورود OTP با locale=fa (هم‌خوان با otp_login_service)"""
	rows: list[dict] = []
	for ch in CHANNELS:
		if ch == "sms":
			subject = "ورود یک‌بارمصرف"
			body = "کد ورود حسابیکس: {{ code }}\nاعتبار {{ expiry_minutes }} دقیقه."
		elif ch == "email":
			subject = "کد ورود به حساب کاربری"
			body = "کد ورود شما: {{ code }}\nاین کد تا {{ expiry_minutes }} دقیقه معتبر است.\n\nاگر شما درخواست نداده‌اید، این ایمیل را نادیده بگیرید."
		else:
			subject = "کد ورود"
			body = "کد ورود شما: {{ code }}\nاعتبار: {{ expiry_minutes }} دقیقه."
		rows.append(
			{
				"event_key": "auth.otp_login",
				"channel": ch,
				"locale": "fa",
				"subject": subject,
				"body": body,
			}
		)
	return rows


def upgrade() -> None:
	conn = op.get_bind()
	ins = sa.text("""
		INSERT INTO notification_templates (event_key, channel, locale, subject, body, is_active, created_at, updated_at)
		VALUES (:event_key, :channel, :locale, :subject, :body, TRUE, CURRENT_DATE, CURRENT_DATE)
		ON CONFLICT (event_key, channel, locale) DO UPDATE SET
			subject = EXCLUDED.subject,
			body = EXCLUDED.body,
			is_active = EXCLUDED.is_active,
			updated_at = CURRENT_DATE
	""")
	for row in _auth_otp_templates():
		conn.execute(ins, row)

	for ek in EVENT_KEYS_DEFAULT_LOCALE:
		per_ch = _templates_for_event(ek)
		for ch in CHANNELS:
			tpl = per_ch[ch]
			conn.execute(
				ins,
				{
					"event_key": ek,
					"channel": ch,
					"locale": None,
					"subject": tpl.get("subject"),
					"body": tpl["body"],
				},
			)


def downgrade() -> None:
	conn = op.get_bind()
	# حذف قالب‌های seed با locale پیش‌فرض NULL برای رویدادهای غیر OTP
	for ek in EVENT_KEYS_DEFAULT_LOCALE:
		conn.execute(
			sa.text(
				"DELETE FROM notification_templates WHERE event_key = :ek AND locale IS NULL"
			),
			{"ek": ek},
		)
	# حذف قالب‌های OTP با locale=fa (همان‌هایی که این migration مدیریت می‌کند)
	conn.execute(
		sa.text("DELETE FROM notification_templates WHERE event_key = 'auth.otp_login' AND locale = 'fa'")
	)
