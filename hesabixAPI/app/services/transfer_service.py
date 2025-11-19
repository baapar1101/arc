from __future__ import annotations

from typing import Any, Dict, Optional
from datetime import datetime, date
from decimal import Decimal
import logging

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.currency import Currency
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.user import User
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.petty_cash import PettyCash
from app.core.responses import ApiError
from app.services.document_monetization_service import ensure_document_policy_allows_creation
import jdatetime


logger = logging.getLogger(__name__)


DOCUMENT_TYPE_TRANSFER = "transfer"


def _parse_iso_date(dt: str | datetime | date) -> date:
    if isinstance(dt, date):
        return dt
    if isinstance(dt, datetime):
        return dt.date()

    dt_str = str(dt).strip()

    try:
        dt_str_clean = dt_str.replace('Z', '+00:00')
        parsed = datetime.fromisoformat(dt_str_clean)
        return parsed.date()
    except Exception:
        pass

    try:
        if len(dt_str) == 10 and dt_str.count('-') == 2:
            return datetime.strptime(dt_str, '%Y-%m-%d').date()
    except Exception:
        pass

    try:
        if len(dt_str) == 10 and dt_str.count('/') == 2:
            parts = dt_str.split('/')
            if len(parts) == 3:
                year, month, day = parts
                try:
                    year_int = int(year)
                    month_int = int(month)
                    day_int = int(day)
                    if year_int > 1500:
                        jalali_date = jdatetime.date(year_int, month_int, day_int)
                        gregorian_date = jalali_date.togregorian()
                        return gregorian_date
                    else:
                        return datetime.strptime(dt_str, '%Y/%m/%d').date()
                except (ValueError, jdatetime.JalaliDateError):
                    return datetime.strptime(dt_str, '%Y/%m/%d').date()
    except Exception:
        pass

    raise ApiError("INVALID_DATE", f"Invalid date format: {dt}", http_status=400)


def _get_current_fiscal_year(db: Session, business_id: int) -> FiscalYear:
    fiscal_year = db.query(FiscalYear).filter(
        and_(
            FiscalYear.business_id == business_id,
            FiscalYear.is_last == True,
        )
    ).first()
    if not fiscal_year:
        raise ApiError("NO_FISCAL_YEAR", "No active fiscal year found for this business", http_status=400)
    return fiscal_year


def _get_fixed_account_by_code(db: Session, account_code: str) -> Account:
    account = db.query(Account).filter(
        and_(
            Account.business_id == None,
            Account.code == account_code,
        )
    ).first()
    if not account:
        raise ApiError("ACCOUNT_NOT_FOUND", f"Account with code {account_code} not found", http_status=500)
    return account


def _account_code_for_type(account_type: str) -> str:
    if account_type == "bank":
        return "10203"
    if account_type == "cash_register":
        return "10202"
    if account_type == "petty_cash":
        return "10201"
    raise ApiError("INVALID_ACCOUNT_TYPE", f"Invalid account type: {account_type}", http_status=400)


def _build_doc_code(prefix_base: str) -> str:
    today = datetime.now().date()
    prefix = f"{prefix_base}-{today.strftime('%Y%m%d')}"
    return prefix


