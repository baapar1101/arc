from types import SimpleNamespace
from unittest.mock import Mock

import pytest

from app.core.auth_dependency import AuthContext
from app.core.responses import ApiError
from app.services.customer_quick_entry_service import (
    alias_search_variants,
    clean_customer_alias,
    find_quick_customer_matches,
    mobile_search_needles,
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
        code=None,
        email=None,
        address=None,
        created_at=None,
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


def test_alias_and_mobile_search_helpers_cover_common_variants():
    assert "علی" in alias_search_variants("علي")
    assert "علي" in alias_search_variants("علی")
    needles = mobile_search_needles("09121234567")
    assert "09121234567" in needles
    assert "9121234567" in needles
    assert "989121234567" in needles


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


def test_different_mobile_does_not_match_an_identical_name():
    persons = [
        _person(1, "موسوی", mobile="09207201219"),
        _person(2, "موسوی فروشگاه", mobile="09351234567"),
    ]
    matches = find_quick_customer_matches(
        persons,
        alias_name="موسوی",
        mobile="09171006219",
    )
    assert matches == []


def test_same_mobile_returns_all_duplicates_regardless_of_name():
    persons = [
        _person(1, "موسوی", mobile="09171006219"),
        _person(2, "مشتری دیگر", mobile="+989171006219"),
        _person(3, "موسوی", mobile="09207201219"),
    ]
    matches = find_quick_customer_matches(
        persons,
        alias_name="موسوی",
        mobile="09171006219",
    )
    assert [person.id for person in matches] == [1, 2]


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


@pytest.mark.asyncio
async def test_quick_resolve_requires_business_access(monkeypatch):
    from adapters.api.v1.customers import (
        CustomerQuickResolveRequest,
        quick_resolve_customer,
    )

    user = Mock()
    user.id = 999
    ctx = AuthContext(user=user, api_key_id=1, db=Mock())
    ctx.can_access_business = Mock(return_value=False)

    with pytest.raises(ApiError) as exc:
        await quick_resolve_customer(
            request=Mock(),
            payload=CustomerQuickResolveRequest(
                business_id=15,
                alias_name="علی",
            ),
            ctx=ctx,
            db=Mock(),
        )

    assert exc.value.status_code == 403
    assert exc.value.code == "FORBIDDEN"


@pytest.mark.asyncio
async def test_quick_resolve_allows_business_member(monkeypatch):
    from adapters.api.v1 import customers as customers_api
    from adapters.api.v1.customers import (
        CustomerQuickResolveRequest,
        quick_resolve_customer,
    )
    from app.services.customer_quick_entry_service import QuickCustomerResolution

    user = Mock()
    user.id = 1
    ctx = AuthContext(user=user, api_key_id=1, db=Mock())
    ctx.can_access_business = Mock(return_value=True)

    person = _person(7, "علی رضایی", mobile="09121234567")
    monkeypatch.setattr(
        customers_api,
        "resolve_or_create_quick_customer",
        lambda *args, **kwargs: QuickCustomerResolution(
            persons=[person],
            created=False,
        ),
    )

    response = await quick_resolve_customer(
        request=Mock(),
        payload=CustomerQuickResolveRequest(
            business_id=15,
            alias_name="علی رضایی",
            mobile="09121234567",
        ),
        ctx=ctx,
        db=Mock(),
    )

    assert response.created is False
    assert len(response.customers) == 1
    assert response.customers[0].id == 7
    ctx.can_access_business.assert_called_once_with(15)
