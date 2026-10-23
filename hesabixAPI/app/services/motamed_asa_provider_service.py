"""
اتصال کسب‌وکار به ارائه‌دهندهٔ مالیاتی «معتمد آسا».

The business signs up on ASA's own hosted page (its owner signs in with the tax
organisation's one-time code and agrees there to hand the API key to Hesabix);
Hesabix never collects identity documents for ASA. The partner credential
(client id/secret of Hesabix in ASA's «همکاران API») lives in
tax_provider_credentials; each business's own client id/secret, ASA company id
and fiscal memory id live in business_tax_provider_accounts.
"""
from __future__ import annotations

import re
from datetime import datetime, timedelta
from typing import Any, Callable, TypeVar
from urllib.parse import urlsplit

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.tax_provider import BusinessTaxProviderAccount, TaxProviderCredential
from adapters.db.models.tax_setting import TaxSetting
from adapters.db.models.user import User
from app.core.responses import ApiError
from app.integrations.motamed_asa.client import DEFAULT_BASE_URL, MotamedAsaApiError, MotamedAsaClient
from app.services.tax_provider_service import (
    _decrypt,
    _encrypt,
    _latin_digits,
    _mask,
    _normalize_iranian_mobile,
    get_provider_credential,
)

T = TypeVar("T")

MOTAMED_ASA_PROVIDER = "motamed_asa"
MOTAMED_ASA_DISPLAY_NAME = "معتمد آسا"
MOTAMED_ASA_BASE_URL = DEFAULT_BASE_URL

_REFERENCE_PREFIX = "hesabix-business-"
_CUSTOMER_CLIENT_ID = re.compile(r"^v2-customer-(\d{1,10})$")
_OPEN_SESSION_STATUSES = {"created", "opened", "in_progress"}
_READY_SESSION_STATUSES = {"business_ready", "completed"}
_TOKEN_REFRESH_MARGIN = timedelta(minutes=2)

# business_tax_provider_accounts.status values used for this provider
STATUS_NOT_CONNECTED = "not_connected"
STATUS_ONBOARDING = "onboarding"
STATUS_CREDENTIALS_REQUIRED = "credentials_required"
STATUS_CONNECTED = "connected"

_MESSAGE_EXISTING_CREDENTIALS = (
    "این کسب‌وکار پیش‌تر کلید API نسخهٔ ۲ معتمد آسا داشته و کلید تازه‌ای تحویل نشد. "
    "شناسه و رمز کلاینت را از پنل معتمد آسا (تنظیمات کسب‌وکار › API نسخه ۲) وارد کنید."
)
_MESSAGE_CREDENTIALS_CLAIMED = (
    "کلید API این کسب‌وکار پیش‌تر تحویل شده و دوباره نمایش داده نمی‌شود. "
    "در پنل معتمد آسا (تنظیمات کسب‌وکار › API نسخه ۲) رمز تازه بسازید و شناسه و رمز را اینجا وارد کنید."
)
_MESSAGE_CREDENTIALS_NOT_ALLOWED = (
    "مالک کسب‌وکار در صفحهٔ ثبت‌نام معتمد آسا تحویل کلید API به حسابیکس را تأیید نکرد. "
    "می‌توانید دوباره لینک ثبت‌نام را باز کنید یا شناسه و رمز کلاینت را از پنل معتمد آسا وارد کنید."
)
_MESSAGE_SESSION_CLOSED = "لینک ثبت‌نام معتمد آسا منقضی یا لغو شده است؛ برای ادامه، لینک تازه بگیرید."


# --- System-wide credential (admin) ---------------------------------------------------------


def get_motamed_asa_credential(db: Session) -> TaxProviderCredential | None:
    return get_provider_credential(db, MOTAMED_ASA_PROVIDER)


def motamed_asa_available(credential: TaxProviderCredential | None) -> bool:
    return bool(
        credential
        and credential.is_active
        and credential.username_encrypted
        and credential.password_encrypted
    )


