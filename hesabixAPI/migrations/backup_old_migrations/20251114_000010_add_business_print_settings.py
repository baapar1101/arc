from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "20251114_000010_add_business_print_settings"
down_revision: Union[str, None] = "20251107_170101_add_invoice_item_lines_and_migrate"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if "business_print_settings" not in inspector.get_table_names():
        op.create_table(
            "business_print_settings",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column(
                "business_id",
                sa.Integer(),
                sa.ForeignKey("businesses.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("document_type", sa.String(length=50), nullable=False),
            sa.Column(
                "show_logo",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("1"),
            ),
            sa.Column(
                "show_stamp",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("1"),
            ),
            sa.Column(
                "show_payments",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("1"),
            ),
            sa.Column(
                "show_installment_plan",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("1"),
            ),
            sa.Column("footer_note", sa.Text(), nullable=True),
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
            ),
            sa.UniqueConstraint(
                "business_id",
                "document_type",
                name="uq_business_print_settings_business_doc_type",
            ),
        )
        try:
            op.create_index(
                "ix_business_print_settings_business_id",
                "business_print_settings",
                ["business_id"],
            )
            op.create_index(
                "ix_business_print_settings_document_type",
                "business_print_settings",
                ["document_type"],
            )
        except Exception:
            # ایندکس‌ها اختیاری هستند؛ در صورت خطا ادامه می‌دهیم
            pass


def downgrade() -> None:
    try:
        op.drop_index(
            "ix_business_print_settings_document_type",
            table_name="business_print_settings",
        )
        op.drop_index(
            "ix_business_print_settings_business_id",
            table_name="business_print_settings",
        )
    except Exception:
        pass
    try:
        op.drop_table("business_print_settings")
    except Exception:
        pass


