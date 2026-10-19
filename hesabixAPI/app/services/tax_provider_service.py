from __future__ import annotations

import base64
import json
import re
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import urlsplit

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.tax_provider import BusinessTaxProviderAccount, TaxProviderCredential
from adapters.db.models.tax_setting import TaxSetting
from adapters.db.models.user import User
from app.core.responses import ApiError
from app.integrations.fanava.client import FanavaApiError, FanavaClient
from app.services.ai.encryption import decrypt_api_key, encrypt_api_key

FANAVA_PROVIDER = "fanava"
DIRECT_PROVIDER = "moadian_direct"
FANAVA_BASE_URL = "https://avatsp.net"


def _encrypt(value: str | None) -> str | None:
    if not value:
        return None
    encrypted = encrypt_api_key(value)
    if not encrypted:
        raise ApiError("SECRET_ENCRYPTION_FAILED", "رمزنگاری اطلاعات اتصال مالیاتی ناموفق بود.", http_status=500)
    return encrypted


def _decrypt(value: str | None, label: str) -> str | None:
    if not value:
        return None
    decrypted = decrypt_api_key(value)
    if not decrypted:
        raise ApiError("SECRET_DECRYPTION_FAILED", f"بازیابی امن {label} ممکن نیست.", http_status=500)
    return decrypted


def get_provider_credential(db: Session, provider_code: str = FANAVA_PROVIDER) -> TaxProviderCredential | None:
    return (
        db.query(TaxProviderCredential)
        .filter(TaxProviderCredential.provider_code == provider_code)
        .first()
    )


def serialize_provider_credential(credential: TaxProviderCredential | None) -> dict[str, Any]:
    username = _decrypt(credential.username_encrypted, "نام کاربری بروکر") if credential else None
    return {
        "provider_code": credential.provider_code if credential else FANAVA_PROVIDER,
        "display_name": credential.display_name if credential else "همراه فن‌آوا",
        "base_url": credential.base_url if credential else FANAVA_BASE_URL,
        "username_masked": _mask(username),
        "username_configured": bool(username),
        "password_configured": bool(credential and credential.password_encrypted),
        "broker_code": credential.broker_code if credential else None,
        "contract_duration_days": credential.contract_duration_days if credential else 365,
        "is_active": bool(credential and credential.is_active),
        "updated_at": credential.updated_at.isoformat() if credential and credential.updated_at else None,
    }


def _mask(value: str | None) -> str | None:
    if not value:
        return None
    if len(value) <= 4:
        return "***"
    return f"{value[:2]}***{value[-2:]}"


def save_provider_credential(db: Session, payload: dict[str, Any]) -> TaxProviderCredential:
    base_url = str(payload.get("base_url") or FANAVA_BASE_URL).strip().rstrip("/")
    parsed = urlsplit(base_url)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise ApiError("INVALID_PROVIDER_URL", "نشانی API فن‌آوا باید HTTPS معتبر باشد.", http_status=400)
    if parsed.query or parsed.fragment:
        raise ApiError("INVALID_PROVIDER_URL", "نشانی API نباید query یا fragment داشته باشد.", http_status=400)

    username = str(payload.get("username") or "").strip()
    password = str(payload.get("password") or "")
    broker_code = payload.get("broker_code")
    try:
        broker_code = int(broker_code) if broker_code not in (None, "") else None
    except (TypeError, ValueError) as exc:
        raise ApiError("INVALID_BROKER_CODE", "کد بروکر باید عددی باشد.", http_status=400) from exc
    if broker_code is not None and broker_code <= 0:
        raise ApiError("INVALID_BROKER_CODE", "کد بروکر نامعتبر است.", http_status=400)

    try:
        duration = int(payload.get("contract_duration_days", 365))
    except (TypeError, ValueError) as exc:
        raise ApiError("INVALID_CONTRACT_DURATION", "مدت قرارداد باید عددی باشد.", http_status=400) from exc
    if duration < 1 or duration > 3650:
        raise ApiError("INVALID_CONTRACT_DURATION", "مدت قرارداد باید بین ۱ تا ۳۶۵۰ روز باشد.", http_status=400)

    credential = get_provider_credential(db)
    if credential is None:
        credential = TaxProviderCredential(
            provider_code=FANAVA_PROVIDER,
            display_name="همراه فن‌آوا",
            base_url=base_url,
            is_active=False,
            contract_duration_days=duration,
        )
        db.add(credential)
    credential.base_url = base_url
    credential.broker_code = broker_code
    credential.contract_duration_days = duration
    credential.is_active = payload.get("is_active") is True
    if username:
        credential.username_encrypted = _encrypt(username)
    if password:
        credential.password_encrypted = _encrypt(password)
    if not credential.username_encrypted or not credential.password_encrypted or not credential.broker_code:
        credential.is_active = False
    db.flush()
    return credential


