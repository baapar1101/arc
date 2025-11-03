from __future__ import annotations

from typing import Any, Dict, List, Optional
from datetime import datetime, date
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func

from adapters.db.models.check import Check, CheckType, CheckStatus, HolderType
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.currency import Currency
from adapters.db.models.person import Person
from app.core.responses import ApiError


def _parse_iso(dt: str) -> datetime:
    try:
        return datetime.fromisoformat(dt.replace('Z', '+00:00'))
    except Exception:
        raise ApiError("INVALID_DATE", f"Invalid date: {dt}", http_status=400)


def _parse_iso_date_only(dt: str | datetime | date) -> date:
    if isinstance(dt, date) and not isinstance(dt, datetime):
        return dt
    if isinstance(dt, datetime):
        return dt.date()
    try:
        return datetime.fromisoformat(str(dt)).date()
    except Exception:
        return datetime.utcnow().date()


def _get_fixed_account_by_code(db: Session, account_code: str) -> Account:
    account = db.query(Account).filter(Account.code == str(account_code)).first()
    if not account:
        from app.core.responses import ApiError
        raise ApiError("ACCOUNT_NOT_FOUND", f"Account with code {account_code} not found", http_status=404)
    return account


def _get_business_fiscal_year(db: Session, business_id: int) -> FiscalYear:
    from sqlalchemy import and_  # local import to avoid unused import if not used elsewhere
    fy = db.query(FiscalYear).filter(
        and_(FiscalYear.business_id == business_id, FiscalYear.is_closed == False)  # noqa: E712
    ).order_by(FiscalYear.start_date.desc()).first()
    if not fy:
        from app.core.responses import ApiError
        raise ApiError("FISCAL_YEAR_NOT_FOUND", "Active fiscal year not found", http_status=404)
    return fy


