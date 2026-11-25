"""Exact invoice-currency shares, independent of rounded base-currency GL."""
from decimal import Decimal, InvalidOperation
from typing import Any

from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from app.core.responses import ApiError

ALLOCATION_KEY = "receipt_invoice_allocation"
CONTRACT_KEY = "receipt_invoice_allocations_version"


def capture_invoice_allocation(
    db: Session, business_id: int, currency_id: int, person_line: dict[str, Any],
) -> dict[str, Any] | None:
    extra = person_line.get("extra_info") or {}
    raw_id = extra.get("invoice_id")
    if raw_id is None:
        return None
    try:
        invoice_id = int(raw_id)
        person_id = int(person_line.get("person_id"))
        amount = Decimal(str(person_line.get("amount")))
    except (TypeError, ValueError, InvalidOperation):
        raise ApiError("INVALID_INVOICE_ALLOCATION", "تخصیص فاکتور نامعتبر است", http_status=400) from None
    invoice = db.get(Document, invoice_id)
    if invoice is not None and invoice.business_id == business_id and invoice.document_type != "invoice_sales":
        return None
    if (
        invoice is None or invoice.business_id != business_id
        or invoice.currency_id != currency_id
        or str((invoice.extra_info or {}).get("person_id")) != str(person_id)
        or not amount.is_finite() or amount <= 0
    ):
        raise ApiError(
            "INVALID_INVOICE_ALLOCATION",
            "شخص، ارز یا فاکتور تخصیص با دریافت سازگار نیست", http_status=400,
        )
    return {"invoice_id": invoice_id, "person_id": person_id,
            "currency_id": currency_id, "amount": str(amount)}


def preserve_readback_allocations(
    db: Session, document: Document, data: dict[str, Any],
) -> dict[int, dict[str, Any]]:
    """A base-currency readback can preserve unchanged shares by persisted line ID.

    Changed shares must arrive in settlement currency; rounded GL cannot prove
    their original amounts. Client-provided developer data is never consulted.
    """
    if (document.developer_settings or {}).get(CONTRACT_KEY) != 1:
        return {}
    if int(data.get("currency_id") or document.currency_id) != document.currency_id:
        return {}
    stored = {line.id: line for line in document.lines}
    allocations = {}
    seen = set()
    for index, incoming in enumerate(data.get("person_lines") or []):
        invoice_id = (incoming.get("extra_info") or {}).get("invoice_id")
        if invoice_id is None:
            continue
        try:
            invoice = db.get(Document, int(invoice_id))
        except (TypeError, ValueError):
            raise ApiError("INVALID_INVOICE_ALLOCATION", "شناسه فاکتور نامعتبر است", http_status=400) from None
        if invoice is not None and invoice.currency_id == document.currency_id:
            allocation = capture_invoice_allocation(
                db, document.business_id, document.currency_id, incoming,
            )
            if allocation is not None:
                allocations[index] = allocation
                continue
        line = stored.get(incoming.get("id"))
        allocation = (line.developer_data or {}).get(ALLOCATION_KEY) if line else None
        try:
            base_amount = Decimal(str(incoming.get("amount")))
        except InvalidOperation:
            raise ApiError(
                "INVOICE_ALLOCATION_CURRENCY_REQUIRED", "مبلغ تخصیص نامعتبر است", http_status=400,
            ) from None
        if (
            not isinstance(allocation, dict)
            or str(allocation["invoice_id"]) != str(invoice_id)
            or str(allocation["person_id"]) != str(incoming.get("person_id"))
            or base_amount != line.credit
            or line.id in seen
        ):
            raise ApiError(
                "INVOICE_ALLOCATION_CURRENCY_REQUIRED",
                "ویرایش سهم تخصیص باید با مبلغ دقیق در ارز فاکتور ارسال شود", http_status=400,
            )
        allocations[index] = dict(allocation)
        seen.add(line.id)
    return allocations


def exact_receipt_allocation(receipt: Document, invoice: Document) -> Decimal | None:
    """None selects the legacy reader; zero is authoritative for removed shares."""
    if (receipt.developer_settings or {}).get(CONTRACT_KEY) != 1:
        return None
    if receipt.document_type != "receipt" or invoice.document_type != "invoice_sales":
        return None
    total = Decimal(0)
    seen = set()
    for line in receipt.lines:
        allocation = (line.developer_data or {}).get(ALLOCATION_KEY)
        if not isinstance(allocation, dict) or line.id in seen:
            continue
        if (
            receipt.business_id != invoice.business_id
            or allocation.get("invoice_id") != invoice.id
            or allocation.get("currency_id") != invoice.currency_id
            or allocation.get("person_id") != line.person_id
            or str(line.person_id) != str((invoice.extra_info or {}).get("person_id"))
            or str((line.extra_info or {}).get("invoice_id")) != str(invoice.id)
            or line.account is None or line.account.code != "10401"
            or line.debit != 0 or line.credit < 0
        ):
            continue
        amount = Decimal(allocation["amount"])
        if amount.is_finite() and amount > 0:
            total += amount
            seen.add(line.id)
    return total
