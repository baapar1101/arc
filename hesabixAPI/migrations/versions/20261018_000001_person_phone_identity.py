"""Add indexed international phone identities for persons.

Revision ID: 20261018_000001_person_phone_identity
Revises: 20261017_000001_quick_sales_audit_permissions
"""

from __future__ import annotations

import phonenumbers
import sqlalchemy as sa
from alembic import op
from phonenumbers import NumberParseException, PhoneNumberFormat

revision = "20261018_000001_person_phone_identity"
down_revision = "20261017_000001_quick_sales_audit_permissions"
branch_labels = None
depends_on = None

_DIGIT_TRANSLATION = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "0123456789" * 2)
_PHONE_COLUMNS = ("mobile", "mobile_2", "mobile_3", "phone")


def _normalize(value: str | None, region: str) -> str | None:
    if value is None:
        return None
    raw = str(value).translate(_DIGIT_TRANSLATION).strip()
    if not raw:
        return None
    compact = "".join(char for char in raw if char.isdigit() or char == "+")
    if compact.startswith("00"):
        compact = f"+{compact[2:]}"
    parse_region = None if compact.startswith("+") else region
    try:
        parsed = phonenumbers.parse(compact, parse_region)
    except NumberParseException:
        return None
    if not phonenumbers.is_valid_number(parsed):
        return None
    return phonenumbers.format_number(parsed, PhoneNumberFormat.E164)


def _backfill() -> None:
    connection = op.get_bind()
    region_rows = connection.execute(
        sa.text("SELECT id, default_phone_region FROM businesses")
    ).mappings()
    regions = {
        int(row["id"]): str(row["default_phone_region"] or "IR").upper() for row in region_rows
    }
    result = connection.execute(
        sa.text(
            """
            SELECT id, business_id, mobile, mobile_2, mobile_3, phone
            FROM persons
            ORDER BY id
            """
        )
    ).mappings()
    update_sql = sa.text(
        """
        UPDATE persons
        SET mobile_normalized = :mobile_normalized,
            mobile_2_normalized = :mobile_2_normalized,
            mobile_3_normalized = :mobile_3_normalized,
            phone_normalized = :phone_normalized
        WHERE id = :id
        """
    )
    while True:
        rows = result.fetchmany(1000)
        if not rows:
            break
        updates = []
        for row in rows:
            region = regions.get(int(row["business_id"]), "IR")
            if region not in phonenumbers.SUPPORTED_REGIONS:
                region = "IR"
            updates.append(
                {
                    "id": int(row["id"]),
                    **{
                        f"{field}_normalized": _normalize(row[field], region)
                        for field in _PHONE_COLUMNS
                    },
                }
            )
        if updates:
            connection.execute(update_sql, updates)


def upgrade() -> None:
    op.add_column(
        "businesses",
        sa.Column(
            "default_phone_region",
            sa.String(length=2),
            nullable=False,
            server_default="IR",
            comment="ISO-3166 alpha-2 region used to parse local phone numbers",
        ),
    )
    for field in _PHONE_COLUMNS:
        op.add_column(
            "persons",
            sa.Column(f"{field}_normalized", sa.String(length=32), nullable=True),
        )

    _backfill()

    for field in _PHONE_COLUMNS:
        op.create_index(
            f"ix_persons_business_{field}_normalized",
            "persons",
            ["business_id", f"{field}_normalized"],
            unique=False,
        )


def downgrade() -> None:
    for field in reversed(_PHONE_COLUMNS):
        op.drop_index(f"ix_persons_business_{field}_normalized", table_name="persons")
        op.drop_column("persons", f"{field}_normalized")
    op.drop_column("businesses", "default_phone_region")
