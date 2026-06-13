"""رویداد نوتیفیکیشن لینک فاکتور و پرداخت آنلاین (فروش سریع).

Revision ID: 20260630_000001_invoice_share_link_notification_event
Revises: 20260629_000001_ai_provider_credentials
"""

from __future__ import annotations

import json

import sqlalchemy as sa
from alembic import op

from adapters.db.seed_data.notification_event_types_seed import (
    INVOICE_SHARE_LINK_EVENT_CODES,
    NOTIFICATION_EVENT_TYPES_ROWS,
)

revision = "20260630_000001_invoice_share_link_notification_event"
down_revision = "20260629_000001_ai_provider_credentials"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    insp = sa.inspect(conn)
    if "notification_event_types" not in insp.get_table_names():
        return

    rows = [r for r in NOTIFICATION_EVENT_TYPES_ROWS if r["code"] in INVOICE_SHARE_LINK_EVENT_CODES]
    for row in rows:
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

    for code in INVOICE_SHARE_LINK_EVENT_CODES:
        conn.execute(
            sa.text("DELETE FROM notification_event_types WHERE code = :c"),
            {"c": code},
        )
