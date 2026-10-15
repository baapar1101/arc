from types import SimpleNamespace
from unittest.mock import MagicMock, Mock

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
    resolve_or_create_quick_customer,
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


@pytest.mark.parametrize("configured_group_id", [None, 27])
def test_new_quick_customer_uses_group_from_quick_sales_settings(
    monkeypatch,
    configured_group_id,
):
    from adapters.db.models.person import Person
    from adapters.db.models.quick_sales_settings import QuickSalesSetting
    from app.services import customer_quick_entry_service as service

    db = MagicMock()
    db.get_bind.return_value = SimpleNamespace(dialect=SimpleNamespace(name="sqlite"))
    settings_query = MagicMock()
    settings_query.filter.return_value.first.return_value = (
        SimpleNamespace(quick_customer_group_id=configured_group_id)
        if configured_group_id is not None
        else None
    )
    created_person = _person(41, "مشتری جدید", mobile="09121234567")
    person_query = MagicMock()
    person_query.filter.return_value.one.return_value = created_person

    def query_for(model):
        if model is QuickSalesSetting:
            return settings_query
        if model is Person:
            return person_query
        return MagicMock()

    db.query.side_effect = query_for
    monkeypatch.setattr(service, "load_quick_customer_candidates", lambda *args, **kwargs: [])
    captured_request = {}

    def fake_create_person(_db, _business_id, request):
        captured_request["value"] = request
        return {"data": {"id": 41}}

    monkeypatch.setattr(service, "create_person", fake_create_person)

    result = resolve_or_create_quick_customer(
        db,
        business_id=8,
        alias_name="مشتری جدید",
        mobile="09121234567",
    )

    assert result.created is True
    assert result.persons == [created_person]
    assert captured_request["value"].person_group_id == configured_group_id


def test_existing_quick_customer_keeps_its_current_group(monkeypatch):
    from app.services import customer_quick_entry_service as service

    db = MagicMock()
    db.get_bind.return_value = SimpleNamespace(dialect=SimpleNamespace(name="sqlite"))
    existing = _person(9, "مشتری موجود", mobile="09121234567")
    existing.person_group_id = 4
    monkeypatch.setattr(
        service,
        "load_quick_customer_candidates",
        lambda *args, **kwargs: [existing],
    )
    create_person = MagicMock()
    monkeypatch.setattr(service, "create_person", create_person)

    result = resolve_or_create_quick_customer(
        db,
        business_id=8,
        alias_name="مشتری موجود",
        mobile="09121234567",
    )

    assert result.created is False
    assert result.persons == [existing]
    assert existing.person_group_id == 4
    create_person.assert_not_called()
    db.query.assert_not_called()


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
