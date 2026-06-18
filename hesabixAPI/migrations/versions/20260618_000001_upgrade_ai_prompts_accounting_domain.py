"""به‌روزرسانی پرامپت‌های AI — چارچوب حسابداری، routing ابزار و مهارت‌های جدید.

Revision ID: 20260618_000001_upgrade_ai_prompts_accounting_domain
Revises: 20260703_000001_merge_heads_seed_ai_prompts_and_ai_skill_publisher_revenue
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

from adapters.db.seed_data.ai_default_prompts import AI_DEFAULT_PROMPT_ROWS

revision = "20260618_000001_upgrade_ai_prompts_accounting_domain"
down_revision = "20260703_000001_merge_heads_seed_ai_prompts_and_ai_skill_publisher_revenue"
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

    # مهارت‌های رسمی جدید/به‌روز — idempotent
    try:
        from adapters.db.session import SessionLocal
        from app.services.ai.ai_skill_service import seed_official_skills

        db = SessionLocal()
        try:
            seed_official_skills(db)
        finally:
            db.close()
    except Exception:
        pass


def downgrade() -> None:
    # پرامپت‌های جدید را حذف کن؛ بقیه را به نسخه قبلی seed برنگردانیم (غیرقابل برگشت امن)
    conn = op.get_bind()
    new_keys = (
        "chat.accounting_domain",
        "chat.tool_routing",
        "chat.operator_security",
        "chat.admin_security",
        "insight.suggestion.profit_loss",
        "insight.suggestion.accounting_guide",
    )
    for key in new_keys:
        conn.execute(
            sa.text("DELETE FROM ai_prompts WHERE prompt_key = :k AND user_id IS NULL"),
            {"k": key},
        )
