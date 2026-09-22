from types import SimpleNamespace

from app.services.customer_quick_entry_service import (
    clean_customer_alias,
    find_quick_customer_matches,
    normalize_customer_alias,
    normalize_customer_mobile,
)


def _person(
    person_id: int,
    alias_name: str,
    *,
    mobile: str | None = None,
    first_name: str | None = None,
    last_name: str | None = None,
):
    return SimpleNamespace(
        id=person_id,
        alias_name=alias_name,
        first_name=first_name,
        last_name=last_name,
        company_name=None,
        mobile=mobile,
        mobile_2=None,
        mobile_3=None,
        phone=None,
    )


def test_normalizes_customer_alias_and_mobile_variants():
    assert clean_customer_alias("  علي   رضايي  ") == "علی رضایی"
    assert normalize_customer_alias("علي‌ رضايي") == "علی رضایی"
    assert normalize_customer_mobile("+98 912 123 4567") == "09121234567"
    assert normalize_customer_mobile("۰۹۱۲۱۲۳۴۵۶۷") == "09121234567"


def test_finds_existing_person_by_mobile_before_creation():
    persons = [_person(1, "علی رضایی", mobile="+989121234567")]
    matches = find_quick_customer_matches(
        persons,
        alias_name=None,
        mobile="09121234567",
    )
    assert [person.id for person in matches] == [1]


def test_finds_similar_normalized_alias():
    persons = [
        _person(1, "علی رضایی"),
        _person(2, "زهرا موسوی"),
    ]
    matches = find_quick_customer_matches(
        persons,
        alias_name="علي",
        mobile=None,
    )
    assert [person.id for person in matches] == [1]


def test_finds_name_split_between_person_fields():
    persons = [
        _person(
            1,
            "محمدرضا",
            first_name="محمدرضا",
            last_name="حسینی",
        )
    ]
    matches = find_quick_customer_matches(
        persons,
        alias_name="محمدرضا حسینی",
        mobile=None,
    )
    assert [person.id for person in matches] == [1]


def test_mobile_match_takes_priority_over_similar_names():
    persons = [
        _person(1, "علی رضایی", mobile="09121234567"),
        _person(2, "علی رضایی فروشگاه"),
    ]
    matches = find_quick_customer_matches(
        persons,
        alias_name="علی رضایی",
        mobile="+989121234567",
    )
    assert [person.id for person in matches] == [1]


def test_exact_name_takes_priority_over_partial_names():
    persons = [
        _person(1, "علی رضایی فروشگاه"),
        _person(2, "علی رضایی"),
    ]
    matches = find_quick_customer_matches(
        persons,
        alias_name="علی رضایی",
        mobile=None,
    )
    assert [person.id for person in matches] == [2]


def test_returns_all_similar_names_when_there_is_no_exact_match():
    persons = [
        _person(1, "علی رضایی"),
        _person(2, "علی احمدی"),
        _person(3, "زهرا موسوی"),
    ]
    matches = find_quick_customer_matches(
        persons,
        alias_name="علی",
        mobile=None,
    )
    assert [person.id for person in matches] == [1, 2]