def _read_provider_secrets(credential: TaxProviderCredential) -> tuple[str, str]:
    username = _decrypt(credential.username_encrypted, "نام کاربری بروکر")
    password = _decrypt(credential.password_encrypted, "رمز بروکر")
    if not username or not password:
        raise ApiError("TAX_PROVIDER_NOT_CONFIGURED", "اعتبارنامهٔ بروکر فن‌آوا در مدیریت سیستم کامل نیست.", http_status=503)
    return username, password


def test_provider_connection(db: Session) -> dict[str, Any]:
    credential = get_provider_credential(db)
    if credential is None:
        raise ApiError("TAX_PROVIDER_NOT_CONFIGURED", "ابتدا اعتبارنامهٔ فن‌آوا را در مدیریت سیستم ثبت کنید.", http_status=400)
    username, password = _read_provider_secrets(credential)
    client = FanavaClient(credential.base_url, username=username, password=password)
    try:
        token = client.login(username, password)
        response = client.broker_list(token)
        brokers = response.get("data") if isinstance(response.get("data"), list) else []
        return {
            "connected": True,
            "broker_code_configured": bool(credential.broker_code),
            "broker_count": len(brokers),
            "active_broker_count": sum(1 for item in brokers if isinstance(item, dict) and item.get("isActive") is True),
        }
    except FanavaApiError as exc:
        raise ApiError("TAX_PROVIDER_CONNECTION_FAILED", str(exc), http_status=502) from exc
    finally:
        client.close()


def get_business_provider_state(db: Session, business_id: int) -> dict[str, Any]:
    setting = db.query(TaxSetting).filter(TaxSetting.business_id == int(business_id)).first()
    business = db.query(Business).filter(Business.id == int(business_id)).first()
    owner = db.query(User).filter(User.id == int(business.owner_id)).first() if business else None
    # Lock the business row as the serialization point when the provider-account
    # row does not exist yet. This prevents two consent requests from racing to
    # create the same taxpayer twice at Fanava.
    business = (
        db.query(Business)
        .filter(Business.id == int(business_id))
        .with_for_update()
        .first()
    )
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار پیدا نشد.", http_status=404)

    account = (
        db.query(BusinessTaxProviderAccount)
        .filter_by(business_id=int(business_id), provider_code=FANAVA_PROVIDER)
        .first()
    )
    credential = get_provider_credential(db)
    from app.services.motamed_asa_provider_service import motamed_asa_provider_state

    return {
        **motamed_asa_provider_state(db, int(business_id)),
        "submission_provider": setting.submission_provider if setting else DIRECT_PROVIDER,
        "fanava_available": bool(credential and credential.is_active and credential.username_encrypted and credential.password_encrypted and credential.broker_code),
        "enrollment_prefill": {
            "first_name": owner.first_name if owner else None,
            "last_name": owner.last_name if owner else None,
            "phone_number": (owner.mobile if owner else None) or (business.mobile if business else None) or (business.phone if business else None),
            "national_code": (business.national_id if business and getattr(business.business_type, "name", "") == "INDIVIDUAL" else None),
            "economic_code": setting.economic_code if setting else (business.economic_id if business else None),
            "memory_number": setting.tax_memory_id if setting else None,
        },
        "fanava_account": {
            "status": account.status,
            "connected": account.status == "connected" and bool(account.cartable_id and account.memory_id),
            "cartable_id": account.cartable_id,
            "memory_id": account.memory_id,
            "memory_number": account.memory_number,
            "last_error": account.last_error if account.status in {"failed", "registration_unknown", "needs_attention"} else None,
            "registered_at": account.registered_at.isoformat() if account.registered_at else None,
        } if account else None,
    }


def _latin_digits(value: Any) -> str:
    text = str(value or "").strip()
    table = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
    return text.translate(table)


