"""صورت جریان وجوه نقد عملیاتی (نسخهٔ گزارشات) با پشتیبانی چندارزی."""
from __future__ import annotations

from collections import defaultdict
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional, Set, Tuple

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.account import Account
from adapters.db.models.business import Business
from adapters.db.models.currency import Currency
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear


CASH_ACCOUNT_TYPES = frozenset({"bank", "cash_register", "petty_cash", "3", "1", "2"})

# پیشوندهای چارت ایرانی برای تعدیلات روش غیرمستقیم (IAS 7)
_AR_PREFIXES = ("104",)  # دریافتنی‌ها
_INV_PREFIXES = ("105",)  # موجودی کالا
_AP_PREFIXES = ("201", "202")  # پرداختنی‌ها
_ACC_DEP_PREFIXES = ("108",)  # استهلاک انباشته → افزایش = افزودن به سود


def _parse_date(value: Optional[str]) -> Optional[date]:
    if not value:
        return None
    try:
        return datetime.strptime(str(value)[:10], "%Y-%m-%d").date()
    except Exception:
        return None


def _line_amount(line: DocumentLine, *, use_base: bool, side: str) -> Decimal:
    if side == "debit":
        if use_base and getattr(line, "debit_base", None) is not None:
            return Decimal(str(line.debit_base))
        return Decimal(str(line.debit or 0))
    if use_base and getattr(line, "credit_base", None) is not None:
        return Decimal(str(line.credit_base))
    return Decimal(str(line.credit or 0))


def _code_matches(code: str, prefixes: Tuple[str, ...]) -> bool:
    c = (code or "").strip()
    return any(c.startswith(p) for p in prefixes)


def _section_closing_amount(
    db: Session,
    business_id: int,
    *,
    fy_id: Optional[int],
    fy_start: date,
    as_of: date,
    currency_id: Optional[int],
    prefixes: Tuple[str, ...],
    asset_like: bool,
) -> Decimal:
    """مانده تجمیعی حساب‌های با پیشوند مشخص تا تاریخ as_of."""
    from app.services.account_balance_core import compute_leaf_balances, fetch_business_accounts

    accounts = fetch_business_accounts(db, business_id)
    matched = [a for a in accounts if _code_matches(getattr(a, "code", "") or "", prefixes)]
    if not matched:
        return Decimal(0)

    leaf = compute_leaf_balances(
        db,
        business_id,
        [a.id for a in matched],
        fy_start,
        as_of,
        fy_id or 0,
        currency_id,
        None,
        amounts_in_base=True if currency_id is None else None,
    )
    total = Decimal(0)
    for a in matched:
        bal = leaf.get(a.id)
        if bal is None:
            continue
        debit = Decimal(str(bal.opening_debit + bal.period_debit))
        credit = Decimal(str(bal.opening_credit + bal.period_credit))
        if asset_like:
            total += debit - credit
        else:
            total += credit - debit
    return total


