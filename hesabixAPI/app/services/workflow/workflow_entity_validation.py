"""
اعتبارسنجی اینکه شناسه‌های استفاده‌شده در فیلترهای تریگر ورک‌فلو واقعاً به همان کسب‌وکار تعلق دارند.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from adapters.db.models.account import Account
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.currency import BusinessCurrency
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.person import Person
from adapters.db.models.project import Project


def validate_person_for_business(db: Session, business_id: int, person_id: Optional[int]) -> bool:
    if person_id is None:
        return True
    try:
        pid = int(person_id)
    except (TypeError, ValueError):
        return False
    row = db.execute(
        select(Person.id).where(and_(Person.id == pid, Person.business_id == int(business_id))).limit(1)
    ).scalar_one_or_none()
    return row is not None


def validate_project_for_business(db: Session, business_id: int, project_id: Optional[int]) -> bool:
    if project_id is None:
        return True
    try:
        prid = int(project_id)
    except (TypeError, ValueError):
        return False
    row = db.execute(
        select(Project.id).where(and_(Project.id == prid, Project.business_id == int(business_id))).limit(1)
    ).scalar_one_or_none()
    return row is not None


def validate_account_for_business(db: Session, business_id: int, account_id: Optional[int]) -> bool:
    if account_id is None:
        return True
    try:
        aid = int(account_id)
    except (TypeError, ValueError):
        return False
    row = db.execute(
        select(Account.id).where(and_(Account.id == aid, Account.business_id == int(business_id))).limit(1)
    ).scalar_one_or_none()
    return row is not None


def validate_bank_account_for_business(db: Session, business_id: int, bank_account_id: Optional[int]) -> bool:
    if bank_account_id is None:
        return True
    try:
        bid = int(bank_account_id)
    except (TypeError, ValueError):
        return False
    row = db.execute(
        select(BankAccount.id).where(
            and_(BankAccount.id == bid, BankAccount.business_id == int(business_id))
        ).limit(1)
    ).scalar_one_or_none()
    return row is not None


def validate_currency_for_business(db: Session, business_id: int, currency_id: Optional[int]) -> bool:
    if currency_id is None:
        return True
    try:
        cid = int(currency_id)
    except (TypeError, ValueError):
        return False
    row = db.execute(
        select(BusinessCurrency.currency_id).where(
            and_(
                BusinessCurrency.business_id == int(business_id),
                BusinessCurrency.currency_id == cid,
            )
        ).limit(1)
    ).scalar_one_or_none()
    return row is not None


def validate_fiscal_year_for_business(db: Session, business_id: int, fiscal_year_id: Optional[int]) -> bool:
    if fiscal_year_id is None:
        return True
    try:
        fid = int(fiscal_year_id)
    except (TypeError, ValueError):
        return False
    row = db.execute(
        select(FiscalYear.id).where(
            and_(FiscalYear.id == fid, FiscalYear.business_id == int(business_id))
        ).limit(1)
    ).scalar_one_or_none()
    return row is not None


def validate_receipt_payment_config_entities(
    db: Session, business_id: int, config: Dict[str, Any]
) -> bool:
    """بررسی فیلترهایی که به شناسهٔ موجودیت اشاره می‌کنند."""
    c: Dict[str, Any] = config or {}

    if not validate_person_for_business(db, business_id, c.get("person_id_filter")):
        return False
    if not validate_project_for_business(db, business_id, c.get("project_id_filter")):
        return False
    if not validate_currency_for_business(db, business_id, c.get("currency_id_filter")):
        return False
    if not validate_fiscal_year_for_business(db, business_id, c.get("fiscal_year_id_filter")):
        return False
    if not validate_account_for_business(db, business_id, c.get("account_id_filter")):
        return False

    raw_extra = c.get("account_ids_filter")
    ids: List[int] = []
    if isinstance(raw_extra, list):
        for x in raw_extra:
            try:
                ids.append(int(x))
            except (TypeError, ValueError):
                return False
    for aid in ids:
        if not validate_account_for_business(db, business_id, aid):
            return False

    return True


def validate_document_created_config_entities(
    db: Session, business_id: int, config: Dict[str, Any]
) -> bool:
    c: Dict[str, Any] = config or {}

    if not validate_person_for_business(db, business_id, c.get("person_id_filter")):
        return False
    if not validate_project_for_business(db, business_id, c.get("project_id_filter")):
        return False
    if not validate_currency_for_business(db, business_id, c.get("currency_id_filter")):
        return False
    if not validate_fiscal_year_for_business(db, business_id, c.get("fiscal_year_filter")):
        return False
    if not validate_account_for_business(db, business_id, c.get("line_account_id_filter")):
        return False
    if not validate_account_for_business(db, business_id, c.get("item_account_id_filter")):
        return False

    return True
