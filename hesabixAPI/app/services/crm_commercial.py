"""تجمیع فروش، برگشت و حاشیه بدون تعریف مانده جدید.

مبلغ فروش از جمع فاکتور است. حاشیه فقط برای خطی حساب می‌شود که بهای
شناخته‌شده دارد: بهای قطعی دفتر، cogs_amount یا cost_price. قیمت فروش
هرگز به‌جای بها استفاده نمی‌شود.
"""
from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Any


def money(value: Any) -> Decimal:
    if value is None or value == "":
        return Decimal("0.00")
    return Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def line_revenue(extra: dict | None, quantity: Any) -> Decimal:
    info = extra or {}
    if info.get("net") is not None:
        return money(info.get("net"))
    unit = info.get("unit_price")
    if unit is None:
        return Decimal("0.00")
    discount = money(info.get("discount_amount") if info.get("discount_amount") is not None else info.get("line_discount") or info.get("discount") or 0)
    return money(Decimal(str(unit)) * Decimal(str(quantity or 0)) - discount)


def known_line_cost(extra: dict | None, quantity: Any, ledger_line_cogs: Any = None) -> Decimal | None:
    if ledger_line_cogs is not None:
        return money(ledger_line_cogs)
    info = extra or {}
    if info.get("cogs_amount") is not None:
        return money(info.get("cogs_amount"))
    if info.get("cost_price") is not None:
        return money(Decimal(str(info.get("cost_price"))) * Decimal(str(quantity or 0)))
    return None


def document_total(totals_net: Any, lines: list[dict[str, Any]]) -> Decimal:
    if totals_net is not None:
        return money(totals_net)
    return money(sum((line_revenue(line.get("extra_info"), line.get("quantity")) for line in lines), Decimal("0")))


def aggregate_commercial(documents: list[dict[str, Any]]) -> dict[str, Any]:
    """اسناد پیش‌فاکتور نادیده گرفته می‌شوند. ارزهای مختلف با هم جمع نمی‌شوند."""
    groups: dict[Any, dict[str, Any]] = {}
    repeats: dict[Any, dict[str, Any]] = {}
    receipt_ids: set[int] = set()

    for doc in documents:
        if doc.get("is_proforma"):
            continue
        kind = doc.get("document_type")
        if kind not in ("invoice_sales", "invoice_sales_return"):
            continue
        sign = -1 if kind == "invoice_sales_return" else 1
        currency_id = doc.get("currency_id")
        bucket = groups.setdefault(
            currency_id,
            {
                "currency_id": currency_id,
                "sales_total": Decimal("0.00"),
                "returns_total": Decimal("0.00"),
                "margin_amount": Decimal("0.00"),
                "margin_lines": 0,
                "product_lines": 0,
                "document_count": 0,
            },
        )
        if doc.get("currency_code") and not bucket.get("currency_code"):
            bucket["currency_code"] = doc.get("currency_code")
        lines = list(doc.get("lines") or [])
        total = document_total(doc.get("totals_net"), lines)
        if sign > 0:
            bucket["sales_total"] += total
        else:
            bucket["returns_total"] += total
        bucket["document_count"] += 1
        for raw in doc.get("receipt_ids") or []:
            try:
                receipt_ids.add(int(raw))
            except (TypeError, ValueError):
                continue
        for line in lines:
            product_id = line.get("product_id")
            if not product_id:
                continue
            bucket["product_lines"] += 1
            revenue = line_revenue(line.get("extra_info"), line.get("quantity"))
            cost = known_line_cost(line.get("extra_info"), line.get("quantity"), line.get("ledger_line_cogs"))
            if cost is None:
                continue
            bucket["margin_lines"] += 1
            bucket["margin_amount"] += Decimal(sign) * (revenue - cost)
            if sign > 0:
                item = repeats.setdefault(
                    product_id,
                    {
                        "product_id": int(product_id),
                        "product_name": line.get("product_name"),
                        "invoice_ids": set(),
                        "quantity": Decimal("0"),
                        "last_document_date": None,
                    },
                )
                if line.get("product_name"):
                    item["product_name"] = line.get("product_name")
                item["invoice_ids"].add(doc.get("id"))
                item["quantity"] += Decimal(str(line.get("quantity") or 0))
                current = doc.get("document_date")
                if current and (item["last_document_date"] is None or str(current) > str(item["last_document_date"])):
                    item["last_document_date"] = str(current)

    currencies = []
    for bucket in groups.values():
        applicable = bucket["product_lines"] > 0
        complete = applicable and bucket["margin_lines"] == bucket["product_lines"]
        currencies.append(
            {
                "currency_id": bucket["currency_id"],
                "currency_code": bucket.get("currency_code"),
                "sales_total": float(money(bucket["sales_total"])),
                "returns_total": float(money(bucket["returns_total"])),
                "net_sales": float(money(bucket["sales_total"] - bucket["returns_total"])),
                "margin_amount": float(money(bucket["margin_amount"])) if bucket["margin_lines"] else None,
                "margin_applicable": applicable,
                "margin_complete": complete,
                "document_count": bucket["document_count"],
            }
        )
    currencies.sort(key=lambda row: (row["currency_id"] is None, str(row["currency_id"])))
    suggestions = []
    for item in repeats.values():
        invoice_count = len(item["invoice_ids"])
        if invoice_count < 2:
            continue
        suggestions.append(
            {
                "product_id": item["product_id"],
                "product_name": item["product_name"],
                "invoice_count": invoice_count,
                "quantity": float(item["quantity"]),
                "last_document_date": item["last_document_date"],
            }
        )
    suggestions.sort(key=lambda row: (-row["invoice_count"], row["product_id"]))
    single = currencies[0] if len(currencies) == 1 else None
    return {
        "amounts_basis": "document_currency_not_converted",
        "sales_basis": "invoice_total",
        "margin_basis": "line_revenue_minus_known_cost",
        "mixed_currency": len(currencies) > 1,
        "sales_total": None if single is None else single["sales_total"],
        "returns_total": None if single is None else single["returns_total"],
        "net_sales": None if single is None else single["net_sales"],
        "margin_amount": None if single is None else single["margin_amount"],
        "margin_complete": False if single is None else single["margin_complete"],
        "currencies": currencies,
        "repeat_products": suggestions[:8],
        "receipt_ids": sorted(receipt_ids),
    }
