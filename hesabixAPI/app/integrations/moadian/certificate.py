"""
Resolve the X.509 signing certificate used for Moadian API v2 (JWS with x5c).

The tax portal does not always offer a downloadable ``.crt`` file; the signed
certificate is often delivered as PEM text from a PKI provider (GICA, tax office,
Sepidar CSR signing, etc.) after the CSR registered in Moadian is approved.

API v1 (فقط کلید خصوصی، مشابه SDK قدیمی PHP) بدون گواهی x5c کار می‌کند.
"""
from __future__ import annotations

from app.core.responses import ApiError


def normalize_certificate_pem(raw: str) -> str:
    pem = (raw or "").strip().replace("\r\n", "\n").replace("\r", "\n")
    if not pem:
        raise ApiError(
            "TAX_CERTIFICATE_REQUIRED",
            "گواهی امضای الکترونیک برای اتصال به سامانه مودیان (API v2) الزامی است.",
            http_status=400,
        )
    if "-----BEGIN CERTIFICATE-----" not in pem:
        pem = f"-----BEGIN CERTIFICATE-----\n{pem}\n-----END CERTIFICATE-----"
    return pem


def certificate_to_x5c_base64(certificate_pem: str) -> str:
    """Strip PEM headers for the JWS x5c header (moadian2 format)."""
    pem = normalize_certificate_pem(certificate_pem)
    return (
        pem.replace("-----BEGIN CERTIFICATE-----", "")
        .replace("-----END CERTIFICATE-----", "")
        .replace("\n", "")
        .strip()
    )


def resolve_signing_certificate_pem(
    *,
    certificate: str | None,
) -> str:
    """
    Return PEM certificate for API v2 signing.

    Raises:
        ApiError: when no certificate PEM is configured.
    """
    cert = (certificate or "").strip()
    if not cert:
        raise ApiError(
            "TAX_CERTIFICATE_REQUIRED",
            (
                "گواهی امضای الکترونیک در تنظیمات مودیان ثبت نشده است. "
                "پس از تأیید CSR در کارپوشه مودیان، فایل گواهی (معمولاً PEM یا CRT) "
                "را از مرکز صدور گواهی (GICA، دفتر مالیاتی، یا سامانه صدور CSR) "
                "دریافت و متن PEM آن را در فیلد «گواهی» تنظیمات مودیان در Hesabix "
                "قرار دهید. سامانه مودیان فایل قابل دانلود ارائه نمی‌دهد؛ "
                "گواهی از مرکز میانی صادر می‌شود."
            ),
            http_status=400,
        )
    return normalize_certificate_pem(cert)


def is_usable_signing_certificate_pem(
    certificate: str | None,
    *,
    private_key_pem: str | None = None,
) -> bool:
    """
    آیا متن ذخیره‌شده یک گواهی X.509 معتبر برای API v2 است؟

    CSR، کلید عمومی، یا متن نامعتبر باعث False می‌شود تا کلاینت مانند نسخه PHP
    از API v1 (packet + private key) استفاده کند.
    """
    raw = (certificate or "").strip()
    if not raw:
        return False
    upper = raw.upper()
    if "BEGIN CERTIFICATE REQUEST" in upper or "BEGIN NEW CERTIFICATE REQUEST" in upper:
        return False
    if "BEGIN PUBLIC KEY" in upper or "BEGIN RSA PUBLIC KEY" in upper:
        return False
    if "BEGIN PRIVATE KEY" in upper or "BEGIN RSA PRIVATE KEY" in upper:
        return False
    try:
        pem = normalize_certificate_pem(raw)
        from cryptography import x509
        from cryptography.hazmat.backends import default_backend

        x509.load_pem_x509_certificate(pem.encode("utf-8"), backend=default_backend())
    except Exception:
        return False

    if not private_key_pem:
        return True

    try:
        from app.services.tax_key_material_service import private_key_matches_certificate

        return private_key_matches_certificate(private_key_pem, pem)
    except Exception:
        return False
