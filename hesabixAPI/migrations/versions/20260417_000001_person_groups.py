"""Person groups: templates + categorization; parent_id reserved for future hierarchy

Revision ID: 20260417_000001_person_groups
Revises: 20260416_000004_person_name_prefix_legal_entity
Create Date: 2026-04-17
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260417_000001_person_groups"
down_revision = "20260416_000004_person_name_prefix_legal_entity"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"person_groups",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("parent_id", sa.Integer(), nullable=True, comment="والد برای سلسله‌مراتب آینده؛ در فاز تک‌سطحی NULL"),
		sa.Column("name", sa.String(length=255), nullable=False, comment="نام گروه"),
		sa.Column("code", sa.Integer(), nullable=True, comment="کد اختیاری یکتا در هر کسب‌وکار"),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column(
			"profile_defaults",
			sa.Text(),
			nullable=False,
			server_default="{}",
			comment="JSON: مقادیر پیش‌فرض قابل اعمال برای اشخاص جدید",
		),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["parent_id"], ["person_groups.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_person_groups_business_code"),
	)
	op.create_index(op.f("ix_person_groups_business_id"), "person_groups", ["business_id"], unique=False)
	op.create_index(op.f("ix_person_groups_parent_id"), "person_groups", ["parent_id"], unique=False)

	op.add_column(
		"persons",
		sa.Column(
			"person_group_id",
			sa.Integer(),
			nullable=True,
			comment="گروه اشخاص (دسته‌بندی و قالب پیش‌فرض)",
		),
	)
	op.create_index(op.f("ix_persons_person_group_id"), "persons", ["person_group_id"], unique=False)
	op.create_foreign_key(
		"fk_persons_person_group_id",
		"persons",
		"person_groups",
		["person_group_id"],
		["id"],
		ondelete="SET NULL",
	)


def downgrade() -> None:
	op.drop_constraint("fk_persons_person_group_id", "persons", type_="foreignkey")
	op.drop_index(op.f("ix_persons_person_group_id"), table_name="persons")
	op.drop_column("persons", "person_group_id")
	op.drop_index(op.f("ix_person_groups_parent_id"), table_name="person_groups")
	op.drop_index(op.f("ix_person_groups_business_id"), table_name="person_groups")
	op.drop_table("person_groups")
