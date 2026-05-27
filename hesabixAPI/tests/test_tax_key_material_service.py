"""تست تولید CSR و اعتبارسنجی کلید/گواهی مودیان."""

from __future__ import annotations

from datetime import datetime, timedelta

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

from adapters.api.v1.schema_models.tax_settings import GenerateKeysRequest
from adapters.db.models.business import BusinessType
from app.core.responses import ApiError
from app.services.tax_key_material_service import (
    generate_csr_pem,
    private_key_matches_certificate,
    private_key_matches_public_key,
    suggested_moadian_person_type,
    validate_generate_keys_request,
    validate_tax_setting_key_material,
)


def _generate_rsa_key_pair():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode("utf-8")
    public_pem = key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode("utf-8")
    return private_pem, public_pem, key


def test_suggested_person_type():
    assert suggested_moadian_person_type(BusinessType.INDIVIDUAL) == "natural"
    assert suggested_moadian_person_type(BusinessType.COMPANY) == "legal"


def test_generate_csr_for_natural_and_legal():
  private_pem, public_pem, private_key = _generate_rsa_key_pair()

  natural_req = GenerateKeysRequest(
      person_type="natural",
      national_id="1234567890",
      name_fa="علی رضایی",
  )
  natural_csr = generate_csr_pem(private_key, natural_req)
  assert "BEGIN CERTIFICATE REQUEST" in natural_csr
  natural_parsed = x509.load_pem_x509_csr(natural_csr.encode())
  attrs = natural_parsed.subject.get_attributes_for_oid(NameOID.SERIAL_NUMBER)
  assert str(attrs[0].value) == "1234567890"

  legal_req = GenerateKeysRequest(
      person_type="legal",
      national_id="12345678901",
      name_fa="شرکت نمونه",
      name_en="Sample Co",
      email="tax@example.com",
  )
  legal_csr = generate_csr_pem(private_key, legal_req)
  assert "BEGIN CERTIFICATE REQUEST" in legal_csr
  legal_parsed = x509.load_pem_x509_csr(legal_csr.encode())
  cn_attrs = legal_parsed.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
  assert "[Stamp]" in str(cn_attrs[0].value)


def test_validate_natural_national_id_length():
    with pytest.raises(ApiError) as exc:
        validate_generate_keys_request(
            GenerateKeysRequest(
                person_type="natural",
                national_id="12345678901",
                name_fa="نام تست",
            )
        )
    assert exc.value.detail["error"]["code"] == "TAX_INVALID_NATIONAL_ID"


def test_private_key_certificate_match():
    private_pem, public_pem, private_key = _generate_rsa_key_pair()
    req = GenerateKeysRequest(
        person_type="natural",
        national_id="1234567890",
        name_fa="تست",
    )
    csr_pem = generate_csr_pem(private_key, req)
    csr = x509.load_pem_x509_csr(csr_pem.encode())
    cert = (
        x509.CertificateBuilder()
        .subject_name(csr.subject)
        .issuer_name(csr.subject)
        .public_key(csr.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.utcnow())
        .not_valid_after(datetime.utcnow() + timedelta(days=365))
        .sign(private_key, hashes.SHA256())
    )
    cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode()

    assert private_key_matches_public_key(private_pem, public_pem)
    assert private_key_matches_certificate(private_pem, cert_pem)

    other_private, _, _ = _generate_rsa_key_pair()
    assert not private_key_matches_certificate(other_private, cert_pem)


def test_validate_tax_setting_key_material_mismatch():
    private_pem, public_pem, _ = _generate_rsa_key_pair()
    other_private, other_public, _ = _generate_rsa_key_pair()

    with pytest.raises(ApiError) as exc:
        validate_tax_setting_key_material({
            "private_key": private_pem,
            "public_key": other_public,
        })
    assert exc.value.detail["error"]["code"] == "TAX_KEY_PUBLIC_MISMATCH"

    validate_tax_setting_key_material({
        "private_key": private_pem,
        "public_key": public_pem,
    })
