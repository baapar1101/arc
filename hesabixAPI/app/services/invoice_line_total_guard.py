from decimal import Decimal, DecimalException

from app.core.responses import ApiError
from app.services.currency_quant import decimal_places_to_quant
from app.services.invoice_unit_conversion_service import extra_info_dict


def _positive(value):
    try:
        number = Decimal(str(value or 0))
        return number.is_finite() and number > 0
    except DecimalException:
        return False


def _has_global_discount(payload):
    keys = ("header_discount", "global_discount_amount", "global_discount_percent")
    if any(_positive(payload.get(key)) for key in keys):
        return True
    discount = extra_info_dict(payload.get("extra_info")).get("global_discount")
    if not isinstance(discount, dict):
        return _positive(discount)
    return _positive(discount.get("amount")) or _positive(discount.get("value"))


def validate_invoice_line_totals(data, lines, currency, *, document=None):
    """Validate client amounts before an invoice is written; H37 owns global discount."""
    stored = {"extra_info": getattr(document, "extra_info", None),
              "global_discount_amount": getattr(document, "global_discount_amount", None)}
    if any(_has_global_discount(entry) for entry in (data, stored, *lines)):
        return
    places = currency.decimal_places
    quant = decimal_places_to_quant(places if places is not None else 2)
    for index, line in enumerate(lines, 1):
        info = extra_info_dict(line.get("extra_info"))
        sent = info.get("line_total", line.get("line_total"))
        if sent is None:
            continue
        try:
            quantity = Decimal(str(line.get("quantity") or 0))
            price, discount, tax = (
                Decimal(str(info.get(key, line.get(key)) or 0))
                for key in ("unit_price", "line_discount", "tax_amount")
            )
            supplied = Decimal(str(sent))
            expected = quantity * price - discount + tax
            if (all(value.is_finite() for value in (supplied, expected, quantity))
                    and abs(supplied - expected) <= max(abs(quantity) * quant, quant)):
                continue
        except DecimalException:
            pass
        raise ApiError(
            "INCONSISTENT_LINE_TOTAL",
            "مبلغ ردیف با تعداد، قیمت واحد، تخفیف و مالیات آن سازگار نیست",
            http_status=422, details={"line_index": index},
        )
