"""AI Skills: packages and business installs (Agent Skills / Anthropic compatible)

Revision ID: 20260702_000001_ai_skills
Revises: 20260701_000001_backfill_notification_event_type_defaults
Create Date: 2026-07-02
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260702_000001_ai_skills"
down_revision = "20260701_000001_backfill_notification_event_type_defaults"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_skill_packages",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("skill_slug", sa.String(length=64), nullable=False),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("skill_body", sa.Text(), nullable=False, server_default=""),
        sa.Column("source_type", sa.String(length=32), nullable=False, server_default="portable"),
        sa.Column("anthropic_skill_id", sa.String(length=64), nullable=True),
        sa.Column("bundle_files", sa.JSON(), nullable=True),
        sa.Column("allowed_tool_names", sa.JSON(), nullable=True),
        sa.Column("compatibility_report", sa.JSON(), nullable=True),
        sa.Column("has_scripts", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("publisher_user_id", sa.Integer(), nullable=True),
        sa.Column("publisher_business_id", sa.Integer(), nullable=True),
        sa.Column("owner_business_id", sa.Integer(), nullable=True),
        sa.Column("visibility", sa.String(length=32), nullable=False, server_default="draft"),
        sa.Column("version_label", sa.String(length=64), nullable=False, server_default="1.0.0"),
        sa.Column("changelog", sa.Text(), nullable=True),
        sa.Column("tags", sa.JSON(), nullable=True),
        sa.Column("short_description", sa.Text(), nullable=True),
        sa.Column("long_description", sa.Text(), nullable=True),
        sa.Column("install_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("published_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["owner_business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["publisher_business_id"], ["businesses.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["publisher_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_ai_skill_packages_skill_slug"), "ai_skill_packages", ["skill_slug"], unique=False)
    op.create_index(op.f("ix_ai_skill_packages_title"), "ai_skill_packages", ["title"], unique=False)
    op.create_index(op.f("ix_ai_skill_packages_source_type"), "ai_skill_packages", ["source_type"], unique=False)
    op.create_index(
        op.f("ix_ai_skill_packages_anthropic_skill_id"),
        "ai_skill_packages",
        ["anthropic_skill_id"],
        unique=False,
    )
    op.create_index(op.f("ix_ai_skill_packages_visibility"), "ai_skill_packages", ["visibility"], unique=False)
    op.create_index(op.f("ix_ai_skill_packages_published_at"), "ai_skill_packages", ["published_at"], unique=False)
    op.create_index("ix_ai_skill_pkg_vis_published", "ai_skill_packages", ["visibility", "published_at"], unique=False)

    op.create_table(
        "ai_skill_installs",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("package_id", sa.Integer(), nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("installed_by_user_id", sa.Integer(), nullable=True),
        sa.Column("is_enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("custom_title", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["installed_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["package_id"], ["ai_skill_packages.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_ai_skill_installs_package_id"), "ai_skill_installs", ["package_id"], unique=False)
    op.create_index(op.f("ix_ai_skill_installs_business_id"), "ai_skill_installs", ["business_id"], unique=False)
    op.create_index(
        op.f("ix_ai_skill_installs_installed_by_user_id"),
        "ai_skill_installs",
        ["installed_by_user_id"],
        unique=False,
    )
    op.create_index("ix_ai_skill_install_biz_pkg", "ai_skill_installs", ["business_id", "package_id"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_ai_skill_install_biz_pkg", table_name="ai_skill_installs")
    op.drop_index(op.f("ix_ai_skill_installs_installed_by_user_id"), table_name="ai_skill_installs")
    op.drop_index(op.f("ix_ai_skill_installs_business_id"), table_name="ai_skill_installs")
    op.drop_index(op.f("ix_ai_skill_installs_package_id"), table_name="ai_skill_installs")
    op.drop_table("ai_skill_installs")
    op.drop_index("ix_ai_skill_pkg_vis_published", table_name="ai_skill_packages")
    op.drop_index(op.f("ix_ai_skill_packages_published_at"), table_name="ai_skill_packages")
    op.drop_index(op.f("ix_ai_skill_packages_visibility"), table_name="ai_skill_packages")
    op.drop_index(op.f("ix_ai_skill_packages_anthropic_skill_id"), table_name="ai_skill_packages")
    op.drop_index(op.f("ix_ai_skill_packages_source_type"), table_name="ai_skill_packages")
    op.drop_index(op.f("ix_ai_skill_packages_title"), table_name="ai_skill_packages")
    op.drop_index(op.f("ix_ai_skill_packages_skill_slug"), table_name="ai_skill_packages")
    op.drop_table("ai_skill_packages")
