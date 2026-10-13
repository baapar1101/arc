from __future__ import annotations

import datetime as dt
import logging
from typing import Any
from zoneinfo import ZoneInfo

import jdatetime
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.tax_provider import BusinessTaxProviderAccount, TaxProviderCredential
from adapters.db.models.tax_setting import TaxSetting
from app.core.responses import ApiError
from app.integrations.fanava.client import FanavaApiError, FanavaClient
from app.integrations.moadian.dto import InvoiceDto
from app.services.tax_reference_service import resolve_reference_document
from app.services.tax_provider_service import (
    FANAVA_PROVIDER,
    _ensure_business_token,
    call_as_business,
    get_fanava_client_for_business,
)

logger = logging.getLogger(__name__)
_TEHRAN = ZoneInfo("Asia/Tehran")


def _jalali_datetime_from_timestamp(value: Any) -> str | None:
    if value in (None, ""):
        return None
    try:
        instant = dt.datetime.fromtimestamp(int(value) / 1000, tz=dt.timezone.utc).astimezone(_TEHRAN)
        return jdatetime.datetime.fromgregorian(datetime=instant.replace(tzinfo=None)).strftime("%Y/%m/%d %H:%M")
    except (TypeError, ValueError, OverflowError):
        return None


def _jalali_now() -> str:
    return jdatetime.datetime.fromgregorian(datetime=dt.datetime.now(_TEHRAN).replace(tzinfo=None)).strftime("%Y/%m/%d %H:%M")


def build_fanava_invoice_payload(
    invoice_dto: InvoiceDto,
    *,
    document: Document,
    tax_setting: TaxSetting,
    account: BusinessTaxProviderAccount,
    remote_invoice_id: int | None = None,
    reference_remote_id: int | None = None,
) -> dict[str, Any]:
    detail = invoice_dto.to_dict()
    # Fanava's service DTO differs from the organization's Moadian wire DTO:
    # coded fields are strings and its date fields are Solar Hijri strings.
    if detail.get("extension") is None:
        detail.pop("extension", None)
    header = detail.get("header") or {}
    issue_time = _jalali_datetime_from_timestamp(header.get("indatim"))
    for key in ("indatim", "indati2m"):
        converted = _jalali_datetime_from_timestamp(header.get(key))
        if converted:
            header[key] = converted
    payments = []
    for payment in detail.get("payments") or []:
        if isinstance(payment, dict):
            converted = _jalali_datetime_from_timestamp(payment.get("pdt"))
            if converted:
                payment["pdt"] = converted
            if payment.get("pmt") is not None:
                payment["pmt"] = str(payment["pmt"])
            payments.append({key: value for key, value in payment.items() if value is not None})
        else:
            payments.append(payment)
    detail["payments"] = payments

    for field in ("inty", "inp", "ins", "tob", "ft", "setm"):
        if header.get(field) is not None:
            header[field] = str(header[field])

    try:
        subject_code = int(invoice_dto.header.ins)
    except (TypeError, ValueError):
        subject_code = 1
    subject = {
        1: "ORIGINAL",
        2: "REVISED",
        3: "CANCEL",
        4: "SALES_RETURNED",
    }.get(subject_code, "ORIGINAL")

    payload: dict[str, Any] = {
        "cartableId": int(account.cartable_id),
        "memoryId": int(account.memory_id),
        "memoryNumber": account.memory_number or tax_setting.tax_memory_id,
        "status": "SAVE",
        "issueDateTime": issue_time or _jalali_now(),
        "createDateTime": _jalali_now(),
        "invoiceDetail": detail,
        "taxId": header.get("taxid"),
        "inputType": "API",
        "sellerEconomicCode": tax_setting.economic_code,
        "buyerEconomicCode": header.get("tinb"),
        "invoiceNumber": header.get("inno"),
        "pattern": int(invoice_dto.header.inp),
        "type": int(invoice_dto.header.inty),
        "subject": subject,
        "referenceInvoice": bool(reference_remote_id or header.get("irtaxid")),
        "referenceInvoiceId": reference_remote_id or (document.extra_info or {}).get("fanava_reference_invoice_id"),
        "description": document.description,
        "dateValid": True,
    }
    if remote_invoice_id is not None:
        payload["id"] = int(remote_invoice_id)
    return {key: value for key, value in payload.items() if value is not None}


def _normalize_status(raw_status: Any) -> str:
    status = str(raw_status or "").strip().upper()
    if status in {"SAVE", "EDITED", "NOT_FOUND"}:
        return "not_sent" if status in {"SAVE", "EDITED"} else "unknown"
    if status in {"SEND_QUEUE", "CHECK_QUEUE", "IN_PROGRESS", "IS_PENDING"}:
        return "pending"
    if status == "SUCCESS":
        return "sent"
    if status in {"FAILED", "ERROR_BUSINESS"}:
        return "failed"
    return "unknown"


