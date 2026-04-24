"""Workflow marketplace: published packages and installs

Revision ID: 20260417_000002_workflow_marketplace
Revises: 20260417_000001_person_groups
Create Date: 2026-04-17
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260417_000002_workflow_marketplace"
down_revision = "20260417_000001_person_groups"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"workflow_marketplace_packages",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("source_workflow_id", sa.Integer(), nullable=True),
		sa.Column("publisher_user_id", sa.Integer(), nullable=False),
		sa.Column("publisher_business_id", sa.Integer(), nullable=False),
		sa.Column("title", sa.String(length=255), nullable=False),
		sa.Column("short_description", sa.Text(), nullable=True),
		sa.Column("long_description", sa.Text(), nullable=True),
		sa.Column("tags", sa.JSON(), nullable=True),
		sa.Column("workflow_data", sa.JSON(), nullable=False),
		sa.Column("settings", sa.JSON(), nullable=True),
		sa.Column("version_label", sa.String(length=64), nullable=False, server_default="1.0.0"),
		sa.Column("changelog", sa.Text(), nullable=True),
		sa.Column("status", sa.String(length=32), nullable=False, server_default="published"),
		sa.Column("install_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("published_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["source_workflow_id"], ["workflows.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["publisher_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["publisher_business_id"], ["businesses.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index(op.f("ix_workflow_marketplace_packages_source_workflow_id"), "workflow_marketplace_packages", ["source_workflow_id"], unique=False)
	op.create_index(op.f("ix_workflow_marketplace_packages_publisher_user_id"), "workflow_marketplace_packages", ["publisher_user_id"], unique=False)
	op.create_index(op.f("ix_workflow_marketplace_packages_publisher_business_id"), "workflow_marketplace_packages", ["publisher_business_id"], unique=False)
	op.create_index(op.f("ix_workflow_marketplace_packages_title"), "workflow_marketplace_packages", ["title"], unique=False)
	op.create_index(op.f("ix_workflow_marketplace_packages_status"), "workflow_marketplace_packages", ["status"], unique=False)
	op.create_index(op.f("ix_workflow_marketplace_packages_published_at"), "workflow_marketplace_packages", ["published_at"], unique=False)
	op.create_index("ix_wf_mpkg_pub_status_published", "workflow_marketplace_packages", ["status", "published_at"], unique=False)

	op.create_table(
		"workflow_marketplace_installs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("package_id", sa.Integer(), nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("installed_workflow_id", sa.Integer(), nullable=True),
		sa.Column("installed_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["package_id"], ["workflow_marketplace_packages.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["installed_workflow_id"], ["workflows.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["installed_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index(op.f("ix_workflow_marketplace_installs_package_id"), "workflow_marketplace_installs", ["package_id"], unique=False)
	op.create_index(op.f("ix_workflow_marketplace_installs_business_id"), "workflow_marketplace_installs", ["business_id"], unique=False)
	op.create_index(op.f("ix_workflow_marketplace_installs_installed_workflow_id"), "workflow_marketplace_installs", ["installed_workflow_id"], unique=False)
	op.create_index(op.f("ix_workflow_marketplace_installs_installed_by_user_id"), "workflow_marketplace_installs", ["installed_by_user_id"], unique=False)


def downgrade() -> None:
	op.drop_index(op.f("ix_workflow_marketplace_installs_installed_by_user_id"), table_name="workflow_marketplace_installs")
	op.drop_index(op.f("ix_workflow_marketplace_installs_installed_workflow_id"), table_name="workflow_marketplace_installs")
	op.drop_index(op.f("ix_workflow_marketplace_installs_business_id"), table_name="workflow_marketplace_installs")
	op.drop_index(op.f("ix_workflow_marketplace_installs_package_id"), table_name="workflow_marketplace_installs")
	op.drop_table("workflow_marketplace_installs")
	op.drop_index("ix_wf_mpkg_pub_status_published", table_name="workflow_marketplace_packages")
	op.drop_index(op.f("ix_workflow_marketplace_packages_published_at"), table_name="workflow_marketplace_packages")
	op.drop_index(op.f("ix_workflow_marketplace_packages_status"), table_name="workflow_marketplace_packages")
	op.drop_index(op.f("ix_workflow_marketplace_packages_title"), table_name="workflow_marketplace_packages")
	op.drop_index(op.f("ix_workflow_marketplace_packages_publisher_business_id"), table_name="workflow_marketplace_packages")
	op.drop_index(op.f("ix_workflow_marketplace_packages_publisher_user_id"), table_name="workflow_marketplace_packages")
	op.drop_index(op.f("ix_workflow_marketplace_packages_source_workflow_id"), table_name="workflow_marketplace_packages")
	op.drop_table("workflow_marketplace_packages")