def create_transfer(
    db: Session,
    business_id: int,
    user_id: int,
    data: Dict[str, Any],
) -> Dict[str, Any]:
    logger.info("=== شروع ایجاد سند انتقال ===")

    document_date = _parse_iso_date(data.get("document_date", datetime.now()))
    currency_id = data.get("currency_id")
    if not currency_id:
        raise ApiError("CURRENCY_REQUIRED", "currency_id is required", http_status=400)
    currency = db.query(Currency).filter(Currency.id == int(currency_id)).first()
    if not currency:
        raise ApiError("CURRENCY_NOT_FOUND", "Currency not found", http_status=404)

    fiscal_year = _get_current_fiscal_year(db, business_id)

    source = data.get("source") or {}
    destination = data.get("destination") or {}
    amount = Decimal(str(data.get("amount", 0)))
    commission = Decimal(str(data.get("commission", 0))) if data.get("commission") is not None else Decimal(0)

    if amount <= 0:
        raise ApiError("INVALID_AMOUNT", "amount must be greater than 0", http_status=400)
    if commission < 0:
        raise ApiError("INVALID_COMMISSION", "commission must be >= 0", http_status=400)

    src_type = str(source.get("type") or "").strip()
    dst_type = str(destination.get("type") or "").strip()
    src_id = source.get("id")
    dst_id = destination.get("id")

    if src_type not in ("bank", "cash_register", "petty_cash"):
        raise ApiError("INVALID_SOURCE", "source.type must be bank|cash_register|petty_cash", http_status=400)
    if dst_type not in ("bank", "cash_register", "petty_cash"):
        raise ApiError("INVALID_DESTINATION", "destination.type must be bank|cash_register|petty_cash", http_status=400)
    if src_type == dst_type and src_id and dst_id and str(src_id) == str(dst_id):
        raise ApiError("SAME_SOURCE_DESTINATION", "source and destination cannot be the same", http_status=400)

    # Resolve accounts by fixed codes
    src_account = _get_fixed_account_by_code(db, _account_code_for_type(src_type))
    dst_account = _get_fixed_account_by_code(db, _account_code_for_type(dst_type))

    # Generate document code TR-YYYYMMDD-NNNN
    prefix = _build_doc_code("TR")
    last_doc = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.code.like(f"{prefix}-%"),
        )
    ).order_by(Document.code.desc()).first()
    if last_doc:
        try:
            last_num = int(last_doc.code.split("-")[-1])
            next_num = last_num + 1
        except Exception:
            next_num = 1
    else:
        next_num = 1
    doc_code = f"{prefix}-{next_num:04d}"

    # Resolve names for auto description if needed
    def _resolve_name(tp: str, _id: Any) -> str | None:
        try:
            if tp == "bank" and _id is not None:
                ba = db.query(BankAccount).filter(BankAccount.id == int(_id)).first()
                return ba.name if ba else None
            if tp == "cash_register" and _id is not None:
                cr = db.query(CashRegister).filter(CashRegister.id == int(_id)).first()
                return cr.name if cr else None
            if tp == "petty_cash" and _id is not None:
                pc = db.query(PettyCash).filter(PettyCash.id == int(_id)).first()
                return pc.name if pc else None
        except Exception:
            return None
        return None

    auto_description = None
    if not data.get("description"):
        src_name = _resolve_name(src_type, src_id) or "مبدأ"
        dst_name = _resolve_name(dst_type, dst_id) or "مقصد"
        # human readable types
        def _type_name(tp: str) -> str:
            return "حساب بانکی" if tp == "bank" else ("صندوق" if tp == "cash_register" else "تنخواه")
        auto_description = f"انتقال از {_type_name(src_type)} {src_name} به {_type_name(dst_type)} {dst_name}"

    ensure_document_policy_allows_creation(
        db,
        business_id,
        document_type=DOCUMENT_TYPE_TRANSFER,
        document_date=document_date,
        amount=amount,
    )

    document = Document(
        business_id=business_id,
        fiscal_year_id=fiscal_year.id,
        code=doc_code,
        document_type=DOCUMENT_TYPE_TRANSFER,
        document_date=document_date,
        currency_id=int(currency_id),
        created_by_user_id=user_id,
        registered_at=datetime.utcnow(),
        is_proforma=False,
        description=data.get("description") or auto_description,
        extra_info=data.get("extra_info"),
    )
    db.add(document)
    db.flush()

    # Destination line (Debit)
    dest_kwargs: Dict[str, Any] = {}
    if dst_type == "bank" and dst_id is not None:
        try:
            dest_kwargs["bank_account_id"] = int(dst_id)
        except Exception:
            pass
    elif dst_type == "cash_register" and dst_id is not None:
        dest_kwargs["cash_register_id"] = dst_id
    elif dst_type == "petty_cash" and dst_id is not None:
        dest_kwargs["petty_cash_id"] = dst_id

    dest_line = DocumentLine(
        document_id=document.id,
        account_id=dst_account.id,
        debit=amount,
        credit=Decimal(0),
        description=data.get("destination_description") or data.get("description"),
        extra_info={
            "side": "destination",
            "destination_type": dst_type,
            "destination_id": dst_id,
        },
        **dest_kwargs,
    )
    db.add(dest_line)

    # Source line (Credit)
    src_kwargs: Dict[str, Any] = {}
    if src_type == "bank" and src_id is not None:
        try:
            src_kwargs["bank_account_id"] = int(src_id)
        except Exception:
            pass
    elif src_type == "cash_register" and src_id is not None:
        src_kwargs["cash_register_id"] = src_id
    elif src_type == "petty_cash" and src_id is not None:
        src_kwargs["petty_cash_id"] = src_id

    src_line = DocumentLine(
        document_id=document.id,
        account_id=src_account.id,
        debit=Decimal(0),
        credit=amount,
        description=data.get("source_description") or data.get("description"),
        extra_info={
            "side": "source",
            "source_type": src_type,
            "source_id": src_id,
        },
        **src_kwargs,
    )
    db.add(src_line)

    if commission > 0:
        # Debit commission expense 70902
        commission_service_account = _get_fixed_account_by_code(db, "70902")
        commission_expense_line = DocumentLine(
            document_id=document.id,
            account_id=commission_service_account.id,
            debit=commission,
            credit=Decimal(0),
            description="کارمزد خدمات بانکی",
            extra_info={
                "side": "commission",
                "is_commission_line": True,
            },
            **src_kwargs,
        )
        db.add(commission_expense_line)

        # Credit commission to source account (increase credit of source)
        commission_credit_line = DocumentLine(
            document_id=document.id,
            account_id=src_account.id,
            debit=Decimal(0),
            credit=commission,
            description="کارمزد انتقال (ثبت در مبدأ)",
            extra_info={
                "side": "commission",
                "is_commission_line": True,
                "source_type": src_type,
                "source_id": src_id,
            },
            **src_kwargs,
        )
        db.add(commission_credit_line)

    db.commit()
    db.refresh(document)
    return transfer_document_to_dict(db, document)


