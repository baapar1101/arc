"""Persist structured quick-sale job errors.

Revision ID: 20261019_000002_quick_sale_job_error_details
Revises: 20261019_000001_quick_sale_invoice_jobs
"""

from alembic import op
import sqlalchemy as sa


revision = "20261019_000002_quick_sale_job_error_details"
down_revision = "20261019_000001_quick_sale_invoice_jobs"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"quick_sale_invoice_jobs",
		sa.Column("error_details", sa.JSON(), nullable=True),
	)


def downgrade() -> None:
	op.drop_column("quick_sale_invoice_jobs", "error_details")
