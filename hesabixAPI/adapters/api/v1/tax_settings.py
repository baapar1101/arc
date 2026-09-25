from typing import Dict, Any, Tuple

from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.api.v1.schema_models.tax_settings import (
    TaxSettingsSaveRequest,
    TaxSettingsTestConnectionRequest,
    GenerateKeysRequest,
    GenerateKeysResponse,
)
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.moadian_plugin_dependency import ensure_moadian_plugin_active
from app.core.responses import success_response, ApiError
from app.services.tax_setting_service import (
    get_tax_setting,
    serialize_tax_setting,
    upsert_tax_setting,
    merge_tax_setting_for_test,
    validate_tax_setting_complete,
)
from app.services.tax_data_quality_service import (
    get_tax_data_quality,
    format_tax_data_quality,
)
from app.services.tax_key_material_service import (
    generate_csr_pem,
    validate_generate_keys_request,
    validate_tax_setting_key_material,
)

from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization


router = APIRouter(prefix="/tax-settings", tags=["مالیات"])

@router.get("/business/{business_id}")
@require_business_access("business_id")
def get_tax_settings_endpoint(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("moadian", "manage_settings")),
):
    ensure_moadian_plugin_active(db, business_id)
    setting = get_tax_setting(db, business_id)
    data = serialize_tax_setting(setting, business_id=business_id, db=db)
    return success_response(data=data, request=request, message="TAX_SETTINGS_FETCHED")


@router.post("/business/{business_id}")
@require_business_access("business_id")
def save_tax_settings_endpoint(
    request: Request,
    business_id: int,
    payload: TaxSettingsSaveRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("moadian", "manage_settings")),
):
    ensure_moadian_plugin_active(db, business_id)
    user_id = ctx.get_user_id()
    if not user_id:
        raise ApiError("UNAUTHORIZED", "Authentication required", http_status=401)

    validate_tax_setting_key_material(payload.dict())

    setting = upsert_tax_setting(
        db,
        business_id=business_id,
        user_id=int(user_id),
        payload=payload.dict(),
    )
    db.commit()
    db.refresh(setting)
    data = serialize_tax_setting(setting, business_id=business_id, db=db)
    return success_response(data=data, request=request, message="TAX_SETTINGS_SAVED")


@router.post("/business/{business_id}/generate-keys")
@require_business_access("business_id")
def generate_keys_endpoint(
    request: Request,
    business_id: int,
    payload: GenerateKeysRequest = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("moadian", "manage_settings")),
):
    ensure_moadian_plugin_active(db, business_id)
    validate_generate_keys_request(payload)

    private_pem, public_pem, private_key = _generate_rsa_key_pair()
    csr_pem = generate_csr_pem(private_key, payload)

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
    _: None = Depends(require_business_permission_dep("moadian", "manage_settings")),
):
    ensure_moadian_plugin_active(db, business_id)
    report = get_tax_data_quality(db, business_id)
    data = format_tax_data_quality(report)
    return success_response(data=data, request=request, message="TAX_DATA_QUALITY_REPORT")


@router.post("/business/{business_id}/test-connection")
@require_business_access("business_id")
def test_tax_connection_endpoint(
    request: Request,
    business_id: int,
    payload: TaxSettingsTestConnectionRequest | None = Body(default=None),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("moadian", "manage_settings")),
):
    """
    تست اتصال به سامانه مودیان (API v2).

    اگر body ارسال شود، مقادیر فرم UI با تنظیمات ذخیره‌شده ادغام می‌شود
    تا بدون «ذخیره» قبلی هم بتوان اتصال را آزمایش کرد.
    """
    ensure_moadian_plugin_active(db, business_id)
    from app.integrations.moadian.client import MoadianClient, uses_moadian_v2
    from app.core.settings import get_settings
    from app.services.tax_setting_health_service import run_extended_connection_test

    stored = get_tax_setting(db, business_id)
    if stored is None and payload is None:
        raise ApiError(
            "TAX_SETTINGS_NOT_CONFIGURED",
            "تنظیمات سامانه مودیان یافت نشد.",
            http_status=400,
        )

    tax_setting = merge_tax_setting_for_test(stored, payload, business_id=business_id)
    missing = validate_tax_setting_complete(tax_setting)
    if missing:
        labels = {
            "tax_memory_id": "شناسه حافظه مالیاتی",
            "economic_code": "کد اقتصادی",
            "private_key": "کلید خصوصی",
            "certificate": "گواهی امضای الکترونیک (PEM)",
        }
        missing_fa = "، ".join(labels.get(f, f) for f in missing)
        raise ApiError(
            "TAX_SETTINGS_INCOMPLETE",
            f"تنظیمات ناقص است. فیلدهای الزامی: {missing_fa}.",
            http_status=400,
            details={"missing_fields": missing, "api_mode": "v2" if uses_moadian_v2(tax_setting) else "v1"},
        )

    client = MoadianClient(settings=get_settings(), tax_setting=tax_setting)
    
    try:
        # 1. دریافت اطلاعات سرور
        server_info = client.get_server_information()
        
        # 2. تست لاگین + بررسی JWT، هشدارها، و سوابق 4103
        token = client.login()
        result = run_extended_connection_test(
            db,
            tax_setting,
            token=token,
            server_info=server_info if isinstance(server_info, dict) else {},
        )
        result["api_version"] = client.api_version

        message_key = "TAX_CONNECTION_SUCCESS"
        if result.get("status") == "identity_mismatch":
            message_key = "TAX_CONNECTION_IDENTITY_MISMATCH"
        elif result.get("status") == "connected_with_warnings":
            message_key = "TAX_CONNECTION_WITH_WARNINGS"

        return success_response(
            data=result,
            request=request,
            message=message_key,
        )
        
    except ApiError:
        raise
    except Exception as exc:
        raise ApiError(
            "TAX_CONNECTION_FAILED",
            f"خطا در اتصال به سامانه: {str(exc)}",
            http_status=502,
            details={"error": str(exc)},
        ) from exc
    finally:
        try:
            client.close()
        except Exception as close_error:
            # لاگ می‌کنیم اما exception را propagate نمی‌کنیم
            import logging
            logger = logging.getLogger(__name__)
            logger.warning(f"Error closing MoadianClient during test connection: {close_error}")


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


