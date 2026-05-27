"""
تولید CSR و اعتبارسنجی جفت کلید/گواهی برای تنظیمات مودیان.
"""
from __future__ import annotations

import base64
import re
from typing import Any, Dict, Optional, Tuple

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.backends import default_backend
from cryptography.x509.oid import NameOID

from adapters.api.v1.schema_models.tax_settings import GenerateKeysRequest
from adapters.db.models.business import BusinessType
from app.core.responses import ApiError
from app.integrations.moadian.utils import validate_national_id
from app.services.tax_setting_health_service import extract_certificate_serial_number


_LEGAL_BUSINESS_TYPES = {
    BusinessType.COMPANY,
    BusinessType.SHOP,
    BusinessType.STORE,
    BusinessType.UNION,
    BusinessType.CLUB,
    BusinessType.INSTITUTE,
}


def suggested_moadian_person_type(business_type: BusinessType | str | None) -> str:
    """پیشنهاد نوع مودی برای تولید CSR بر اساس نوع کسب‌وکار."""
    if business_type is None:
        return "legal"
    if isinstance(business_type, str):
        if business_type.strip().upper() in ("INDIVIDUAL", "شخصی"):
            return "natural"
        if business_type.strip() in {t.value for t in _LEGAL_BUSINESS_TYPES}:
            return "legal"
        return "legal"
    if business_type == BusinessType.INDIVIDUAL:
        return "natural"
    return "legal"


def generate_csr_pem(private_key: rsa.RSAPrivateKey, request_data: GenerateKeysRequest) -> str:
    """ساخت CSR برای اشخاص حقیقی و حقوقی."""
    if request_data.person_type == "legal":
        subject = _legal_csr_subject(request_data)
    else:
        subject = _natural_csr_subject(request_data)

    builder = x509.CertificateSigningRequestBuilder().subject_name(subject)
    if request_data.email and str(request_data.email).strip():
        builder = builder.add_extension(
            x509.SubjectAlternativeName([x509.RFC822Name(str(request_data.email).strip())]),
            critical=False,
        )

    csr = builder.sign(private_key, hashes.SHA256())
    return csr.public_bytes(serialization.Encoding.PEM).decode("utf-8")


def _legal_csr_subject(request_data: GenerateKeysRequest) -> x509.Name:
    display_fa = (request_data.name_fa or "").strip() or "Legal Entity"
    display_en = (request_data.name_en or "").strip() or display_fa
    return x509.Name(
        [
            x509.NameAttribute(NameOID.SERIAL_NUMBER, request_data.national_id),
            x509.NameAttribute(NameOID.COUNTRY_NAME, "IR"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, display_fa),
            x509.NameAttribute(NameOID.LOCALITY_NAME, display_fa),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, display_fa),
            x509.NameAttribute(NameOID.COMMON_NAME, f"{display_en} [Stamp]"),
        ]
    )


def _natural_csr_subject(request_data: GenerateKeysRequest) -> x509.Name:
    display_name = (request_data.name_fa or request_data.name_en or "").strip() or "Taxpayer"
    locality = (request_data.name_fa or "تهران").strip()
    return x509.Name(
        [
            x509.NameAttribute(NameOID.SERIAL_NUMBER, request_data.national_id),
            x509.NameAttribute(NameOID.COUNTRY_NAME, "IR"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, locality),
            x509.NameAttribute(NameOID.LOCALITY_NAME, locality),
            x509.NameAttribute(NameOID.COMMON_NAME, display_name),
        ]
    )


def _load_private_key_obj(pem: str) -> rsa.RSAPrivateKey:
    raw = (pem or "").strip().replace("\r\n", "\n")
    if "-----BEGIN" in raw:
        key = serialization.load_pem_private_key(
            raw.encode("utf-8"),
            password=None,
            backend=default_backend(),
        )
    else:
        compact = "".join(raw.split())
        der = base64.b64decode(compact)
        key = serialization.load_der_private_key(der, password=None, backend=default_backend())
    if not isinstance(key, rsa.RSAPrivateKey):
        raise ValueError("کلید خصوصی RSA نیست")
    return key


def _load_public_key_obj(pem: str):
    raw = (pem or "").strip().replace("\r\n", "\n")
    if "-----BEGIN" not in raw:
        raw = "-----BEGIN PUBLIC KEY-----\n" + raw + "\n-----END PUBLIC KEY-----"
    return serialization.load_pem_public_key(raw.encode("utf-8"), backend=default_backend())


def _public_key_der(public_key_obj) -> bytes:
    return public_key_obj.public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )


def private_key_matches_public_key(private_key_pem: str, public_key_pem: str) -> bool:
    try:
        private_key = _load_private_key_obj(private_key_pem)
        stored_public = _load_public_key_obj(public_key_pem)
        return _public_key_der(private_key.public_key()) == _public_key_der(stored_public)
    except Exception:
        return False


