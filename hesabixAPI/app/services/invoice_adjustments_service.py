"""
اضافات و کسورات فاکتور (فروش/خرید): اعتبارسنجی، ادغام در جمع فاکتور، و خطوط حسابداری.

فقط برای invoice_sales و invoice_purchase؛ در پیش‌فاکتور فقط در extra_info ذخیره می‌شود.
"""
from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Tuple

from sqlalchemy import or_
from sqlalchemy.orm import Session

from adapters.db.models.account import Account
from adapters.db.models.document_line import DocumentLine
from app.core.responses import ApiError

INVOICE_ADJUSTMENTS_KEY = "invoice_adjustments"

INVOICE_SALES = "invoice_sales"
INVOICE_PURCHASE = "invoice_purchase"

_ADJUSTMENT_SUPPORTED = frozenset({INVOICE_SALES, INVOICE_PURCHASE})

_KIND_ADD = "addition"
_KIND_DED = "deduction"


def _money_quant(x: Decimal) -> Decimal:
    return x.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def total_with_tax_from_totals_dict(totals: Dict[str, Any]) -> Decimal:
    gross = Decimal(str(totals.get("gross", 0)))
    discount = Decimal(str(totals.get("discount", 0)))
    tax = Decimal(str(totals.get("tax", 0)))
    adj_n = Decimal(str(totals.get("adjustments_net", 0)))
    adj_t = Decimal(str(totals.get("adjustments_tax", 0)))
    return _money_quant(gross - discount + tax + adj_n + adj_t)


def _validate_account_for_business(db: Session, business_id: int, account_id: int) -> Account:
    acc = (
        db.query(Account)
        .filter(
            Account.id == int(account_id),
            or_(Account.business_id == business_id, Account.business_id.is_(None)),  # noqa: E711
        )
        .first()
    )
    if not acc:
        raise ApiError(
            "ADJUSTMENT_ACCOUNT_NOT_FOUND",
            f"حساب اضافات/کسورات با شناسه {account_id} یافت نشد",
            http_status=404,
        )
    return acc


def normalize_invoice_adjustments(
    db: Session,
    business_id: int,
    invoice_type: str,
    raw: Any,
) -> List[Dict[str, Any]]:
    if raw is None or raw == []:
        return []
    if invoice_type not in _ADJUSTMENT_SUPPORTED:
        raise ApiError(
            "INVOICE_ADJUSTMENTS_NOT_ALLOWED",
            "اضافات و کسورات فقط برای فاکتور فروش یا خرید مجاز است",
            http_status=400,
        )
    if not isinstance(raw, list):
        raise ApiError("INVALID_INVOICE_ADJUSTMENTS", "invoice_adjustments باید آرایه باشد", http_status=400)

    out: List[Dict[str, Any]] = []
    for i, row in enumerate(raw):
        if not isinstance(row, dict):
            raise ApiError("INVALID_INVOICE_ADJUSTMENTS", f"ردیف {i + 1} نامعتبر است", http_status=400)
        kind = str(row.get("kind") or "").strip().lower()
        if kind not in (_KIND_ADD, _KIND_DED):
            raise ApiError(
                "INVALID_ADJUSTMENT_KIND",
                f"ردیف {i + 1}: kind باید addition یا deduction باشد",
                http_status=400,
            )
        try:
            amount = Decimal(str(row.get("amount", 0) or 0))
        except Exception as exc:
            raise ApiError("INVALID_ADJUSTMENT_AMOUNT", f"ردیف {i + 1}: مبلغ نامعتبر", http_status=400) from exc
        if amount <= 0:
            raise ApiError("INVALID_ADJUSTMENT_AMOUNT", f"ردیف {i + 1}: مبلغ باید مثبت باشد", http_status=400)

        tax_rate = row.get("tax_rate")
        tr = Decimal(0)
        if tax_rate is not None and str(tax_rate).strip() != "":
            try:
                tr = Decimal(str(tax_rate))
            except Exception as exc:
                raise ApiError("INVALID_ADJUSTMENT_TAX", f"ردیف {i + 1}: نرخ مالیات نامعتبر", http_status=400) from exc
        if tr < 0 or tr > 100:
            raise ApiError("INVALID_ADJUSTMENT_TAX", f"ردیف {i + 1}: نرخ مالیات باید بین 0 و 100 باشد", http_status=400)

        tax_amt = _money_quant(amount * tr / Decimal(100)) if tr > 0 else Decimal(0)
        total = _money_quant(amount + tax_amt)

        aid = row.get("account_id")
        if aid is None:
            raise ApiError("ADJUSTMENT_ACCOUNT_REQUIRED", f"ردیف {i + 1}: انتخاب حساب الزامی است", http_status=400)
        try:
            acc_id = int(aid)
        except Exception as exc:
            raise ApiError("ADJUSTMENT_ACCOUNT_REQUIRED", f"ردیف {i + 1}: شناسه حساب نامعتبر", http_status=400) from exc
        _validate_account_for_business(db, business_id, acc_id)

        desc = row.get("description")
        desc_s = str(desc).strip() if desc is not None else ""
        source = row.get("source")
        source_s = str(source).strip() if source is not None else ""
        exclude_raw = row.get("exclude_from_profit", False)
        exclude_from_profit = (
            exclude_raw is True
            or str(exclude_raw).strip().lower() in {"1", "true", "yes", "on"}
        )

        signed_net = amount if kind == _KIND_ADD else -amount
        signed_tax = tax_amt if kind == _KIND_ADD else -tax_amt

        normalized_row = {
            "kind": kind,
            "amount": float(amount),
            "tax_rate": float(tr),
            "tax_amount": float(tax_amt),
            "total": float(total),
            "account_id": acc_id,
            "description": desc_s or None,
            "_signed_net": signed_net,
            "_signed_tax": signed_tax,
        }
        if source_s:
            normalized_row["source"] = source_s[:80]
        if exclude_from_profit:
            normalized_row["exclude_from_profit"] = True
        out.append(normalized_row)
    return out