def _normalize_iranian_mobile(value: Any) -> str:
    raw = _latin_digits(value)
    if not re.fullmatch(r"[0-9+()\-\s]+", raw):
        return ""
    digits = re.sub(r"\D", "", raw)
    if digits.startswith("0098") and len(digits) == 14:
        return "0" + digits[4:]
    if digits.startswith("98") and len(digits) == 12:
        return "0" + digits[2:]
    if len(digits) == 10 and digits.startswith("9"):
        return "0" + digits
    return digits


def _is_valid_iranian_national_code(value: str) -> bool:
    if not re.fullmatch(r"\d{10}", value) or len(set(value)) == 1:
        return False
    checksum = sum(int(value[index]) * (10 - index) for index in range(9)) % 11
    check_digit = int(value[9])
    return check_digit == checksum if checksum < 2 else check_digit == 11 - checksum


def _account_token_expiry(token: str) -> datetime:
    try:
        encoded = token.split(".")[1]
        payload = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
        if payload.get("exp"):
            return datetime.fromtimestamp(int(payload["exp"]), tz=timezone.utc).replace(tzinfo=None)
    except Exception:
        pass
    # Fanava documents login tokens as 24-hour credentials. Never extend a
    # token just because the broker contract lasts longer.
    return datetime.utcnow() + timedelta(hours=23)


def _set_account_token(account: BusinessTaxProviderAccount, token: str, _contract_duration_days: int) -> None:
    account.access_token_encrypted = _encrypt(token)
    account.token_expires_at = _account_token_expiry(token)
    account.last_synced_at = datetime.utcnow()


def _account_login(db: Session, client: FanavaClient, account: BusinessTaxProviderAccount, credential: TaxProviderCredential) -> str:
    username = _decrypt(account.username_encrypted, "شناسه ورود کسب‌وکار فن‌آوا")
    password = _decrypt(account.password_encrypted, "رمز کسب‌وکار فن‌آوا")
    if not username or not password:
        raise ApiError("FANAVA_ACCOUNT_CREDENTIALS_MISSING", "اطلاعات لازم برای تمدید اتصال فن‌آوا موجود نیست.", http_status=409)
    try:
        token = client.login(username, password)
    except FanavaApiError as exc:
        raise ApiError("FANAVA_REAUTH_FAILED", "تمدید دسترسی حساب فن‌آوا ناموفق بود؛ پشتیبانی باید اتصال را بررسی کند.", http_status=502) from exc
    _set_account_token(account, token, credential.contract_duration_days)
    db.flush()
    return token


def _ensure_business_token(db: Session, client: FanavaClient, account: BusinessTaxProviderAccount, credential: TaxProviderCredential) -> str:
    expires = account.token_expires_at
    token = _decrypt(account.access_token_encrypted, "توکن فن‌آوا")
    if token and expires is not None and expires > datetime.utcnow() + timedelta(minutes=2):
        return token
    return _account_login(db, client, account, credential)


def call_as_business(
    db: Session,
    client: FanavaClient,
    account: BusinessTaxProviderAccount,
    credential: TaxProviderCredential,
    operation,
):
    token = _ensure_business_token(db, client, account, credential)
    try:
        return operation(token)
    except FanavaApiError as exc:
        if exc.status_code != 401:
            raise
        token = _account_login(db, client, account, credential)
        return operation(token)


def _account_for(db: Session, business_id: int) -> tuple[TaxProviderCredential, BusinessTaxProviderAccount]:
    credential = get_provider_credential(db)
    account = (
        db.query(BusinessTaxProviderAccount)
        .filter_by(business_id=int(business_id), provider_code=FANAVA_PROVIDER)
        .first()
    )
    if not credential or not credential.is_active:
        raise ApiError("TAX_PROVIDER_NOT_CONFIGURED", "ارسال از طریق فن‌آوا در مدیریت سیستم فعال نیست.", http_status=503)
    if not account or account.status != "connected" or not account.cartable_id or not account.memory_id:
        raise ApiError("FANAVA_ACCOUNT_NOT_CONNECTED", "حساب مالیاتی این کسب‌وکار در فن‌آوا هنوز فعال نشده است.", http_status=409)
    _read_provider_secrets(credential)
    return credential, account