def private_key_matches_certificate(private_key_pem: str, certificate_pem: str) -> bool:
    try:
        private_key = _load_private_key_obj(private_key_pem)
        cert = _load_certificate(certificate_pem)
        cert_public = cert.public_key()
        return _public_key_der(private_key.public_key()) == _public_key_der(cert_public)
    except Exception:
        return False


def _load_certificate(pem: str) -> x509.Certificate:
    raw = str(pem).strip().replace("\r\n", "\n")
    if "-----BEGIN" not in raw:
        raw = "-----BEGIN CERTIFICATE-----\n" + raw + "\n-----END CERTIFICATE-----"
    return x509.load_pem_x509_certificate(raw.encode("utf-8"), backend=default_backend())


def validate_generate_keys_request(request_data: GenerateKeysRequest) -> None:
    """اعتبارسنجی ورودی تولید کلید قبل از ساخت CSR."""
    national_id = re.sub(r"[\s\-]", "", request_data.national_id or "")
    is_valid, person_kind = validate_national_id(national_id)
    if not is_valid:
        raise ApiError(
            "TAX_INVALID_NATIONAL_ID",
            "کد ملی / شناسه ملی نامعتبر است.",
            http_status=400,
        )

    if request_data.person_type == "natural" and person_kind != "natural":
        raise ApiError(
            "TAX_INVALID_NATIONAL_ID",
            "برای شخص حقیقی، کد ملی ۱۰ رقمی وارد کنید.",
            http_status=400,
        )
    if request_data.person_type == "legal" and person_kind != "legal":
        raise ApiError(
            "TAX_INVALID_NATIONAL_ID",
            "برای شخص حقوقی، شناسه ملی ۱۱ رقمی وارد کنید.",
            http_status=400,
        )

    if not (request_data.name_fa or "").strip():
        raise ApiError(
            "TAX_CSR_NAME_REQUIRED",
            "نام فارسی برای ساخت CSR الزامی است.",
            http_status=400,
        )


def validate_tax_setting_key_material(payload: Dict[str, Any]) -> None:
    """
    بررسی تطابق کلید خصوصی با کلید عمومی و گواهی قبل از ذخیره تنظیمات.
    """
    private_key = (payload.get("private_key") or "").strip()
    public_key = (payload.get("public_key") or "").strip()
    certificate = (payload.get("certificate") or "").strip()

    if not private_key:
        return

    if public_key and not private_key_matches_public_key(private_key, public_key):
        raise ApiError(
            "TAX_KEY_PUBLIC_MISMATCH",
            "کلید عمومی ذخیره‌شده با کلید خصوصی هم‌خوان نیست.",
            http_status=400,
        )

    if certificate and not private_key_matches_certificate(private_key, certificate):
        raise ApiError(
            "TAX_KEY_CERT_MISMATCH",
            "گواهی دیجیتال با کلید خصوصی جفت نیست. همان گواهی صادرشده از CSR این کلید را بارگذاری کنید.",
            http_status=400,
        )


def key_material_warnings(
    *,
    private_key: str | None,
    public_key: str | None,
    certificate: str | None,
    certificate_request: str | None,
) -> list[Dict[str, Any]]:
    """هشدارهای تکمیلی مرتبط با کلید و گواهی."""
    warnings: list[Dict[str, Any]] = []
    pk = (private_key or "").strip()
    pub = (public_key or "").strip()
    cert = (certificate or "").strip()

    if pk and pub and not private_key_matches_public_key(pk, pub):
        warnings.append({
            "code": "KEY_PUBLIC_MISMATCH",
            "level": "error",
            "message": "کلید عمومی با کلید خصوصی مطابقت ندارد.",
        })

    if pk and cert and not private_key_matches_certificate(pk, cert):
        warnings.append({
            "code": "KEY_CERT_MISMATCH",
            "level": "error",
            "message": "گواهی دیجیتال با کلید خصوصی جفت نیست.",
        })

    if pk and not cert:
        warnings.append({
            "code": "CERTIFICATE_MISSING",
            "level": "warning",
            "message": (
                "گواهی دیجیتال صادرشده از کارپوشه مودیان در تنظیمات ذخیره نشده است. "
                "پس از تأیید CSR، فایل گواهی (.crt) را در همین صفحه بارگذاری کنید."
            ),
        })

    if pk and not (certificate_request or "").strip():
        warnings.append({
            "code": "CSR_NOT_SAVED",
            "level": "info",
            "message": (
                "درخواست CSR در سیستم ذخیره نشده است. "
                "اگر کلید را خارج از حسابیکس ساخته‌اید، مطمئن شوید همان کلید در مودیان ثبت شده است."
            ),
        })

    cert_serial = extract_certificate_serial_number(cert or None)
    if cert_serial:
        warnings.append({
            "code": "CERTIFICATE_SERIAL",
            "level": "info",
            "message": f"کد ملی/شناسه داخل گواهی ذخیره‌شده: {cert_serial}",
            "meta": {"serial_number": cert_serial},
        })

    return warnings