def get_transfer(db: Session, document_id: int) -> Optional[Dict[str, Any]]:
    document = db.query(Document).filter(Document.id == document_id).first()
    if not document or document.document_type != DOCUMENT_TYPE_TRANSFER:
        return None
    return transfer_document_to_dict(db, document)


def list_transfers(db: Session, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
    q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == DOCUMENT_TYPE_TRANSFER,
        )
    )

    fiscal_year_id = query.get("fiscal_year_id")
    if fiscal_year_id is not None:
        try:
            fiscal_year_id = int(fiscal_year_id)
        except (TypeError, ValueError):
            fiscal_year_id = None
    if fiscal_year_id is None:
        try:
            fiscal_year = _get_current_fiscal_year(db, business_id)
            fiscal_year_id = fiscal_year.id
        except Exception:
            fiscal_year_id = None
    if fiscal_year_id is not None:
        q = q.filter(Document.fiscal_year_id == fiscal_year_id)

    from_date = query.get("from_date")
    to_date = query.get("to_date")
    if from_date:
        try:
            from_dt = _parse_iso_date(from_date)
            q = q.filter(Document.document_date >= from_dt)
        except Exception:
            pass
    if to_date:
        try:
            to_dt = _parse_iso_date(to_date)
            q = q.filter(Document.document_date <= to_dt)
        except Exception:
            pass

    # Apply advanced filters (e.g., DataTable date range filters)
    filters = query.get("filters")
    if filters and isinstance(filters, (list, tuple)):
        for flt in filters:
            try:
                prop = getattr(flt, 'property', None) if not isinstance(flt, dict) else flt.get('property')
                op = getattr(flt, 'operator', None) if not isinstance(flt, dict) else flt.get('operator')
                val = getattr(flt, 'value', None) if not isinstance(flt, dict) else flt.get('value')
                if not prop or not op:
                    continue
                if prop == 'document_date':
                    if isinstance(val, str) and val:
                        try:
                            dt = _parse_iso_date(val)
                            col = getattr(Document, prop)
                            if op == ">=":
                                q = q.filter(col >= dt)
                            elif op == "<=":
                                q = q.filter(col <= dt)
                        except Exception:
                            pass
            except Exception:
                pass

    search = query.get("search")
    if search:
        q = q.filter(Document.code.ilike(f"%{search}%"))

    sort_by = query.get("sort_by", "document_date")
    sort_desc = bool(query.get("sort_desc", True))
    if sort_by and isinstance(sort_by, str) and hasattr(Document, sort_by):
        col = getattr(Document, sort_by)
        q = q.order_by(col.desc() if sort_desc else col.asc())
    else:
        q = q.order_by(Document.document_date.desc())

    skip = int(query.get("skip", 0))
    take = int(query.get("take", 20))

    total = q.count()
    items = q.offset(skip).limit(take).all()

    return {
        "items": [transfer_document_to_dict(db, doc) for doc in items],
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


def delete_transfer(db: Session, document_id: int) -> bool:
    document = db.query(Document).filter(Document.id == document_id).first()
    if not document or document.document_type != DOCUMENT_TYPE_TRANSFER:
        return False
    try:
        fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == document.fiscal_year_id).first()
        if fiscal_year is not None and getattr(fiscal_year, "is_last", False) is not True:
            raise ApiError("FISCAL_YEAR_LOCKED", "سند متعلق به سال مالی جاری نیست و قابل حذف نمی‌باشد", http_status=409)
    except ApiError:
        raise
    except Exception:
        pass

    db.delete(document)
    db.commit()
    return True