def _latest_history(history: list[dict[str, Any]]) -> dict[str, Any]:
    return history[-1] if history else {}


def _find_existing_invoice(client: FanavaClient, token: str, account: BusinessTaxProviderAccount, tax_id: str) -> dict[str, Any] | None:
    # The API has no documented taxId filter. A just-created item is at the top of the newest-first list.
    for page in range(3):
        result = client.list_invoices(token, int(account.cartable_id), page=page, size=50)
        items = result.get("data") if isinstance(result.get("data"), list) else []
        for item in items:
            if isinstance(item, dict) and str(item.get("taxId") or "") == tax_id:
                return item
        if len(items) < 50:
            break
    return None


def _status_for_remote(client: FanavaClient, token: str, account: BusinessTaxProviderAccount, invoice_id: int) -> tuple[str, dict[str, Any]]:
    history = client.check_status(token, int(account.cartable_id), invoice_id)
    latest = _latest_history(history)
    if latest.get("status"):
        return _normalize_status(latest.get("status")), latest
    try:
        remote = client.get_invoice(token, int(account.cartable_id), invoice_id)
        data = FanavaClient.unwrap_data(remote)
        if isinstance(data, dict):
            return _normalize_status(data.get("status")), data
    except FanavaApiError:
        pass
    return "unknown", latest


def _safe_result(invoice_id: int, tax_id: str, status: str, details: dict[str, Any] | None = None) -> dict[str, Any]:
    details = details or {}
    return {
        "mode": FANAVA_PROVIDER,
        "status": status,
        "tracking_code": str(invoice_id),
        "fanava_invoice_id": int(invoice_id),
        "tax_id": tax_id,
        "raw_response": {
            "provider": FANAVA_PROVIDER,
            "invoice_id": int(invoice_id),
            "tax_id": tax_id,
            "status": details.get("status"),
            "messages": details.get("messages") or details.get("serverMessages"),
            "error_codes": details.get("messageErrorCodes"),
        },
        "sent_at": dt.datetime.utcnow().isoformat(),
    }


