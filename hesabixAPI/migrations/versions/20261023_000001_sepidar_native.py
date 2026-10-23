"""Source identity and native projection settings for Sepidar."""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "20261023_000001_sepidar_native"
down_revision = "20261022_000001_sepidar_live_import"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("sepidar_import_rows", sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("sepidar_import_settings", sa.Column("native_enabled", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("sepidar_import_settings", sa.Column("native_summary", postgresql.JSONB()))
    op.add_column("sepidar_import_settings", sa.Column("native_last_error", sa.Text()))
    op.create_table("sepidar_native_maps",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("database_name", sa.String(255), nullable=False),
        sa.Column("source_table", sa.String(128), nullable=False),
        sa.Column("source_id", sa.String(128), nullable=False),
        sa.Column("target_table", sa.String(64), nullable=False),
        sa.Column("target_id", sa.Integer(), nullable=False),
        sa.Column("source_hash", sa.String(64), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("business_id", "database_name", "source_table", "source_id", name="uq_sepidar_native_source"))
    op.create_index("ix_sepidar_native_maps_business_id", "sepidar_native_maps", ["business_id"])


def downgrade():
    op.drop_table("sepidar_native_maps")
    for column in ("native_last_error", "native_summary", "native_enabled"):
        op.drop_column("sepidar_import_settings", column)
    op.drop_column("sepidar_import_rows", "is_deleted")
