"""
تخفیف کلی فاکتور: نرمال‌سازی payload، محاسبهٔ جمع‌ها و اعمال روی ردیف‌ها (مالیات متناسب).
"""
from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from app.core.responses import ApiError
from app.services.currency_quant import get_currency_quant_and_round

SCRATCH_QUANT = Decimal("0.00000001")


def _make_q(quant: Decimal, round_monetary: bool):
    def q(x: Decimal) -> Decimal:
        if not round_monetary:
            return x.quantize(SCRATCH_QUANT, rounding=ROUND_HALF_UP)
        return x.quantize(quant, rounding=ROUND_HALF_UP)

    return q


def _line_core_amounts(line: Dict[str, Any]) -> Tuple[Decimal, Decimal, Decimal, Decimal]:
    """gross_line, line_discount, taxable (>=0), tax_rate_percent"""
    info = line.get("extra_info") or {}
    qty = Decimal(str(line.get("quantity", 0) or 0))
    unit_price = Decimal(str(info.get("unit_price", 0) or 0))
    line_discount = Decimal(str(info.get("line_discount", 0) or 0))
    tax_rate = Decimal(str(info.get("tax_rate", 0) or 0))
    gross_line = qty * unit_price
    taxable = gross_line - line_discount
    if taxable < 0:
        taxable = Decimal(0)
    return gross_line, line_discount, taxable, tax_rate


def _line_tax_from_taxable(
    taxable: Decimal, tax_rate: Decimal, q
) -> Decimal:
    if taxable <= 0 or tax_rate <= 0:
        return Decimal(0)
    return q(taxable * tax_rate / Decimal(100))


def normalize_global_discount_in_payload(data: Dict[str, Any]) -> None:
    """انتقال global_discount_percent / global_discount_amount به extra_info.global_discount"""
    ex = dict(data.get("extra_info") or {}) if isinstance(data.get("extra_info"), dict) else {}
    gd_existing = dict(ex.get("global_discount") or {}) if isinstance(ex.get("global_discount"), dict) else {}

    pct = data.pop("global_discount_percent", None)
    amt = data.pop("global_discount_amount", None)

    if pct is not None:
        try:
            p = Decimal(str(pct))
        except Exception:
            p = Decimal(0)
        if p > 0:
            gd_existing["type"] = "percent"
            gd_existing["value"] = float(p)

    if amt is not None:
        try:
            a = Decimal(str(amt))
        except Exception:
            a = Decimal(0)
        if a > 0:
            gd_existing["type"] = "amount"
            gd_existing["value"] = float(a)

    if gd_existing.get("type") and gd_existing.get("value") is not None:
        ex["global_discount"] = gd_existing
        data["extra_info"] = ex


