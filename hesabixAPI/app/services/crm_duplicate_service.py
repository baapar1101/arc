"""تشخیص شباهت سرنخ با سرنخ باز و شخص حسابداری.

کلید تلفن ده رقم آخر است تا ۰۹۱۲… و ‎+98912… یک هویت باشند.
"""
from __future__ import annotations

from typing import Any

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from adapters.db.models.crm import Lead
from adapters.db.models.person import Person
from app.core.responses import ApiError

_DIGIT_MAP = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")


def phone_match_key(value: str | None) -> str | None:
    if value is None:
        return None
    raw = str(value).strip().translate(_DIGIT_MAP)
    if not raw:
        return None
    e164 = None
    try:
        from app.services.person_phone_normalization import normalize_phone_e164

        e164 = normalize_phone_e164(raw)
    except Exception:
        e164 = None
    digits = "".join(ch for ch in (e164 or raw) if ch.isdigit())
    if not e164:
        if digits.startswith("0098"):
            digits = digits[4:]
        elif digits.startswith("98") and len(digits) >= 12:
            digits = digits[2:]
        elif digits.startswith("0"):
            digits = digits[1:]
    if len(digits) >= 10:
        return digits[-10:]
    return None


def email_match_key(value: str | None) -> str | None:
    if value is None:
        return None
    text = str(value).strip().lower()
    if "@" not in text or len(text) < 5:
        return None
    return text


def duplicate_should_block(matches: dict[str, Any], allow_similar: bool) -> bool:
    if allow_similar:
        return False
    return bool(matches.get("leads") or matches.get("persons"))


def _remember(bucket: list[dict[str, Any]], item: dict[str, Any]) -> None:
    for existing in bucket:
        if existing["id"] == item["id"] and existing["kind"] == item["kind"]:
            if item["match"] not in str(existing["match"]).split("+"):
                existing["match"] = f"{existing['match']}+{item['match']}"
            return
    bucket.append(item)


def _person_phones(person: Person) -> list[str | None]:
    return [
        person.mobile_normalized,
        person.mobile,
        person.mobile_2_normalized,
        person.mobile_2,
        person.mobile_3_normalized,
        person.mobile_3,
        person.phone_normalized,
        person.phone,
    ]


def find_lead_similarities(
    db: Session,
    business_id: int,
    mobile: str | None,
    email: str | None,
    *,
    exclude_lead_id: int | None = None,
    exclude_person_id: int | None = None,
) -> dict[str, list[dict[str, Any]]]:
    leads: list[dict[str, Any]] = []
    persons: list[dict[str, Any]] = []
    phone_key = phone_match_key(mobile)
    email_key = email_match_key(email)

    if phone_key:
        lead_rows = (
            db.query(Lead)
            .filter(
                Lead.business_id == business_id,
                Lead.person_id.is_(None),
                Lead.mobile.isnot(None),
                Lead.mobile.ilike(f"%{phone_key}"),
            )
            .limit(30)
            .all()
        )
        for row in lead_rows:
            if exclude_lead_id is not None and int(row.id) == int(exclude_lead_id):
                continue
            if phone_match_key(row.mobile) != phone_key:
                continue
            _remember(
                leads,
                {"kind": "lead", "id": int(row.id), "code": row.code, "name": row.name, "match": "phone"},
            )
        phone_columns = (
            Person.mobile_normalized,
            Person.mobile,
            Person.mobile_2_normalized,
            Person.mobile_2,
            Person.mobile_3_normalized,
            Person.mobile_3,
            Person.phone_normalized,
            Person.phone,
        )
        person_rows = (
            db.query(Person)
            .filter(Person.business_id == business_id, or_(*[col.ilike(f"%{phone_key}") for col in phone_columns]))
            .limit(30)
            .all()
        )
        for row in person_rows:
            if exclude_person_id is not None and int(row.id) == int(exclude_person_id):
                continue
            if not any(phone_match_key(value) == phone_key for value in _person_phones(row)):
                continue
            _remember(
                persons,
                {
                    "kind": "person",
                    "id": int(row.id),
                    "code": getattr(row, "code", None),
                    "name": row.alias_name,
                    "match": "phone",
                },
            )

    if email_key:
        email_leads = (
            db.query(Lead)
            .filter(
                Lead.business_id == business_id,
                Lead.person_id.is_(None),
                func.lower(Lead.email) == email_key,
            )
            .limit(20)
            .all()
        )
        for row in email_leads:
            if exclude_lead_id is not None and int(row.id) == int(exclude_lead_id):
                continue
            _remember(
                leads,
                {"kind": "lead", "id": int(row.id), "code": row.code, "name": row.name, "match": "email"},
            )
        email_persons = (
            db.query(Person)
            .filter(Person.business_id == business_id, func.lower(Person.email) == email_key)
            .limit(20)
            .all()
        )
        for row in email_persons:
            if exclude_person_id is not None and int(row.id) == int(exclude_person_id):
                continue
            _remember(
                persons,
                {
                    "kind": "person",
                    "id": int(row.id),
                    "code": getattr(row, "code", None),
                    "name": row.alias_name,
                    "match": "email",
                },
            )

    return {"leads": leads[:10], "persons": persons[:10]}


def assert_lead_identity_available(
    db: Session,
    business_id: int,
    mobile: str | None,
    email: str | None,
    *,
    allow_similar: bool = False,
    exclude_lead_id: int | None = None,
    exclude_person_id: int | None = None,
) -> dict[str, list[dict[str, Any]]]:
    matches = find_lead_similarities(
        db,
        business_id,
        mobile,
        email,
        exclude_lead_id=exclude_lead_id,
        exclude_person_id=exclude_person_id,
    )
    if duplicate_should_block(matches, allow_similar):
        raise ApiError(
            "CRM_LEAD_DUPLICATE",
            "سرنخ یا شخص مشابه با همین موبایل یا ایمیل وجود دارد (CRM_LEAD_DUPLICATE).",
            http_status=409,
            details=matches,
        )
    return matches
