"""seed standard measurement units into tax_units

Revision ID: 20250106_000004
Revises: 20250106_000003
Create Date: 2025-10-06 13:10:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20250106_000004'
down_revision = '20250106_000003'
branch_labels = None
depends_on = None


UNIT_NAMES = [
    "بانكه", "برگ", "بسته", "بشكه", "بطری", "بندیل", "پاکت", "پالت", "تانكر", "تخته",
    "تن", "تن کیلومتر", "توپ", "تیوب", "ثانیه", "ثوب", "جام", "جعبه", "جفت", "جلد",
    "چلیك", "حلب", "حلقه (رول)", "حلقه (دیسک)", "حلقه (رینگ)", "دبه", "دست", "دستگاه",
    "دقیقه", "دوجین", "روز", "رول", "ساشه", "ساعت", "سال", "سانتی متر",
    "سانتی متر مربع", "سبد", "ست", "سطل", "سیلندر", "شاخه", "شانه", "شعله", "شیت",
    "صفحه", "طاقه", "طغرا", "عدد", "عدل", "فاقد بسته بندی", "فروند", "فوت مربع", "قالب",
    "قراص", "قراصه (bundle)", "قرقره", "قطعه", "قوطي", "قیراط", "کارتن",
    "کارتن (master case)", "کلاف", "کپسول", "کیسه", "کیلوگرم", "کیلومتر", "کیلووات ساعت",
    "گالن", "گرم", "گیگابایت بر ثانیه", "لنگه", "لیتر", "لیوان", "ماه", "متر",
    "متر مربع", "متر مكعب", "مخزن", "مگاوات ساعت", "میلي گرم", "میلي لیتر", "میلي متر",
    "نخ", "نسخه (جلد)", "نفر", "نفر- ساعت", "نوبت", "نیم دوجین", "واحد", "ورق", "ویال",
]


def _slugify(name: str) -> str:
    # Create a simple ASCII-ish code: replace spaces and special chars with underscore, keep letters/numbers
    code = name
    for ch in [' ', '-', '(', ')', '–', 'ـ', '،', '/', '\\']:
        code = code.replace(ch, '_')
    code = code.replace('‌', '_')  # zero-width non-joiner
    # collapse underscores
    while '__' in code:
        code = code.replace('__', '_')
    return code.strip('_').upper()


def upgrade() -> None:
    conn = op.get_bind()

    # Insert units if not already present (by code)
    for name in UNIT_NAMES:
        code = _slugify(name)
        exists = conn.execute(sa.text("SELECT id FROM tax_units WHERE code = :code LIMIT 1"), {"code": code}).fetchone()
        if not exists:
            conn.execute(
                sa.text(
                    """
                    INSERT INTO tax_units (name, code, description, created_at, updated_at)
                    VALUES (:name, :code, :description, NOW(), NOW())
                    """
                ),
                {"name": name, "code": code, "description": None},
            )
            conn.commit()


def downgrade() -> None:
    conn = op.get_bind()
    # Remove only units we added (by code set)
    codes = [_slugify(n) for n in UNIT_NAMES]
    conn.execute(
        sa.text("DELETE FROM tax_units WHERE code IN :codes"),
        {"codes": tuple(codes)},
    )