def summarize_normalized_adjustments(rows: List[Dict[str, Any]]) -> Tuple[Decimal, Decimal]:
    net = Decimal(0)
    tax = Decimal(0)
    for r in rows:
        net += Decimal(str(r["_signed_net"]))
        tax += Decimal(str(r["_signed_tax"]))
    return _money_quant(net), _money_quant(tax)


def merge_invoice_adjustments_into_header_extra(
    db: Session,
    business_id: int,
    invoice_type: str,
    header_extra: Dict[str, Any],
) -> None:
    """اعتبارسنجی، نرمال‌سازی invoice_adjustments و قرار دادن adjustments_net/tax در totals."""
    raw = header_extra.get(INVOICE_ADJUSTMENTS_KEY)
    totals = dict(header_extra.get("totals") or {})

    if not raw:
        totals.setdefault("adjustments_net", 0.0)
        totals.setdefault("adjustments_tax", 0.0)
        header_extra.pop(INVOICE_ADJUSTMENTS_KEY, None)
        header_extra["totals"] = totals
        return

    normalized = normalize_invoice_adjustments(db, business_id, invoice_type, raw)
    adj_net, adj_tax = summarize_normalized_adjustments(normalized)
    for r in normalized:
        r.pop("_signed_net", None)
        r.pop("_signed_tax", None)

    header_extra[INVOICE_ADJUSTMENTS_KEY] = normalized
    totals["adjustments_net"] = float(adj_net)
    totals["adjustments_tax"] = float(adj_tax)
    header_extra["totals"] = totals


def add_adjustment_document_lines(
    db: Session,
    *,
    business_id: int,
    document_id: int,
    invoice_type: str,
    accounts: Dict[str, Any],
    header_extra: Dict[str, Any],
) -> None:
    """خطوط حسابداری اضافات/کسورات؛ فقط برای فاکتور قطعی فراخوانی شود."""
    rows_raw = header_extra.get(INVOICE_ADJUSTMENTS_KEY) or []
    if not rows_raw:
        return
    if invoice_type not in _ADJUSTMENT_SUPPORTED:
        return

    rows = normalize_invoice_adjustments(db, business_id, invoice_type, rows_raw)
    if not rows:
        return

    vat_out = accounts["vat_out"]
    vat_in = accounts["vat_in"]

    for r in rows:
        kind = r["kind"]
        net = Decimal(str(r["amount"]))
        tax_amt = Decimal(str(r["tax_amount"]))
        acc_id = int(r["account_id"])
        desc = (r.get("description") or "").strip() or ("اضافات/کسورات فاکتور")

        def _extra(kind_value: str) -> Dict[str, Any]:
            extra: Dict[str, Any] = {"invoice_adjustment": True, "kind": kind_value}
            if r.get("source"):
                extra["source"] = r.get("source")
            if r.get("exclude_from_profit"):
                extra["exclude_from_profit"] = True
            return extra

        if invoice_type == INVOICE_SALES:
            if kind == _KIND_ADD:
                db.add(
                    DocumentLine(
                        document_id=document_id,
                        account_id=acc_id,
                        debit=Decimal(0),
                        credit=net,
                        description=desc,
                        extra_info=_extra("addition"),
                    )
                )
                if tax_amt > 0:
                    db.add(
                        DocumentLine(
                            document_id=document_id,
                            account_id=vat_out.id,
                            debit=Decimal(0),
                            credit=tax_amt,
                            description=f"مالیات خروجی — {desc}",
                            extra_info=_extra("addition_vat"),
                        )
                    )
            else:
                db.add(
                    DocumentLine(
                        document_id=document_id,
                        account_id=acc_id,
                        debit=net,
                        credit=Decimal(0),
                        description=desc,
                        extra_info=_extra("deduction"),
                    )
                )
                if tax_amt > 0:
                    db.add(
                        DocumentLine(
                            document_id=document_id,
                            account_id=vat_out.id,
                            debit=tax_amt,
                            credit=Decimal(0),
                            description=f"تعدیل مالیات خروجی — {desc}",
                            extra_info=_extra("deduction_vat"),
                        )
                    )

        elif invoice_type == INVOICE_PURCHASE:
            if kind == _KIND_ADD:
                db.add(
                    DocumentLine(
                        document_id=document_id,
                        account_id=acc_id,
                        debit=net,
                        credit=Decimal(0),
                        description=desc,
                        extra_info=_extra("addition"),
                    )
                )
                if tax_amt > 0:
                    db.add(
                        DocumentLine(
                            document_id=document_id,
                            account_id=vat_in.id,
                            debit=tax_amt,
                            credit=Decimal(0),
                            description=f"مالیات ورودی — {desc}",
                            extra_info=_extra("addition_vat"),
                        )
                    )
            else:
                db.add(
                    DocumentLine(
                        document_id=document_id,
                        account_id=acc_id,
                        debit=Decimal(0),
                        credit=net,
                        description=desc,
                        extra_info=_extra("deduction"),
                    )
                )
                if tax_amt > 0:
                    db.add(
                        DocumentLine(
                            document_id=document_id,
                            account_id=vat_in.id,
                            debit=Decimal(0),
                            credit=tax_amt,
                            description=f"تعدیل مالیات ورودی — {desc}",
                            extra_info=_extra("deduction_vat"),
                        )
                    )
