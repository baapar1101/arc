"""Add AI voice model catalog, policy, and per-business cloud-audio settings.

Revision ID: 20260818_000001_ai_voice_models
Revises: 20260817_000002_ai_agent_runs
Create Date: 2026-08-18
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260818_000001_ai_voice_models"
down_revision = "20260817_000002_ai_agent_runs"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"ai_voice_models",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("code", sa.String(length=80), nullable=False),
		sa.Column("kind", sa.String(length=20), nullable=False),
		sa.Column("display_name", sa.String(length=255), nullable=False),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("provider", sa.String(length=50), nullable=False, server_default="local"),
		sa.Column("model_id", sa.String(length=160), nullable=False),
		sa.Column("language", sa.String(length=16), nullable=False, server_default="fa"),
		sa.Column("voice_id", sa.String(length=80), nullable=True),
		sa.Column("tier", sa.String(length=50), nullable=True),
		sa.Column("reference_cost_per_minute", sa.Numeric(18, 4), nullable=True),
		sa.Column("reference_cost_per_1k_chars", sa.Numeric(18, 4), nullable=True),
		sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.false()),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("extra_json", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("code", name="uq_ai_voice_models_code"),
	)
	op.create_index("ix_ai_voice_models_code", "ai_voice_models", ["code"])
	op.create_index("ix_ai_voice_models_kind", "ai_voice_models", ["kind"])

	op.create_table(
		"ai_voice_policy",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("allow_cloud_audio", sa.Boolean(), nullable=False, server_default=sa.false()),
		sa.Column("default_stt_code", sa.String(length=80), nullable=True),
		sa.Column("default_tts_code", sa.String(length=80), nullable=True),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.PrimaryKeyConstraint("id"),
	)

	op.create_table(
		"business_ai_voice_settings",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("allow_cloud_audio", sa.Boolean(), nullable=False, server_default=sa.false()),
		sa.Column("preferred_stt_code", sa.String(length=80), nullable=True),
		sa.Column("preferred_tts_code", sa.String(length=80), nullable=True),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", name="uq_business_ai_voice_settings_business"),
	)
	op.create_index(
		"ix_business_ai_voice_settings_business_id",
		"business_ai_voice_settings",
		["business_id"],
	)


def downgrade() -> None:
	op.drop_index("ix_business_ai_voice_settings_business_id", table_name="business_ai_voice_settings")
	op.drop_table("business_ai_voice_settings")
	op.drop_table("ai_voice_policy")
	op.drop_index("ix_ai_voice_models_kind", table_name="ai_voice_models")
	op.drop_index("ix_ai_voice_models_code", table_name="ai_voice_models")
	op.drop_table("ai_voice_models")