def serialize_motamed_asa_credential(credential: TaxProviderCredential | None) -> dict[str, Any]:
    client_id = _decrypt(credential.username_encrypted, "شناسه کلاینت همکار") if credential else None
    return {
        "provider_code": MOTAMED_ASA_PROVIDER,
        "display_name": credential.display_name if credential else MOTAMED_ASA_DISPLAY_NAME,
        "base_url": credential.base_url if credential else MOTAMED_ASA_BASE_URL,
        "client_id_masked": _mask(client_id),
        "client_id_configured": bool(client_id),
        "client_secret_configured": bool(credential and credential.password_encrypted),
        "is_active": bool(credential and credential.is_active),
        "updated_at": credential.updated_at.isoformat() if credential and credential.updated_at else None,
    }


def save_motamed_asa_credential(db: Session, payload: dict[str, Any]) -> TaxProviderCredential:
    base_url = str(payload.get("base_url") or MOTAMED_ASA_BASE_URL).strip().rstrip("/")
    parsed = urlsplit(base_url)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise ApiError("INVALID_PROVIDER_URL", "نشانی API معتمد آسا باید HTTPS معتبر باشد.", http_status=400)
    if parsed.query or parsed.fragment or parsed.path not in ("", "/"):
        raise ApiError("INVALID_PROVIDER_URL", "نشانی API معتمد آسا فقط دامنه است و مسیر، query یا fragment ندارد.", http_status=400)

    client_id = str(payload.get("client_id") or "").strip()
    client_secret = str(payload.get("client_secret") or "")
    if client_id and not client_id.startswith("v2-partner-"):
        raise ApiError("INVALID_CLIENT_ID", "شناسه کلاینت همکار باید با v2-partner- شروع شود.", http_status=400)

    credential = get_motamed_asa_credential(db)
    if credential is None:
        credential = TaxProviderCredential(
            provider_code=MOTAMED_ASA_PROVIDER,
            display_name=MOTAMED_ASA_DISPLAY_NAME,
            base_url=base_url,
            is_active=False,
        )
        db.add(credential)
    credential.base_url = base_url
    credential.is_active = payload.get("is_active") is True
    if client_id:
        credential.username_encrypted = _encrypt(client_id)
    if client_secret:
        credential.password_encrypted = _encrypt(client_secret)
    if not credential.username_encrypted or not credential.password_encrypted:
        credential.is_active = False
    db.flush()
    return credential


def _partner_secrets(credential: TaxProviderCredential) -> tuple[str, str]:
    client_id = _decrypt(credential.username_encrypted, "شناسه کلاینت همکار")
    client_secret = _decrypt(credential.password_encrypted, "رمز کلاینت همکار")
    if not client_id or not client_secret:
        raise ApiError(
            "TAX_PROVIDER_NOT_CONFIGURED",
            "شناسه و رمز کلاینت حسابیکس در معتمد آسا در مدیریت سیستم کامل نیست.",
            http_status=503,
        )
    return client_id, client_secret


def _partner_token(client: MotamedAsaClient, credential: TaxProviderCredential) -> str:
    client_id, client_secret = _partner_secrets(credential)
    token, _ = client.issue_token(client_id, client_secret)
    return token


def test_motamed_asa_connection(db: Session) -> dict[str, Any]:
    credential = get_motamed_asa_credential(db)
    if credential is None:
        raise ApiError("TAX_PROVIDER_NOT_CONFIGURED", "ابتدا شناسه و رمز کلاینت معتمد آسا را ثبت کنید.", http_status=400)
    client = MotamedAsaClient(credential.base_url)
    try:
        profile = client.partner_profile(_partner_token(client, credential))
        capabilities = profile.get("capabilities") if isinstance(profile.get("capabilities"), dict) else {}
        return {
            "connected": True,
            "partner_status": profile.get("status"),
            "display_name": profile.get("displayName"),
            "hosted_onboarding": capabilities.get("hostedOnboarding") is True,
            "credential_handover": capabilities.get("credentialHandover") is True,
            "default_return_url": profile.get("defaultReturnUrl"),
        }
    except MotamedAsaApiError as exc:
        raise ApiError("TAX_PROVIDER_CONNECTION_FAILED", str(exc), http_status=502) from exc
    finally:
        client.close()


# --- Business account ---------------------------------------------------------------------


def _get_account(db: Session, business_id: int, *, lock: bool = False) -> BusinessTaxProviderAccount | None:
    query = db.query(BusinessTaxProviderAccount).filter_by(
        business_id=int(business_id), provider_code=MOTAMED_ASA_PROVIDER
    )
    if lock:
        query = query.with_for_update()
    return query.first()


