"""add person_share_links table

Revision ID: 20251119_000001_add_person_share_links
Revises: 20251118_000001_add_document_monetization
Create Date: 2025-11-19 00:00:01.000001

"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "20251119_000001_add_person_share_links"
down_revision = "20251118_000001_add_document_monetization"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    table_name = "person_share_links"

    if table_name not in inspector.get_table_names():
        op.create_table(
            table_name,
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column(
                "business_id",
                sa.Integer(),
                sa.ForeignKey("businesses.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "person_id",
                sa.Integer(),
                sa.ForeignKey("persons.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "created_by_user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="SET NULL"),
                nullable=True,
            ),
            sa.Column(
                "revoked_by_user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="SET NULL"),
                nullable=True,
            ),
            sa.Column("code", sa.String(length=16), nullable=False, unique=True),
            sa.Column("token_hash", sa.String(length=128), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("expires_at", sa.DateTime(), nullable=True),
            sa.Column("revoked_at", sa.DateTime(), nullable=True),
            sa.Column("last_view_at", sa.DateTime(), nullable=True),
            sa.Column("view_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
            sa.Column("max_view_count", sa.Integer(), nullable=True),
            sa.Column("options", sa.JSON(), nullable=True),
            sa.Column("meta", sa.JSON(), nullable=True),
            sa.UniqueConstraint("code", name="uq_person_share_links_code"),
        )
        op.create_index(
            "ix_person_share_links_code", table_name, ["code"], unique=False
        )
        op.create_index(
            "ix_person_share_links_person_id", table_name, ["person_id"], unique=False
        )
        op.create_index(
            "ix_person_share_links_business_id", table_name, ["business_id"], unique=False
        )
    else:
        existing_indexes = {
            idx["name"] for idx in inspector.get_indexes(table_name)
        }
        if "ix_person_share_links_code" not in existing_indexes:
            op.create_index(
                "ix_person_share_links_code", table_name, ["code"], unique=False
            )
        if "ix_person_share_links_person_id" not in existing_indexes:
            op.create_index(
                "ix_person_share_links_person_id", table_name, ["person_id"], unique=False
            )
        if "ix_person_share_links_business_id" not in existing_indexes:
            op.create_index(
                "ix_person_share_links_business_id",
                table_name,
                ["business_id"],
                unique=False,
            )


def downgrade() -> None:
    op.drop_index("ix_person_share_links_business_id", table_name="person_share_links")
    op.drop_index("ix_person_share_links_person_id", table_name="person_share_links")
    op.drop_index("ix_person_share_links_code", table_name="person_share_links")
    op.drop_table("person_share_links")