def _build_indirect_operating(
    db: Session,
    business_id: int,
    *,
    fy: Optional[FiscalYear],
    date_from_obj: date,
    date_to_obj: date,
    currency_id: Optional[int],
    direct_operating_net: float,
) -> Dict[str, Any]:
    """
    روش غیرمستقیم IAS 7: سود خالص → تعدیلات غیرنقدی و سرمایه در گردش → جریان عملیاتی.

    توجه حسابداری: این تقریب بر اساس پیشوندهای چارت استاندارد ایرانی است؛
    تفاوت با روش مستقیم در meta.bridge_difference گزارش می‌شود.
    """
    from app.services.pnl_service import get_pnl_period_report

    fy_id = fy.id if fy else None
    fy_start = fy.start_date if fy and fy.start_date else date_from_obj
    day_before = date_from_obj - timedelta(days=1)

    pnl = get_pnl_period_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fy_id,
        currency_id=currency_id,
        date_from=date_from_obj.isoformat(),
        date_to=date_to_obj.isoformat(),
        include_zero_balance=True,
        skip=0,
        take=1,
    )
    s = pnl.get("summary") or {}
    net_profit = Decimal(str(s.get("net_profit_after_tax", s.get("net_profit_loss", 0)) or 0))

    def delta(prefixes: Tuple[str, ...], *, asset_like: bool) -> Decimal:
        end = _section_closing_amount(
            db,
            business_id,
            fy_id=fy_id,
            fy_start=fy_start,
            as_of=date_to_obj,
            currency_id=currency_id,
            prefixes=prefixes,
            asset_like=asset_like,
        )
        start = _section_closing_amount(
            db,
            business_id,
            fy_id=fy_id,
            fy_start=fy_start,
            as_of=day_before,
            currency_id=currency_id,
            prefixes=prefixes,
            asset_like=asset_like,
        )
        return end - start

    delta_ar = delta(_AR_PREFIXES, asset_like=True)
    delta_inv = delta(_INV_PREFIXES, asset_like=True)
    delta_ap = delta(_AP_PREFIXES, asset_like=False)
    delta_acc_dep = delta(_ACC_DEP_PREFIXES, asset_like=False)  # افزایش استهلاک انباشته = افزودن

    # افزایش دارایی عملیاتی → کسر؛ افزایش بدهی عملیاتی → اضافه
    adj_ar = -delta_ar
    adj_inv = -delta_inv
    adj_ap = delta_ap
    depreciation_addback = delta_acc_dep if delta_acc_dep > 0 else Decimal(0)

    lines = [
        {
            "key": "net_profit",
            "label_fa": "سود (زیان) خالص دوره",
            "label_en": "Net profit (loss)",
            "amount": float(net_profit),
            "sign": "+",
        },
        {
            "key": "depreciation_addback",
            "label_fa": "استهلاک (افزایش استهلاک انباشته)",
            "label_en": "Depreciation (increase in accumulated depreciation)",
            "amount": float(depreciation_addback),
            "sign": "+",
        },
        {
            "key": "change_in_receivables",
            "label_fa": "تغییر در دریافتنی‌ها (کاهش + / افزایش −)",
            "label_en": "Change in receivables",
            "amount": float(adj_ar),
            "delta_raw": float(delta_ar),
            "sign": "±",
        },
        {
            "key": "change_in_inventory",
            "label_fa": "تغییر در موجودی کالا",
            "label_en": "Change in inventory",
            "amount": float(adj_inv),
            "delta_raw": float(delta_inv),
            "sign": "±",
        },
        {
            "key": "change_in_payables",
            "label_fa": "تغییر در پرداختنی‌ها",
            "label_en": "Change in payables",
            "amount": float(adj_ap),
            "delta_raw": float(delta_ap),
            "sign": "±",
        },
    ]

    operating_net = net_profit + depreciation_addback + adj_ar + adj_inv + adj_ap
    bridge = float(operating_net) - float(direct_operating_net)

    return {
        "net_profit": float(net_profit),
        "adjustments": lines[1:],
        "lines": lines,
        "operating_cash_flow": float(operating_net),
        "direct_operating_net": float(direct_operating_net),
        "bridge_difference": bridge,
        "note_fa": (
            "روش غیرمستقیم از سود خالص با تعدیل تغییرات سرمایه در گردش و استهلاک "
            "(پیشوندهای ۱۰۴/۱۰۵/۲۰۱/۲۰۲/۱۰۸). اختلاف با روش مستقیم در bridge_difference است."
        ),
        "note_en": (
            "Indirect method starts from net profit and adjusts WC and depreciation "
            "(Iran CoA prefixes). bridge_difference vs direct operating net."
        ),
    }


