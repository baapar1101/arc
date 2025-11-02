from __future__ import annotations

from typing import Any, Dict, List, Optional
from datetime import datetime

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func

from adapters.db.models.check import Check, CheckType
from adapters.db.models.person import Person
from adapters.db.models.currency import Currency
from app.core.responses import ApiError


def _parse_iso(dt: str) -> datetime:
    try:
        return datetime.fromisoformat(dt.replace('Z', '+00:00'))
    except Exception:
        raise ApiError("INVALID_DATE", f"Invalid date: {dt}", http_status=400)


def create_check(db: Session, business_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
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

    db.add(obj)
    db.commit()
    db.refresh(obj)
    return check_to_dict(db, obj)


def get_check_by_id(db: Session, check_id: int) -> Optional[Dict[str, Any]]:
    obj = db.query(Check).filter(Check.id == check_id).first()
    return check_to_dict(db, obj) if obj else None


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
        "created_at": obj.created_at.isoformat(),
        "updated_at": obj.updated_at.isoformat(),
    }


