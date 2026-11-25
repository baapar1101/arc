"""«معتمد آسا» connection of a business: partner settings, the one-shot key handover and the token cache."""

from __future__ import annotations

from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from app.core.responses import ApiError
from app.integrations.motamed_asa.client import MotamedAsaApiError
from app.services import motamed_asa_provider_service as service


@pytest.fixture(autouse=True)
def _plain_secrets(monkeypatch: pytest.MonkeyPatch) -> None:
    # The real helpers need the deployment's encryption key; the flow is what is tested here.
    monkeypatch.setattr(service, "_encrypt", lambda value: f"enc:{value}" if value else None)
    monkeypatch.setattr(service, "_decrypt", lambda value, _label: value[4:] if value else None)


def _account(**values) -> SimpleNamespace:
    fields = {
        "status": "onboarding", "cartable_id": None, "memory_number": None, "last_error": None,
        "username_encrypted": None, "password_encrypted": None, "access_token_encrypted": None,
        "token_expires_at": None, "registered_at": None, "last_synced_at": None,
    }
    fields.update(values)
    return SimpleNamespace(**fields)


def _session(**credentials) -> dict:
    return {
        "sessionId": "6f1c0b9e-0000-4000-8000-000000000001",
        "status": "completed",
        "business": {"companyId": 812, "economicCode": "14001234567", "name": "نمونه", "created": True},
        "memory": {"memoryUniqueId": "A1B2C3", "issued": True},
        "credentials": {"available": True, "claimed": False, "clientId": "v2-customer-812", **credentials},
    }


@pytest.mark.parametrize(
    ("payload", "code"),
    [
        ({"base_url": "http://api-v2.asatsp.ir"}, "INVALID_PROVIDER_URL"),
        ({"base_url": "https://api-v2.asatsp.ir/api"}, "INVALID_PROVIDER_URL"),
        ({"client_id": "v2-customer-1"}, "INVALID_CLIENT_ID"),
    ],
)
def test_partner_settings_are_validated(monkeypatch: pytest.MonkeyPatch, payload: dict, code: str) -> None:
    monkeypatch.setattr(service, "get_motamed_asa_credential", lambda db: None)
    with pytest.raises(ApiError) as error:
        service.save_motamed_asa_credential(MagicMock(), payload)
    assert error.value.code == code


def test_partner_settings_stay_inactive_without_a_secret(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(service, "get_motamed_asa_credential", lambda db: None)
    credential = service.save_motamed_asa_credential(
        MagicMock(), {"client_id": "v2-partner-7", "is_active": True}
    )
    assert credential.provider_code == "motamed_asa"
    assert credential.base_url == "https://api-v2.asatsp.ir"
    assert credential.is_active is False


def test_handed_over_key_connects_the_business() -> None:
    db = MagicMock()
    client = MagicMock()
    client.claim_credentials.return_value = {
        "companyId": 812, "clientId": "v2-customer-812", "clientSecret": "s3cret", "secretIssued": True,
    }
    account = _account()
    setting = SimpleNamespace(submission_provider="moadian_direct")

    service._complete_from_session(db, client, "partner-token", account, setting, _session())

    assert account.status == "connected"
    assert (account.username_encrypted, account.password_encrypted) == ("enc:v2-customer-812", "enc:s3cret")
    assert (account.cartable_id, account.memory_number) == (812, "A1B2C3")
    assert setting.submission_provider == "motamed_asa"
    db.commit.assert_called()


def test_existing_key_is_not_handed_over() -> None:
    client = MagicMock()
    client.claim_credentials.return_value = {"companyId": 812, "clientId": "v2-customer-812", "secretIssued": False}
    account = _account()
    setting = SimpleNamespace(submission_provider="moadian_direct")

    service._complete_from_session(MagicMock(), client, "partner-token", account, setting, _session())

    assert account.status == "credentials_required"
    assert account.password_encrypted is None
    assert setting.submission_provider == "moadian_direct"


def test_key_claimed_before_asks_for_manual_entry() -> None:
    client = MagicMock()
    client.claim_credentials.side_effect = MotamedAsaApiError(
        "already", status_code=409, code="credentials_already_claimed"
    )
    account = _account()

    service._complete_from_session(MagicMock(), client, "partner-token", account, None, _session())

    assert account.status == "credentials_required"
    assert account.last_error


def test_owner_who_did_not_allow_the_handover_is_told_so() -> None:
    client = MagicMock()
    account = _account()

    service._complete_from_session(
        MagicMock(), client, "partner-token", account, None, _session(available=False)
    )

    client.claim_credentials.assert_not_called()
    assert account.status == "credentials_required"


def test_session_body_prefills_only_what_the_link_needs() -> None:
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = SimpleNamespace(mobile="+98 912 000 0000")
    business = SimpleNamespace(id=5, name="فروشگاه نمونه", owner_id=1, mobile=None)
    setting = SimpleNamespace(economic_code="۱۴۰۰۱۲۳۴۵۶۷")

    body = service._session_body(db, business, setting)

    assert body == {
        "economicCode": "14001234567",
        "businessName": "فروشگاه نمونه",
        "reference": "hesabix-business-5",
        "issueMemoryUniqueId": True,
        "requestCredentials": True,
        "mobile": "09120000000",
    }


def test_customer_token_is_reused_until_close_to_expiry() -> None:
    client = MagicMock()
    account = _account(
        status="connected",
        username_encrypted="enc:v2-customer-812",
        password_encrypted="enc:s3cret",
        access_token_encrypted="enc:cached",
        token_expires_at=datetime.utcnow() + timedelta(minutes=30),
    )
    assert service._customer_token(MagicMock(), client, account) == "cached"
    client.issue_token.assert_not_called()

    account.token_expires_at = datetime.utcnow() + timedelta(seconds=30)
    client.issue_token.return_value = ("fresh", 3600)
    assert service._customer_token(MagicMock(), client, account) == "fresh"
    assert account.access_token_encrypted == "enc:fresh"


def test_health_without_a_connected_account_is_not_healthy(monkeypatch: pytest.MonkeyPatch) -> None:
    credential = SimpleNamespace(is_active=True, username_encrypted="enc:p", password_encrypted="enc:s", base_url="https://x")
    monkeypatch.setattr(service, "get_motamed_asa_credential", lambda db: credential)
    monkeypatch.setattr(service, "_get_account", lambda db, business_id, lock=False: _account(status="onboarding"))

    checks = service.motamed_asa_health(MagicMock(), 5)

    assert checks["settings"]["status"] == "error"


def test_revoked_customer_key_asks_for_a_new_one() -> None:
    client = MagicMock()
    client.issue_token.side_effect = MotamedAsaApiError("no", status_code=401, code="UNAUTHORIZED")
    account = _account(status="connected", username_encrypted="enc:id", password_encrypted="enc:secret")

    with pytest.raises(ApiError) as error:
        service._customer_token(MagicMock(), client, account, force=True)

    assert error.value.code == "MOTAMED_ASA_CREDENTIALS_REJECTED"
    assert account.status == "credentials_required"
