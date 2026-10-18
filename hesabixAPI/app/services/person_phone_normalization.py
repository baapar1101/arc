"""Canonical, business-aware phone normalization for person identity lookups."""

from __future__ import annotations

from typing import TYPE_CHECKING

import phonenumbers
from phonenumbers import NumberParseException, PhoneNumberFormat

if TYPE_CHECKING:
    from sqlalchemy.orm import Session


DEFAULT_PHONE_REGION = "IR"
PHONE_REGION_SESSION_CACHE_KEY = "person_phone_regions"
PHONE_FIELDS = ("mobile", "mobile_2", "mobile_3", "phone")
NORMALIZED_PHONE_FIELDS = tuple(f"{field}_normalized" for field in PHONE_FIELDS)
_DIGIT_TRANSLATION = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "0123456789" * 2)


def normalize_phone_region(value: str | None, *, fallback: str = DEFAULT_PHONE_REGION) -> str:
    """Return an ISO-3166 alpha-2 region understood by libphonenumber."""
    candidate = str(value or "").strip().upper()
    if candidate in phonenumbers.SUPPORTED_REGIONS:
        return candidate
    fallback_value = str(fallback or DEFAULT_PHONE_REGION).strip().upper()
    if fallback_value in phonenumbers.SUPPORTED_REGIONS:
        return fallback_value
    return DEFAULT_PHONE_REGION


def validate_phone_region(value: str | None) -> str:
    """Validate a user supplied default region without silently changing it."""
    candidate = str(value or "").strip().upper()
    if candidate not in phonenumbers.SUPPORTED_REGIONS:
        raise ValueError("کد کشور شماره تلفن معتبر نیست؛ مانند IR، AE، TR یا US")
    return candidate


def normalize_phone_e164(
    value: str | None, *, default_region: str = DEFAULT_PHONE_REGION
) -> str | None:
    """Normalize a valid local or international number to E.164.

    Numbers that start with ``+`` or ``00`` carry their own country code. Local
    numbers use the business' default region. Invalid or ambiguous values are
    deliberately left unresolved instead of manufacturing an identity key.
    """
    if value is None:
        return None
    raw = str(value).translate(_DIGIT_TRANSLATION).strip()
    if not raw:
        return None
    compact = "".join(char for char in raw if char.isdigit() or char == "+")
    if compact.startswith("00"):
        compact = f"+{compact[2:]}"
    if not compact:
        return None
    region = None if compact.startswith("+") else normalize_phone_region(default_region)
    try:
        parsed = phonenumbers.parse(compact, region)
    except NumberParseException:
        return None
    if not phonenumbers.is_valid_number(parsed):
        return None
    return phonenumbers.format_number(parsed, PhoneNumberFormat.E164)


def normalized_person_phone_values(
    *,
    default_region: str,
    mobile: str | None = None,
    mobile_2: str | None = None,
    mobile_3: str | None = None,
    phone: str | None = None,
) -> dict[str, str | None]:
    raw_values = {
        "mobile": mobile,
        "mobile_2": mobile_2,
        "mobile_3": mobile_3,
        "phone": phone,
    }
    return {
        f"{field}_normalized": normalize_phone_e164(value, default_region=default_region)
        for field, value in raw_values.items()
    }


def invalidate_business_phone_region_cache(db: "Session", business_id: int) -> None:
    """Discard one business region cached for ORM person hooks."""
    cache = db.info.get(PHONE_REGION_SESSION_CACHE_KEY)
    if isinstance(cache, dict):
        cache.pop(int(business_id), None)


def renormalize_business_person_phones(
    db: "Session",
    *,
    business_id: int,
    default_region: str,
    batch_size: int = 1000,
) -> int:
    """Rebuild indexed phone identities after a business region changes.

    Raw phone values remain unchanged. Rows are read and updated in bounded
    batches so a business with many persons does not have to load them all into
    the ORM identity map at once.
    """
    from adapters.db.models.person import Person

    region = validate_phone_region(default_region)
    updated_count = 0
    last_id = 0
    while True:
        rows = (
            db.query(
                Person.id,
                Person.mobile,
                Person.mobile_2,
                Person.mobile_3,
                Person.phone,
            )
            .filter(
                Person.business_id == int(business_id),
                Person.id > int(last_id),
            )
            .order_by(Person.id)
            .limit(int(batch_size))
            .all()
        )
        if not rows:
            break

        mappings = []
        for row in rows:
            mappings.append(
                {
                    "id": int(row.id),
                    **normalized_person_phone_values(
                        default_region=region,
                        mobile=row.mobile,
                        mobile_2=row.mobile_2,
                        mobile_3=row.mobile_3,
                        phone=row.phone,
                    ),
                }
            )
        db.bulk_update_mappings(Person, mappings)
        updated_count += len(mappings)
        last_id = int(rows[-1].id)

    return updated_count