def get_cash_flow_report(
    db: Session,
    business_id: int,
    *,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    include_indirect: bool = True,
) -> Dict[str, Any]:
    """
    جریان وجوه بر اساس گردش حساب‌های نقدی/بانک/تنخواه.

    - افزایش نقد = بدهکار حساب نقدی
    - کاهش نقد = بستانکار حساب نقدی
    - بدون فیلتر ارز → معادل پایه
    - include_indirect: اضافه کردن reconciliation روش غیرمستقیم (IAS 7)
    """
    use_base = currency_id is None

    fy = None
    if fiscal_year_id:
        fy = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
    if fy is None:
        fy = (
            db.query(FiscalYear)
            .filter(FiscalYear.business_id == business_id, FiscalYear.is_last == True)  # noqa: E712
            .first()
        )

    date_from_obj = _parse_date(date_from) or (fy.start_date if fy else date.today().replace(month=1, day=1))
    date_to_obj = _parse_date(date_to) or (fy.end_date if fy and fy.end_date else date.today())

    cash_accounts = (
        db.query(Account)
        .filter(
            and_(
                (Account.business_id == None) | (Account.business_id == business_id),  # noqa: E711
                Account.account_type.in_(tuple(CASH_ACCOUNT_TYPES)),
            )
        )
        .all()
    )
    cash_ids = [a.id for a in cash_accounts]

    empty_sections = {
        "operating": {"inflows": 0.0, "outflows": 0.0, "net": 0.0},
        "investing": {"inflows": 0.0, "outflows": 0.0, "net": 0.0},
        "financing": {"inflows": 0.0, "outflows": 0.0, "net": 0.0},
        "transfers": {"inflows": 0.0, "outflows": 0.0, "net": 0.0},
        "fx_and_other": {"inflows": 0.0, "outflows": 0.0, "net": 0.0},
    }

    def _attach_quality(meta: Dict[str, Any]) -> None:
        try:
            from app.services.fx_data_quality_service import get_missing_base_amount_warnings

            meta["fx_data_quality"] = get_missing_base_amount_warnings(
                db,
                business_id,
                fiscal_year_id=fy.id if fy else None,
                date_from=date_from_obj.isoformat(),
                date_to=date_to_obj.isoformat(),
                sample_limit=5,
            )
        except Exception:
            pass

    if not cash_ids:
        result = {
            "sections": empty_sections,
            "opening_cash": 0.0,
            "closing_cash": 0.0,
            "net_change": 0.0,
            "by_document_type": [],
            "meta": {
                "currency_id": currency_id,
                "amounts_in_base": use_base,
                "date_from": date_from_obj.isoformat(),
                "date_to": date_to_obj.isoformat(),
                "fiscal_year_id": fy.id if fy else None,
                "method": "direct_cash_accounts_counterpart_classified",
            },
        }
        if include_indirect:
            result["indirect_operating"] = _build_indirect_operating(
                db,
                business_id,
                fy=fy,
                date_from_obj=date_from_obj,
                date_to_obj=date_to_obj,
                currency_id=currency_id,
                direct_operating_net=0.0,
            )
        _attach_quality(result["meta"])
        return result

    def _cash_movement_query(date_lo: Optional[date], date_hi: date, *, before_period: bool = False):
        q = (
            db.query(DocumentLine, Document)
            .join(Document, DocumentLine.document_id == Document.id)
            .filter(
                and_(
                    Document.business_id == business_id,
                    Document.is_proforma == False,  # noqa: E712
                    DocumentLine.account_id.in_(cash_ids),
                    Document.document_date <= date_hi,
                )
            )
        )
        if before_period and date_lo is not None:
            q = q.filter(Document.document_date < date_lo)
        elif date_lo is not None:
            q = q.filter(Document.document_date >= date_lo)
        if fy:
            q = q.filter(Document.fiscal_year_id == fy.id)
        if currency_id:
            q = q.filter(Document.currency_id == currency_id)
        return q

    opening = Decimal(0)
    for line, _doc in _cash_movement_query(date_from_obj, date_from_obj, before_period=True).all():
        opening += _line_amount(line, use_base=use_base, side="debit")
        opening -= _line_amount(line, use_base=use_base, side="credit")

    sections = {
        "operating": {"inflows": Decimal(0), "outflows": Decimal(0)},
        "investing": {"inflows": Decimal(0), "outflows": Decimal(0)},
        "financing": {"inflows": Decimal(0), "outflows": Decimal(0)},
        "transfers": {"inflows": Decimal(0), "outflows": Decimal(0)},
        "fx_and_other": {"inflows": Decimal(0), "outflows": Decimal(0)},
    }
    by_type: Dict[str, Dict[str, Decimal]] = defaultdict(
        lambda: {"inflows": Decimal(0), "outflows": Decimal(0), "count": Decimal(0)}
    )

    period_rows = _cash_movement_query(date_from_obj, date_to_obj).all()
    period_net = Decimal(0)

    doc_ids = list({int(doc.id) for _line, doc in period_rows if doc and doc.id})
    counterpart_by_doc: Dict[int, List[Account]] = defaultdict(list)
    if doc_ids:
        other_lines = (
            db.query(DocumentLine, Account)
            .outerjoin(Account, Account.id == DocumentLine.account_id)
            .filter(DocumentLine.document_id.in_(doc_ids))
            .all()
        )
        cash_id_set = set(cash_ids)
        for ol, acc in other_lines:
            if ol.account_id is None:
                continue
            if int(ol.account_id) in cash_id_set:
                continue
            if acc is not None:
                counterpart_by_doc[int(ol.document_id)].append(acc)

    cash_counterpart_only: Dict[int, bool] = {}
    if doc_ids:
        rows_acc = (
            db.query(DocumentLine.document_id, DocumentLine.account_id)
            .filter(
                DocumentLine.document_id.in_(doc_ids),
                DocumentLine.account_id.isnot(None),
            )
            .all()
        )
        by_doc_accs: Dict[int, Set[int]] = defaultdict(set)
        for did, aid in rows_acc:
            by_doc_accs[int(did)].add(int(aid))
        cash_id_set = set(cash_ids)
        for did, aids in by_doc_accs.items():
            non_cash = [a for a in aids if a not in cash_id_set]
            cash_counterpart_only[did] = len(non_cash) == 0 and len(aids) > 1

    from app.services.cash_flow_classification import classify_cfs_section

    for line, doc in period_rows:
        debit = _line_amount(line, use_base=use_base, side="debit")
        credit = _line_amount(line, use_base=use_base, side="credit")
        period_net += debit - credit
        dtype = (doc.document_type or "other").strip() or "other"
        extra = doc.extra_info if isinstance(doc.extra_info, dict) else {}
        line_extra = line.extra_info if isinstance(line.extra_info, dict) else {}
        is_fx = bool(
            extra.get("fx_period_revaluation")
            or extra.get("period_end_fx_revaluation")
            or line_extra.get("fx_period_revaluation")
        )
        counterparts = counterpart_by_doc.get(int(doc.id), [])
        counterpart_codes = [getattr(a, "code", "") or "" for a in counterparts]
        section = classify_cfs_section(
            document_type=dtype,
            is_fx_revaluation=is_fx,
            counterpart_account_codes=counterpart_codes,
            counterpart_is_only_cash=bool(cash_counterpart_only.get(int(doc.id))),
        )

        if debit > 0:
            sections[section]["inflows"] += debit
            by_type[dtype]["inflows"] += debit
        if credit > 0:
            sections[section]["outflows"] += credit
            by_type[dtype]["outflows"] += credit
        by_type[dtype]["count"] += 1

    closing = opening + period_net

    def _sec(name: str) -> Dict[str, float]:
        inf = sections[name]["inflows"]
        out = sections[name]["outflows"]
        return {
            "inflows": float(inf),
            "outflows": float(out),
            "net": float(inf - out),
        }

    biz = db.query(Business).filter(Business.id == business_id).first()
    base_currency = None
    if biz and biz.default_currency_id:
        cur = db.query(Currency).filter(Currency.id == biz.default_currency_id).first()
        if cur:
            base_currency = {"id": cur.id, "code": cur.code, "symbol": cur.symbol, "name": cur.name}

    by_document_type = [
        {
            "document_type": k,
            "inflows": float(v["inflows"]),
            "outflows": float(v["outflows"]),
            "net": float(v["inflows"] - v["outflows"]),
            "document_count": int(v["count"]),
        }
        for k, v in sorted(by_type.items(), key=lambda x: x[0])
    ]

    operating_sec = _sec("operating")
    result: Dict[str, Any] = {
        "sections": {
            "operating": operating_sec,
            "investing": _sec("investing"),
            "financing": _sec("financing"),
            "transfers": _sec("transfers"),
            "fx_and_other": _sec("fx_and_other"),
        },
        "opening_cash": float(opening),
        "closing_cash": float(closing),
        "net_change": float(period_net),
        "by_document_type": by_document_type,
        "meta": {
            "currency_id": currency_id,
            "amounts_in_base": use_base,
            "base_currency": base_currency,
            "date_from": date_from_obj.isoformat(),
            "date_to": date_to_obj.isoformat(),
            "fiscal_year_id": fy.id if fy else None,
            "method": "direct_cash_accounts_counterpart_classified",
            "classification": "IAS7_iran_coa_v2",
            "include_indirect": include_indirect,
            "note": (
                "طبقه‌بندی بر اساس حساب طرف مقابل نقد: دارایی ثابت/سپرده→سرمایه‌گذاری؛ "
                "وام/سرمایه→تأمین مالی؛ انتقال نقد↔نقد جدا؛ تسعیر جدا. "
                "روش غیرمستقیم در کلید indirect_operating."
            ),
        },
    }

    if include_indirect:
        result["indirect_operating"] = _build_indirect_operating(
            db,
            business_id,
            fy=fy,
            date_from_obj=date_from_obj,
            date_to_obj=date_to_obj,
            currency_id=currency_id,
            direct_operating_net=float(operating_sec["net"]),
        )

    _attach_quality(result["meta"])
    return result


