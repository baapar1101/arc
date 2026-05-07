"""سیاست‌های نرخ (فایروال مرکزی — فقط دیتابیس/پایتون) برای مسیرها مثل چت وب عمومی

Revision ID: 20260528_000001_firewall_rate_policies
Revises: 20260527_000001_business_user_quick_links
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260528_000001_firewall_rate_policies"
down_revision = "20260527_000001_business_user_quick_links"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"firewall_rate_policies",
		sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
		sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("priority", sa.Integer(), nullable=False, server_default=sa.text("100")),
		sa.Column("path_prefix", sa.String(length=512), nullable=False),
		sa.Column("http_methods", sa.String(length=128), nullable=True),
		sa.Column("max_requests", sa.Integer(), nullable=False),
		sa.Column("window_seconds", sa.Integer(), nullable=False),
		sa.Column("note", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_firewall_rate_enabled_prio", "firewall_rate_policies", ["enabled", "priority"])
	# قوانین پیش‌فرض چت وب عمومی (مطابق دکوراتورهای سابق)
	op.execute(
		sa.text(
			"""
			INSERT INTO firewall_rate_policies
			(enabled, priority, path_prefix, http_methods, max_requests, window_seconds, note, created_at, updated_at)
			VALUES
			(true, 5,  '/api/v1/public/crm-chat/conversations/start', 'POST', 30, 60,
				'شروع مکالمه چت CRM', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
			(true, 8,  '/api/v1/public/crm-chat/messages', 'POST', 90, 60,
				'ارسال پیام توسط بازدیدکننده', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
			(true, 6,  '/api/v1/public/crm-chat/messages/file', 'POST', 20, 60,
				'آپلود فایل چت', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
			(true, 10, '/api/v1/public/crm-chat/conversations/', 'GET', 150, 60,
				'لیست پیام / دانلود (GET)', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
			"""
		)
	)


def downgrade() -> None:
	op.drop_index("ix_firewall_rate_enabled_prio", table_name="firewall_rate_policies")
	op.drop_table("firewall_rate_policies")
