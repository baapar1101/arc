from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from app.services.person_phone_normalization import (
    normalize_phone_e164,
    normalize_phone_region,
    normalized_person_phone_values,
    renormalize_business_person_phones,
    validate_phone_region,
)


@pytest.mark.parametrize(
    ("raw", "region", "expected"),
    [
        ("0917 100 6219", "IR", "+989171006219"),
        ("۰۹۱۷۱۰۰۶۲۱۹", "IR", "+989171006219"),
        ("0098 917 100 6219", "US", "+989171006219"),
        ("+98 917 100 6219", "AE", "+989171006219"),
        ("050 123 4567", "AE", "+971501234567"),
        ("(415) 555-2671", "US", "+14155552671"),
        ("+49 151 23456789", "IR", "+4915123456789"),
    ],
)
def test_normalizes_local_and_international_numbers(raw, region, expected):
    assert normalize_phone_e164(raw, default_region=region) == expected


def test_invalid_number_is_not_assigned_an_identity():
    assert normalize_phone_e164("123", default_region="IR") is None


def test_validates_supported_business_region():
    assert normalize_phone_region("ae") == "AE"
    assert validate_phone_region("us") == "US"
    with pytest.raises(ValueError):
        validate_phone_region("XX")


def test_normalizes_all_person_phone_slots():
    values = normalized_person_phone_values(
        default_region="AE",
        mobile="050 123 4567",
        mobile_2="+1 415 555 2671",
        mobile_3=None,
        phone="04 234 5678",
    )
    assert values["mobile_normalized"] == "+971501234567"
    assert values["mobile_2_normalized"] == "+14155552671"
    assert values["mobile_3_normalized"] is None
    assert values["phone_normalized"] == "+97142345678"


def test_renormalizes_existing_persons_in_bounded_batches():
    db = MagicMock()
    rows = [
        SimpleNamespace(
            id=1,
            mobile="050 123 4567",
            mobile_2=None,
            mobile_3=None,
            phone="04 234 5678",
        ),
        SimpleNamespace(
            id=2,
            mobile="+1 415 555 2671",
            mobile_2=None,
            mobile_3=None,
            phone=None,
        ),
    ]
    all_rows = (
        db.query.return_value.filter.return_value.order_by.return_value.limit.return_value.all
    )
    all_rows.side_effect = [rows, []]

    count = renormalize_business_person_phones(
        db,
        business_id=8,
        default_region="AE",
        batch_size=2,
    )

    assert count == 2
    mappings = db.bulk_update_mappings.call_args.args[1]
    assert mappings[0]["mobile_normalized"] == "+971501234567"
    assert mappings[0]["phone_normalized"] == "+97142345678"
    assert mappings[1]["mobile_normalized"] == "+14155552671"


def test_person_orm_hook_populates_indexed_phone_identity():
    from adapters.db.models.person import Person, _sync_person_normalized_phones

    person = Person(
        business_id=8,
        alias_name="مشتری",
        person_types='["مشتری"]',
        mobile="۰۹۱۷۱۰۰۶۲۱۹",
    )
    connection = MagicMock()
    connection.execute.return_value.scalar_one_or_none.return_value = "IR"

    _sync_person_normalized_phones(None, connection, person)

    assert person.mobile_normalized == "+989171006219"
    connection.execute.assert_called_once()
