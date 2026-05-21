"""
بررسی سلامت تنظیمات مودیان: هشدارها، تطابق JWT، و کشف خطای 4103.
"""
from __future__ import annotations

import base64
import json
import re
from typing import Any, Dict, List, Optional

from sqlalchemy import Boolean, String, cast, or_
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.tax_setting import TaxSetting
from app.services.tax_submission_service import extract_moadian_errors_from_extra


def decode_jwt_payload(token: str) -> Optional[Dict[str, Any]]:
    """استخراج payload از JWT بدون اعتبارسنجی امضا."""
    if not token or "." not in token:
        return None
    try:
        payload_b64 = token.split(".")[1]
        payload_b64 += "=" * (-len(payload_b64) % 4)
        raw = base64.urlsafe_b64decode(payload_b64)
        return json.loads(raw.decode("utf-8"))
    except Exception:
        return None


def _digits_only(value: Any) -> str:
    return re.sub(r"\D", "", str(value or ""))


def economic_codes_align(stored: str | None, token_taxpayer_id: str | None) -> bool:
    """تطابق کد اقتصادی تنظیمات با taxpayerId توکن (با تحمل ۱۰/۱۴ رقم)."""
    a = _digits_only(stored)
    b = _digits_only(token_taxpayer_id)
    if not a or not b:
        return True
    if a == b:
        return True
    if len(a) >= 10 and len(b) >= 10 and a[:10] == b[:10]:
        return True
    return a.startswith(b) or b.startswith(a)


def extract_certificate_serial_number(certificate_pem: str | None) -> Optional[str]:
    if not certificate_pem or not str(certificate_pem).strip():
        return None
    try:
        from cryptography import x509
        from cryptography.x509.oid import NameOID

        pem = str(certificate_pem).strip().replace("\r\n", "\n")
        cert = x509.load_pem_x509_certificate(pem.encode("utf-8"))
        attrs = cert.subject.get_attributes_for_oid(NameOID.SERIAL_NUMBER)
        if attrs:
            return str(attrs[0].value).strip()
    except Exception:
        return None
    return None


def find_recent_identity_failures(db: Session, business_id: int, *, limit: int = 5) -> List[Dict[str, Any]]:
    """فاکتورهای اخیر با خطای 4103 یا پیام عدم تطابق گواهی."""
    _extra_info_jb = cast(Document.extra_info, JSONB)
    extra_text = cast(Document.extra_info, String)
    docs = (
        db.query(Document)
        .filter(
            Document.business_id == int(business_id),
            cast(_extra_info_jb["tax_workspace"], Boolean) == True,
            or_(
                extra_text.ilike("%4103%"),
                extra_text.ilike("%گواهی امضا%"),
                _extra_info_jb["tax_error_message"].astext.ilike("%4103%"),
                _extra_info_jb["tax_error_message"].astext.ilike("%گواهی امضا%"),
            ),
        )
        .order_by(Document.id.desc())
        .limit(limit)
        .all()
    )
    failures: List[Dict[str, Any]] = []
    for doc in docs:
        extra = dict(doc.extra_info or {})
        err_msg = str(extra.get("tax_error_message") or "")
        errors = extract_moadian_errors_from_extra(extra)
        failures.append({
            "invoice_id": doc.id,
            "code": doc.code,
            "tax_status": extra.get("tax_status"),
            "tax_tracking_code": extra.get("tax_tracking_code"),
            "tax_error_message": err_msg or next(
                (e.get("message") for e in errors if str(e.get("code")) == "4103"),
                "خطای 4103: عدم تطابق گواهی امضا با شناسه کلاینت",
            ),
        })
    return failures


