"""backfill receipt_payment document_lines extra_info person_id

برای رفع مشکل نمایش «نامشخص» در لیست دریافت/پرداخت:
خطوط سند که person_id در ستون دارند ولی در extra_info ندارند،
extra_info آن‌ها با person_id پر می‌شود.

Revision ID: 20250226_000001
Revises: 20251003_010501_add_name_to_cash_registers
Create Date: 2025-02-26

"""
from __future__ import annotations

from alembic import op
from sqlalchemy import text


revision = "20250226_000001_backfill_receipt_payment_person_id_extra_info"
down_revision = "20251003_010501_add_name_to_cash_registers"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    # فقط برای PostgreSQL از JSON/JSONB پشتیبانی می‌کنیم
    if conn.dialect.name != "postgresql":
        return
    # خطوط سند دریافت/پرداخت که person_id دارند ولی در extra_info ندارند را به‌روز کن
    # استفاده از jsonb برای merge تا با همه نسخه‌های پشتیبانی‌شده PostgreSQL کار کند
    conn.execute(
        text("""
        UPDATE document_lines dl
        SET extra_info = (
            COALESCE(dl.extra_info::jsonb, '{}'::jsonb)
            || jsonb_build_object('person_id', dl.person_id)
        )::json
        FROM documents d
        WHERE dl.document_id = d.id
          AND d.document_type IN ('receipt', 'payment')
          AND dl.person_id IS NOT NULL
          AND (dl.extra_info IS NULL
               OR (dl.extra_info->>'person_id') IS NULL
               OR (dl.extra_info->>'person_id') = '')
        """)
    )


def downgrade() -> None:
    # برگرداندن extra_info ممکن است داده‌های دیگر را از بین ببرد؛ downgrade خالی می‌ماند
    pass
