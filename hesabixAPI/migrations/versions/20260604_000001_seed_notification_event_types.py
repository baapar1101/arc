"""پر کردن جدول notification_event_types در صورت خالی بودن (رفع خطای نوع رویداد نامعتبر).

Revision ID: 20260604_000001_seed_notification_event_types
Revises: 20260603_000001_crm_chat_message_edited_at
Create Date: 2026-06-04

اگر جدول روی دیتابیس وجود نداشته باشد (نصب قدیمی فقط با SQL دستی)، این مهاجرت بدون خطا رد می‌شود.
"""
from __future__ import annotations

import json

import sqlalchemy as sa
from alembic import op

from adapters.db.seed_data.notification_event_types_seed import NOTIFICATION_EVENT_TYPES_ROWS

revision = "20260604_000001_seed_notification_event_types"
down_revision = "20260603_000001_crm_chat_message_edited_at"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)
	if "notification_event_types" not in insp.get_table_names():
		return

	for row in NOTIFICATION_EVENT_TYPES_ROWS:
		conn.execute(
			sa.text(
				"""
				INSERT INTO notification_event_types (
					code, name, description, category, available_variables,
					default_sms_template, default_email_template, default_email_subject,
					is_active, requires_approval, created_at, updated_at
				) VALUES (
					:code, :name, :description, :category, CAST(:vars AS JSONB),
					:dst, :det, :des,
					true, true, NOW(), NOW()
				)
				ON CONFLICT (code) DO NOTHING
				"""
			),
			{
				"code": row["code"],
				"name": row["name"],
				"description": row.get("description"),
				"category": row.get("category"),
				"vars": json.dumps(row["available_variables"], ensure_ascii=False),
				"dst": row.get("default_sms_template"),
				"det": row.get("default_email_template"),
				"des": row.get("default_email_subject"),
			},
		)


def downgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)
	if "notification_event_types" not in insp.get_table_names():
		return

	codes = [r["code"] for r in NOTIFICATION_EVENT_TYPES_ROWS]
	for code in codes:
		conn.execute(
			sa.text("DELETE FROM notification_event_types WHERE code = :c"),
			{"c": code},
		)