def _is_connected(account: BusinessTaxProviderAccount | None) -> bool:
    return bool(
        account
        and account.status == STATUS_CONNECTED
        and account.username_encrypted
        and account.password_encrypted
    )


def serialize_motamed_asa_account(account: BusinessTaxProviderAccount | None) -> dict[str, Any] | None:
    if account is None:
        return None
    return {
        "status": account.status,
        "connected": _is_connected(account),
        "company_id": account.cartable_id,
        "memory_unique_id": account.memory_number,
        "last_error": account.last_error if account.status != STATUS_CONNECTED else None,
        "consented_at": account.consented_at.isoformat() if account.consented_at else None,
        "registered_at": account.registered_at.isoformat() if account.registered_at else None,
        "last_synced_at": account.last_synced_at.isoformat() if account.last_synced_at else None,
    }


def motamed_asa_provider_state(db: Session, business_id: int) -> dict[str, Any]:
    return {
        "motamed_asa_available": motamed_asa_available(get_motamed_asa_credential(db)),
        "motamed_asa_account": serialize_motamed_asa_account(_get_account(db, business_id)),
    }


def _require_active_credential(db: Session) -> TaxProviderCredential:
    credential = get_motamed_asa_credential(db)
    if not motamed_asa_available(credential):
        raise ApiError(
            "TAX_PROVIDER_NOT_CONFIGURED",
            "ارسال از طریق معتمد آسا هنوز در مدیریت سیستم فعال نشده است.",
            http_status=503,
        )
    return credential  # type: ignore[return-value]


def _onboarding_reference(business_id: int) -> str:
    return f"{_REFERENCE_PREFIX}{int(business_id)}"


def _latest_session(client: MotamedAsaClient, token: str, business_id: int) -> dict[str, Any] | None:
    sessions = client.list_onboarding_sessions(token, reference=_onboarding_reference(business_id))
    if not sessions:
        return None
    return max(sessions, key=lambda item: str(item.get("createdAt") or ""))


def _ensure_economic_code(db: Session, business_id: int, setting: TaxSetting | None, economic_code: str | None, user_id: int | None) -> TaxSetting:
    requested = _latin_digits(economic_code)
    if setting is not None and setting.economic_code:
        saved = _latin_digits(setting.economic_code)
        if requested and requested != saved:
            raise ApiError(
                "TAX_SETTINGS_UNSAVED",
                "کد اقتصادی واردشده با کد ذخیره‌شده یکی نیست؛ ابتدا تنظیمات را ذخیره کنید.",
                http_status=400,
            )
        return setting
    if not re.fullmatch(r"\d{11}|\d{14}", requested or ""):
        raise ApiError(
            "TAX_SETTINGS_INCOMPLETE",
            "برای اتصال به معتمد آسا ابتدا کد اقتصادی ۱۱ یا ۱۴ رقمی کسب‌وکار را وارد کنید.",
            http_status=400,
        )
    if setting is None:
        setting = TaxSetting(business_id=int(business_id), created_by_user_id=user_id)
        db.add(setting)
    setting.economic_code = requested
    db.flush()
    return setting


def _session_body(db: Session, business: Business, setting: TaxSetting) -> dict[str, Any]:
    owner = db.query(User).filter(User.id == int(business.owner_id)).first()
    mobile = _normalize_iranian_mobile((owner.mobile if owner else None) or business.mobile)
    body: dict[str, Any] = {
        "economicCode": _latin_digits(setting.economic_code),
        "businessName": (business.name or "")[:200] or None,
        "reference": _onboarding_reference(int(business.id)),
        "issueMemoryUniqueId": True,
        "requestCredentials": True,
    }
    if re.fullmatch(r"09\d{9}", mobile or ""):
        body["mobile"] = mobile
    return {key: value for key, value in body.items() if value is not None}


def _onboarding_link(session: dict[str, Any]) -> dict[str, Any] | None:
    url = session.get("url")
    if not url:
        return None
    return {
        "url": url,
        "expires_at": session.get("expiresAt"),
        "session_status": session.get("status"),
    }


