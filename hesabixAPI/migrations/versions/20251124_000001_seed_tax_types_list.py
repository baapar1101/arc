"""seed standard tax types with legacy options

Revision ID: 20251124_000001_seed_tax_types_list
Revises: 20250130_000001_create_tax_settings_table
Create Date: 2025-11-24 09:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251124_000001_seed_tax_types_list'
down_revision = '20250130_000001_create_tax_settings_table'
branch_labels = None
depends_on = None


LEGACY_TAX_TYPES = [
    (1, "۱- دارو", "1"),
    (2, "۲- دخانیات", "2"),
    (3, "۳- موبایل", "3"),
    (4, "۴- لوازم خانگی برقی", "4"),
    (5, "۵- قطعات مصرفی و یدکی وسایل نقلیه", "5"),
    (6, "۶- فراورده ها و مشتقات نفتی و گازی و پتروشیمیایی", "6"),
    (7, "۷- طلا اعم از شمش ،مسکوکات و مصنوعات زینتی", "7"),
    (8, "۸- منسوجات و پوشاک", "8"),
    (9, "۹- اسباب بازی", "9"),
    (10, "۱۰- دام زنده، گوشت سفید و قرمز", "10"),
    (11, "۱۱- محصولات اساسی کشاورزی", "11"),
    (12, "۱۲- سایر کالا ها", "12"),
]


def upgrade() -> None:
    conn = op.get_bind()
    conn.execute(sa.text("DELETE FROM tax_types"))

    insert_stmt = sa.text(
        """
        INSERT INTO tax_types (id, title, code, description, created_at, updated_at)
        VALUES (:id, :title, :code, :description, NOW(), NOW())
        """
    )
    for tax_id, title, code in LEGACY_TAX_TYPES:
        conn.execute(
            insert_stmt,
            {
                "id": tax_id,
                "title": title,
                "code": code,
                "description": None,
            },
        )


def downgrade() -> None:
    conn = op.get_bind()
    codes = [code for _, _, code in LEGACY_TAX_TYPES]
    conn.execute(
        sa.text("DELETE FROM tax_types WHERE code IN :codes"),
        {"codes": tuple(codes)},
    )