def get_fx_revaluation_report(
    db: Session,
    business_id: int,
    *,
    fiscal_year_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """گزارش اسناد تسعیر پایان‌دوره و اثر سود/زیان تسعیر."""
    from app.services.period_end_fx_revaluation_service import preview_period_end_fx_revaluation

    date_from_obj = _parse_date(date_from)
    date_to_obj = _parse_date(date_to) or date.today()

    q = (
        db.query(Document)
        .filter(
            Document.business_id == business_id,
            Document.is_proforma == False,  # noqa: E712
        )
        .order_by(Document.document_date.desc(), Document.id.desc())
    )
    if fiscal_year_id:
        q = q.filter(Document.fiscal_year_id == fiscal_year_id)
    if date_from_obj:
        q = q.filter(Document.document_date >= date_from_obj)
    if date_to_obj:
        q = q.filter(Document.document_date <= date_to_obj)

    docs = q.all()
    fx_docs: List[Document] = []
    for doc in docs:
        extra = doc.extra_info if isinstance(doc.extra_info, dict) else {}
        if extra.get("fx_period_revaluation") or extra.get("period_end_fx_revaluation"):
            fx_docs.append(doc)
            continue
        if doc.document_type == "manual_document":
            lines = (
                db.query(DocumentLine)
                .filter(DocumentLine.document_id == doc.id)
                .limit(50)
                .all()
            )
            if any(
                isinstance(ln.extra_info, dict) and ln.extra_info.get("fx_period_revaluation")
                for ln in lines
            ):
                fx_docs.append(doc)

    items: List[Dict[str, Any]] = []
    total_gain = Decimal(0)
    total_loss = Decimal(0)
    for doc in fx_docs:
        lines = db.query(DocumentLine).filter(DocumentLine.document_id == doc.id).all()
        gain = Decimal(0)
        loss = Decimal(0)
        for ln in lines:
            lex = ln.extra_info if isinstance(ln.extra_info, dict) else {}
            credit_b = (
                Decimal(str(ln.credit_base))
                if ln.credit_base is not None
                else Decimal(str(ln.credit or 0))
            )
            debit_b = (
                Decimal(str(ln.debit_base))
                if ln.debit_base is not None
                else Decimal(str(ln.debit or 0))
            )
            if lex.get("side") == "gain":
                gain += credit_b
            if lex.get("side") == "loss":
                loss += debit_b
        if gain == 0 and loss == 0:
            for ln in lines:
                desc = (ln.description or "").lower()
                credit_b = (
                    Decimal(str(ln.credit_base))
                    if ln.credit_base is not None
                    else Decimal(str(ln.credit or 0))
                )
                debit_b = (
                    Decimal(str(ln.debit_base))
                    if ln.debit_base is not None
                    else Decimal(str(ln.debit or 0))
                )
                if "سود تسعیر" in (ln.description or "") or "gain" in desc:
                    gain += credit_b
                if "زیان تسعیر" in (ln.description or "") or "loss" in desc:
                    loss += debit_b
        total_gain += gain
        total_loss += loss
        items.append(
            {
                "document_id": doc.id,
                "document_code": doc.code or "",
                "document_date": doc.document_date.isoformat() if doc.document_date else None,
                "description": doc.description or "",
                "fx_gain": float(gain),
                "fx_loss": float(loss),
                "net_fx": float(gain - loss),
            }
        )

    preview = None
    try:
        preview = preview_period_end_fx_revaluation(
            db, business_id, fiscal_year_id=fiscal_year_id
        )
    except Exception:
        preview = None

    total = len(items)
    page_items = items[skip : skip + take]
    return {
        "items": page_items,
        "summary": {
            "total_count": total,
            "total_fx_gain": float(total_gain),
            "total_fx_loss": float(total_loss),
            "net_fx": float(total_gain - total_loss),
        },
        "preview": preview,
        "pagination": {
            "total": total,
            "page": (skip // take) + 1 if take > 0 else 1,
            "per_page": take,
            "total_pages": (total + take - 1) // take if take > 0 else 0,
            "has_next": (skip + take) < total,
            "has_prev": skip > 0,
        },
        "meta": {
            "amounts_in_base": True,
            "date_from": date_from_obj.isoformat() if date_from_obj else None,
            "date_to": date_to_obj.isoformat() if date_to_obj else None,
            "fiscal_year_id": fiscal_year_id,
        },
    }
