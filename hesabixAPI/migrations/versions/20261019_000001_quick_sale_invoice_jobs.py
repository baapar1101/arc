"""Create durable quick-sale invoice outbox.

Revision ID: 20261019_000001_quick_sale_invoice_jobs
Revises: 20261018_000003_navasan_fx_provider
"""

from alembic import op
import sqlalchemy as sa


revision = "20261019_000001_quick_sale_invoice_jobs"
down_revision = "20261018_000003_navasan_fx_provider"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"quick_sale_invoice_jobs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("request_id", sa.String(length=160), nullable=False),
		sa.Column("payload", sa.JSON(), nullable=False),
		sa.Column("user_can_select_fx_rate", sa.Boolean(), server_default=sa.false(), nullable=False),
		sa.Column("user_can_change_invoice_unit_price", sa.Boolean(), server_default=sa.true(), nullable=False),
		sa.Column("status", sa.String(length=16), server_default="queued", nullable=False),
		sa.Column("attempt_count", sa.Integer(), server_default="0", nullable=False),
		sa.Column("available_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
		sa.Column("locked_until", sa.DateTime(), nullable=True),
		sa.Column("invoice_id", sa.Integer(), nullable=True),
		sa.Column("invoice_code", sa.String(length=100), nullable=True),
		sa.Column("error_code", sa.String(length=100), nullable=True),
		sa.Column("error_message", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
		sa.Column("finished_at", sa.DateTime(), nullable=True),
	sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
	sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
	sa.ForeignKeyConstraint(["invoice_id"], ["documents.id"], ondelete="SET NULL"),
	sa.PrimaryKeyConstraint("id"),
	sa.UniqueConstraint("business_id", "request_id", name="uq_quick_sale_invoice_jobs_request"),
	)
	op.create_index(
		"ix_quick_sale_invoice_jobs_due",
		"quick_sale_invoice_jobs",
		["status", "available_at", "locked_until"],
	)
	op.create_index(
		"ix_quick_sale_invoice_jobs_user_created",
		"quick_sale_invoice_jobs",
		["business_id", "user_id", "created_at"],
	)


def downgrade() -> None:
	op.drop_index("ix_quick_sale_invoice_jobs_user_created", table_name="quick_sale_invoice_jobs")
	op.drop_index("ix_quick_sale_invoice_jobs_due", table_name="quick_sale_invoice_jobs")
	op.drop_table("quick_sale_invoice_jobs")