def build_configuration_warnings(
    tax_setting: TaxSetting,
    *,
    jwt_claims: Optional[Dict[str, Any]] = None,
) -> List[Dict[str, Any]]:
    warnings: List[Dict[str, Any]] = []

    if not (tax_setting.certificate or "").strip():
        warnings.append({
            "code": "CERTIFICATE_MISSING",
            "level": "warning",
            "message": (
                "گواهی دیجیتال صادرشده از کارپوشه مودیان در تنظیمات ذخیره نشده است. "
                "پس از تأیید CSR، فایل گواهی (.crt) را در همین صفحه بارگذاری کنید."
            ),
        })

    if (tax_setting.private_key or "").strip() and not (tax_setting.certificate_request or "").strip():
        warnings.append({
            "code": "CSR_NOT_SAVED",
            "level": "info",
            "message": (
                "درخواست CSR در سیستم ذخیره نشده است. "
                "اگر کلید را خارج از حسابیکس ساخته‌اید، مطمئن شوید همان کلید در مودیان ثبت شده است."
            ),
        })

    economic = (tax_setting.economic_code or "").strip()
    memory_id = (tax_setting.tax_memory_id or "").strip()
    if economic and not re.fullmatch(r"\d{11}|\d{14}", _digits_only(economic)):
        warnings.append({
            "code": "ECONOMIC_CODE_FORMAT",
            "level": "warning",
            "message": "کد اقتصادی باید ۱۱ یا ۱۴ رقم باشد.",
        })

    if jwt_claims:
        token_sub = str(jwt_claims.get("sub") or jwt_claims.get("jti") or "").strip()
        token_taxpayer = str(jwt_claims.get("taxpayerId") or "").strip()

        if memory_id and token_sub and token_sub.upper() != memory_id.upper():
            warnings.append({
                "code": "JWT_MEMORY_MISMATCH",
                "level": "error",
                "message": (
                    f"شناسه حافظه در توکن ({token_sub}) با تنظیمات ({memory_id}) مطابقت ندارد."
                ),
            })

        if economic and token_taxpayer and not economic_codes_align(economic, token_taxpayer):
            warnings.append({
                "code": "JWT_TAXPAYER_MISMATCH",
                "level": "error",
                "message": (
                    f"کد اقتصادی توکن مودیان ({token_taxpayer}) با مقدار ذخیره‌شده "
                    f"({economic}) هم‌خوان نیست."
                ),
            })

    cert_serial = extract_certificate_serial_number(tax_setting.certificate)
    if cert_serial:
        warnings.append({
            "code": "CERTIFICATE_SERIAL",
            "level": "info",
            "message": f"کد ملی/شناسه داخل گواهی ذخیره‌شده: {cert_serial}",
            "meta": {"serial_number": cert_serial},
        })

    return warnings


def build_identity_check(
    db: Session,
    business_id: int,
    *,
    jwt_claims: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    بررسی احتمال خطای 4103 بر اساس سوابق ارسال.
    (تشخیص قطعی بدون ارسال فاکتور ممکن نیست؛ سوابق 4103 نشانه قوی است.)
    """
    recent = find_recent_identity_failures(db, business_id)
    if recent:
        return {
            "status": "failed",
            "code": "4103",
            "message": (
                "در ارسال‌های اخیر خطای 4103 ثبت شده: کلید خصوصی/گواهی امضا "
                "با هویت ثبت‌شده برای شناسه حافظه در مودیان مطابقت ندارد."
            ),
            "recent_failures": recent,
        }

    if jwt_claims:
        return {
            "status": "ok",
            "code": None,
            "message": (
                "لاگین موفق بود و مورد 4103 در ارسال‌های اخیر این کسب‌وکار دیده نشد. "
                "برای اطمینان کامل، یک فاکتور تست ارسال و استعلام وضعیت کنید."
            ),
            "recent_failures": [],
        }

    return {
        "status": "unknown",
        "code": None,
        "message": "احراز هویت انجام نشد؛ بررسی هویت امضا ممکن نبود.",
        "recent_failures": [],
    }


def resolve_connection_status(
    warnings: List[Dict[str, Any]],
    identity_check: Dict[str, Any],
) -> str:
    if identity_check.get("status") == "failed":
        return "identity_mismatch"
    if any(w.get("level") == "error" for w in warnings):
        return "connected_with_warnings"
    if warnings:
        return "connected_with_warnings"
    return "connected"


def run_extended_connection_test(
    db: Session,
    tax_setting: TaxSetting,
    *,
    token: str,
    server_info: Dict[str, Any],
) -> Dict[str, Any]:
    jwt_claims = decode_jwt_payload(token)
    warnings = build_configuration_warnings(tax_setting, jwt_claims=jwt_claims)
    identity_check = build_identity_check(
        db,
        tax_setting.business_id,
        jwt_claims=jwt_claims,
    )
    status = resolve_connection_status(warnings, identity_check)

    message_map = {
        "connected": "اتصال به سامانه مودیان با موفقیت برقرار شد.",
        "connected_with_warnings": "اتصال برقرار است اما هشدارهای پیکربندی وجود دارد.",
        "identity_mismatch": (
            "اتصال برقرار است، اما احتمال ناهماهنگی کلید/گواهی با حافظه مودیان وجود دارد "
            "(خطای 4103 در ارسال‌های اخیر)."
        ),
    }

    return {
        "status": status,
        "sandbox_mode": bool(tax_setting.sandbox_mode),
        "server_info": {
            "has_public_key": bool(server_info.get("publicKeys")),
            "key_count": len(server_info.get("publicKeys", [])),
        },
        "auth": {
            "logged_in": bool(token),
            "token_length": len(token) if token else 0,
            "jwt_claims": jwt_claims,
            "tax_memory_id_match": (
                not jwt_claims
                or str(jwt_claims.get("sub") or jwt_claims.get("jti") or "").strip().upper()
                == (tax_setting.tax_memory_id or "").strip().upper()
            ),
            "economic_code_match": (
                not jwt_claims
                or economic_codes_align(
                    tax_setting.economic_code,
                    str(jwt_claims.get("taxpayerId") or ""),
                )
            ),
        },
        "warnings": warnings,
        "identity_check": identity_check,
        "message": message_map.get(status, message_map["connected"]),
    }
