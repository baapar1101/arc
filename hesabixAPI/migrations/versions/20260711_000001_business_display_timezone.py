"""business display_timezone column

Revision ID: 20260711_000001
Revises: 20260710_000001
Create Date: 2026-07-11
"""

from alembic import op
import sqlalchemy as sa

revision = "20260711_000001_business_display_timezone"
down_revision = "20260710_000001_product_catalog_gallery"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"businesses",
		sa.Column(
			"display_timezone",
			sa.String(length=80),
			nullable=True,
			comment="IANA timezone for datetime display; null = use system default",
		),
	)


def downgrade() -> None:
	op.drop_column("businesses", "display_timezone")
