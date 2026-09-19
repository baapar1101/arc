"""API version selection: v1 (PHP-style) vs v2 (certificate)."""
from __future__ import annotations

from cryptography.hazmat.primitives import serialization
from types import SimpleNamespace

from app.integrations.moadian.certificate import is_usable_signing_certificate_pem
from app.integrations.moadian.client import uses_moadian_v2
from tests.test_moadian_v2_client import _make_self_signed_cert


def test_csr_in_certificate_field_is_not_usable_for_v2() -> None:
    csr = (
        "-----BEGIN CERTIFICATE REQUEST-----\n"
        "MIICfakeCSRdata\n"
        "-----END CERTIFICATE REQUEST-----"
    )
    assert is_usable_signing_certificate_pem(csr) is False
    setting = SimpleNamespace(
        certificate=csr,
        private_key="-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----",
    )
    assert uses_moadian_v2(setting) is False


def test_public_key_in_certificate_field_is_not_usable_for_v2() -> None:
    pub = "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZI\n-----END PUBLIC KEY-----"
    assert is_usable_signing_certificate_pem(pub) is False


def test_valid_certificate_matching_private_key_enables_v2() -> None:
    cert_pem, key = _make_self_signed_cert()
    key_pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode("utf-8")
    assert is_usable_signing_certificate_pem(cert_pem, private_key_pem=key_pem) is True
    setting = SimpleNamespace(certificate=cert_pem, private_key=key_pem)
    assert uses_moadian_v2(setting) is True


def test_empty_certificate_uses_v1() -> None:
    setting = SimpleNamespace(
        certificate=None,
        private_key="-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----",
    )
    assert uses_moadian_v2(setting) is False
