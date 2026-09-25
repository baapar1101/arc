"""Resolve or create a customer entered directly in a customer search field."""
from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Iterable

from sqlalchemy import and_, func, literal, or_, text
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.person import (
    PersonCreateRequest,
    PersonType as PersonRequestType,
)
from adapters.db.models.person import Person
from app.core.responses import ApiError
from app.services.person_service import create_person
from app.services.telephony.phone_normalizer import normalize_iran_phone, numbers_match


_NAME_TRANSLATION = str.maketrans({"ي": "ی", "ى": "ی", "ك": "ک", "ۀ": "ه"})
_CANDIDATE_FETCH_LIMIT = 500


@dataclass(frozen=True)
class QuickCustomerResolution:
    persons: list[Person]
    created: bool


def clean_customer_alias(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.translate(_NAME_TRANSLATION).replace("‌", " ")
    cleaned = " ".join(cleaned.split())
    return cleaned or None


def normalize_customer_alias(value: str | None) -> str:
    return (clean_customer_alias(value) or "").casefold()


def normalize_customer_mobile(value: str | None) -> str | None:
    if value is None or not str(value).strip():
        return None
    canonical = normalize_iran_phone(str(value)).get("canonical")
    if canonical and re.fullmatch(r"09\d{9}", canonical):
        return canonical
    return None


def alias_search_variants(alias: str) -> set[str]:
    """Variants covering Arabic/Persian yeh/kaf so SQL prefilter does not miss rows."""
    cleaned = clean_customer_alias(alias) or alias
    return {
        cleaned,
        cleaned.replace("ی", "ي").replace("ک", "ك"),
        cleaned.replace("ي", "ی").replace("ك", "ک"),
    }


def mobile_search_needles(mobile: str) -> set[str]:
    """Digit fragments useful for SQL prefiltering of stored phone fields."""
    digits = re.sub(r"\D", "", mobile)
    needles = {digits}
    if digits.startswith("0") and len(digits) >= 11:
        without_zero = digits[1:]
        needles.add(without_zero)
        needles.add(f"98{without_zero}")
    elif digits.startswith("98") and len(digits) >= 12:
        local = digits[2:]
        needles.add(local)
        needles.add(f"0{local}")
    elif len(digits) == 10 and digits.startswith("9"):
        needles.add(f"0{digits}")
        needles.add(f"98{digits}")
    return {needle for needle in needles if len(needle) >= 10}


def _person_alias_candidates(person: Person) -> set[str]:
    raw_values = {
        person.alias_name,
        person.first_name,
        person.last_name,
        person.company_name,
        " ".join(
            value
            for value in (person.alias_name, person.first_name, person.last_name)
            if value
        ),
        " ".join(
            value for value in (person.first_name, person.last_name) if value
        ),
    }
    return {
        normalized
        for normalized in (normalize_customer_alias(value) for value in raw_values)
        if normalized
    }


def person_matches_quick_customer_entry(
    person: Person,
    *,
    alias_name: str | None,
    mobile: str | None,
) -> bool:
    if mobile:
        stored_numbers = (
            person.mobile,
            person.mobile_2,
            person.mobile_3,
            person.phone,
        )
        # When a mobile is supplied it is the customer identity. A matching
        # name with another mobile must remain eligible for a new record.
        return any(
            numbers_match(mobile, stored, min_len=10)
            for stored in stored_numbers
        )

    normalized_alias = normalize_customer_alias(alias_name)
    if normalized_alias:
        for candidate in _person_alias_candidates(person):
            if normalized_alias in candidate or candidate in normalized_alias:
                return True

    return False


def _person_matches_mobile(person: Person, mobile: str) -> bool:
    stored_numbers = (
        person.mobile,
        person.mobile_2,
        person.mobile_3,
        person.phone,
    )
    return any(numbers_match(mobile, stored, min_len=10) for stored in stored_numbers)


def find_quick_customer_matches(
    persons: Iterable[Person],
    *,
    alias_name: str | None,
    mobile: str | None,
    limit: int = 20,
) -> list[Person]:
    candidates = list(persons)

    # با وجود موبایل، نام هیچ‌وقت معیار تطبیق نیست. این کار اجازه می‌دهد
    # دو مشتری هم‌نام با موبایل‌های متفاوت بدون هشدار ثبت شوند.
    if mobile:
        return [
            person for person in candidates if _person_matches_mobile(person, mobile)
        ][:limit]

    normalized_alias = normalize_customer_alias(alias_name)
    if not normalized_alias:
        return []

    exact_matches: list[Person] = []
    similar_matches: list[Person] = []
    for person in candidates:
        aliases = _person_alias_candidates(person)
        if normalized_alias in aliases:
            exact_matches.append(person)
        elif any(
            normalized_alias in candidate or candidate in normalized_alias
            for candidate in aliases
        ):
            similar_matches.append(person)

    # نام دقیق نیز قبل از نتایج جزئی انتخاب می‌شود. چند رکورد دقیق همچنان برای
    # انتخاب صریح کاربر برگردانده می‌شوند و رکورد تازه ساخته نمی‌شود.
    return (exact_matches or similar_matches)[:limit]


def _name_column_filters(column, variants: set[str]):
    filters = []
    for variant in variants:
        like = f"%{variant}%"
        filters.append(column.ilike(like))
        # نام کوتاه ذخیره‌شده داخل ورودی بلندتر (مثل alias=علی و ورودی=علی رضایی)
        filters.append(
            and_(
                column.isnot(None),
                column != "",
                literal(variant).ilike(func.concat("%", column, "%")),
            )
        )
    return filters


def load_quick_customer_candidates(
    db: Session,
    *,
    business_id: int,
    alias_name: str | None,
    mobile: str | None,
    limit: int = _CANDIDATE_FETCH_LIMIT,
) -> list[Person]:
    """Load a bounded candidate set instead of every person in the business."""
    filters = []
    if mobile:
        phone_columns = (Person.mobile, Person.mobile_2, Person.mobile_3, Person.phone)
        for needle in mobile_search_needles(mobile):
            like = f"%{needle}%"
            for column in phone_columns:
                filters.append(and_(column.isnot(None), column.ilike(like)))

    # If a mobile is present, only load phone candidates. Mixing common-name
    # candidates into this bounded query could hide the actual mobile match.
    if alias_name and not mobile:
        variants = alias_search_variants(alias_name)
        name_columns = (
            Person.alias_name,
            Person.first_name,
            Person.last_name,
            Person.company_name,
        )
        for column in name_columns:
            filters.extend(_name_column_filters(column, variants))

        # ترکیب نام+نام‌خانوادگی برای حالتی که فقط جداگانه ذخیره شده‌اند
        full_name = func.concat(
            func.coalesce(Person.first_name, ""),
            " ",
            func.coalesce(Person.last_name, ""),
        )
        for variant in variants:
            like = f"%{variant}%"
            filters.append(full_name.ilike(like))
            filters.append(
                and_(
                    or_(Person.first_name.isnot(None), Person.last_name.isnot(None)),
                    literal(variant).ilike(func.concat("%", full_name, "%")),
                )
            )

    query = (
        db.query(Person)
        .filter(Person.business_id == int(business_id))
        .order_by(Person.alias_name, Person.id)
    )
    if filters:
        query = query.filter(or_(*filters))
    else:
        return []

    return query.limit(int(limit)).all()


def resolve_or_create_quick_customer(
    db: Session,
    *,
    business_id: int,
    alias_name: str | None,
    mobile: str | None,
) -> QuickCustomerResolution:
    cleaned_alias = clean_customer_alias(alias_name)
    normalized_mobile = normalize_customer_mobile(mobile)
    if mobile and not normalized_mobile:
        raise ApiError("INVALID_CUSTOMER_MOBILE", "شماره موبایل معتبر نیست")
    if not cleaned_alias and not normalized_mobile:
        raise ApiError(
            "CUSTOMER_QUICK_ENTRY_REQUIRED",
            "نام مشتری یا شماره موبایل را وارد کنید",
        )

    # درخواست‌های هم‌زمان یک کسب‌وکار نباید بین بررسی تکراری و ایجاد فاصله بیفتند.
    bind = db.get_bind()
    if bind is not None and bind.dialect.name == "postgresql":
        db.execute(
            text("SELECT pg_advisory_xact_lock(:namespace, :business_id)"),
            {"namespace": 1129665364, "business_id": int(business_id)},
        )

    persons = load_quick_customer_candidates(
        db,
        business_id=int(business_id),
        alias_name=cleaned_alias,
        mobile=normalized_mobile,
    )
    matches = find_quick_customer_matches(
        persons,
        alias_name=cleaned_alias,
        mobile=normalized_mobile,
    )
    if matches:
        return QuickCustomerResolution(persons=matches, created=False)

    stored_alias = cleaned_alias or normalized_mobile
    assert stored_alias is not None
    result = create_person(
        db,
        int(business_id),
        PersonCreateRequest(
            alias_name=stored_alias,
            mobile=normalized_mobile,
            person_types=[PersonRequestType.CUSTOMER],
        ),
    )
    person_id = int(result["data"]["id"])
    created = (
        db.query(Person)
        .filter(
            Person.business_id == int(business_id),
            Person.id == person_id,
        )
        .one()
    )
    return QuickCustomerResolution(persons=[created], created=True)