def _parse_global_discount_spec(header_extra: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    gd = header_extra.get("global_discount")
    if not isinstance(gd, dict):
        return None
    t = str(gd.get("type") or "").strip().lower()
    if t not in ("percent", "amount"):
        return None
    try:
        v = Decimal(str(gd.get("value") or 0))
    except Exception:
        return None
    if v <= 0:
        return None
    if t == "percent" and v > Decimal(100):
        return None
    return {"type": t, "value": v}


def _business_discount_settings(biz: Optional[Business]) -> Dict[str, Any]:
    if not biz:
        return {
            "percent_basis": "subtotal_after_line_discount",
            "tax_mode": "recalculate_tax_proportional",
            "max_percent": None,
            "max_amount": None,
        }
    return {
        "percent_basis": str(
            getattr(biz, "invoice_global_discount_percent_basis", None)
            or "subtotal_after_line_discount"
        ).strip(),
        "tax_mode": str(
            getattr(biz, "invoice_global_discount_tax_mode", None) or "recalculate_tax_proportional"
        ).strip(),
        "max_percent": getattr(biz, "invoice_global_discount_max_percent", None),
        "max_amount": getattr(biz, "invoice_global_discount_max_amount", None),
    }


def _basis_amount(
    basis_code: str,
    sums: Dict[str, Decimal],
) -> Decimal:
    if basis_code == "gross_before_line_discount":
        return sums["G"]
    if basis_code == "total_after_lines_including_tax":
        return sums["N0"] + sums["T0"]
    # پیش‌فرض: بعد از تخفیف ردیف، پیش از اعمال تخفیف کلی
    return sums["N0"]


def _cap_global_discount(
    raw: Decimal, basis: Decimal, settings: Dict[str, Any], q
) -> Decimal:
    g = max(Decimal(0), min(raw, basis))
    max_pct = settings.get("max_percent")
    if max_pct is not None:
        try:
            mp = Decimal(str(max_pct))
        except Exception:
            mp = None
        if mp is not None and mp > 0:
            cap_from_pct = q(basis * mp / Decimal(100))
            g = min(g, cap_from_pct)
    max_amt = settings.get("max_amount")
    if max_amt is not None:
        try:
            ma = Decimal(str(max_amt))
        except Exception:
            ma = None
        if ma is not None and ma > 0:
            g = min(g, ma)
    return g


def apply_global_discount_to_invoice_payload(
    db: Session,
    business_id: int,
    invoice_type: str,
    lines_input: List[Dict[str, Any]],
    data: Dict[str, Any],
) -> bool:
    """
    اگر تخفیف کلی در extra_info باشد، جمع‌ها را محاسبه و در صورت نیاز tax_amount ردیف‌ها را به‌روز می‌کند.
    برمی‌گرداند True اگر تخفیف کلی اعمال شده باشد.
    """
    supported = {
        "invoice_sales",
        "invoice_purchase",
        "invoice_sales_return",
        "invoice_purchase_return",
    }
    if invoice_type not in supported:
        return False

    raw_cid = data.get("currency_id")
    try:
        cid_int = int(raw_cid) if raw_cid is not None else None
    except (TypeError, ValueError):
        cid_int = None
    quant, round_monetary = get_currency_quant_and_round(db, cid_int)
    q = _make_q(quant, round_monetary)

    normalize_global_discount_in_payload(data)
    header_extra: Dict[str, Any] = dict(data.get("extra_info") or {})
    spec = _parse_global_discount_spec(header_extra)
    if not spec:
        return False

    biz = db.query(Business).filter(Business.id == int(business_id)).first()
    st = _business_discount_settings(biz)
    basis_code = st["percent_basis"]
    if basis_code not in (
        "subtotal_after_line_discount",
        "gross_before_line_discount",
        "total_after_lines_including_tax",
    ):
        basis_code = "subtotal_after_line_discount"
    tax_mode = st["tax_mode"]
    if tax_mode not in ("recalculate_tax_proportional", "keep_line_taxes"):
        tax_mode = "recalculate_tax_proportional"

    gross = Decimal(0)
    line_disc_sum = Decimal(0)
    taxables: List[Decimal] = []
    rates: List[Decimal] = []
    taxes_orig: List[Decimal] = []

    for line in lines_input:
        g_l, d_l, tx, tr = _line_core_amounts(line)
        gross += g_l
        line_disc_sum += d_l
        taxables.append(tx)
        rates.append(tr)
        taxes_orig.append(_line_tax_from_taxable(tx, tr, q))

    N0 = sum(taxables)
    T0 = sum(taxes_orig)
    Gsum = gross
    sums_map = {"G": Gsum, "N0": N0, "T0": T0}
    basis = _basis_amount(basis_code, sums_map)
    if basis <= 0:
        raise ApiError(
            "GLOBAL_DISCOUNT_BASIS_ZERO",
            "مبنای تخفیف کلی صفر است؛ ابتدا اقلام یا مبلغ معتبر وارد کنید.",
            http_status=400,
        )

    if spec["type"] == "percent":
        pct_eff = spec["value"]
        max_pct = st.get("max_percent")
        if max_pct is not None:
            try:
                mp = Decimal(str(max_pct))
            except Exception:
                mp = None
            if mp is not None and mp > 0:
                pct_eff = min(pct_eff, mp)
        raw = q(basis * pct_eff / Decimal(100))
    else:
        raw = q(spec["value"])

    Gdisc = _cap_global_discount(raw, basis, st, q)
    if Gdisc <= 0:
        header_extra.pop("global_discount", None)
        data["extra_info"] = header_extra
        return False

    N1 = max(Decimal(0), N0 - Gdisc)

    if tax_mode == "keep_line_taxes":
        T1 = T0
        # ردیف‌ها: مالیات و line_total قبلی حفظ؛ فقط سربرگ اصلاح می‌شود
        for i, line in enumerate(lines_input):
            info = dict(line.get("extra_info") or {})
            info["tax_amount"] = float(taxes_orig[i])
            txb = taxables[i]
            info["line_total"] = float(q(txb + taxes_orig[i]))
            line["extra_info"] = info
    else:
        T1 = Decimal(0)
        if N0 > 0 and N1 >= 0:
            factor = N1 / N0
        else:
            factor = Decimal(0)
        new_taxables: List[Decimal] = []
        for tx in taxables:
            new_taxables.append(q(tx * factor))
        drift = N1 - sum(new_taxables)
        if new_taxables and drift != 0:
            idx = max(range(len(new_taxables)), key=lambda j: new_taxables[j])
            new_taxables[idx] = q(new_taxables[idx] + drift)

        new_taxes: List[Decimal] = []
        for i, txb in enumerate(new_taxables):
            new_taxes.append(_line_tax_from_taxable(txb, rates[i], q))
        T1 = sum(new_taxes)

        for i, line in enumerate(lines_input):
            info = dict(line.get("extra_info") or {})
            info["tax_amount"] = float(new_taxes[i])
            info["line_total"] = float(q(new_taxables[i] + new_taxes[i]))
            line["extra_info"] = info

    discount_total = line_disc_sum + Gdisc
    grand_total = q(N1 + T1)
    header_extra["totals"] = {
        "gross": float(gross),
        "discount": float(discount_total),
        "tax": float(T1),
        "net": float(grand_total),
    }
    header_extra["global_discount"] = {
        "type": spec["type"],
        "value": float(spec["value"]),
        "amount": float(Gdisc),
        "basis": basis_code,
        "tax_mode": tax_mode,
    }
    data["extra_info"] = header_extra
    return True
