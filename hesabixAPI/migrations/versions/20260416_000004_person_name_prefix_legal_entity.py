"""Person: name prefix and legal entity type (natural/legal)

Revision ID: 20260416_000004_person_name_prefix_legal_entity
Revises: 20260416_000003_business_inventory_negative_policy
Create Date: 2026-04-16
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260416_000004_person_name_prefix_legal_entity"
down_revision = "20260416_000003_business_inventory_negative_policy"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"persons",
		sa.Column(
			"name_prefix",
			sa.String(length=64),
			nullable=True,
			comment="پیشوند نام (آقای، خانم، شرکت، …)",
		),
	)
	op.add_column(
		"persons",
		sa.Column(
			"legal_entity_type",
			sa.String(length=16),
			nullable=False,
			server_default="natural",
			comment="نوع حقوقی: natural=حقیقی، legal=حقوقی",
		),
	)


def downgrade() -> None:
	op.drop_column("persons", "legal_entity_type")
	op.drop_column("persons", "name_prefix")