def send_document_via_fanava(
    db: Session,
    document: Document,
    tax_setting: TaxSetting,
    invoice_dto: InvoiceDto,
    *,
    submission_mode: str,
) -> dict[str, Any]:
    client, account, credential = get_fanava_client_for_business(db, int(document.business_id))
    extra = dict(document.extra_info or {})
    extra["tax_submission_provider"] = FANAVA_PROVIDER
    extra["tax_provider_operation"] = submission_mode
    tax_id = str(invoice_dto.header.taxid)
    extra["tax_moadian_taxid"] = tax_id
    document.extra_info = extra
    db.add(document)
    db.flush()
    invoice_ids_by_mode = dict(extra.get("fanava_invoice_ids_by_mode") or {})
    remote_id_raw = invoice_ids_by_mode.get(submission_mode)
    if remote_id_raw in (None, "") and submission_mode == "normal":
        remote_id_raw = extra.get("fanava_invoice_id")
    reference_remote_id = None
    if submission_mode in {"cancel", "corrective"}:
        reference_remote_id = extra.get("fanava_invoice_id")
    else:
        ref_doc = resolve_reference_document(db, int(document.business_id), document)
        if ref_doc:
            reference_remote_id = (ref_doc.extra_info or {}).get("fanava_invoice_id")
    try:
        token = _ensure_business_token(db, client, account, credential)
        remote_id = int(remote_id_raw) if remote_id_raw not in (None, "") else None
        existing: dict[str, Any] | None = None
        if remote_id is None:
            existing = _find_existing_invoice(client, token, account, tax_id)
            if existing and existing.get("id"):
                remote_id = int(existing["id"])
                if submission_mode == "normal":
                    extra["fanava_invoice_id"] = remote_id
                document.extra_info = extra
                db.add(document)
                db.flush()

        if remote_id is not None:
            extra["fanava_latest_invoice_id"] = int(remote_id)
            invoice_ids_by_mode[submission_mode] = int(remote_id)
            extra["fanava_invoice_ids_by_mode"] = invoice_ids_by_mode
            document.extra_info = extra
            db.add(document)
            db.flush()
            status, last_status = _status_for_remote(client, token, account, remote_id)
            if status in {"pending", "sent"}:
                return _safe_result(remote_id, tax_id, status, last_status)
            # Existing saved/edited drafts are updated in place before sending.
            payload = build_fanava_invoice_payload(
                invoice_dto, document=document, tax_setting=tax_setting,
                account=account, remote_invoice_id=remote_id,
                reference_remote_id=int(reference_remote_id) if reference_remote_id else None,
            )
            try:
                call_as_business(db, client, account, credential, lambda fresh: client.save_invoice(fresh, payload))
            except FanavaApiError as exc:
                if exc.code not in {"TIMEOUT", "NETWORK_ERROR"} and (exc.status_code or 0) < 500:
                    raise
                extra["tax_status"] = "pending"
                extra["tax_provider_state"] = "save_result_unknown"
                extra["tax_error_message"] = "نتیجهٔ به‌روزرسانی صورتحساب در فن‌آوا نامشخص است؛ پیش از ارسال، وضعیت را استعلام کنید."
                document.extra_info = extra
                db.add(document)
                db.flush()
                return {
                    "mode": FANAVA_PROVIDER,
                    "status": "pending",
                    "tracking_code": str(remote_id),
                    "fanava_invoice_id": int(remote_id),
                    "tax_id": tax_id,
                    "error_message": extra["tax_error_message"],
                    "raw_response": {"provider": FANAVA_PROVIDER, "invoice_id": int(remote_id), "state": "save_result_unknown"},
                    "sent_at": dt.datetime.utcnow().isoformat(),
                }
        else:
            payload = build_fanava_invoice_payload(
                invoice_dto, document=document, tax_setting=tax_setting, account=account,
                reference_remote_id=int(reference_remote_id) if reference_remote_id else None,
            )
            try:
                remote_id = call_as_business(db, client, account, credential, lambda fresh: client.save_invoice(fresh, payload))
            except FanavaApiError as exc:
                # A save timeout can have committed remotely. Reconcile by deterministic taxId; never repeat the POST blindly.
                if exc.code not in {"TIMEOUT", "NETWORK_ERROR"} and (exc.status_code or 0) < 500:
                    raise
                fresh = _ensure_business_token(db, client, account, credential)
                existing = _find_existing_invoice(client, fresh, account, tax_id)
                if existing and existing.get("id"):
                    remote_id = int(existing["id"])
                else:
                    extra["tax_status"] = "pending"
                    extra["tax_provider_state"] = "save_result_unknown"
                    extra["tax_moadian_taxid"] = tax_id
                    extra["tax_error_message"] = "وضعیت ثبت صورتحساب در فن‌آوا نامشخص است؛ استعلام را اجرا کنید و از ثبت مجدد خودداری کنید."
                    document.extra_info = extra
                    db.add(document)
                    db.flush()
                    return {
                        "mode": FANAVA_PROVIDER,
                        "status": "pending",
                        "tracking_code": None,
                        "tax_id": tax_id,
                        "error_message": extra["tax_error_message"],
                        "raw_response": {"provider": FANAVA_PROVIDER, "state": "save_result_unknown"},
                        "sent_at": dt.datetime.utcnow().isoformat(),
                    }

        if not remote_id:
            raise FanavaApiError("شناسه صورتحساب فن‌آوا دریافت نشد.", code="INVOICE_ID_MISSING")
        if submission_mode == "normal":
            extra["fanava_invoice_id"] = int(remote_id)
        invoice_ids_by_mode[submission_mode] = int(remote_id)
        extra["fanava_invoice_ids_by_mode"] = invoice_ids_by_mode
        extra["fanava_latest_invoice_id"] = int(remote_id)
        extra["tax_submission_provider"] = FANAVA_PROVIDER
        extra["tax_provider_state"] = "saved"
        extra["tax_moadian_taxid"] = tax_id
        document.extra_info = extra
        db.add(document)
        db.flush()

        try:
            call_as_business(
                db, client, account, credential,
                lambda fresh: client.send_invoice(fresh, int(account.cartable_id), int(remote_id)),
            )
        except FanavaApiError as exc:
            if exc.code not in {"TIMEOUT", "NETWORK_ERROR"} and (exc.status_code or 0) < 500:
                raise
            # Check the existing remote invoice before reporting an ambiguous send.
            token = _ensure_business_token(db, client, account, credential)
            try:
                status, last_status = _status_for_remote(client, token, account, int(remote_id))
            except FanavaApiError:
                status, last_status = "unknown", {}
            if status in {"pending", "sent", "failed"}:
                result = _safe_result(int(remote_id), tax_id, status, last_status)
                result["error_message"] = None
                return result
            extra["tax_status"] = "pending"
            extra["tax_provider_state"] = "send_result_unknown"
            extra["tax_error_message"] = "فن‌آوا هنوز نتیجهٔ ارسال را روشن نکرده؛ پیش از تلاش دوباره وضعیت را استعلام کنید."
            document.extra_info = extra
            db.add(document)
            db.flush()
            return {
                "mode": FANAVA_PROVIDER,
                "status": "pending",
                "tracking_code": str(remote_id),
                "fanava_invoice_id": int(remote_id),
                "tax_id": tax_id,
                "error_message": extra["tax_error_message"],
                "raw_response": {"provider": FANAVA_PROVIDER, "invoice_id": int(remote_id), "state": "send_result_unknown"},
                "sent_at": dt.datetime.utcnow().isoformat(),
            }

        token = _ensure_business_token(db, client, account, credential)
        try:
            status, last_status = _status_for_remote(client, token, account, int(remote_id))
        except FanavaApiError as exc:
            logger.warning("Fanava status check failed for document %s: %s", document.id, exc.code or exc.status_code)
            status, last_status = "pending", {}
        if status == "unknown" or status == "not_sent":
            status = "pending"
        result = _safe_result(int(remote_id), tax_id, status, last_status)
        result["raw_response"]["state"] = "submitted"
        return result
    except FanavaApiError as exc:
        if exc.code in {"TIMEOUT", "NETWORK_ERROR"} or (exc.status_code or 0) >= 500:
            raise ApiError(
                "FANAVA_RESULT_UNKNOWN",
                "نتیجهٔ عملیات فن‌آوا نامشخص است؛ وضعیت آن باید استعلام شود و ارسال خودکار تکرار نخواهد شد.",
                http_status=502,
                details={"provider": FANAVA_PROVIDER, "operation": submission_mode},
            ) from exc
        raise ApiError("FANAVA_SUBMISSION_FAILED", str(exc), http_status=exc.status_code or 400) from exc
    finally:
        client.close()