def create_check(db: Session, business_id: int, user_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
    ctype = str(data.get('type', '')).lower()
    if ctype not in ("received", "transferred"):
        raise ApiError("INVALID_CHECK_TYPE", "Invalid check type", http_status=400)

    person_id = data.get('person_id')
    if ctype == "received" and not person_id:
        raise ApiError("PERSON_REQUIRED", "person_id is required for received checks", http_status=400)

    issue_date = _parse_iso(str(data.get('issue_date')))
    due_date = _parse_iso(str(data.get('due_date')))
    if due_date < issue_date:
        raise ApiError("INVALID_DATES", "due_date must be >= issue_date", http_status=400)

    sayad = data.get('sayad_code')
    if sayad is not None:
        s = str(sayad).strip()
        if s and (len(s) != 16 or not s.isdigit()):
            raise ApiError("INVALID_SAYAD", "sayad_code must be 16 digits", http_status=400)

    amount = data.get('amount')
    try:
        amount_val = float(amount)
    except Exception:
        raise ApiError("INVALID_AMOUNT", "amount must be a number", http_status=400)
    if amount_val <= 0:
        raise ApiError("INVALID_AMOUNT", "amount must be > 0", http_status=400)

    check_number = str(data.get('check_number', '')).strip()
    if not check_number:
        raise ApiError("CHECK_NUMBER_REQUIRED", "check_number is required", http_status=400)

    # یونیک بودن در سطح کسب‌وکار
    exists = db.query(Check).filter(and_(Check.business_id == business_id, Check.check_number == check_number)).first()
    if exists is not None:
        raise ApiError("DUPLICATE_CHECK_NUMBER", "Duplicate check number in this business", http_status=400)

    if sayad:
        exists_sayad = db.query(Check).filter(and_(Check.business_id == business_id, Check.sayad_code == sayad)).first()
        if exists_sayad is not None:
            raise ApiError("DUPLICATE_SAYAD", "Duplicate sayad_code in this business", http_status=400)

    obj = Check(
        business_id=business_id,
        type=CheckType[ctype.upper()],
        person_id=int(person_id) if person_id else None,
        issue_date=issue_date,
        due_date=due_date,
        check_number=check_number,
        sayad_code=str(sayad).strip() if sayad else None,
        bank_name=(str(data.get('bank_name')).strip() if data.get('bank_name') else None),
        branch_name=(str(data.get('branch_name')).strip() if data.get('branch_name') else None),
        amount=amount_val,
        currency_id=int(data.get('currency_id')),
    )

    # تعیین وضعیت اولیه
    if ctype == "received":
        obj.status = CheckStatus.RECEIVED_ON_HAND
        obj.current_holder_type = HolderType.BUSINESS
        obj.current_holder_id = None
    else:
        obj.status = CheckStatus.TRANSFERRED_ISSUED
        obj.current_holder_type = HolderType.PERSON if person_id else HolderType.BUSINESS
        obj.current_holder_id = int(person_id) if person_id else None

    db.add(obj)
    db.commit()
    db.refresh(obj)

    # ایجاد سند حسابداری خودکار در صورت درخواست
    created_document_id: Optional[int] = None
    try:
        if bool(data.get("auto_post")):
            # آماده‌سازی داده‌های سند
            document_date: date = _parse_iso_date_only(data.get("document_date") or issue_date)
            fiscal_year = _get_business_fiscal_year(db, business_id)

            # تعیین حساب‌ها و سطرها
            amount_dec = Decimal(str(amount_val))
            lines: List[Dict[str, Any]] = []
            description = (str(data.get("document_description")).strip() or None) if data.get("document_description") is not None else None

            if ctype == "received":
                # بدهکار: اسناد دریافتنی 10403
                acc_notes_recv = _get_fixed_account_by_code(db, "10403")
                lines.append({
                    "account_id": acc_notes_recv.id,
                    "debit": amount_dec,
                    "credit": Decimal(0),
                    "description": description or "ثبت چک دریافتی",
                    "check_id": obj.id,
                })
                # بستانکار: حساب دریافتنی شخص 10401
                acc_ar = _get_fixed_account_by_code(db, "10401")
                lines.append({
                    "account_id": acc_ar.id,
                    "person_id": int(person_id) if person_id else None,
                    "debit": Decimal(0),
                    "credit": amount_dec,
                    "description": description or "ثبت چک دریافتی",
                    "check_id": obj.id,
                })
            else:  # transferred
                # بدهکار: حساب پرداختنی شخص 20201 (در صورت وجود شخص)
                acc_ap = _get_fixed_account_by_code(db, "20201")
                lines.append({
                    "account_id": acc_ap.id,
                    "person_id": int(person_id) if person_id else None,
                    "debit": amount_dec,
                    "credit": Decimal(0),
                    "description": description or "ثبت چک واگذار شده",
                    "check_id": obj.id,
                })
                # بستانکار: اسناد پرداختنی 20202
                acc_notes_pay = _get_fixed_account_by_code(db, "20202")
                lines.append({
                    "account_id": acc_notes_pay.id,
                    "debit": Decimal(0),
                    "credit": amount_dec,
                    "description": description or "ثبت چک واگذار شده",
                    "check_id": obj.id,
                })

            # ایجاد سند
            document = Document(
                code=f"CHK-{document_date.strftime('%Y%m%d')}-{int(datetime.utcnow().timestamp())%100000}",
                business_id=business_id,
                fiscal_year_id=fiscal_year.id,
                currency_id=int(data.get("currency_id")),
                created_by_user_id=int(user_id),
                document_date=document_date,
                document_type="check",
                is_proforma=False,
                description=description,
                extra_info={
                    "source": "check_create",
                    "check_id": obj.id,
                    "check_type": ctype,
                },
            )
            db.add(document)
            db.flush()

            for line in lines:
                db.add(DocumentLine(document_id=document.id, **line))

            db.commit()
            db.refresh(document)
            created_document_id = document.id
    except Exception:
        # در صورت شکست ایجاد سند، تغییری در ایجاد چک نمی‌دهیم و خطا نمی‌ریزیم
        # (می‌توان رفتار را سخت‌گیرانه کرد و رول‌بک نمود؛ فعلاً نرم)
        db.rollback()

    result = check_to_dict(db, obj)
    if created_document_id:
        result["document_id"] = created_document_id
    return result


def get_check_by_id(db: Session, check_id: int) -> Optional[Dict[str, Any]]:
    obj = db.query(Check).filter(Check.id == check_id).first()
    return check_to_dict(db, obj) if obj else None


# =====================
# Action helpers
# =====================

def _create_document_for_check_action(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    currency_id: int,
    document_date: date,
    description: Optional[str],
    lines: List[Dict[str, Any]],
    extra_info: Dict[str, Any],
) -> int:
    document = Document(
        code=f"CHK-{document_date.strftime('%Y%m%d')}-{int(datetime.utcnow().timestamp())%100000}",
        business_id=business_id,
        fiscal_year_id=_get_business_fiscal_year(db, business_id).id,
        currency_id=int(currency_id),
        created_by_user_id=int(user_id),
        document_date=document_date,
        document_type="check",
        is_proforma=False,
        description=description,
        extra_info=extra_info,
    )
    db.add(document)
    db.flush()
    for line in lines:
        db.add(DocumentLine(document_id=document.id, **line))
    db.commit()
    db.refresh(document)
    return document.id


def _ensure_account(db: Session, code: str) -> int:
    return _get_fixed_account_by_code(db, code).id


def _parse_optional_date(d: Any, fallback: date) -> date:
    return _parse_iso_date_only(d) if d else fallback


def _load_check_or_404(db: Session, check_id: int) -> Check:
    obj = db.query(Check).filter(Check.id == check_id).first()
    if not obj:
        raise ApiError("CHECK_NOT_FOUND", "Check not found", http_status=404)
    return obj


def endorse_check(db: Session, check_id: int, user_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
    obj = _load_check_or_404(db, check_id)
    if obj.type != CheckType.RECEIVED:
        raise ApiError("INVALID_ACTION", "Only received checks can be endorsed", http_status=400)
    if obj.status not in (CheckStatus.RECEIVED_ON_HAND, CheckStatus.RETURNED, CheckStatus.BOUNCED):
        raise ApiError("INVALID_STATE", f"Cannot endorse from status {obj.status}", http_status=400)

    target_person_id = int(data.get("target_person_id"))
    document_date = _parse_optional_date(data.get("document_date"), obj.issue_date.date())
    description = (data.get("description") or None)

    lines: List[Dict[str, Any]] = []
    amount_dec = Decimal(str(obj.amount))
    # Dr 20201 (target person AP), Cr 10403
    lines.append({
        "account_id": _ensure_account(db, "20201"),
        "person_id": target_person_id,
        "debit": amount_dec,
        "credit": Decimal(0),
        "description": description or "واگذاری چک",
        "check_id": obj.id,
    })
    lines.append({
        "account_id": _ensure_account(db, "10403"),
        "debit": Decimal(0),
        "credit": amount_dec,
        "description": description or "واگذاری چک",
        "check_id": obj.id,
    })

    document_id = None
    if bool(data.get("auto_post", True)):
        document_id = _create_document_for_check_action(
            db,
            business_id=obj.business_id,
            user_id=user_id,
            currency_id=obj.currency_id,
            document_date=document_date,
            description=description,
            lines=lines,
            extra_info={"source": "check_action", "action": "endorse", "check_id": obj.id},
        )

    # Update state
    obj.status = CheckStatus.ENDORSED
    obj.status_at = datetime.utcnow()
    obj.current_holder_type = HolderType.PERSON
    obj.current_holder_id = target_person_id
    obj.last_action_document_id = document_id
    db.commit(); db.refresh(obj)
    res = check_to_dict(db, obj)
    if document_id:
        res["document_id"] = document_id
    return res


def clear_check(db: Session, check_id: int, user_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
    obj = _load_check_or_404(db, check_id)
    document_date = _parse_optional_date(data.get("document_date"), obj.due_date.date())
    description = (data.get("description") or None)
    amount_dec = Decimal(str(obj.amount))
    lines: List[Dict[str, Any]] = []

    if obj.type == CheckType.RECEIVED:
        # Dr 10203 (bank), Cr 10403
        lines.append({
            "account_id": _ensure_account(db, "10203"),
            "bank_account_id": int(data.get("bank_account_id")),
            "debit": amount_dec,
            "credit": Decimal(0),
            "description": description or "وصول چک",
            "check_id": obj.id,
        })
        lines.append({
            "account_id": _ensure_account(db, "10403"),
            "debit": Decimal(0),
            "credit": amount_dec,
            "description": description or "وصول چک",
            "check_id": obj.id,
        })
    else:
        # transferred/pay: Dr 20202, Cr 10203
        lines.append({
            "account_id": _ensure_account(db, "20202"),
            "debit": amount_dec,
            "credit": Decimal(0),
            "description": description or "پرداخت چک",
            "check_id": obj.id,
        })
        lines.append({
            "account_id": _ensure_account(db, "10203"),
            "bank_account_id": int(data.get("bank_account_id")),
            "debit": Decimal(0),
            "credit": amount_dec,
            "description": description or "پرداخت چک",
            "check_id": obj.id,
        })

    document_id = None
    if bool(data.get("auto_post", True)):
        document_id = _create_document_for_check_action(
            db,
            business_id=obj.business_id,
            user_id=user_id,
            currency_id=obj.currency_id,
            document_date=document_date,
            description=description,
            lines=lines,
            extra_info={"source": "check_action", "action": "clear", "check_id": obj.id},
        )

    obj.status = CheckStatus.CLEARED
    obj.status_at = datetime.utcnow()
    obj.current_holder_type = HolderType.BANK
    obj.current_holder_id = int(data.get("bank_account_id"))
    obj.last_action_document_id = document_id
    db.commit(); db.refresh(obj)
    res = check_to_dict(db, obj)
    if document_id:
        res["document_id"] = document_id
    return res


def pay_check(db: Session, check_id: int, user_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
    # alias to clear_check for transferred
    obj = _load_check_or_404(db, check_id)
    if obj.type != CheckType.TRANSFERRED:
        raise ApiError("INVALID_ACTION", "Only transferred checks can be paid", http_status=400)
    return clear_check(db, check_id, user_id, data)


def return_check(db: Session, check_id: int, user_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
    obj = _load_check_or_404(db, check_id)
    document_date = _parse_optional_date(data.get("document_date"), obj.issue_date.date())
    description = (data.get("description") or None)
    amount_dec = Decimal(str(obj.amount))
    lines: List[Dict[str, Any]] = []

    if obj.type == CheckType.RECEIVED:
        if not obj.person_id:
            raise ApiError("PERSON_REQUIRED", "person_id is required on received check to return", http_status=400)
        # Dr 10401(person), Cr 10403
        lines.append({
            "account_id": _ensure_account(db, "10401"),
            "person_id": int(obj.person_id),
            "debit": amount_dec,
            "credit": Decimal(0),
            "description": description or "عودت چک",
            "check_id": obj.id,
        })
        lines.append({
            "account_id": _ensure_account(db, "10403"),
            "debit": Decimal(0),
            "credit": amount_dec,
            "description": description or "عودت چک",
            "check_id": obj.id,
        })
        obj.current_holder_type = HolderType.PERSON
        obj.current_holder_id = int(obj.person_id)
    else:
        # transferred: Dr 20202, Cr 20201(person)
        if not obj.person_id:
            raise ApiError("PERSON_REQUIRED", "person_id is required on transferred check to return", http_status=400)
        lines.append({
            "account_id": _ensure_account(db, "20202"),
            "debit": amount_dec,
            "credit": Decimal(0),
            "description": description or "عودت چک",
            "check_id": obj.id,
        })
        lines.append({
            "account_id": _ensure_account(db, "20201"),
            "person_id": int(obj.person_id),
            "debit": Decimal(0),
            "credit": amount_dec,
            "description": description or "عودت چک",
            "check_id": obj.id,
        })
        obj.current_holder_type = HolderType.BUSINESS
        obj.current_holder_id = None

    document_id = None
    if bool(data.get("auto_post", True)):
        document_id = _create_document_for_check_action(
            db,
            business_id=obj.business_id,
            user_id=user_id,
            currency_id=obj.currency_id,
            document_date=document_date,
            description=description,
            lines=lines,
            extra_info={"source": "check_action", "action": "return", "check_id": obj.id},
        )

    obj.status = CheckStatus.RETURNED
    obj.status_at = datetime.utcnow()
    obj.last_action_document_id = document_id
    db.commit(); db.refresh(obj)
    res = check_to_dict(db, obj)
    if document_id:
        res["document_id"] = document_id
    return res


def bounce_check(db: Session, check_id: int, user_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
    obj = _load_check_or_404(db, check_id)
    document_date = _parse_optional_date(data.get("document_date"), obj.due_date.date())
    description = (data.get("description") or None)
    amount_dec = Decimal(str(obj.amount))
    lines: List[Dict[str, Any]] = []

    if obj.type == CheckType.RECEIVED:
        # Reverse cash if previously cleared; simplified: Dr 10403, Cr 10203
        bank_account_id = data.get("bank_account_id")
        lines.append({
            "account_id": _ensure_account(db, "10403"),
            "debit": amount_dec,
            "credit": Decimal(0),
            "description": description or "برگشت چک",
            "check_id": obj.id,
        })
        lines.append({
            "account_id": _ensure_account(db, "10203"),
            **({"bank_account_id": int(bank_account_id)} if bank_account_id else {}),
            "debit": Decimal(0),
            "credit": amount_dec,
            "description": description or "برگشت چک",
            "check_id": obj.id,
        })
    else:
        # transferred: Dr 20202, Cr 20201(person) (increase AP again)
        if not obj.person_id:
            raise ApiError("PERSON_REQUIRED", "person_id is required on transferred check to bounce", http_status=400)
        lines.append({
            "account_id": _ensure_account(db, "20202"),
            "debit": amount_dec,
            "credit": Decimal(0),
            "description": description or "برگشت چک",
            "check_id": obj.id,
        })
        lines.append({
            "account_id": _ensure_account(db, "20201"),
            "person_id": int(obj.person_id),
            "debit": Decimal(0),
            "credit": amount_dec,
            "description": description or "برگشت چک",
            "check_id": obj.id,
        })

    # Optional expense fee
    expense_amount = data.get("expense_amount")
    expense_account_id = data.get("expense_account_id")
    bank_account_id = data.get("bank_account_id")
    if expense_amount and expense_account_id and float(expense_amount) > 0:
        lines.append({
            "account_id": int(expense_account_id),
            "debit": Decimal(str(expense_amount)),
            "credit": Decimal(0),
            "description": description or "هزینه برگشت چک",
            "check_id": obj.id,
        })
        lines.append({
            "account_id": _ensure_account(db, "10203"),
            **({"bank_account_id": int(bank_account_id)} if bank_account_id else {}),
            "debit": Decimal(0),
            "credit": Decimal(str(expense_amount)),
            "description": description or "هزینه برگشت چک",
            "check_id": obj.id,
        })

    document_id = None
    if bool(data.get("auto_post", True)):
        document_id = _create_document_for_check_action(
            db,
            business_id=obj.business_id,
            user_id=user_id,
            currency_id=obj.currency_id,
            document_date=document_date,
            description=description,
            lines=lines,
            extra_info={"source": "check_action", "action": "bounce", "check_id": obj.id},
        )

    obj.status = CheckStatus.BOUNCED
    obj.status_at = datetime.utcnow()
    obj.current_holder_type = HolderType.BUSINESS
    obj.current_holder_id = None
    obj.last_action_document_id = document_id
    db.commit(); db.refresh(obj)
    res = check_to_dict(db, obj)
    if document_id:
        res["document_id"] = document_id
    return res


def deposit_check(db: Session, check_id: int, user_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
    obj = _load_check_or_404(db, check_id)
    if obj.type != CheckType.RECEIVED:
        raise ApiError("INVALID_ACTION", "Only received checks can be deposited", http_status=400)
    document_date = _parse_optional_date(data.get("document_date"), obj.due_date.date())
    description = (data.get("description") or None)
    amount_dec = Decimal(str(obj.amount))
    # Requires account 10404 to exist
    in_collection = _get_fixed_account_by_code(db, "10404")  # may raise 404
    lines: List[Dict[str, Any]] = [
        {
            "account_id": in_collection.id,
            "debit": amount_dec,
            "credit": Decimal(0),
            "description": description or "سپرده چک به بانک",
            "check_id": obj.id,
        },
        {
            "account_id": _ensure_account(db, "10403"),
            "debit": Decimal(0),
            "credit": amount_dec,
            "description": description or "سپرده چک به بانک",
            "check_id": obj.id,
        },
    ]
    document_id = None
    if bool(data.get("auto_post", True)):
        document_id = _create_document_for_check_action(
            db,
            business_id=obj.business_id,
            user_id=user_id,
            currency_id=obj.currency_id,
            document_date=document_date,
            description=description,
            lines=lines,
            extra_info={"source": "check_action", "action": "deposit", "check_id": obj.id},
        )

    obj.status = CheckStatus.DEPOSITED
    obj.status_at = datetime.utcnow()
    obj.current_holder_type = HolderType.BANK
    obj.last_action_document_id = document_id
    db.commit(); db.refresh(obj)
    res = check_to_dict(db, obj)
    if document_id:
        res["document_id"] = document_id
    return res


def update_check(db: Session, check_id: int, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    obj = db.query(Check).filter(Check.id == check_id).first()
    if obj is None:
        return None

    if 'type' in data and data['type'] is not None:
        ctype = str(data['type']).lower()
        if ctype not in ("received", "transferred"):
            raise ApiError("INVALID_CHECK_TYPE", "Invalid check type", http_status=400)
        obj.type = CheckType[ctype.upper()]

    if 'person_id' in data:
        obj.person_id = int(data['person_id']) if data['person_id'] is not None else None

    if 'issue_date' in data and data['issue_date'] is not None:
        obj.issue_date = _parse_iso(str(data['issue_date']))
    if 'due_date' in data and data['due_date'] is not None:
        obj.due_date = _parse_iso(str(data['due_date']))
    if obj.due_date < obj.issue_date:
        raise ApiError("INVALID_DATES", "due_date must be >= issue_date", http_status=400)

    if 'check_number' in data and data['check_number'] is not None:
        new_num = str(data['check_number']).strip()
        if not new_num:
            raise ApiError("CHECK_NUMBER_REQUIRED", "check_number is required", http_status=400)
        exists = db.query(Check).filter(and_(Check.business_id == obj.business_id, Check.check_number == new_num, Check.id != obj.id)).first()
        if exists is not None:
            raise ApiError("DUPLICATE_CHECK_NUMBER", "Duplicate check number in this business", http_status=400)
        obj.check_number = new_num

    if 'sayad_code' in data:
        s = data['sayad_code']
        if s is not None:
            s = str(s).strip()
            if s and (len(s) != 16 or not s.isdigit()):
                raise ApiError("INVALID_SAYAD", "sayad_code must be 16 digits", http_status=400)
            if s:
                exists_sayad = db.query(Check).filter(and_(Check.business_id == obj.business_id, Check.sayad_code == s, Check.id != obj.id)).first()
                if exists_sayad is not None:
                    raise ApiError("DUPLICATE_SAYAD", "Duplicate sayad_code in this business", http_status=400)
            obj.sayad_code = s if s else None

    for field in ["bank_name", "branch_name"]:
        if field in data:
            setattr(obj, field, (str(data[field]).strip() if data[field] is not None else None))

    if 'amount' in data and data['amount'] is not None:
        try:
            amount_val = float(data['amount'])
        except Exception:
            raise ApiError("INVALID_AMOUNT", "amount must be a number", http_status=400)
        if amount_val <= 0:
            raise ApiError("INVALID_AMOUNT", "amount must be > 0", http_status=400)
        obj.amount = amount_val

    if 'currency_id' in data and data['currency_id'] is not None:
        obj.currency_id = int(data['currency_id'])

    db.commit()
    db.refresh(obj)
    return check_to_dict(db, obj)


def delete_check(db: Session, check_id: int) -> bool:
    obj = db.query(Check).filter(Check.id == check_id).first()
    if obj is None:
        return False
    db.delete(obj)
    db.commit()
    return True


def list_checks(db: Session, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
    q = db.query(Check).filter(Check.business_id == business_id)

    # جستجو
    if query.get("search") and query.get("search_fields"):
        term = f"%{query['search']}%"
        conditions = []
        for f in query["search_fields"]:
            if f == "check_number":
                conditions.append(Check.check_number.ilike(term))
            elif f == "sayad_code":
                conditions.append(Check.sayad_code.ilike(term))
            elif f == "bank_name":
                conditions.append(Check.bank_name.ilike(term))
            elif f == "branch_name":
                conditions.append(Check.branch_name.ilike(term))
            elif f == "person_name":
                # join به persons
                q = q.join(Person, Check.person_id == Person.id, isouter=True)
                conditions.append(Person.alias_name.ilike(term))
        if conditions:
            from sqlalchemy import or_
            q = q.filter(or_(*conditions))

    # فیلترها
    if query.get("filters"):
        from app.core.calendar import CalendarConverter
        for flt in query["filters"]:
            prop = getattr(flt, 'property', None) if not isinstance(flt, dict) else flt.get('property')
            op = getattr(flt, 'operator', None) if not isinstance(flt, dict) else flt.get('operator')
            val = getattr(flt, 'value', None) if not isinstance(flt, dict) else flt.get('value')
            if not prop or not op:
                continue
            if prop == 'type' and op == '=':
                try:
                    enum_val = CheckType[str(val).upper()]
                    q = q.filter(Check.type == enum_val)
                except Exception:
                    pass
            elif prop == 'status':
                try:
                    if op == '=' and isinstance(val, str) and val:
                        enum_val = CheckStatus[val]
                        q = q.filter(Check.status == enum_val)
                    elif op == 'in' and isinstance(val, list) and val:
                        enum_vals = []
                        for v in val:
                            try:
                                enum_vals.append(CheckStatus[str(v)])
                            except Exception:
                                pass
                        if enum_vals:
                            q = q.filter(Check.status.in_(enum_vals))
                except Exception:
                    pass
            elif prop == 'currency' and op == '=':
                try:
                    q = q.filter(Check.currency_id == int(val))
                except Exception:
                    pass
            elif prop == 'person_id' and op == '=':
                try:
                    q = q.filter(Check.person_id == int(val))
                except Exception:
                    pass
            elif prop in ('issue_date', 'due_date'):
                # انتظار: فیلترهای بازه با اپراتورهای ">=" و "<=" از DataTable
                try:
                    if isinstance(val, str) and val:
                        # ورودی تاریخ ممکن است بر اساس هدر تقویم باشد؛ در این لایه فرض بر ISO است (از فرانت ارسال می‌شود)
                        dt = _parse_iso(val)
                        col = getattr(Check, prop)
                        if op == ">=":
                            q = q.filter(col >= dt)
                        elif op == "<=":
                            q = q.filter(col <= dt)
                except Exception:
                    pass

    # additional params: person_id
    person_param = query.get('person_id')
    if person_param:
        try:
            q = q.filter(Check.person_id == int(person_param))
        except Exception:
            pass

    # مرتب‌سازی
    sort_by = query.get("sort_by") or "created_at"
    sort_desc = bool(query.get("sort_desc", True))
    col = getattr(Check, sort_by, Check.created_at)
    q = q.order_by(col.desc() if sort_desc else col.asc())

    # صفحه‌بندی
    skip = int(query.get("skip", 0))
    take = int(query.get("take", 20))
    total = q.count()
    items = q.offset(skip).limit(take).all()

    return {
        "items": [check_to_dict(db, i) for i in items],
        "pagination": {
            "total": total,
            "page": (skip // take) + 1,
            "per_page": take,
            "total_pages": (total + take - 1) // take,
            "has_next": skip + take < total,
            "has_prev": skip > 0,
        },
        "query_info": query,
    }


def check_to_dict(db: Session, obj: Optional[Check]) -> Optional[Dict[str, Any]]:
    if obj is None:
        return None
    person_name = None
    if obj.person_id:
        p = db.query(Person).filter(Person.id == obj.person_id).first()
        person_name = getattr(p, 'alias_name', None)
    currency_title = None
    try:
        c = db.query(Currency).filter(Currency.id == obj.currency_id).first()
        currency_title = c.title or c.code if c else None
    except Exception:
        pass
    return {
        "id": obj.id,
        "business_id": obj.business_id,
        "type": obj.type.name.lower(),
        "person_id": obj.person_id,
        "person_name": person_name,
        "issue_date": obj.issue_date.isoformat(),
        "due_date": obj.due_date.isoformat(),
        "check_number": obj.check_number,
        "sayad_code": obj.sayad_code,
        "bank_name": obj.bank_name,
        "branch_name": obj.branch_name,
        "amount": float(obj.amount),
        "currency_id": obj.currency_id,
        "currency": currency_title,
        "status": (obj.status.name if obj.status else None),
        "status_at": (obj.status_at.isoformat() if obj.status_at else None),
        "current_holder_type": (obj.current_holder_type.name if obj.current_holder_type else None),
        "current_holder_id": obj.current_holder_id,
        "last_action_document_id": obj.last_action_document_id,
        "created_at": obj.created_at.isoformat(),
        "updated_at": obj.updated_at.isoformat(),
    }