def update_transfer(
    db: Session,
    document_id: int,
    user_id: int,
    data: Dict[str, Any],
) -> Dict[str, Any]:
    document = db.query(Document).filter(Document.id == document_id).first()
    if document is None or document.document_type != DOCUMENT_TYPE_TRANSFER:
        raise ApiError("DOCUMENT_NOT_FOUND", "Transfer document not found", http_status=404)

    try:
        fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == document.fiscal_year_id).first()
        if fiscal_year is not None and getattr(fiscal_year, "is_last", False) is not True:
            raise ApiError("FISCAL_YEAR_LOCKED", "سند متعلق به سال مالی جاری نیست و قابل ویرایش نمی‌باشد", http_status=409)
    except ApiError:
        raise
    except Exception:
        pass

    document_date = _parse_iso_date(data.get("document_date", document.document_date))
    currency_id = data.get("currency_id", document.currency_id)
    if not currency_id:
        raise ApiError("CURRENCY_REQUIRED", "currency_id is required", http_status=400)
    currency = db.query(Currency).filter(Currency.id == int(currency_id)).first()
    if not currency:
        raise ApiError("CURRENCY_NOT_FOUND", "Currency not found", http_status=404)

    source = data.get("source") or {}
    destination = data.get("destination") or {}
    amount = Decimal(str(data.get("amount", 0)))
    commission = Decimal(str(data.get("commission", 0))) if data.get("commission") is not None else Decimal(0)

    if amount <= 0:
        raise ApiError("INVALID_AMOUNT", "amount must be greater than 0", http_status=400)
    if commission < 0:
        raise ApiError("INVALID_COMMISSION", "commission must be >= 0", http_status=400)

    src_type = str(source.get("type") or "").strip()
    dst_type = str(destination.get("type") or "").strip()
    src_id = source.get("id")
    dst_id = destination.get("id")

    if src_type not in ("bank", "cash_register", "petty_cash"):
        raise ApiError("INVALID_SOURCE", "source.type must be bank|cash_register|petty_cash", http_status=400)
    if dst_type not in ("bank", "cash_register", "petty_cash"):
        raise ApiError("INVALID_DESTINATION", "destination.type must be bank|cash_register|petty_cash", http_status=400)
    if src_type == dst_type and src_id and dst_id and str(src_id) == str(dst_id):
        raise ApiError("SAME_SOURCE_DESTINATION", "source and destination cannot be the same", http_status=400)

    # Update document fields
    document.document_date = document_date
    document.currency_id = int(currency_id)
    if isinstance(data.get("extra_info"), dict) or data.get("extra_info") is None:
        document.extra_info = data.get("extra_info")
    if isinstance(data.get("description"), str) or data.get("description") is None:
        if data.get("description"):
            document.description = data.get("description")
        else:
            # regenerate auto description
            def _resolve_name(tp: str, _id: Any) -> str | None:
                try:
                    if tp == "bank" and _id is not None:
                        ba = db.query(BankAccount).filter(BankAccount.id == int(_id)).first()
                        return ba.name if ba else None
                    if tp == "cash_register" and _id is not None:
                        cr = db.query(CashRegister).filter(CashRegister.id == int(_id)).first()
                        return cr.name if cr else None
                    if tp == "petty_cash" and _id is not None:
                        pc = db.query(PettyCash).filter(PettyCash.id == int(_id)).first()
                        return pc.name if pc else None
                except Exception:
                    return None
                return None
            def _type_name(tp: str) -> str:
                return "حساب بانکی" if tp == "bank" else ("صندوق" if tp == "cash_register" else "تنخواه")
            src_name = _resolve_name(src_type, src_id) or "مبدأ"
            dst_name = _resolve_name(dst_type, dst_id) or "مقصد"
            document.description = f"انتقال از {_type_name(src_type)} {src_name} به {_type_name(dst_type)} {dst_name}"

    # Remove old lines and recreate
    db.query(DocumentLine).filter(DocumentLine.document_id == document.id).delete(synchronize_session=False)

    src_account = _get_fixed_account_by_code(db, _account_code_for_type(src_type))
    dst_account = _get_fixed_account_by_code(db, _account_code_for_type(dst_type))

    dest_kwargs: Dict[str, Any] = {}
    if dst_type == "bank" and dst_id is not None:
        try:
            dest_kwargs["bank_account_id"] = int(dst_id)
        except Exception:
            pass
    elif dst_type == "cash_register" and dst_id is not None:
        dest_kwargs["cash_register_id"] = dst_id
    elif dst_type == "petty_cash" and dst_id is not None:
        dest_kwargs["petty_cash_id"] = dst_id

    db.add(DocumentLine(
        document_id=document.id,
        account_id=dst_account.id,
        debit=amount,
        credit=Decimal(0),
        description=data.get("destination_description") or data.get("description"),
        extra_info={
            "side": "destination",
            "destination_type": dst_type,
            "destination_id": dst_id,
        },
        **dest_kwargs,
    ))

    src_kwargs: Dict[str, Any] = {}
    if src_type == "bank" and src_id is not None:
        try:
            src_kwargs["bank_account_id"] = int(src_id)
        except Exception:
            pass
    elif src_type == "cash_register" and src_id is not None:
        src_kwargs["cash_register_id"] = src_id
    elif src_type == "petty_cash" and src_id is not None:
        src_kwargs["petty_cash_id"] = src_id

    db.add(DocumentLine(
        document_id=document.id,
        account_id=src_account.id,
        debit=Decimal(0),
        credit=amount,
        description=data.get("source_description") or data.get("description"),
        extra_info={
            "side": "source",
            "source_type": src_type,
            "source_id": src_id,
        },
        **src_kwargs,
    ))

    if commission > 0:
        commission_service_account = _get_fixed_account_by_code(db, "70902")
        db.add(DocumentLine(
            document_id=document.id,
            account_id=commission_service_account.id,
            debit=commission,
            credit=Decimal(0),
            description="کارمزد خدمات بانکی",
            extra_info={
                "side": "commission",
                "is_commission_line": True,
            },
            **src_kwargs,
        ))
        db.add(DocumentLine(
            document_id=document.id,
            account_id=src_account.id,
            debit=Decimal(0),
            credit=commission,
            description="کارمزد انتقال (ثبت در مبدأ)",
            extra_info={
                "side": "commission",
                "is_commission_line": True,
                "source_type": src_type,
                "source_id": src_id,
            },
            **src_kwargs,
        ))

    db.commit()
    db.refresh(document)
    return transfer_document_to_dict(db, document)


