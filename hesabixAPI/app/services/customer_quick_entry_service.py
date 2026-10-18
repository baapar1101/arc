"""Resolve or create a customer entered directly in a customer search field."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from sqlalchemy import and_, func, literal, or_, text
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.person import (
    PersonCreateRequest,
)
from adapters.api.v1.schema_models.person import (
    PersonType as PersonRequestType,
)
from adapters.db.models.business import Business
from adapters.db.models.person import Person
from adapters.db.models.quick_sales_settings import QuickSalesSetting
from app.core.responses import ApiError
from app.services.person_phone_normalization import (
    DEFAULT_PHONE_REGION,
    normalize_phone_e164,
    normalize_phone_region,
)
from app.services.person_service import create_person

_NAME_TRANSLATION = str.maketrans({"ي": "ی", "ى": "ی", "ك": "ک", "ۀ": "ه"})
_NAME_CANDIDATE_FETCH_LIMIT = 500


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


def normalize_customer_mobile(
    value: str | None,
    *,
    default_region: str = DEFAULT_PHONE_REGION,
) -> str | None:
    return normalize_phone_e164(value, default_region=default_region)


def alias_search_variants(alias: str) -> set[str]:
    """Variants covering Arabic/Persian yeh/kaf so SQL prefilter does not miss rows."""
    cleaned = clean_customer_alias(alias) or alias
    return {
        cleaned,
        cleaned.replace("ی", "ي").replace("ک", "ك"),
        cleaned.replace("ي", "ی").replace("ك", "ک"),
    }


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
        stored_numbers = (person.mobile, person.mobile_2, person.mobile_3, person.phone)
        # When a mobile is supplied it is the customer identity. A matching
        # name with another mobile must remain eligible for a new record.
        canonical = normalize_customer_mobile(mobile)
        return canonical is not None and any(
            normalize_customer_mobile(stored) == canonical for stored in stored_numbers
        )

    normalized_alias = normalize_customer_alias(alias_name)
    if normalized_alias:
        for candidate in _person_alias_candidates(person):
            if normalized_alias in candidate or candidate in normalized_alias:
                return True

    return False


def _person_matches_mobile(
    person: Person,
    mobile: str,
    *,
    default_region: str = DEFAULT_PHONE_REGION,
) -> bool:
    canonical = normalize_customer_mobile(mobile, default_region=default_region)
    if canonical is None:
        return False
    normalized_values = (
        getattr(person, "mobile_normalized", None),
        getattr(person, "mobile_2_normalized", None),
        getattr(person, "mobile_3_normalized", None),
        getattr(person, "phone_normalized", None),
    )
    if canonical in normalized_values:
        return True
    stored_numbers = (
        person.mobile,
        person.mobile_2,
        person.mobile_3,
        person.phone,
    )
    return any(
        normalize_customer_mobile(stored, default_region=default_region) == canonical
        for stored in stored_numbers
    )


def find_quick_customer_matches(
    persons: Iterable[Person],
    *,
    alias_name: str | None,
    mobile: str | None,
    limit: int = 20,
    default_region: str = DEFAULT_PHONE_REGION,
) -> list[Person]:
    candidates = list(persons)

    # با وجود موبایل، نام هیچ‌وقت معیار تطبیق نیست. این کار اجازه می‌دهد
    # دو مشتری هم‌نام با موبایل‌های متفاوت بدون هشدار ثبت شوند.
    if mobile:
        return [
            person
            for person in candidates
            if _person_matches_mobile(person, mobile, default_region=default_region)
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
    limit: int = _NAME_CANDIDATE_FETCH_LIMIT,
) -> list[Person]:
    """Load bounded fuzzy-name suggestions; phone identity uses an exact index."""
    filters = []
    if alias_name:
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


def get_business_default_phone_region(db: Session, business_id: int) -> str:
    value = (
        db.query(Business.default_phone_region)
        .filter(Business.id == int(business_id))
        .scalar()
    )
    return normalize_phone_region(value if isinstance(value, str) else None)


def load_quick_customer_mobile_matches(
    db: Session,
    *,
    business_id: int,
    normalized_mobile: str,
) -> list[Person]:
    """Find every matching person through indexed E.164 identity columns."""
    return (
        db.query(Person)
        .filter(
            Person.business_id == int(business_id),
            or_(
                Person.mobile_normalized == normalized_mobile,
                Person.mobile_2_normalized == normalized_mobile,
                Person.mobile_3_normalized == normalized_mobile,
                Person.phone_normalized == normalized_mobile,
            ),
        )
        .order_by(Person.id)
        .all()
    )


def load_exact_quick_customer_candidates(
    db: Session,
    *,
    business_id: int,
    alias_name: str | None,
) -> list[Person]:
    """تطبیق دقیق نام را مستقل از سقف نتایج مشابه انجام می‌دهد."""
    if not alias_name:
        return []
    variants = alias_search_variants(alias_name)
    name_columns = (
        Person.alias_name,
        Person.first_name,
        Person.last_name,
        Person.company_name,
    )
    exact_filters = [
        func.lower(func.trim(column)) == variant.casefold()
        for column in name_columns
        for variant in variants
    ]
    full_name = func.trim(
        func.concat(
            func.coalesce(Person.first_name, ""),
            " ",
            func.coalesce(Person.last_name, ""),
        )
    )
    exact_filters.extend(
        func.lower(full_name) == variant.casefold() for variant in variants
    )
    return (
        db.query(Person)
        .filter(
            Person.business_id == int(business_id),
            or_(*exact_filters),
        )
        .order_by(Person.id)
        .all()
    )


def resolve_or_create_quick_customer(
    db: Session,
    *,
    business_id: int,
    alias_name: str | None,
    mobile: str | None,
) -> QuickCustomerResolution:
    cleaned_alias = clean_customer_alias(alias_name)
    phone_region = get_business_default_phone_region(db, int(business_id))
    normalized_mobile = normalize_customer_mobile(mobile, default_region=phone_region)
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

    exact_persons = (
        load_exact_quick_customer_candidates(
            db,
            business_id=int(business_id),
            alias_name=cleaned_alias,
        )
        if not normalized_mobile
        else []
    )
    persons = (
        load_quick_customer_mobile_matches(
            db,
            business_id=int(business_id),
            normalized_mobile=normalized_mobile,
        )
        if normalized_mobile
        else load_quick_customer_candidates(
            db,
            business_id=int(business_id),
            alias_name=cleaned_alias,
        )
    )
    if exact_persons:
        seen_ids = {int(person.id) for person in exact_persons}
        persons = exact_persons + [
            person for person in persons if int(person.id) not in seen_ids
        ]
    matches = find_quick_customer_matches(
        persons,
        alias_name=cleaned_alias,
        mobile=normalized_mobile,
        default_region=phone_region,
    )
    if matches:
        return QuickCustomerResolution(persons=matches, created=False)

    stored_alias = cleaned_alias or normalized_mobile
    assert stored_alias is not None
    settings = (
        db.query(QuickSalesSetting)
        .filter(QuickSalesSetting.business_id == int(business_id))
        .first()
    )
    quick_customer_group_id = (
        int(settings.quick_customer_group_id)
        if settings is not None and settings.quick_customer_group_id is not None
        else None
    )
    result = create_person(
        db,
        int(business_id),
        PersonCreateRequest(
            alias_name=stored_alias,
            mobile=normalized_mobile,
            person_types=[PersonRequestType.CUSTOMER],
            person_group_id=quick_customer_group_id,
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
