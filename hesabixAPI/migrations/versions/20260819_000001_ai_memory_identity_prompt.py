"""پرامپت هویت کاربر: نام خطاب از حافظه، نه get_business_info.

Revision ID: 20260819_000001_ai_memory_identity_prompt
Revises: 20260818_000001_ai_voice_models
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

from adapters.db.seed_data.ai_default_prompts import AI_DEFAULT_PROMPT_ROWS

revision = "20260819_000001_ai_memory_identity_prompt"
down_revision = "20260818_000001_ai_voice_models"
branch_labels = None
depends_on = None

_PROMPT_KEYS = frozenset({
    "chat.user.base",
    "chat.tool_routing",
    "aux.memory_curate",
})


def upgrade() -> None:
    conn = op.get_bind()
    for row in AI_DEFAULT_PROMPT_ROWS:
        if row["prompt_key"] not in _PROMPT_KEYS:
            continue
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
    pass
