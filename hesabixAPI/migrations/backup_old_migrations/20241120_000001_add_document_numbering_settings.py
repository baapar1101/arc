"""add business_document_numbering_settings table

Revision ID: 20241120_000001_add_document_numbering_settings
Revises: eb9be5452535
Create Date: 2024-11-20 00:00:01.000001

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "20241120_000001_add_document_numbering_settings"
down_revision: Union[str, None] = "eb9be5452535"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if "business_document_numbering_settings" not in inspector.get_table_names():
        op.create_table(
            "business_document_numbering_settings",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column(
                "business_id",
                sa.Integer(),
                sa.ForeignKey("businesses.id", ondelete="CASCADE"),
                nullable=False,
                index=True,
            ),
            sa.Column("document_type", sa.String(length=50), nullable=False, index=True),
            sa.Column("prefix", sa.String(length=20), nullable=True),
            sa.Column(
                "include_date",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("1"),
            ),
            sa.Column(
                "calendar_type",
                sa.String(length=10),
                nullable=False,
                server_default="gregorian",
            ),
            sa.Column("date_format", sa.String(length=20), nullable=True),
            sa.Column(
                "separator",
                sa.String(length=5),
                nullable=False,
                server_default="-",
            ),
            sa.Column(
                "start_number",
                sa.Integer(),
                nullable=False,
                server_default=sa.text("1"),
            ),
            sa.Column(
                "number_padding",
                sa.Integer(),
                nullable=False,
                server_default=sa.text("4"),
            ),
            sa.Column("reset_period", sa.String(length=20), nullable=True),
            sa.Column("custom_format", sa.String(length=100), nullable=True),
            sa.Column(
                "is_active",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("1"),
            ),
            sa.Column(
                "created_at",
                sa.DateTime(),
                nullable=False,
                server_default=sa.func.now(),
            ),
            sa.Column(
                "updated_at",
                sa.DateTime(),
                nullable=False,
                server_default=sa.func.now(),
                onupdate=sa.func.now(),
            ),
            sa.UniqueConstraint(
                "business_id",
                "document_type",
                name="uq_doc_numbering_business_type",
            ),
        )
        try:
            op.create_index(
                "ix_doc_numbering_business",
                "business_document_numbering_settings",
                ["business_id"],
            )
        except Exception:
            pass
        try:
            op.create_index(
                "ix_doc_numbering_type",
                "business_document_numbering_settings",
                ["document_type"],
            )
        except Exception:
            pass


def downgrade() -> None:
    try:
        op.drop_index("ix_doc_numbering_type", table_name="business_document_numbering_settings")
    except Exception:
        pass
    try:
        op.drop_index("ix_doc_numbering_business", table_name="business_document_numbering_settings")
    except Exception:
        pass
    try:
        op.drop_table("business_document_numbering_settings")
    except Exception:
        pass