def _store_business_credentials(
    db: Session,
    account: BusinessTaxProviderAccount,
    setting: TaxSetting | None,
    *,
    client_id: str,
    client_secret: str,
    company_id: int | None,
    memory_unique_id: str | None,
) -> None:
    account.username_encrypted = _encrypt(client_id)
    account.password_encrypted = _encrypt(client_secret)
    account.access_token_encrypted = None
    account.token_expires_at = None
    if company_id:
        account.cartable_id = int(company_id)
    if memory_unique_id:
        account.memory_number = str(memory_unique_id)
    account.status = STATUS_CONNECTED
    account.last_error = None
    account.registered_at = account.registered_at or datetime.utcnow()
    account.last_synced_at = datetime.utcnow()
    if setting is not None:
        setting.submission_provider = MOTAMED_ASA_PROVIDER
    # The handover secret is shown once: persist it before anything else can fail.
    db.commit()


def _complete_from_session(
    db: Session,
    client: MotamedAsaClient,
    token: str,
    account: BusinessTaxProviderAccount,
    setting: TaxSetting | None,
    session: dict[str, Any],
) -> None:
    business = session.get("business") if isinstance(session.get("business"), dict) else {}
    memory = session.get("memory") if isinstance(session.get("memory"), dict) else {}
    credentials = session.get("credentials") if isinstance(session.get("credentials"), dict) else {}
    if business.get("companyId"):
        account.cartable_id = int(business["companyId"])
    if memory.get("memoryUniqueId"):
        account.memory_number = str(memory["memoryUniqueId"])

    if credentials.get("available") is True and credentials.get("claimed") is not True:
        try:
            handed = client.claim_credentials(token, str(session["sessionId"]))
        except MotamedAsaApiError as exc:
            if exc.status_code == 409 and exc.code == "credentials_already_claimed":
                account.status = STATUS_CREDENTIALS_REQUIRED
                account.last_error = _MESSAGE_CREDENTIALS_CLAIMED
                db.commit()
                return
            raise
        secret = handed.get("clientSecret")
        if handed.get("secretIssued") is True and secret:
            _store_business_credentials(
                db,
                account,
                setting,
                client_id=str(handed.get("clientId") or ""),
                client_secret=str(secret),
                company_id=handed.get("companyId") or business.get("companyId"),
                memory_unique_id=memory.get("memoryUniqueId"),
            )
            return
        account.status = STATUS_CREDENTIALS_REQUIRED
        account.last_error = _MESSAGE_EXISTING_CREDENTIALS
    elif credentials.get("claimed") is True:
        account.status = STATUS_CREDENTIALS_REQUIRED
        account.last_error = _MESSAGE_CREDENTIALS_CLAIMED
    else:
        account.status = STATUS_CREDENTIALS_REQUIRED
        account.last_error = _MESSAGE_CREDENTIALS_NOT_ALLOWED
    account.last_synced_at = datetime.utcnow()
    db.commit()


def _apply_session(
    db: Session,
    client: MotamedAsaClient,
    token: str,
    account: BusinessTaxProviderAccount,
    setting: TaxSetting | None,
    session: dict[str, Any] | None,
) -> None:
    status = str((session or {}).get("status") or "")
    if session is None:
        account.status = STATUS_NOT_CONNECTED
        account.last_error = None
    elif status in _READY_SESSION_STATUSES:
        _complete_from_session(db, client, token, account, setting, session)
        return
    elif status in _OPEN_SESSION_STATUSES:
        account.status = STATUS_ONBOARDING
        last_error = session.get("lastError") if isinstance(session.get("lastError"), dict) else None
        account.last_error = str(last_error.get("message"))[:500] if last_error and last_error.get("message") else None
    else:
        account.status = STATUS_NOT_CONNECTED
        account.last_error = _MESSAGE_SESSION_CLOSED
    account.last_synced_at = datetime.utcnow()
    db.commit()