def _find_business_cartable(client: FanavaClient, token: str, economic_code: str, memory_number: str) -> tuple[int, int] | None:
    economic_code = _latin_digits(economic_code)
    memory_number = _latin_digits(memory_number)
    for page in range(10):
        result = client.list_cartables(token, page=page, size=50)
        items = result.get("data") if isinstance(result.get("data"), list) else []
        if not items:
            break
        for item in items:
            if not isinstance(item, dict) or _latin_digits(item.get("economicCode")) != economic_code:
                continue
            cartable_id = item.get("id")
            if not cartable_id:
                continue
            result_memories = client.list_memories(token, int(cartable_id), page=0, size=50)
            memories = result_memories.get("data") if isinstance(result_memories.get("data"), list) else []
            match = next((m for m in memories if isinstance(m, dict) and _latin_digits(m.get("number")) == memory_number), None)
            if match and match.get("id"):
                return int(cartable_id), int(match["id"])
    return None


def _try_reconcile_registration(db: Session, account: BusinessTaxProviderAccount, credential: TaxProviderCredential, tax_setting: TaxSetting) -> bool:
    username = _decrypt(account.username_encrypted, "شناسه ورود کسب‌وکار فن‌آوا")
    password = _decrypt(account.password_encrypted, "رمز کسب‌وکار فن‌آوا")
    if not username or not password:
        return False
    client = FanavaClient(credential.base_url, username=_read_provider_secrets(credential)[0], password=_read_provider_secrets(credential)[1])
    try:
        token = client.login(username, password)
        match = _find_business_cartable(client, token, tax_setting.economic_code or "", tax_setting.tax_memory_id or "")
        if not match:
            account.status = "registration_unknown"
            account.last_error = "ثبت در فن‌آوا تأیید نشد؛ برای جلوگیری از ثبت تکراری، ثبت دوباره به‌صورت خودکار انجام نمی‌شود."
            db.commit()
            return False
        account.cartable_id, account.memory_id = match
        account.memory_number = tax_setting.tax_memory_id
        account.status = "connected"
        account.last_error = None
        account.registered_at = account.registered_at or datetime.utcnow()
        _set_account_token(account, token, credential.contract_duration_days)
        db.commit()
        return True
    except FanavaApiError:
        account.status = "registration_unknown"
        account.last_error = "نتیجهٔ ثبت در فن‌آوا نامشخص است؛ اتصال باید دوباره بررسی شود."
        db.commit()
        return False
    finally:
        client.close()


