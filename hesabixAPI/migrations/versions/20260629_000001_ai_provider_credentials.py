"""اعتبارنامه چند provider + seed اولیه مدل‌ها

Revision ID: 20260629_000001_ai_provider_credentials
Revises: 20260628_000001_ai_models_catalog
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260629_000001_ai_provider_credentials"
down_revision = "20260628_000001_ai_models_catalog"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_provider_credentials",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("provider", sa.String(50), nullable=False),
        sa.Column("display_name", sa.String(120), nullable=False),
        sa.Column("api_base_url", sa.String(500), nullable=True),
        sa.Column("api_key", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column(
            "function_calling_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("provider", name="uq_ai_provider_credentials_provider"),
    )
    op.create_index("ix_ai_provider_credentials_provider", "ai_provider_credentials", ["provider"])

    bind = op.get_bind()
    if bind is None:
        return

    # انتقال credential از ai_configs
    rows = bind.execute(
        sa.text(
            """
            SELECT provider, api_base_url, api_key, is_active, function_calling_enabled
            FROM ai_configs
            WHERE is_active = true
            ORDER BY id ASC
            LIMIT 1
            """
        )
    ).mappings().all()
    for row in rows:
        provider = row["provider"] or "openai"
        labels = {
            "openai": "OpenAI",
            "anthropic": "Anthropic",
            "local": "Local / Ollama",
            "custom": "Custom Gateway",
        }
        bind.execute(
            sa.text(
                """
                INSERT INTO ai_provider_credentials
                (provider, display_name, api_base_url, api_key, is_active, function_calling_enabled)
                VALUES (:provider, :display_name, :api_base_url, :api_key, :is_active, :fce)
                """
            ),
            {
                "provider": provider,
                "display_name": labels.get(provider, provider),
                "api_base_url": row["api_base_url"],
                "api_key": row["api_key"],
                "is_active": bool(row["is_active"]),
                "fce": bool(row.get("function_calling_enabled", True)),
            },
        )

    # seed مدل‌ها اگر خالی باشد
    from app.services.ai.ai_model_seed_service import seed_models_from_config
    from adapters.db.session import SessionLocal

    session = SessionLocal(bind=bind)
    try:
        seed_models_from_config(session, include_presets=True, force=False)
    finally:
        session.close()


def downgrade() -> None:
    op.drop_index("ix_ai_provider_credentials_provider", table_name="ai_provider_credentials")
    op.drop_table("ai_provider_credentials")
