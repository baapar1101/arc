"""ایجاد حساب هزینه هوش مصنوعی (70508)

Revision ID: 20250121_000001_add_ai_expense_account
Revises: 20250120_000002
Create Date: 2025-01-21 00:00:01.000001

این migration یک حساب ثابت (business_id = NULL) با کد 70508 برای "هزینه هوش مصنوعی"
ایجاد می‌کند تا سرویس‌های AI بتوانند سند حسابداری صادر کنند.
"""

from __future__ import annotations

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "20250121_000001_add_ai_expense_account"
down_revision: Union[str, None] = "20250120_000002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()

    # حساب والد (705) باید وجود داشته باشد
    parent_705 = conn.execute(
        sa.text("SELECT id FROM accounts WHERE code = '705' AND business_id IS NULL LIMIT 1")
    ).fetchone()
    if not parent_705:
        # اگر به هر دلیل chart حساب‌ها هنوز seed نشده باشد، این migration را fail نمی‌کنیم
        # تا مسیر upgrade کل سیستم نشکند؛ ایجاد 70508 بدون والد هم معنی ندارد.
        return

    parent_id_705 = parent_705[0]

    # اگر 70508 وجود ندارد، ایجادش کن؛ اگر هست، نام/والد را اصلاح کن (idempotent)
    existing_70508 = conn.execute(
        sa.text("SELECT id FROM accounts WHERE code = '70508' AND business_id IS NULL LIMIT 1")
    ).fetchone()

    if not existing_70508:
        conn.execute(
            sa.text(
                """
                INSERT INTO accounts (name, code, account_type, business_id, parent_id, created_at, updated_at)
                VALUES ('هزینه هوش مصنوعی', '70508', 'accounting_document', NULL, :parent_id, NOW(), NOW())
                """
            ),
            {"parent_id": parent_id_705},
        )
    else:
        conn.execute(
            sa.text(
                """
                UPDATE accounts
                SET name = 'هزینه هوش مصنوعی',
                    parent_id = :parent_id,
                    account_type = 'accounting_document',
                    updated_at = NOW()
                WHERE code = '70508' AND business_id IS NULL
                """
            ),
            {"parent_id": parent_id_705},
        )


def downgrade() -> None:
    conn = op.get_bind()
    conn.execute(
        sa.text("DELETE FROM accounts WHERE code = '70508' AND business_id IS NULL")
    )