def start_motamed_asa_onboarding(
    db: Session,
    *,
    business_id: int,
    consent: bool,
    consented_by_user_id: int | None,
    economic_code: str | None = None,
) -> dict[str, Any]:
    """
    Selects «معتمد آسا» for the business. A connected account switches at once;
    otherwise a hosted sign-up link on ASA is returned under "motamed_asa_onboarding".
    """
    if not consent:
        raise ApiError(
            "MOTAMED_ASA_CONSENT_REQUIRED",
            "برای اتصال به معتمد آسا، تأیید صریح شما لازم است.",
            http_status=400,
        )
    credential = _require_active_credential(db)
    # The business row is the serialisation point, as for the other providers.
    business = db.query(Business).filter(Business.id == int(business_id)).with_for_update().first()
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار پیدا نشد.", http_status=404)
    setting = db.query(TaxSetting).filter(TaxSetting.business_id == int(business_id)).first()
    setting = _ensure_economic_code(db, business_id, setting, economic_code, consented_by_user_id)
    if setting.sandbox_mode:
        raise ApiError(
            "MOTAMED_ASA_SANDBOX_UNAVAILABLE",
            "ارسال از طریق معتمد آسا فقط در محیط اصلی سامانهٔ مؤدیان انجام می‌شود؛ حالت آزمایشی را خاموش کنید.",
            http_status=400,
        )

    account = _get_account(db, business_id, lock=True)
    if account is None:
        account = BusinessTaxProviderAccount(business_id=int(business_id), provider_code=MOTAMED_ASA_PROVIDER)
        db.add(account)
    account.consented_by_user_id = consented_by_user_id
    account.consented_at = datetime.utcnow()
    if _is_connected(account):
        setting.submission_provider = MOTAMED_ASA_PROVIDER
        db.commit()
        return motamed_asa_provider_state(db, business_id)
    account.status = STATUS_ONBOARDING
    account.last_error = None
    db.commit()

    client = MotamedAsaClient(credential.base_url)
    try:
        return _link_or_complete(db, client, credential, account, business, setting)
    except MotamedAsaApiError as exc:
        account.last_error = str(exc)[:500]
        db.commit()
        raise ApiError("MOTAMED_ASA_ONBOARDING_FAILED", str(exc), http_status=502 if exc.is_transient else 400) from exc
    finally:
        client.close()


def _link_or_complete(
    db: Session,
    client: MotamedAsaClient,
    credential: TaxProviderCredential,
    account: BusinessTaxProviderAccount,
    business: Business,
    setting: TaxSetting,
) -> dict[str, Any]:
    """
    The session is found by its reference, so a create whose answer was lost is
    found again instead of opening a second sign-up for the same business.
    """
    business_id = int(business.id)
    token = _partner_token(client, credential)
    session = _latest_session(client, token, business_id)
    status = str((session or {}).get("status") or "")
    if session and status in _READY_SESSION_STATUSES:
        # The owner finished on ASA earlier: take the handed-over key instead of a new link.
        _complete_from_session(db, client, token, account, setting, session)
        return motamed_asa_provider_state(db, business_id)
    if session and status in _OPEN_SESSION_STATUSES:
        session = {**session, **client.renew_onboarding_link(token, str(session["sessionId"]))}
    else:
        session = client.create_onboarding_session(token, _session_body(db, business, setting))
    account.status = STATUS_ONBOARDING
    account.last_error = None
    account.last_synced_at = datetime.utcnow()
    db.commit()
    state = motamed_asa_provider_state(db, business_id)
    state["motamed_asa_onboarding"] = _onboarding_link(session)
    return state


def renew_motamed_asa_link(db: Session, business_id: int) -> dict[str, Any]:
    """A fresh sign-up link for the business's open session (or a new session after consent)."""
    credential = _require_active_credential(db)
    account = _get_account(db, business_id, lock=True)
    if account is None or not account.consented_at:
        raise ApiError(
            "MOTAMED_ASA_CONSENT_REQUIRED",
            "ابتدا روش ارسال «معتمد آسا» را انتخاب و شرایط آن را تأیید کنید.",
            http_status=400,
        )
    if _is_connected(account):
        raise ApiError("MOTAMED_ASA_ALREADY_CONNECTED", "این کسب‌وکار به معتمد آسا متصل است.", http_status=409)
    business = db.query(Business).filter(Business.id == int(business_id)).first()
    setting = db.query(TaxSetting).filter(TaxSetting.business_id == int(business_id)).first()
    if business is None or setting is None or not setting.economic_code:
        raise ApiError("TAX_SETTINGS_INCOMPLETE", "کد اقتصادی کسب‌وکار ثبت نشده است.", http_status=400)

    client = MotamedAsaClient(credential.base_url)
    try:
        return _link_or_complete(db, client, credential, account, business, setting)
    except MotamedAsaApiError as exc:
        raise ApiError("MOTAMED_ASA_ONBOARDING_FAILED", str(exc), http_status=502 if exc.is_transient else 400) from exc
    finally:
        client.close()


