"""
ارسال و استعلام صورتحساب از طریق «معتمد آسا» (ASA TSP API v2).

ASA issues the tax id and the fiscal-memory serial itself, so the Hesabix taxid
in the DTO is not sent. Each Hesabix document is one ASA invoice chain keyed by
its internalId; ASA answers an inquiry with the latest invoice of that chain.

Operations (API v2 docs, sections 05, 07, 08D):
- original sale: POST /api/invoice/send (ins=1); a rejected or unsent invoice
  is edited in place with /api/invoice/editInvoice;
- correction: /api/invoice/editInvoice with confirmCorrection (ASA sets ins=2
  and the reference);
- cancellation: /api/invoice/cancelInvoice on the chain;
- sales return: /send with ins=4 whose Body is the rows remaining after the
  return, per RC_IITP.IS_V7.9 table 1 (pp. 14-18).
"""
from __future__ import annotations

import datetime as dt
import uuid
from decimal import Decimal, InvalidOperation
from typing import Any

from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.tax_setting import TaxSetting
from app.core.responses import ApiError
from app.integrations.moadian.dto import InvoiceDto
from app.integrations.moadian.utils import normalize_invoice_number, round_to_int, timestamp_to_unix_ms
from app.integrations.motamed_asa.client import MotamedAsaApiError, MotamedAsaClient
from app.services.motamed_asa_provider_service import (
    MOTAMED_ASA_PROVIDER,
    motamed_asa_business_call,
)
from app.services.tax_reference_service import resolve_reference_document

# InvoicePhases of API v2 results
_PHASE_AWAITING_SEND = 0
_PHASE_PENDING = 1
_PHASE_SUCCESS = 2
_PHASE_ERROR = 3
_PHASE_NAMES = {"awaitingsend": 0, "pending": 1, "success": 2, "haserror": 3, "proforma": 7}

# InvoiceIssues (Header.ins)
_ISSUE_ORIGINAL = 1
_ISSUE_CORRECTION = 2
_ISSUE_CANCELLATION = 3
_ISSUE_RETURN = 4

_INQUIRY_BATCH = 250
_NOT_FOUND_MARKER = "یافت نشد"
# Spellings of the Article 6 status the tax system and the ASA panel use (MegaPay GetArticle6StatusText).
_ARTICLE6_NOT_VIOLATED = {"NOT_EXCEEDED", "NO_DEVIATION", "NOT_DEVIATED", "NOT_VIOLATED", "NO", "FALSE", "0"}
_ARTICLE6_VIOLATED = {"EXCEEDED", "DEVIATION", "DEVIATED", "VIOLATION", "VIOLATED", "YES", "TRUE", "1"}
_PAYMENT_TYPES = range(1, 9)
_PAYMENT_ROWS_MAX = 50

_HEADER_FIELDS = (
    "indatim", "inty", "inp", "ins", "inno", "tins", "irtaxid", "tob", "bid", "tinb",
    "sbc", "bpc", "bbc", "bpn", "scln", "scc", "crn", "billid", "cdcn", "cdcd",
    "tprdis", "tdis", "tadis", "tvam", "todam", "tbill", "setm", "cap", "insp", "tvop",
)
_BODY_FIELDS = (
    "sstid", "sstt", "mu", "am", "fee", "prdis", "dis", "adis", "vra", "vam", "tsstam",
    "vop", "ssrv", "bsrn", "nw",
)
_PAYMENT_FIELDS = ("iinn", "acn", "trmn", "trn", "pcn", "pid", "pdt", "pmt", "pv")


# --- Identifiers ----------------------------------------------------------------------------


def motamed_asa_internal_id(document: Document) -> str:
    """The ASA internalId of the document's invoice chain; stable across retries."""
    stored = str((document.extra_info or {}).get("asa_internal_id") or "").strip()
    return stored or f"hesabix-{int(document.id)}"


def _cancel_internal_id(internal_id: str) -> str:
    return f"{internal_id}-cancel"


# --- Payload ----------------------------------------------------------------------------------


def build_motamed_asa_invoice(invoice_dto: InvoiceDto, *, document_id: int, subject: int) -> dict[str, Any]:
    """
    The official JSON (Header, Body, Payments) for API v2. Hesabix issues sales of
    pattern 1; its own inp/ins mark the operation, so both are set here.
    """
    payload = invoice_dto.to_dict()
    source_header = payload.get("header") or {}
    header = {key: source_header[key] for key in _HEADER_FIELDS if source_header.get(key) is not None}
    header["inp"] = 1
    header["ins"] = int(subject)
    header["inno"] = normalize_invoice_number(document_id)
    if subject == _ISSUE_ORIGINAL:
        header.pop("irtaxid", None)

    body = [
        {key: row[key] for key in _BODY_FIELDS if row.get(key) is not None}
        for row in payload.get("body") or []
        if isinstance(row, dict)
    ]
    payments: list[dict[str, Any]] = []
    if header.get("inty") == 1:
        for payment in payload.get("payments") or []:
            if not isinstance(payment, dict) or payment.get("pmt") in (None, ""):
                continue
            row = {key: payment[key] for key in _PAYMENT_FIELDS if payment.get(key) not in (None, "")}
            row["pmt"] = int(_decimal(row["pmt"]))
            if "pdt" in row:
                row["pdt"] = _unix_ms(row["pdt"])
            payments.append({key: value for key, value in row.items() if value is not None})
    return {"Header": header, "Body": body, "Payments": payments}


