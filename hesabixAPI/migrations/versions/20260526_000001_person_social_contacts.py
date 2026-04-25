"""Person social / messenger contact rows

Revision ID: 20260526_000001_person_social_contacts
Revises: 20260525_000001_crm_chat_files_settings
Create Date: 2026-05-26
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260526_000001_person_social_contacts"
down_revision = "20260525_000001_crm_chat_files_settings"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"person_social_contacts",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("platform_key", sa.String(length=64), nullable=False, comment="کلید پلتفرم"),
		sa.Column("custom_label", sa.String(length=128), nullable=True, comment="برچسب سفارشی"),
		sa.Column("value", sa.Text(), nullable=False, comment="مقدار"),
		sa.Column("sort_order", sa.Integer(), server_default="0", nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index(op.f("ix_person_social_contacts_person_id"), "person_social_contacts", ["person_id"], unique=False)


def downgrade() -> None:
	op.drop_index(op.f("ix_person_social_contacts_person_id"), table_name="person_social_contacts")
	op.drop_table("person_social_contacts")