def sync_motamed_asa_account(db: Session, business_id: int) -> dict[str, Any]:
    """Reads the sign-up result from ASA, takes the handed-over key once, or re-checks a connected key."""
    credential = _require_active_credential(db)
    account = _get_account(db, business_id, lock=True)
    if account is None:
        raise ApiError("MOTAMED_ASA_ACCOUNT_NOT_FOUND", "این کسب‌وکار هنوز به معتمد آسا وصل نشده است.", http_status=404)
    setting = db.query(TaxSetting).filter(TaxSetting.business_id == int(business_id)).first()
    client = MotamedAsaClient(credential.base_url)
    try:
        if _is_connected(account):
            _customer_token(db, client, account, force=True)
            account.last_synced_at = datetime.utcnow()
            db.commit()
            return motamed_asa_provider_state(db, business_id)
        token = _partner_token(client, credential)
        _apply_session(db, client, token, account, setting, _latest_session(client, token, business_id))
        return motamed_asa_provider_state(db, business_id)
    except MotamedAsaApiError as exc:
        raise ApiError("MOTAMED_ASA_SYNC_FAILED", str(exc), http_status=502 if exc.is_transient else 400) from exc
    finally:
        client.close()


def save_motamed_asa_business_credentials(
    db: Session,
    *,
    business_id: int,
    client_id: str,
    client_secret: str,
    consent: bool,
    consented_by_user_id: int | None,
    economic_code: str | None = None,
) -> dict[str, Any]:
    """The owner's own API v2 customer client id/secret, copied from the ASA panel."""
    if not consent:
        raise ApiError(
            "MOTAMED_ASA_CONSENT_REQUIRED",
            "برای اتصال به معتمد آسا، تأیید صریح شما لازم است.",
            http_status=400,
        )
    credential = _require_active_credential(db)
    client_id = str(client_id or "").strip()
    client_secret = str(client_secret or "").strip()
    match = _CUSTOMER_CLIENT_ID.fullmatch(client_id)
    if not match or not client_secret or len(client_secret) > 512:
        raise ApiError(
            "MOTAMED_ASA_CREDENTIALS_INVALID",
            "شناسه کلاینت باید به شکل v2-customer-شماره باشد و رمز کلاینت خالی نباشد.",
            http_status=400,
        )
    business = db.query(Business).filter(Business.id == int(business_id)).with_for_update().first()
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار پیدا نشد.", http_status=404)
    setting = db.query(TaxSetting).filter(TaxSetting.business_id == int(business_id)).first()
    setting = _ensure_economic_code(db, business_id, setting, economic_code, consented_by_user_id)
    if setting.sandbox_mode:
        raise ApiError(
            "MOTAMED_ASA_SANDBOX_UNAVAILABLE",
            "ارسال از طریق معتمد آسا فقط در محیط اصلی سامانهٔ مؤدیان انجام می‌شود؛ حالت آزمایشی را خاموش کنید.",
            http_status=400,
        )

    client = MotamedAsaClient(credential.base_url)
    try:
        client.issue_token(client_id, client_secret)
    except MotamedAsaApiError as exc:
        if exc.is_transient:
            raise ApiError("MOTAMED_ASA_UNAVAILABLE", str(exc), http_status=502) from exc
        raise ApiError(
            "MOTAMED_ASA_CREDENTIALS_INVALID",
            "معتمد آسا این شناسه و رمز کلاینت را نپذیرفت؛ مقدارها را از پنل معتمد آسا دوباره کپی کنید.",
            http_status=400,
        ) from exc
    finally:
        client.close()

    account = _get_account(db, business_id, lock=True)
    if account is None:
        account = BusinessTaxProviderAccount(business_id=int(business_id), provider_code=MOTAMED_ASA_PROVIDER)
        db.add(account)
    account.consented_by_user_id = consented_by_user_id
    account.consented_at = datetime.utcnow()
    _store_business_credentials(
        db,
        account,
        setting,
        client_id=client_id,
        client_secret=client_secret,
        company_id=int(match.group(1)),
        memory_unique_id=None,
    )
    return motamed_asa_provider_state(db, business_id)


