"""ایجاد/به‌روزرسانی جدول ai_prompts و seed پرامپت‌های پیش‌فرض AI.

Revision ID: 20260613_000004_seed_ai_default_prompts
Revises: 20260613_000003_profile_user_dashboard_layouts
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

from adapters.db.seed_data.ai_default_prompts import AI_DEFAULT_PROMPT_ROWS

revision = "20260613_000004_seed_ai_default_prompts"
down_revision = "20260613_000003_profile_user_dashboard_layouts"
branch_labels = None
depends_on = None


def _ensure_ai_prompts_table(conn) -> None:
    insp = sa.inspect(conn)
    if "ai_prompts" not in insp.get_table_names():
        op.create_table(
            "ai_prompts",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("prompt_key", sa.String(100), nullable=False),
            sa.Column("role", sa.String(50), nullable=False),
            sa.Column("prompt_type", sa.String(50), nullable=False),
            sa.Column("category", sa.String(50), nullable=False, server_default="chat"),
            sa.Column("title", sa.String(255), nullable=False),
            sa.Column("content", sa.Text(), nullable=False),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=True),
            sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.text("false")),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("prompt_key", name="uq_ai_prompts_prompt_key"),
        )
        op.create_index("ix_ai_prompts_prompt_key", "ai_prompts", ["prompt_key"])
        op.create_index("ix_ai_prompts_role", "ai_prompts", ["role"])
        op.create_index("ix_ai_prompts_category", "ai_prompts", ["category"])
        op.create_index("ix_ai_prompts_user_id", "ai_prompts", ["user_id"])
        return

    columns = {col["name"] for col in insp.get_columns("ai_prompts")}
    if "prompt_key" not in columns:
        op.add_column("ai_prompts", sa.Column("prompt_key", sa.String(100), nullable=True))
        op.add_column(
            "ai_prompts",
            sa.Column("category", sa.String(50), nullable=False, server_default="chat"),
        )
        conn.execute(
            sa.text(
                """
                UPDATE ai_prompts
                SET prompt_key = CONCAT('legacy.', role, '.', prompt_type, '.', id)
                WHERE prompt_key IS NULL
                """
            )
        )
        op.alter_column("ai_prompts", "prompt_key", nullable=False)
        op.create_index("ix_ai_prompts_prompt_key", "ai_prompts", ["prompt_key"], unique=False)
        op.create_index("ix_ai_prompts_category", "ai_prompts", ["category"], unique=False)

    unique_names = {uc["name"] for uc in insp.get_unique_constraints("ai_prompts")}
    if "uq_ai_prompts_prompt_key" not in unique_names:
        try:
            op.create_unique_constraint("uq_ai_prompts_prompt_key", "ai_prompts", ["prompt_key"])
        except Exception:
            pass


def _backfill_legacy_prompt_keys(conn) -> None:
    role_key_map = {
        ("operator", "system"): "chat.operator",
        ("admin", "system"): "chat.admin",
    }
    for (role, prompt_type), prompt_key in role_key_map.items():
        conn.execute(
            sa.text(
                """
                UPDATE ai_prompts
                SET prompt_key = :prompt_key
                WHERE role = :role
                  AND prompt_type = :prompt_type
                  AND is_default = true
                  AND user_id IS NULL
                  AND prompt_key LIKE 'legacy.%'
                  AND NOT EXISTS (
                    SELECT 1 FROM ai_prompts p2
                    WHERE p2.prompt_key = :prompt_key
                  )
                """
            ),
            {"role": role, "prompt_type": prompt_type, "prompt_key": prompt_key},
        )


def upgrade() -> None:
    conn = op.get_bind()
    _ensure_ai_prompts_table(conn)
    _backfill_legacy_prompt_keys(conn)

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
                ON CONFLICT (prompt_key) DO NOTHING
                """
            ),
            row,
        )


def downgrade() -> None:
    conn = op.get_bind()
    insp = sa.inspect(conn)
    if "ai_prompts" not in insp.get_table_names():
        return

    keys = [row["prompt_key"] for row in AI_DEFAULT_PROMPT_ROWS]
    for key in keys:
        conn.execute(
            sa.text("DELETE FROM ai_prompts WHERE prompt_key = :k AND user_id IS NULL"),
            {"k": key},
        )