def _unix_ms(value: Any) -> int | None:
    """API v2 takes payment times as Unix milliseconds; Hesabix may keep them as dates."""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) or (isinstance(value, str) and value.strip().isdigit()):
        return int(value)
    if isinstance(value, str):
        try:
            value = dt.datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError:
            # An unreadable payment time is left out rather than replaced by "now".
            return None
    if isinstance(value, (dt.datetime, dt.date)):
        return timestamp_to_unix_ms(value)
    return None


def _lower_keys(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(key).lower(): _lower_keys(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_lower_keys(item) for item in value]
    return value


def _sent_invoice(info: dict[str, Any]) -> dict[str, Any] | None:
    """The invoice JSON the tax organisation accepted, as API v2 returns it in «json»."""
    raw = info.get("json")
    if isinstance(raw, list):
        raw = next((item for item in raw if isinstance(item, dict)), None)
    if not isinstance(raw, dict):
        return None
    invoice = _lower_keys(raw)
    if not isinstance(invoice.get("header"), dict) or not isinstance(invoice.get("body"), list):
        return None
    return invoice


def _decimal(value: Any) -> Decimal:
    try:
        return Decimal(str(value if value not in (None, "") else 0))
    except (InvalidOperation, ValueError):
        return Decimal(0)


def _number(value: Decimal) -> int | float:
    return int(value) if value == value.to_integral_value() else float(value)


def _remaining_row(row: dict[str, Any], quantity: Decimal, discount: Decimal) -> dict[str, Any]:
    fee = _decimal(row.get("fee"))
    vra = _decimal(row.get("vra"))
    prdis = round_to_int(quantity * fee)
    dis = min(max(round_to_int(discount), 0), prdis)
    adis = prdis - dis
    vam = round_to_int(adis * vra / 100) if vra > 0 else 0
    odam = round_to_int(adis * _decimal(row.get("odr")) / 100) if row.get("odr") not in (None, "") else 0
    olam = round_to_int(adis * _decimal(row.get("olr")) / 100) if row.get("olr") not in (None, "") else 0
    remaining = {
        "sstid": str(row.get("sstid") or ""),
        "sstt": row.get("sstt"),
        "mu": row.get("mu"),
        "am": _number(quantity),
        "fee": _number(fee),
        "prdis": prdis,
        "dis": dis,
        "adis": adis,
        "vra": _number(vra),
        "vam": vam,
        "odam": odam,
        "olam": olam,
        "tsstam": adis + vam + odam + olam,
    }
    for key in ("odt", "odr", "olt", "olr", "bsrn"):
        if row.get(key) not in (None, ""):
            remaining[key] = row[key]
    return {key: value for key, value in remaining.items() if value is not None}


def build_motamed_asa_return_invoice(
    invoice_dto: InvoiceDto,
    *,
    document_id: int,
    reference: dict[str, Any],
) -> dict[str, Any]:
    """
    A sales return (ins=4) on the latest registered invoice of the reference chain.
    Its Body is the reference's rows after the return (RC_IITP.IS_V7.9 table 1,
    pp. 14-18): no row is added, a fully returned row is left out, and unit price,
    VAT rate and unit stay the reference's. Hesabix's return lines give the
    returned quantity and discount of each row.
    """
    sent = _sent_invoice(reference)
    reference_tax_id = str(reference.get("taxId") or "").strip()
    if sent is None or not reference_tax_id:
        raise ApiError(
            "MOTAMED_ASA_REFERENCE_UNAVAILABLE",
            "اقلام صورتحساب مرجع از معتمد آسا خوانده نشد؛ برگشت از فروش فقط برای صورتحساب ثبت‌شده در سامانهٔ مؤدیان صادر می‌شود.",
            http_status=409,
        )
    reference_header = sent["header"]
    rows = [dict(row) for row in sent["body"] if isinstance(row, dict)]
    quantities = [_decimal(row.get("am")) for row in rows]
    discounts = [_decimal(row.get("dis")) for row in rows]

    for index, returned in enumerate(invoice_dto.body, start=1):
        returned_quantity = _decimal(returned.am)
        if returned_quantity <= 0:
            continue
        match = next(
            (
                position
                for position, row in enumerate(rows)
                if str(row.get("sstid") or "") == str(returned.sstid or "")
                and quantities[position] >= returned_quantity
            ),
            None,
        )
        if match is None:
            raise ApiError(
                "MOTAMED_ASA_RETURN_ROW_INVALID",
                f"ردیف {index} برگشت («{returned.sstt}») در صورتحساب مرجع نیست یا مقدار برگشتی آن از مقدار باقی‌مانده بیشتر است.",
                http_status=400,
                details={"line_number": index, "sstid": returned.sstid},
            )
        quantities[match] -= returned_quantity
        discounts[match] = max(discounts[match] - _decimal(returned.dis), Decimal(0))

    if all(quantities[position] == _decimal(row.get("am")) for position, row in enumerate(rows)):
        raise ApiError(
            "MOTAMED_ASA_RETURN_NOTHING_RETURNED",
            "در این برگشت از فروش مقدار هیچ ردیفی کم نشده است.",
            http_status=400,
        )
    body = [
        _remaining_row(row, quantities[position], discounts[position])
        for position, row in enumerate(rows)
        if quantities[position] > 0
    ]
    if not body:
        raise ApiError(
            "MOTAMED_ASA_RETURN_NEEDS_CANCELLATION",
            "با این برگشت چیزی از صورتحساب مرجع باقی نمی‌ماند؛ به‌جای برگشت از فروش، صورتحساب مرجع را در سامانهٔ مؤدیان ابطال کنید.",
            http_status=400,
        )

    totals = {
        "tprdis": sum(row["prdis"] for row in body),
        "tdis": sum(row["dis"] for row in body),
        "tadis": sum(row["adis"] for row in body),
        "tvam": sum(row["vam"] for row in body),
        "todam": sum(row["odam"] + row["olam"] for row in body),
    }
    totals["tbill"] = totals["tadis"] + totals["tvam"] + totals["todam"]
    inty = int(_decimal(reference_header.get("inty") or 1))
    header: dict[str, Any] = {
        "indatim": invoice_dto.header.indatim,
        "inty": inty,
        "inp": int(_decimal(reference_header.get("inp") or 1)),
        "ins": _ISSUE_RETURN,
        "inno": normalize_invoice_number(document_id),
        "tins": invoice_dto.header.tins,
        "irtaxid": reference_tax_id,
        **totals,
    }
    if inty == 1:
        setm = int(_decimal(reference_header.get("setm") or 1))
        header["setm"] = setm if setm in (1, 2, 3) else 1
        if header["setm"] == 2:
            header["insp"] = totals["tbill"]
        else:
            header["cap"] = totals["tbill"]
            if header["setm"] == 3:
                header["insp"] = 0
        if totals["tvam"] > 0:
            header["tvop"] = totals["tvam"]
    return {"Header": header, "Body": body, "Payments": []}


# --- Results ----------------------------------------------------------------------------------


def _phase(info: dict[str, Any]) -> int | None:
    value = info.get("status")
    if isinstance(value, str):
        named = _PHASE_NAMES.get(value.strip().lower())
        if named is not None:
            return named
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _issue(info: dict[str, Any]) -> int | None:
    value = info.get("issue")
    if isinstance(value, str):
        named = {"original": 1, "correction": 2, "cancellation": 3, "salesreturn": 4, "return": 4}.get(
            value.strip().lower().replace("_", "")
        )
        if named is not None:
            return named
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _errors(info: dict[str, Any]) -> list[str]:
    raw = info.get("error")
    if isinstance(raw, list):
        return [str(item) for item in raw if item]
    return [str(raw)] if raw else []


def _not_found(info: dict[str, Any] | None) -> bool:
    if not info:
        return True
    return not info.get("asatspId") and any(_NOT_FOUND_MARKER in message for message in _errors(info))


def normalize_article6_status(value: Any) -> str | None:
    """
    «violated» (عدول) or «not_violated» (عدم عدول) for the Article 6 status the
    tax system reports; None when the value is not one of the known spellings,
    so the raw value is shown instead of a guess.
    """
    text = str(value or "").strip()
    if not text:
        return None
    upper = text.upper()
    if upper in _ARTICLE6_NOT_VIOLATED or "عدم" in text:
        return "not_violated"
    if upper in _ARTICLE6_VIOLATED or "عدول" in text:
        return "violated"
    return None


def _hesabix_status(info: dict[str, Any]) -> tuple[str | None, str | None]:
    """(tax_status, error message) in Hesabix's vocabulary for one API v2 result."""
    phase = _phase(info)
    if phase in (_PHASE_AWAITING_SEND, _PHASE_PENDING):
        if phase == _PHASE_AWAITING_SEND and _errors(info):
            return "failed", "؛ ".join(_errors(info))
        return "pending", None
    if phase == _PHASE_SUCCESS:
        # Registered by the tax system; the buyer's reaction is the separate «وضعیت کارپوشه».
        return "finalized", None
    if phase == _PHASE_ERROR:
        return "failed", "؛ ".join(_errors(info)) or "سامانهٔ مؤدیان صورتحساب را نپذیرفت."
    return None, None


def _raw(info: dict[str, Any], *, state: str | None = None) -> dict[str, Any]:
    # The accepted invoice JSON («json») is not kept: it repeats the invoice and buyer data.
    raw = {
        "provider": MOTAMED_ASA_PROVIDER,
        "asatsp_id": info.get("asatspId"),
        "tax_id": info.get("taxId"),
        "status": info.get("status"),
        "issue": info.get("issue"),
        "reference_number": info.get("refrenceNumber"),
        "status_inquiry": info.get("statusInquery"),
        "article6_status": info.get("article6Status"),
        "fiscal_id": info.get("fiscalId"),
        "errors": _errors(info) or None,
    }
    if state:
        raw["state"] = state
    return {key: value for key, value in raw.items() if value not in (None, "")}


def _record(
    db: Session,
    document: Document,
    info: dict[str, Any],
    *,
    mode: str,
    status: str,
    error_message: str | None = None,
    record_tax_id: bool = True,
) -> dict[str, Any]:
    extra = dict(document.extra_info or {})
    asatsp_id = info.get("asatspId")
    if asatsp_id:
        ids = dict(extra.get("asa_invoice_ids_by_mode") or {})
        ids[mode] = int(asatsp_id)
        extra["asa_invoice_ids_by_mode"] = ids
        extra["asa_latest_invoice_id"] = int(asatsp_id)
    if info.get("taxId"):
        tax_ids = dict(extra.get("asa_tax_ids_by_mode") or {})
        tax_ids[mode] = str(info["taxId"])
        extra["asa_tax_ids_by_mode"] = tax_ids
    if info.get("fiscalId"):
        extra["asa_fiscal_id"] = info["fiscalId"]
    document.extra_info = extra
    db.add(document)
    db.flush()
    return {
        "mode": MOTAMED_ASA_PROVIDER,
        "provider": MOTAMED_ASA_PROVIDER,
        "status": status,
        "tracking_code": str(asatsp_id) if asatsp_id else extra.get("tax_tracking_code"),
        "tax_id": str(info["taxId"]) if record_tax_id and info.get("taxId") else None,
        "error_message": error_message,
        "raw_response": _raw(info, state="submitted"),
        "sent_at": dt.datetime.utcnow().isoformat(),
    }


def _rejected(
    response: dict[str, Any],
    item: dict[str, Any] | None = None,
    *,
    code: str = "MOTAMED_ASA_INVOICE_REJECTED",
) -> ApiError:
    messages = _errors(item or {})
    errors = response.get("errors") if isinstance(response.get("errors"), list) else []
    for error in errors:
        if isinstance(error, dict) and error.get("message"):
            text = str(error["message"])
            if text not in messages:
                messages.append(text)
    if not messages and response.get("message"):
        messages.append(str(response["message"]))
    return ApiError(
        code,
        "؛ ".join(messages) or "معتمد آسا درخواست را نپذیرفت.",
        http_status=400,
        details={
            "provider": MOTAMED_ASA_PROVIDER,
            "trace_id": response.get("traceId"),
            "errors": [
                {key: error.get(key) for key in ("code", "path", "field", "message") if error.get(key)}
                for error in errors
                if isinstance(error, dict)
            ],
        },
    )


def _first_item(response: dict[str, Any]) -> dict[str, Any] | None:
    data = response.get("data")
    if isinstance(data, list):
        return next((item for item in data if isinstance(item, dict)), None)
    return None


def _inquire_one(client: MotamedAsaClient, token: str, internal_id: str) -> dict[str, Any] | None:
    items = client.inquire_internal_ids(token, [internal_id])
    info = items[0] if items else None
    return None if _not_found(info) else info


def _duplicate_internal_id(response: dict[str, Any], item: dict[str, Any] | None) -> bool:
    texts = _errors(item or {})
    for error in response.get("errors") or []:
        if isinstance(error, dict):
            texts.append(f"{error.get('path') or ''} {error.get('message') or ''}")
    return any("internalId" in text and "قبلاً" in text for text in texts)


def _description(document: Document) -> str | None:
    text = str(document.description or "").strip()
    return text[:1000] or None


# --- Sending ----------------------------------------------------------------------------------


def _send_or_update(
    db: Session,
    client: MotamedAsaClient,
    token: str,
    document: Document,
    internal_id: str,
    data: dict[str, Any],
    *,
    mode: str,
    fiscal_id: str | None,
) -> dict[str, Any]:
    current = _inquire_one(client, token, internal_id)
    if current is not None:
        status, _ = _hesabix_status(current)
        if status in ("pending", "finalized"):
            return _record(db, document, current, mode=mode, status=status)
        # Rejected or never sent: a new version of the same invoice (same serial) is sent.
        response = client.edit_invoice(
            token,
            {
                "uuid": str(uuid.uuid4()),
                "internalId": internal_id,
                "send": True,
                "confirmCorrection": False,
                "description": _description(document),
                "data": data,
            },
        )
        outcome = str((response.get("edit") or {}).get("outcome") or "")
        if outcome == "unchanged":
            queued = client.queue_invoices(token, [internal_id])
            if queued.get("result") != 1:
                raise _rejected(queued)
            return _record(db, document, current, mode=mode, status="pending")
        if response.get("result") == 1 and outcome in ("draftUpdated", "paymentUpdated", "correctionIssued"):
            return _record(db, document, _first_item(response) or current, mode=mode, status="pending")
        raise _rejected(response, _first_item(response))

    item_request: dict[str, Any] = {
        "internalId": internal_id,
        "send": True,
        "description": _description(document),
        "data": data,
    }
    if fiscal_id:
        item_request["fiscalId"] = fiscal_id
    try:
        response = client.send_invoices(
            token,
            {"uuid": str(uuid.uuid4()), "data": [{k: v for k, v in item_request.items() if v is not None}]},
        )
    except MotamedAsaApiError as exc:
        if not exc.is_transient:
            raise
        # The save may have committed remotely; the internalId finds it without a second save.
        found = _inquire_one(client, token, internal_id)
        if found is None:
            raise
        status, error = _hesabix_status(found)
        return _record(db, document, found, mode=mode, status=status or "pending", error_message=error)

    item = _first_item(response)
    if item is not None and item.get("asatspId") and _phase(item) != _PHASE_ERROR:
        return _record(db, document, item, mode=mode, status="pending")
    if _duplicate_internal_id(response, item):
        found = _inquire_one(client, token, internal_id)
        if found is not None:
            status, error = _hesabix_status(found)
            return _record(db, document, found, mode=mode, status=status or "pending", error_message=error)
    raise _rejected(response, item)


def _correct(
    db: Session,
    client: MotamedAsaClient,
    token: str,
    document: Document,
    internal_id: str,
    data: dict[str, Any],
) -> dict[str, Any]:
    request_uuid = str(uuid.uuid4())
    try:
        response = client.edit_invoice(
            token,
            {
                "uuid": request_uuid,
                "internalId": internal_id,
                "send": True,
                # The user asked for the correction in Hesabix; ASA must not wait for a second confirmation.
                "confirmCorrection": True,
                "description": _description(document),
                "data": data,
            },
        )
    except MotamedAsaApiError as exc:
        if not exc.is_transient:
            raise
        latest = _inquire_one(client, token, internal_id)
        if latest is not None and _issue(latest) == _ISSUE_CORRECTION:
            return _record(db, document, latest, mode="corrective", status="pending")
        raise
    edit = response.get("edit") or {}
    outcome = str(edit.get("outcome") or "")
    if outcome == "unchanged":
        raise ApiError(
            "MOTAMED_ASA_NOTHING_TO_CORRECT",
            "این صورتحساب با نسخهٔ ثبت‌شده در سامانهٔ مؤدیان فرقی ندارد؛ صورتحساب اصلاحی صادر نشد.",
            http_status=409,
        )
    if response.get("result") == 1 and outcome in ("correctionIssued", "draftUpdated", "paymentUpdated"):
        item = dict(_first_item(response) or {})
        if edit.get("taxId") and not item.get("taxId"):
            item["taxId"] = edit["taxId"]
        return _record(db, document, item, mode="corrective", status="pending")
    raise _rejected(response, _first_item(response))


def _cancel(
    db: Session,
    client: MotamedAsaClient,
    token: str,
    document: Document,
    internal_id: str,
) -> dict[str, Any]:
    cancel_id = _cancel_internal_id(internal_id)
    existing = _inquire_one(client, token, cancel_id)
    if existing is not None and _issue(existing) == _ISSUE_CANCELLATION:
        status, error = _hesabix_status(existing)
        return _record(db, document, existing, mode="cancel", status=status or "pending",
                       error_message=error, record_tax_id=False)
    body = {
        "uuid": str(uuid.uuid4()),
        "internalId": internal_id,
        "cancelInternalId": cancel_id,
        "send": True,
        "description": _description(document),
    }
    try:
        response = client.cancel_invoice(token, {k: v for k, v in body.items() if v is not None})
    except MotamedAsaApiError as exc:
        if not exc.is_transient:
            raise
        found = _inquire_one(client, token, cancel_id)
        if found is None:
            raise
        return _record(db, document, found, mode="cancel", status="pending", record_tax_id=False)
    if response.get("result") == -2:
        found = _inquire_one(client, token, cancel_id)
        if found is not None:
            status, error = _hesabix_status(found)
            return _record(db, document, found, mode="cancel", status=status or "pending",
                           error_message=error, record_tax_id=False)
    item = _first_item(response)
    if response.get("result") == 1 and item is not None and item.get("asatspId"):
        return _record(db, document, item, mode="cancel", status="pending", record_tax_id=False)
    raise _rejected(response, item)


def _return_reference(
    db: Session,
    client: MotamedAsaClient,
    token: str,
    document: Document,
) -> dict[str, Any]:
    reference = resolve_reference_document(db, int(document.business_id), document)
    if reference is None:
        raise ApiError(
            "TAX_REFERENCE_INVOICE_MISSING",
            "برای برگشت از فروش، فاکتور مرجع (فروش اصلی) باید مشخص شود.",
            http_status=400,
        )
    reference_extra = reference.extra_info or {}
    if reference_extra.get("tax_submission_provider") != MOTAMED_ASA_PROVIDER:
        raise ApiError(
            "MOTAMED_ASA_REFERENCE_OTHER_PROVIDER",
            "فاکتور مرجع از طریق معتمد آسا ارسال نشده است؛ برگشت آن را از همان روشی بفرستید که فاکتور مرجع با آن ارسال شده است.",
            http_status=409,
        )
    latest = _inquire_one(client, token, motamed_asa_internal_id(reference))
    if latest is None or _phase(latest) != _PHASE_SUCCESS:
        raise ApiError(
            "MOTAMED_ASA_REFERENCE_NOT_REGISTERED",
            "آخرین صورتحساب زنجیرهٔ فاکتور مرجع هنوز در سامانهٔ مؤدیان ثبت نشده است؛ پس از ثبت آن، برگشت از فروش را بفرستید.",
            http_status=409,
        )
    return latest


def send_document_via_motamed_asa(
    db: Session,
    document: Document,
    tax_setting: TaxSetting,
    invoice_dto: InvoiceDto,
    *,
    submission_mode: str,
) -> dict[str, Any]:
    business_id = int(document.business_id)
    internal_id = motamed_asa_internal_id(document)
    extra = dict(document.extra_info or {})
    extra["tax_submission_provider"] = MOTAMED_ASA_PROVIDER
    extra["asa_internal_id"] = internal_id
    extra["tax_provider_operation"] = submission_mode
    document.extra_info = extra
    db.add(document)
    db.flush()

    def operation(client: MotamedAsaClient, token: str, account: Any) -> dict[str, Any]:
        if submission_mode == "cancel":
            return _cancel(db, client, token, document, internal_id)
        if submission_mode == "corrective":
            data = build_motamed_asa_invoice(invoice_dto, document_id=int(document.id), subject=_ISSUE_CORRECTION)
            return _correct(db, client, token, document, internal_id, data)
        if submission_mode == "return":
            data = build_motamed_asa_return_invoice(
                invoice_dto,
                document_id=int(document.id),
                reference=_return_reference(db, client, token, document),
            )
        else:
            data = build_motamed_asa_invoice(invoice_dto, document_id=int(document.id), subject=_ISSUE_ORIGINAL)
        fiscal_id = str(account.memory_number or "").strip() or None
        return _send_or_update(db, client, token, document, internal_id, data, mode=submission_mode, fiscal_id=fiscal_id)

    try:
        return motamed_asa_business_call(db, business_id, operation)
    except MotamedAsaApiError as exc:
        if exc.is_transient:
            raise ApiError(
                "MOTAMED_ASA_RESULT_UNKNOWN",
                "نتیجهٔ عملیات معتمد آسا نامشخص است؛ وضعیت آن را استعلام کنید و تا روشن شدن نتیجه دوباره نفرستید.",
                http_status=502,
                details={"provider": MOTAMED_ASA_PROVIDER, "operation": submission_mode},
            ) from exc
        raise ApiError(
            "MOTAMED_ASA_SUBMISSION_FAILED",
            str(exc),
            http_status=exc.status_code if exc.status_code and 400 <= exc.status_code < 500 else 400,
            details={"provider": MOTAMED_ASA_PROVIDER, "code": exc.code},
        ) from exc


# --- Inquiry ----------------------------------------------------------------------------------


def _inquiry_key(document: Document) -> str:
    extra = document.extra_info or {}
    internal_id = motamed_asa_internal_id(document)
    if extra.get("tax_last_submission_mode") == "cancel" or extra.get("tax_provider_operation") == "cancel":
        return _cancel_internal_id(internal_id)
    return internal_id


def _document_result(document: Document, info: dict[str, Any] | None) -> dict[str, Any]:
    """
    The document's state from the latest invoice of its chain. A later invoice in
    the chain (a correction, return or cancellation registered afterwards) means
    the document's own invoice was registered by the tax organisation.
    """
    extra = document.extra_info or {}
    mode = str(extra.get("tax_last_submission_mode") or extra.get("tax_provider_operation") or "normal")
    updates: dict[str, Any] = {}
    if info is None or _not_found(info):
        return {"status": "unknown", "error_message": None, "raw": None, "updates": updates}
    issue = _issue(info)
    own_issue = {"normal": _ISSUE_ORIGINAL, "corrective": _ISSUE_CORRECTION, "return": _ISSUE_RETURN,
                 "cancel": _ISSUE_CANCELLATION}.get(mode, _ISSUE_ORIGINAL)
    own_tax_id = (extra.get("asa_tax_ids_by_mode") or {}).get(mode)
    is_own = issue == own_issue and (mode != "return" or not own_tax_id or own_tax_id == info.get("taxId"))

    if is_own:
        status, error = _hesabix_status(info)
        if mode == "cancel" and status == "finalized":
            updates["tax_cancelled_in_modian"] = True
        elif mode in ("normal", "corrective", "return") and info.get("taxId"):
            updates["tax_moadian_taxid"] = str(info["taxId"])
        # The کارپوشه status and Article 6 status describe this invoice only, not a later one of its chain.
        if info.get("statusInquery"):
            updates["tax_provider_invoice_status"] = str(info["statusInquery"])
        if info.get("article6Status"):
            updates["tax_article6_status"] = normalize_article6_status(info["article6Status"]) or str(info["article6Status"])
    else:
        status, error = "finalized", None
        if issue == _ISSUE_CANCELLATION and _phase(info) == _PHASE_SUCCESS and mode != "return":
            updates["tax_cancelled_in_modian"] = True
    return {"status": status, "error_message": error, "raw": _raw(info), "updates": updates}


def motamed_asa_inquire_documents(
    db: Session,
    business_id: int,
    documents: list[Document],
) -> list[tuple[Document, dict[str, Any]]]:
    """Latest API v2 state of each document, read in batches of 250 internalIds."""
    keys = [_inquiry_key(document) for document in documents]

    def operation(client: MotamedAsaClient, token: str, _account: Any) -> list[dict[str, Any]]:
        answers: list[dict[str, Any]] = []
        for start in range(0, len(keys), _INQUIRY_BATCH):
            answers.extend(client.inquire_internal_ids(token, keys[start:start + _INQUIRY_BATCH]))
        return answers

    try:
        answers = motamed_asa_business_call(db, business_id, operation)
    except MotamedAsaApiError as exc:
        raise ApiError("MOTAMED_ASA_STATUS_INQUIRY_FAILED", str(exc), http_status=502 if exc.is_transient else 400) from exc
    return [(document, _document_result(document, info)) for document, info in zip(documents, answers)]


# --- Payments registered in the کارپوشه (API v2 docs, section 08C) ------------------------------


def _payments_internal_id(document: Document) -> str:
    extra = document.extra_info or {}
    if extra.get("tax_submission_provider") != MOTAMED_ASA_PROVIDER or not extra.get("asa_internal_id"):
        raise ApiError(
            "MOTAMED_ASA_PAYMENTS_NOT_APPLICABLE",
            "ثبت پرداخت در کارپوشه فقط برای صورت‌حساب‌هایی است که از طریق معتمد آسا ارسال شده‌اند.",
            http_status=409,
        )
    return str(extra["asa_internal_id"])


def _payment_view(row: dict[str, Any]) -> dict[str, Any]:
    registration = row.get("registration") if isinstance(row.get("registration"), dict) else {}
    return {
        "id": row.get("id"),
        "type": row.get("type"),
        "date_time": row.get("dateTime"),
        "timestamp": row.get("timestamp"),
        "price": row.get("price"),
        "trace_no": row.get("traceNo"),
        "terminal_number": row.get("terminalNumber"),
        "description": row.get("description"),
        "locked": row.get("locked") is True,
        "registration_status": registration.get("status"),
        "registration_code": registration.get("code"),
        "registration_message": registration.get("message"),
        "registered_amount": registration.get("registeredAmount"),
        "registered_at": registration.get("registeredAt"),
    }


def _payments_view(response: dict[str, Any]) -> dict[str, Any]:
    info = _first_item(response) or {}
    eligibility = info.get("paymentRegistration") if isinstance(info.get("paymentRegistration"), dict) else {}
    rows = info.get("payments") if isinstance(info.get("payments"), list) else []
    return {
        "tax_id": info.get("taxId"),
        "eligible": eligibility.get("eligible") is True,
        "rows_locked": eligibility.get("rowsLocked") is True,
        "reason_code": eligibility.get("code"),
        "reason": eligibility.get("reason"),
        "payments": [_payment_view(row) for row in rows if isinstance(row, dict)],
    }


def _digits(value: Any, *, field: str, label: str, max_length: int, index: int) -> str | None:
    text = str(value or "").strip().translate(str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789"))
    if not text:
        return None
    if not text.isdigit() or len(text) > max_length:
        raise ApiError(
            "MOTAMED_ASA_PAYMENT_INVALID",
            f"ردیف {index}: {label} فقط رقم و حداکثر {max_length} رقم است.",
            http_status=400,
            details={"row": index, "field": field},
        )
    return text


def build_motamed_asa_payment_rows(payments: Any) -> list[dict[str, Any]]:
    """The registerPayment rows for the payments entered in Hesabix; each row is checked before sending."""
    if not isinstance(payments, list) or not 1 <= len(payments) <= _PAYMENT_ROWS_MAX:
        raise ApiError(
            "MOTAMED_ASA_PAYMENT_INVALID",
            f"بین ۱ تا {_PAYMENT_ROWS_MAX} ردیف پرداخت بفرستید.",
            http_status=400,
        )
    rows: list[dict[str, Any]] = []
    for index, payment in enumerate(payments, start=1):
        if not isinstance(payment, dict):
            raise ApiError("MOTAMED_ASA_PAYMENT_INVALID", f"ردیف {index} پرداخت معتبر نیست.", http_status=400)
        try:
            payment_type = int(payment.get("type"))
        except (TypeError, ValueError):
            payment_type = 0
        if payment_type not in _PAYMENT_TYPES:
            raise ApiError(
                "MOTAMED_ASA_PAYMENT_INVALID", f"ردیف {index}: روش پرداخت را انتخاب کنید.",
                http_status=400, details={"row": index, "field": "type"},
            )
        timestamp = _unix_ms(payment.get("timestamp"))
        if not timestamp or timestamp <= 0:
            raise ApiError(
                "MOTAMED_ASA_PAYMENT_INVALID", f"ردیف {index}: تاریخ و زمان پرداخت را وارد کنید.",
                http_status=400, details={"row": index, "field": "timestamp"},
            )
        price = _decimal(payment.get("price"))
        if price <= 0 or price != price.to_integral_value() or len(str(int(price))) > 18:
            raise ApiError(
                "MOTAMED_ASA_PAYMENT_INVALID", f"ردیف {index}: مبلغ پرداخت باید عدد ریالی صحیح و بزرگ‌تر از صفر باشد.",
                http_status=400, details={"row": index, "field": "price"},
            )
        row: dict[str, Any] = {
            "type": payment_type,
            "dateTime": str(timestamp),
            "price": int(price),
            "traceNo": _digits(payment.get("trace_no"), field="trace_no", label="شماره پیگیری", max_length=14, index=index),
            "terminalNumber": _digits(
                payment.get("terminal_number"), field="terminal_number", label="شماره پایانه", max_length=8, index=index
            ),
            "description": str(payment.get("description") or "").strip()[:500] or None,
        }
        rows.append({key: value for key, value in row.items() if value is not None})
    return rows


def motamed_asa_invoice_payments(db: Session, business_id: int, document: Document) -> dict[str, Any]:
    """Every payment row of the invoice at ASA with its registration status in the کارپوشه."""
    internal_id = _payments_internal_id(document)
    try:
        response = motamed_asa_business_call(
            db, business_id, lambda client, token, _account: client.inquire_payments(token, internal_id)
        )
    except MotamedAsaApiError as exc:
        raise ApiError("MOTAMED_ASA_PAYMENTS_UNAVAILABLE", str(exc), http_status=502 if exc.is_transient else 400) from exc
    if response.get("result") != 1:
        raise _rejected(response, code="MOTAMED_ASA_PAYMENTS_UNAVAILABLE")
    return _payments_view(response)


def register_motamed_asa_payments(
    db: Session,
    business_id: int,
    document: Document,
    payments: Any,
) -> dict[str, Any]:
    """
    Adds payment rows to a sent invoice and registers them in the کارپوشه
    (registerPayment). Rows already held by the tax system cannot be changed;
    a lost answer is never re-sent blindly: the rows are read back instead.
    """
    internal_id = _payments_internal_id(document)
    rows = build_motamed_asa_payment_rows(payments)
    request = {"uuid": str(uuid.uuid4()), "internalId": internal_id, "payments": rows}

    def operation(client: MotamedAsaClient, token: str, _account: Any) -> dict[str, Any]:
        try:
            return client.register_payments(token, request)
        except MotamedAsaApiError as exc:
            if not exc.is_transient:
                raise
            # The request may have been saved: show the rows as ASA holds them now.
            answer = client.inquire_payments(token, internal_id)
            answer["_state"] = "result_unknown"
            return answer

    try:
        response = motamed_asa_business_call(db, business_id, operation)
    except MotamedAsaApiError as exc:
        raise ApiError("MOTAMED_ASA_PAYMENTS_UNAVAILABLE", str(exc), http_status=502 if exc.is_transient else 400) from exc
    if response.get("result") != 1:
        raise _rejected(response, code="MOTAMED_ASA_PAYMENT_REJECTED")
    view = _payments_view(response)
    view["result_unknown"] = response.get("_state") == "result_unknown"
    extra = dict(document.extra_info or {})
    extra["tax_payments_registered_at"] = dt.datetime.utcnow().isoformat()
    document.extra_info = extra
    db.add(document)
    return view