def motamed_asa_health(db: Session, business_id: int) -> dict[str, dict[str, Any]]:
    """Health checks of a business that sends through ASA: its connection replaces the tax-system login."""
    if not motamed_asa_available(get_motamed_asa_credential(db)):
        return {"settings": {"status": "error", "message": "ارسال از طریق معتمد آسا در مدیریت سیستم فعال نیست."}}
    account = _get_account(db, business_id)
    if not _is_connected(account):
        return {"settings": {"status": "error", "message": "حساب این کسب‌وکار در معتمد آسا هنوز متصل نشده است."}}
    checks: dict[str, dict[str, Any]] = {
        "settings": {"status": "ok", "message": "کسب‌وکار به معتمد آسا متصل است.", "provider": MOTAMED_ASA_PROVIDER},
    }
    credential = get_motamed_asa_credential(db)
    client = MotamedAsaClient(credential.base_url)  # type: ignore[union-attr]
    try:
        _customer_token(db, client, account, force=True)  # type: ignore[arg-type]
        checks["connection"] = {"status": "ok", "message": "اتصال به معتمد آسا برقرار است."}
        checks["authentication"] = {"status": "ok", "message": "معتمد آسا کلید API کسب‌وکار را پذیرفت."}
    except ApiError as exc:
        checks["authentication"] = {"status": "error", "message": exc.message}
    except MotamedAsaApiError as exc:
        checks["connection"] = {"status": "error", "message": f"خطا در اتصال به معتمد آسا: {exc}"}
    finally:
        client.close()
    return checks


# --- Customer calls (sending and inquiry) ---------------------------------------------------


def _customer_token(
    db: Session,
    client: MotamedAsaClient,
    account: BusinessTaxProviderAccount,
    *,
    force: bool = False,
) -> str:
    if not force:
        cached = _decrypt(account.access_token_encrypted, "توکن معتمد آسا")
        if cached and account.token_expires_at and account.token_expires_at > datetime.utcnow() + _TOKEN_REFRESH_MARGIN:
            return cached
    client_id = _decrypt(account.username_encrypted, "شناسه کلاینت کسب‌وکار")
    client_secret = _decrypt(account.password_encrypted, "رمز کلاینت کسب‌وکار")
    if not client_id or not client_secret:
        raise ApiError(
            "MOTAMED_ASA_ACCOUNT_NOT_CONNECTED",
            "کلید API معتمد آسا برای این کسب‌وکار ثبت نشده است.",
            http_status=409,
        )
    try:
        token, expires_in = client.issue_token(client_id, client_secret)
    except MotamedAsaApiError as exc:
        if exc.is_transient:
            raise
        account.status = STATUS_CREDENTIALS_REQUIRED
        account.last_error = "معتمد آسا کلید API این کسب‌وکار را دیگر نمی‌پذیرد؛ شناسه و رمز تازه را وارد کنید."
        db.flush()
        raise ApiError("MOTAMED_ASA_CREDENTIALS_REJECTED", account.last_error, http_status=409) from exc
    account.access_token_encrypted = _encrypt(token)
    account.token_expires_at = datetime.utcnow() + timedelta(seconds=max(expires_in - 60, 60))
    account.last_synced_at = datetime.utcnow()
    db.flush()
    return token


def get_motamed_asa_account(db: Session, business_id: int) -> tuple[TaxProviderCredential, BusinessTaxProviderAccount]:
    credential = _require_active_credential(db)
    account = _get_account(db, business_id)
    if not _is_connected(account):
        raise ApiError(
            "MOTAMED_ASA_ACCOUNT_NOT_CONNECTED",
            "حساب این کسب‌وکار در معتمد آسا هنوز متصل نشده است.",
            http_status=409,
        )
    return credential, account  # type: ignore[return-value]


def motamed_asa_business_call(
    db: Session,
    business_id: int,
    operation: Callable[[MotamedAsaClient, str, BusinessTaxProviderAccount], T],
) -> T:
    """Runs one customer operation with a cached token, renewing it once when ASA refuses it."""
    credential, account = get_motamed_asa_account(db, business_id)
    client = MotamedAsaClient(credential.base_url)
    try:
        token = _customer_token(db, client, account)
        try:
            return operation(client, token, account)
        except MotamedAsaApiError as exc:
            if exc.code != "UNAUTHORIZED":
                raise
            token = _customer_token(db, client, account, force=True)
            return operation(client, token, account)
    finally:
        client.close()