def transfer_document_to_dict(db: Session, document: Document) -> Dict[str, Any]:
    lines = db.query(DocumentLine).filter(DocumentLine.document_id == document.id).all()

    account_lines = []
    source_name = None
    destination_name = None
    source_type = None
    destination_type = None
    for line in lines:
        account = db.query(Account).filter(Account.id == line.account_id).first()
        if not account:
            continue

        line_dict: Dict[str, Any] = {
            "id": line.id,
            "account_id": line.account_id,
            "bank_account_id": line.bank_account_id,
            "cash_register_id": line.cash_register_id,
            "petty_cash_id": line.petty_cash_id,
            "quantity": float(line.quantity) if line.quantity else None,
            "account_name": account.name,
            "account_code": account.code,
            "account_type": account.account_type,
            "debit": float(line.debit),
            "credit": float(line.credit),
            "amount": float(line.debit if line.debit > 0 else line.credit),
            "description": line.description,
            "extra_info": line.extra_info,
        }

        if line.extra_info:
            if "side" in line.extra_info:
                line_dict["side"] = line.extra_info["side"]
            if "source_type" in line.extra_info:
                line_dict["source_type"] = line.extra_info["source_type"]
                # Only assign source_type from source lines
                if line_dict.get("side") == "source":
                    source_type = source_type or line.extra_info["source_type"]
            if "destination_type" in line.extra_info:
                line_dict["destination_type"] = line.extra_info["destination_type"]
                # Only assign destination_type from destination lines
                if line_dict.get("side") == "destination":
                    destination_type = destination_type or line.extra_info["destination_type"]
            if "is_commission_line" in line.extra_info:
                line_dict["is_commission_line"] = line.extra_info["is_commission_line"]

        # capture source/destination names from linked entities
        try:
            if line_dict.get("side") == "source":
                if line_dict.get("bank_account_id"):
                    ba = db.query(BankAccount).filter(BankAccount.id == int(line_dict["bank_account_id"])) .first()
                    source_name = ba.name if ba else source_name
                elif line_dict.get("cash_register_id"):
                    cr = db.query(CashRegister).filter(CashRegister.id == int(line_dict["cash_register_id"])) .first()
                    source_name = cr.name if cr else source_name
                elif line_dict.get("petty_cash_id"):
                    pc = db.query(PettyCash).filter(PettyCash.id == int(line_dict["petty_cash_id"])) .first()
                    source_name = pc.name if pc else source_name
            elif line_dict.get("side") == "destination":
                if line_dict.get("bank_account_id"):
                    ba = db.query(BankAccount).filter(BankAccount.id == int(line_dict["bank_account_id"])) .first()
                    destination_name = ba.name if ba else destination_name
                elif line_dict.get("cash_register_id"):
                    cr = db.query(CashRegister).filter(CashRegister.id == int(line_dict["cash_register_id"])) .first()
                    destination_name = cr.name if cr else destination_name
                elif line_dict.get("petty_cash_id"):
                    pc = db.query(PettyCash).filter(PettyCash.id == int(line_dict["petty_cash_id"])) .first()
                    destination_name = pc.name if pc else destination_name
        except Exception:
            pass

        account_lines.append(line_dict)

    # Compute total as sum of debits of non-commission lines (destination line amount)
    total_amount = sum(l.get("debit", 0) for l in account_lines if not l.get("is_commission_line"))
    
    # Compute commission from commission expense lines
    commission = sum(l.get("debit", 0) for l in account_lines if l.get("is_commission_line") and l.get("side") == "commission")

    created_by = db.query(User).filter(User.id == document.created_by_user_id).first()
    created_by_name = f"{created_by.first_name} {created_by.last_name}".strip() if created_by else None

    currency = db.query(Currency).filter(Currency.id == document.currency_id).first()
    currency_code = currency.code if currency else None
    
    # Helper function to get type name in Persian
    def _get_type_name(tp: str) -> str:
        if tp == "bank":
            return "حساب بانکی"
        elif tp == "cash_register":
            return "صندوق"
        elif tp == "petty_cash":
            return "تنخواه"
        return tp or ""
    
    source_type_name = _get_type_name(source_type) if source_type else ""
    destination_type_name = _get_type_name(destination_type) if destination_type else ""

    # Convert dates to datetime for proper formatting
    document_date_dt = datetime.combine(document.document_date, datetime.min.time()) if document.document_date else None
    registered_at_dt = document.registered_at if document.registered_at else None
    
    return {
        "id": document.id,
        "code": document.code,
        "business_id": document.business_id,
        "document_type": document.document_type,
        "document_type_name": "انتقال",
        "document_date": document_date_dt,  # Keep as datetime for format_datetime_fields
        "registered_at": registered_at_dt,  # Keep as datetime for format_datetime_fields
        "currency_id": document.currency_id,
        "currency_code": currency_code,
        "created_by_user_id": document.created_by_user_id,
        "created_by_name": created_by_name,
        "is_proforma": document.is_proforma,
        "description": document.description,
        "source_type": source_type,
        "source_type_name": source_type_name,
        "source_name": source_name,
        "destination_type": destination_type,
        "destination_type_name": destination_type_name,
        "destination_name": destination_name,
        "commission": float(commission),
        "extra_info": document.extra_info,
        "person_lines": [],
        "account_lines": account_lines,
        "total_amount": float(total_amount),
        "person_lines_count": 0,
        "account_lines_count": len(account_lines),
        "created_at": document.created_at if hasattr(document, 'created_at') and document.created_at else None,
        "updated_at": document.updated_at if hasattr(document, 'updated_at') and document.updated_at else None,
    }


