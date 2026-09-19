"""Tests for Moadian API v2 helpers."""
from __future__ import annotations

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from datetime import datetime, timedelta, timezone

from app.integrations.moadian.certificate import certificate_to_x5c_base64, normalize_certificate_pem
from app.integrations.moadian.v2_crypto import sign_jws


def _make_self_signed_cert() -> tuple[str, rsa.RSAPrivateKey]:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name(
        [
            x509.NameAttribute(NameOID.SERIAL_NUMBER, "1234567890"),
            x509.NameAttribute(NameOID.COUNTRY_NAME, "IR"),
            x509.NameAttribute(NameOID.COMMON_NAME, "Test Taxpayer"),
        ]
    )
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(subject)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.now(timezone.utc) - timedelta(days=1))
        .not_valid_after(datetime.now(timezone.utc) + timedelta(days=365))
        .sign(key, hashes.SHA256())
    )
    cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode("utf-8")
    return cert_pem, key


def test_normalize_certificate_pem_adds_headers():
    raw = "MIIBfake"
    pem = normalize_certificate_pem(raw)
    assert "BEGIN CERTIFICATE" in pem


def test_sign_jws_produces_three_parts():
    cert_pem, key = _make_self_signed_cert()
    x5c = certificate_to_x5c_base64(cert_pem)
    token = sign_jws('{"nonce":"n","clientId":"ABC"}', key, x5c)
    assert token.count(".") == 2
    assert len(token) > 100
