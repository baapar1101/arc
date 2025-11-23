"""add description to categories table

Revision ID: 20250123_000001_add_description_to_categories
Revises: 20250122_000001_add_last_reset_at_and_expires_at_to_ai_subscriptions
Create Date: 2025-01-23 00:00:01.000001

"""

from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "20250123_000001_add_description_to_categories"
down_revision: Union[str, None] = "023c8d2d2222"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    table_name = "categories"
    
    if table_name in inspector.get_table_names():
        columns = {col["name"] for col in inspector.get_columns(table_name)}
        if "description" not in columns:
            op.add_column(
                table_name,
                sa.Column(
                    "description",
                    sa.Text(),
                    nullable=True,
                    comment="توضیحات دسته‌بندی",
                ),
            )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    table_name = "categories"
    
    if table_name in inspector.get_table_names():
        columns = {col["name"] for col in inspector.get_columns(table_name)}
        if "description" in columns:
            op.drop_column(table_name, "description")

