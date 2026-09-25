"""به‌روزرسانی پرامپت‌های AI — سیاست زبان کاربر و نمایش مستقیم reasoning.

Revision ID: 20260714_000001_ai_prompts_language_policy
Revises: 20260711_000002_documents_timestamptz
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

from adapters.db.seed_data.ai_default_prompts import AI_DEFAULT_PROMPT_ROWS

revision = "20260714_000001_ai_prompts_language_policy"
down_revision = "20260711_000002_documents_timestamptz"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    for row in AI_DEFAULT_PROMPT_ROWS:
        conn.execute(
            sa.text(
                """
                INSERT INTO ai_prompts (
                    prompt_key, role, prompt_type, category, title, content,
                    user_id, is_default, is_active, created_at, updated_at
                ) VALUES (
                    :prompt_key, :role, :prompt_type, :category, :title, :content,
                    NULL, true, true, NOW(), NOW()
                )
                ON CONFLICT (prompt_key) DO UPDATE SET
                    role = EXCLUDED.role,
                    prompt_type = EXCLUDED.prompt_type,
                    category = EXCLUDED.category,
                    title = EXCLUDED.title,
                    content = EXCLUDED.content,
                    is_default = true,
                    is_active = true,
                    updated_at = NOW()
                WHERE ai_prompts.user_id IS NULL
                """
            ),
            row,
        )


def downgrade() -> None:
    # پرامپت‌های seed را به نسخه قبلی برنمی‌گردانیم (غیرقابل برگشت امن).
    pass
