"""AI skills: pricing, purchases, official seed

Revision ID: 20260702_000003_ai_skills_phase4
Revises: 20260702_000002_ai_skill_reviews
"""
from __future__ import annotations

import json
from datetime import datetime

import sqlalchemy as sa
from alembic import op

revision = "20260702_000003_ai_skills_phase4"
down_revision = "20260702_000002_ai_skill_reviews"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("ai_skill_packages", sa.Column("price_amount", sa.Numeric(18, 2), nullable=True))
    op.add_column("ai_skill_packages", sa.Column("currency_id", sa.Integer(), nullable=True))
    op.add_column("ai_skill_packages", sa.Column("is_official", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("ai_skill_packages", sa.Column("source_repo_url", sa.String(length=1024), nullable=True))
    op.create_foreign_key(
        "fk_ai_skill_packages_currency_id",
        "ai_skill_packages",
        "currencies",
        ["currency_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(op.f("ix_ai_skill_packages_is_official"), "ai_skill_packages", ["is_official"], unique=False)

    op.create_table(
        "ai_skill_purchases",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("package_id", sa.Integer(), nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=True),
        sa.Column("amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("currency_id", sa.Integer(), nullable=True),
        sa.Column("wallet_transaction_id", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["currency_id"], ["currencies.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["package_id"], ["ai_skill_packages.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["wallet_transaction_id"], ["wallet_transactions.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_ai_skill_purchases_package_id"), "ai_skill_purchases", ["package_id"], unique=False)
    op.create_index(op.f("ix_ai_skill_purchases_business_id"), "ai_skill_purchases", ["business_id"], unique=False)
    op.create_index("ix_ai_skill_purchase_biz_pkg", "ai_skill_purchases", ["business_id", "package_id"], unique=True)

    # seed مهارت‌های رسمی
    conn = op.get_bind()
    from adapters.db.seed_data.ai_official_skills_seed import OFFICIAL_ERP_SKILLS

    now = datetime.utcnow()
    for row in OFFICIAL_ERP_SKILLS:
        conn.execute(
            sa.text(
                """
                INSERT INTO ai_skill_packages (
                    skill_slug, title, description, skill_body, source_type,
                    allowed_tool_names, visibility, version_label, tags,
                    is_official, install_count, published_at, created_at, updated_at, has_scripts
                )
                SELECT :skill_slug, :title, :description, :skill_body, 'hesabix_native',
                       :allowed_tool_names, 'published', '1.0.0', :tags,
                       true, 0, :now, :now, :now, false
                WHERE NOT EXISTS (
                    SELECT 1 FROM ai_skill_packages
                    WHERE skill_slug = :skill_slug AND is_official = true
                )
                """
            ),
            {
                "skill_slug": row["skill_slug"],
                "title": row["title"],
                "description": row["description"],
                "skill_body": row["skill_body"],
                "allowed_tool_names": json.dumps(row.get("allowed_tool_names") or []),
                "tags": json.dumps(row.get("tags") or []),
                "now": now,
            },
        )


def downgrade() -> None:
    op.drop_index("ix_ai_skill_purchase_biz_pkg", table_name="ai_skill_purchases")
    op.drop_index(op.f("ix_ai_skill_purchases_business_id"), table_name="ai_skill_purchases")
    op.drop_index(op.f("ix_ai_skill_purchases_package_id"), table_name="ai_skill_purchases")
    op.drop_table("ai_skill_purchases")
    op.drop_index(op.f("ix_ai_skill_packages_is_official"), table_name="ai_skill_packages")
    op.drop_constraint("fk_ai_skill_packages_currency_id", "ai_skill_packages", type_="foreignkey")
    op.drop_column("ai_skill_packages", "source_repo_url")
    op.drop_column("ai_skill_packages", "is_official")
    op.drop_column("ai_skill_packages", "currency_id")
    op.drop_column("ai_skill_packages", "price_amount")
