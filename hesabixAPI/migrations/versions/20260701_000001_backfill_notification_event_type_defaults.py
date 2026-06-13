"""تکمیل قالب‌های پیش‌فرض SMS/Email برای همه رویدادهای notification_event_types

Revision ID: 20260701_000001_backfill_notification_event_type_defaults
Revises: 20260630_000003_merge_heads_ai_memory_items_and_quick_sales_share_defaults
Create Date: 2026-07-01

در صورت وجود ردیف، متن‌های پیش‌فرض از seed به‌روز می‌شوند (برای نصب‌های قبلی که
default_email_template خالی داشتند). ردیف‌های جدید با ON CONFLICT درج می‌شوند.
"""
from __future__ import annotations

import json

import sqlalchemy as sa
from alembic import op

from adapters.db.seed_data.notification_event_types_seed import NOTIFICATION_EVENT_TYPES_ROWS

revision = "20260701_000001_backfill_notification_event_type_defaults"
down_revision = "20260630_000003_merge_heads_ai_memory_items_and_quick_sales_share_defaults"
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
				ON CONFLICT (code) DO UPDATE SET
					name = EXCLUDED.name,
					description = EXCLUDED.description,
					category = EXCLUDED.category,
					available_variables = EXCLUDED.available_variables,
					default_sms_template = EXCLUDED.default_sms_template,
					default_email_template = EXCLUDED.default_email_template,
					default_email_subject = EXCLUDED.default_email_subject,
					updated_at = NOW()
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
	# قالب‌های پیش‌فرض را حذف نمی‌کنیم — فقط مهاجرت بدون downgrade مخرب
	pass
