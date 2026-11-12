from decimal import Decimal, DecimalException

from app.core.responses import ApiError
from app.services.currency_quant import decimal_places_to_quant
from app.services.invoice_global_discount_service import apply_global_discount_to_invoice_payload
from app.services.invoice_unit_conversion_service import extra_info_dict


def _allocated_line_totals(db, business_id, invoice_type, data, lines, prepare_discount_lines):
    # The allocator replaces extra_info on its inputs. Preview on copies so the
    # validation happens before document/GL changes and saving still applies it once.
    if (
        not any(key in data for key in ("global_discount_amount", "global_discount_percent"))
        and not isinstance(extra_info_dict(data.get("extra_info")).get("global_discount"), dict)
    ):
        return []
    preview = dict(data)
    preview_lines = [dict(line) for line in lines]
    if prepare_discount_lines is not None:
        prepare_discount_lines(preview_lines)
    if not apply_global_discount_to_invoice_payload(db, business_id, invoice_type, preview_lines, preview):
        return []
    return [Decimal(str(line["extra_info"]["line_total"])) for line in preview_lines]


def validate_invoice_line_totals(
    data, lines, currency, *, db, business_id, invoice_type, prepare_discount_lines=None,
):
    """Accept the line before header discount or as calculated by the allocator."""
    places = currency.decimal_places
    quant = decimal_places_to_quant(places if places is not None else 2)
    allocated = None
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
            if all(value.is_finite() for value in (supplied, expected, quantity)):
                tolerance = max(abs(quantity) * quant, quant)
                if abs(supplied - expected) <= tolerance:
                    continue
                if allocated is None:
                    allocated = _allocated_line_totals(
                        db, business_id, invoice_type, data, lines, prepare_discount_lines,
                    )
                if allocated and abs(supplied - allocated[index - 1]) <= tolerance:
                    continue
        except DecimalException:
            pass
        raise ApiError(
            "INCONSISTENT_LINE_TOTAL",
            "مبلغ ردیف با تعداد، قیمت واحد، تخفیف و مالیات آن سازگار نیست",
            http_status=422, details={"line_index": index},
        )