def fanava_status_for_document(db: Session, business_id: int, document: Document) -> dict[str, Any]:
    extra = document.extra_info or {}
    invoice_id = extra.get("fanava_latest_invoice_id") or extra.get("fanava_invoice_id")
    client, account, credential = get_fanava_client_for_business(db, business_id)
    try:
        token = _ensure_business_token(db, client, account, credential)
        if not invoice_id and extra.get("tax_moadian_taxid"):
            existing = _find_existing_invoice(
                client, token, account, str(extra["tax_moadian_taxid"])
            )
            if existing and existing.get("id"):
                invoice_id = int(existing["id"])
                extra = dict(extra)
                operation = str(extra.get("tax_provider_operation") or "normal")
                ids_by_mode = dict(extra.get("fanava_invoice_ids_by_mode") or {})
                ids_by_mode[operation] = invoice_id
                extra["fanava_invoice_ids_by_mode"] = ids_by_mode
                if operation == "normal":
                    extra["fanava_invoice_id"] = invoice_id
                extra["fanava_latest_invoice_id"] = invoice_id
                document.extra_info = extra
                db.add(document)
                db.flush()
        if not invoice_id:
            raise ApiError("FANAVA_INVOICE_ID_MISSING", "شناسهٔ صورتحساب فن‌آوا برای این سند ثبت نشده است.", http_status=404)
        return call_as_business(
            db, client, account, credential,
            lambda token: _status_and_inquiry(client, token, account, int(invoice_id)),
        )
    except FanavaApiError as exc:
        raise ApiError("FANAVA_STATUS_INQUIRY_FAILED", str(exc), http_status=exc.status_code or 502) from exc
    finally:
        client.close()


def _status_and_inquiry(client: FanavaClient, token: str, account: BusinessTaxProviderAccount, invoice_id: int) -> dict[str, Any]:
    history = client.check_status(token, int(account.cartable_id), invoice_id)
    latest = _latest_history(history)
    mapped = _normalize_status(latest.get("status"))
    inquiry = None
    if str(latest.get("status") or "").upper() == "SUCCESS":
        try:
            inquiry = client.inquiry_status(token, int(account.cartable_id), invoice_id)
        except FanavaApiError as exc:
            if exc.status_code not in {404}:
                raise
    return {"history": history, "latest": latest, "mapped_status": mapped, "inquiry": inquiry}


def map_fanava_inquiry(item: dict[str, Any]) -> str | None:
    value = str(item.get("invoiceStatus") or "").upper()
    if value in {"APPROVED", "SYSTEMIC_APPROVED", "NO_NEED_REACTION"}:
        return "accepted"
    if value == "REJECTED":
        return "rejected"
    if value in {"AWAITING_REACTION", "IMPOSSIBLE_REACTION"}:
        return "pending"
    if value == "CANCELED":
        return "cancelled"
    return None