def select_business_provider(
    db: Session,
    *,
    business_id: int,
    provider_code: str,
    consent: bool = False,
    consented_by_user_id: int | None = None,
    enrollment: dict[str, Any] | None = None,
) -> dict[str, Any]:
    provider_code = str(provider_code or "").strip().lower()
    from app.services.motamed_asa_provider_service import MOTAMED_ASA_PROVIDER, start_motamed_asa_onboarding

    if provider_code == MOTAMED_ASA_PROVIDER:
        # ASA signs as the trusted company: the business's own private key and memory id are not needed.
        return start_motamed_asa_onboarding(
            db,
            business_id=int(business_id),
            consent=consent,
            consented_by_user_id=consented_by_user_id,
            economic_code=(enrollment or {}).get("economic_code"),
        )
    if provider_code not in {DIRECT_PROVIDER, FANAVA_PROVIDER}:
        raise ApiError("INVALID_TAX_PROVIDER", "روش ارسال مالیاتی نامعتبر است.", http_status=400)
    setting = db.query(TaxSetting).filter(TaxSetting.business_id == int(business_id)).first()
    if not setting or not (setting.economic_code and setting.tax_memory_id and setting.private_key):
        raise ApiError("TAX_SETTINGS_INCOMPLETE", "ابتدا کد اقتصادی، شناسه حافظه و کلید امضای همین کسب‌وکار را در تنظیمات مودیان کامل کنید.", http_status=400)
    if provider_code == DIRECT_PROVIDER:
        setting.submission_provider = DIRECT_PROVIDER
        db.commit()
        return get_business_provider_state(db, business_id)
    if setting.sandbox_mode:
        raise ApiError(
            "FANAVA_SANDBOX_UNAVAILABLE",
            "فن‌آوا محیط آزمایشی ندارد؛ برای انتخاب این روش، حالت آزمایشی ارسال مستقیم را خاموش کنید.",
            http_status=400,
        )
    if not consent:
        raise ApiError("FANAVA_CONSENT_REQUIRED", "برای ثبت کاربر این کسب‌وکار در بروکر فن‌آوا، تأیید صریح لازم است.", http_status=400)

    credential = get_provider_credential(db)
    if not credential or not credential.is_active:
        raise ApiError("TAX_PROVIDER_NOT_CONFIGURED", "فن‌آوا هنوز در مدیریت سیستم پیکربندی و فعال نشده است.", http_status=503)
    broker_username, broker_password = _read_provider_secrets(credential)
    if not credential.broker_code:
        raise ApiError("FANAVA_BROKER_CODE_MISSING", "کد بروکر فن‌آوا در مدیریت سیستم ثبت نشده است.", http_status=503)

    account = (
        db.query(BusinessTaxProviderAccount)
        .filter_by(business_id=int(business_id), provider_code=FANAVA_PROVIDER)
        .with_for_update()
        .first()
    )
    if account and account.status == "connected" and account.cartable_id and account.memory_id:
        setting.submission_provider = FANAVA_PROVIDER
        db.commit()
        return get_business_provider_state(db, business_id)
    if account and account.status == "registering":
        updated_at = account.updated_at
        if updated_at is not None and (datetime.utcnow() - updated_at).total_seconds() < 120:
            raise ApiError(
                "FANAVA_REGISTRATION_IN_PROGRESS",
                "درخواست ثبت فن‌آوا هنوز در حال اجراست؛ کمی بعد وضعیت اتصال را بررسی کنید.",
                http_status=409,
            )
    if account and account.status in {"registering", "registration_unknown"}:
        if _try_reconcile_registration(db, account, credential, setting):
            setting.submission_provider = FANAVA_PROVIDER
            db.commit()
            return get_business_provider_state(db, business_id)
        raise ApiError("FANAVA_REGISTRATION_UNCERTAIN", account.last_error or "وضعیت ثبت در فن‌آوا نامشخص است.", http_status=409)

    owner = db.query(User).filter(User.id == int(business.owner_id)).first()
    enrollment = enrollment or {}
    first_name = str(enrollment.get("first_name") or (owner.first_name if owner else "") or "").strip()
    last_name = str(enrollment.get("last_name") or (owner.last_name if owner else "") or "").strip()
    father_name = str(enrollment.get("father_name") or "").strip()
    national_code = _latin_digits(enrollment.get("national_code"))
    identification_number = _latin_digits(enrollment.get("identification_number"))
    birth_date = _latin_digits(enrollment.get("birth_date")).replace("-", "/")
    phone_number = _normalize_iranian_mobile(
        enrollment.get("phone_number") or ((owner.mobile if owner else None) or business.mobile or business.phone)
    )
    missing = [
        label for label, value in (
            ("نام مالک", first_name), ("نام خانوادگی مالک", last_name), ("نام پدر", father_name),
            ("کد ملی مالک", national_code), ("شماره شناسنامه", identification_number),
            ("تاریخ تولد شمسی", birth_date), ("تلفن همراه", phone_number),
            ("کد اقتصادی", setting.economic_code), ("شماره حافظه مالیاتی", setting.tax_memory_id),
        ) if not value
    ]
    if missing:
        raise ApiError(
            "FANAVA_ENROLLMENT_DATA_MISSING",
            "برای ثبت خودکار در فن‌آوا چند مشخصهٔ الزامی نیاز است.",
            http_status=400,
            details={"missing_fields": missing},
        )
    if not _is_valid_iranian_national_code(national_code):
        raise ApiError("FANAVA_INVALID_NATIONAL_CODE", "کد ملی مالک باید ۱۰ رقم باشد.", http_status=400)
    if not re.fullmatch(r"09\d{9}", phone_number):
        raise ApiError("FANAVA_INVALID_PHONE", "شمارهٔ تماس فن‌آوا معتبر نیست.", http_status=400)
    try:
        import jdatetime
        parts = [int(part) for part in birth_date.split("/")]
        if len(parts) != 3:
            raise ValueError
        jdatetime.date(*parts)
    except Exception as exc:
        raise ApiError("FANAVA_INVALID_BIRTH_DATE", "تاریخ تولد را به شکل سال/ماه/روز شمسی وارد کنید.", http_status=400) from exc

    generated_password = secrets.token_urlsafe(32)
    if account is None:
        account = BusinessTaxProviderAccount(business_id=int(business_id), provider_code=FANAVA_PROVIDER)
        db.add(account)
    account.status = "registering"
    account.last_error = None
    account.cartable_id = None
    account.memory_id = None
    account.memory_number = setting.tax_memory_id
    account.consented_by_user_id = consented_by_user_id
    account.consented_at = datetime.utcnow()
    account.username_encrypted = _encrypt(national_code)
    account.password_encrypted = _encrypt(generated_password)
    account.access_token_encrypted = None
    account.token_expires_at = None
    db.flush()
    # Persist the guard before the external registration: retrying a timed-out POST can create duplicates.
    db.commit()

    payload = {
        "firstName": first_name,
        "lastName": last_name,
        "fatherName": father_name,
        "economicCode": _latin_digits(setting.economic_code),
        "memoryNumber": _latin_digits(setting.tax_memory_id),
        "nationalCode": national_code,
        "identificationNumber": identification_number,
        "birthDate": birth_date,
        "phoneNumber": phone_number,
        "brokerCode": int(credential.broker_code),
        "password": generated_password,
        "contractDuration": int(credential.contract_duration_days),
    }
    client = FanavaClient(credential.base_url, username=broker_username, password=broker_password)
    try:
        result = client.register_user(payload)
        cartable_id = result.get("cartableId")
        memory_id = result.get("memoryId")
        access_token = result.get("token")
        if not cartable_id or not memory_id:
            account.status = "registration_unknown"
            account.last_error = "فن‌آوا پاسخ ثبت را بدون شناسهٔ پرونده یا حافظه برگرداند."
            db.commit()
            raise ApiError("FANAVA_INVALID_REGISTRATION_RESPONSE", account.last_error, http_status=502)
        account.cartable_id = int(cartable_id)
        account.memory_id = int(memory_id)
        account.memory_number = setting.tax_memory_id
        account.status = "connected"
        account.last_error = None
        account.registered_at = datetime.utcnow()
        if access_token:
            _set_account_token(account, str(access_token), credential.contract_duration_days)
        else:
            _account_login(db, client, account, credential)
        setting.submission_provider = FANAVA_PROVIDER
        db.commit()
        return get_business_provider_state(db, business_id)
    except ApiError:
        raise
    except FanavaApiError as exc:
        if exc.code in {"TIMEOUT", "NETWORK_ERROR"} or (exc.status_code is not None and exc.status_code >= 500):
            account.status = "registration_unknown"
            account.last_error = "پاسخ ثبت فن‌آوا دریافت نشد؛ برای جلوگیری از ثبت دوباره، وضعیت حساب بررسی می‌شود."
            db.commit()
            if _try_reconcile_registration(db, account, credential, setting):
                setting.submission_provider = FANAVA_PROVIDER
                db.commit()
                return get_business_provider_state(db, business_id)
            raise ApiError("FANAVA_REGISTRATION_UNCERTAIN", account.last_error, http_status=409) from exc
        account.status = "failed"
        account.last_error = str(exc)[:500]
        db.commit()
        raise ApiError("FANAVA_REGISTRATION_FAILED", str(exc), http_status=exc.status_code or 400) from exc
    finally:
        client.close()


