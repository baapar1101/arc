from typing import Dict, Any, Tuple

from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.api.v1.schema_models.tax_settings import (
    TaxSettingsSaveRequest,
    GenerateKeysRequest,
    GenerateKeysResponse,
)
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response, ApiError
from app.services.tax_setting_service import (
    get_tax_setting,
    serialize_tax_setting,
    upsert_tax_setting,
)
from app.services.tax_data_quality_service import (
    get_tax_data_quality,
    format_tax_data_quality,
)

from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization, hashes
from cryptography import x509
from cryptography.x509.oid import NameOID


router = APIRouter(prefix="/tax-settings", tags=["tax-settings"])

@router.get("/business/{business_id}")
@require_business_access("business_id")
def get_tax_settings_endpoint(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "business")),
):
    setting = get_tax_setting(db, business_id)
    data = serialize_tax_setting(setting, business_id=business_id)
    return success_response(data=data, request=request, message="TAX_SETTINGS_FETCHED")


@router.post("/business/{business_id}")
@require_business_access("business_id")
def save_tax_settings_endpoint(
    request: Request,
    business_id: int,
    payload: TaxSettingsSaveRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "business")),
):
    user_id = ctx.get_user_id()
    if not user_id:
        raise ApiError("UNAUTHORIZED", "Authentication required", http_status=401)

    setting = upsert_tax_setting(
        db,
        business_id=business_id,
        user_id=int(user_id),
        payload=payload.dict(),
    )
    db.commit()
    db.refresh(setting)
    data = serialize_tax_setting(setting, business_id=business_id)
    return success_response(data=data, request=request, message="TAX_SETTINGS_SAVED")


@router.post("/business/{business_id}/generate-keys")
@require_business_access("business_id")
def generate_keys_endpoint(
    request: Request,
    business_id: int,
    payload: GenerateKeysRequest = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "business")),
):
    private_pem, public_pem, private_key = _generate_rsa_key_pair()
    csr_pem = None
    if payload.person_type == "legal":
        csr_pem = _generate_csr(private_key, payload)

    data = GenerateKeysResponse(
        private_key=private_pem,
        public_key=public_pem,
        csr=csr_pem,
    ).dict()
    return success_response(data=data, request=request, message="TAX_KEYS_GENERATED")


@router.get("/business/{business_id}/data-quality")
@require_business_access("business_id")
def tax_data_quality_endpoint(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "business")),
):
    report = get_tax_data_quality(db, business_id)
    data = format_tax_data_quality(report)
    return success_response(data=data, request=request, message="TAX_DATA_QUALITY_REPORT")


def _generate_rsa_key_pair() -> Tuple[str, str, rsa.RSAPrivateKey]:
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


def _generate_csr(private_key: rsa.RSAPrivateKey, request_data: GenerateKeysRequest) -> str:
    subject = x509.Name(
        [
            x509.NameAttribute(NameOID.SERIAL_NUMBER, request_data.national_id),
            x509.NameAttribute(NameOID.COUNTRY_NAME, "IR"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, request_data.name_fa or "تهران"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, request_data.name_fa or "تهران"),
            x509.NameAttribute(
                NameOID.ORGANIZATION_NAME,
                request_data.name_fa or request_data.name_en or "Legal Entity",
            ),
            x509.NameAttribute(
                NameOID.COMMON_NAME,
                f"{request_data.name_en or request_data.name_fa or 'Legal Entity'} [Stamp]",
            ),
        ]
    )

    builder = x509.CertificateSigningRequestBuilder().subject_name(subject)

    if request_data.email:
        builder = builder.add_extension(
            x509.SubjectAlternativeName(
                [
                    x509.RFC822Name(request_data.email),
                ]
            ),
            critical=False,
        )

    csr = builder.sign(private_key, hashes.SHA256())
    return csr.public_bytes(serialization.Encoding.PEM).decode("utf-8")


