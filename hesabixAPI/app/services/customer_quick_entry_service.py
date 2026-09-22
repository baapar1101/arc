"""Resolve or create a customer entered directly in a customer search field."""
from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Iterable

from sqlalchemy import text
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
        if any(numbers_match(mobile, stored, min_len=10) for stored in stored_numbers):
            return True

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

    # موبایل شناسه قوی‌تری از نام است. اگر پیدا شود، شباهت نام نباید اشخاص
    # دیگری را وارد نتیجه کند و جلوی انتخاب خودکار مشتری موجود را بگیرد.
    if mobile:
        mobile_matches = [
            person for person in candidates if _person_matches_mobile(person, mobile)
        ]
        if mobile_matches:
            return mobile_matches[:limit]

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

    persons = (
        db.query(Person)
        .filter(Person.business_id == int(business_id))
        .order_by(Person.alias_name, Person.id)
        .all()
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