def get_fanava_client_for_business(db: Session, business_id: int) -> tuple[FanavaClient, BusinessTaxProviderAccount, TaxProviderCredential]:
    credential, account = _account_for(db, business_id)
    username, password = _read_provider_secrets(credential)
    return FanavaClient(credential.base_url, username=username, password=password), account, credential


def fanava_business_call(db: Session, business_id: int, operation):
    client, account, credential = get_fanava_client_for_business(db, business_id)
    try:
        return call_as_business(db, client, account, credential, lambda token: operation(client, token, account))
    except FanavaApiError as exc:
        raise ApiError("FANAVA_API_FAILED", str(exc), http_status=exc.status_code or 502) from exc
    finally:
        client.close()


def sync_business_fanava_account(db: Session, business_id: int) -> dict[str, Any]:
    client, account, credential = get_fanava_client_for_business(db, business_id)
    setting = db.query(TaxSetting).filter_by(business_id=int(business_id)).first()
    try:
        token = _ensure_business_token(db, client, account, credential)
        match = _find_business_cartable(client, token, setting.economic_code or "", setting.tax_memory_id or "")
        if not match:
            raise ApiError("FANAVA_ACCOUNT_NOT_FOUND", "پرونده و حافظهٔ متناظر در کارتابل فن‌آوا پیدا نشد.", http_status=404)
        account.cartable_id, account.memory_id = match
        account.memory_number = setting.tax_memory_id
        account.status = "connected"
        account.last_error = None
        account.last_synced_at = datetime.utcnow()
        db.commit()
        return get_business_provider_state(db, business_id)
    except FanavaApiError as exc:
        raise ApiError("FANAVA_API_FAILED", str(exc), http_status=exc.status_code or 502) from exc
    finally:
        client.close()
