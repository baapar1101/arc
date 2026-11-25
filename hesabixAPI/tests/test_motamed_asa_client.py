"""«معتمد آسا» API v2 client: the three answer conventions it has to read."""

from __future__ import annotations

import json

import httpx
import pytest

from app.integrations.motamed_asa.client import MotamedAsaApiError, MotamedAsaClient


def _client(handler) -> MotamedAsaClient:
    return MotamedAsaClient("https://api-v2.example.test/", transport=httpx.MockTransport(handler))


def test_issue_token_posts_client_credentials() -> None:
    seen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"] = str(request.url)
        seen["body"] = json.loads(request.content)
        return httpx.Response(200, json={"access_token": "a.b.c", "token_type": "Bearer", "expires_in": 3600})

    with _client(handler) as client:
        token, expires_in = client.issue_token("v2-customer-12", "secret")

    assert (token, expires_in) == ("a.b.c", 3600)
    assert seen["url"] == "https://api-v2.example.test/api/auth/v2/token"
    assert seen["body"] == {
        "grant_type": "client_credentials",
        "client_id": "v2-customer-12",
        "client_secret": "secret",
    }


def test_rejected_token_is_unauthorized() -> None:
    with _client(lambda request: httpx.Response(401)) as client:
        with pytest.raises(MotamedAsaApiError) as error:
            client.issue_token("v2-customer-12", "wrong")
    assert error.value.status_code == 401
    assert error.value.code == "UNAUTHORIZED"
    assert not error.value.is_transient


def test_partner_envelope_error_keeps_code_and_message() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            409,
            json={
                "status": "CONFLICT",
                "data": None,
                "errors": [{"code": "credentials_already_claimed", "message": "already claimed"}],
                "fieldErrors": [],
                "correlationId": "c1",
            },
        )

    with _client(handler) as client:
        with pytest.raises(MotamedAsaApiError) as error:
            client.claim_credentials("partner-token", "6f1c0b9e-0000-4000-8000-000000000001")
    assert (error.value.status_code, error.value.code, str(error.value)) == (
        409,
        "credentials_already_claimed",
        "already claimed",
    )


def test_create_session_unwraps_envelope_and_sends_bearer() -> None:
    seen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["auth"] = request.headers.get("Authorization")
        return httpx.Response(201, json={"status": "OK", "data": {"sessionId": "s-1", "url": "https://x/join/t"}})

    with _client(handler) as client:
        session = client.create_onboarding_session("partner-token", {"reference": "hesabix-business-1"})

    assert seen["auth"] == "Bearer partner-token"
    assert session["url"] == "https://x/join/t"


def test_invoice_result_minus_one_is_unauthorized_although_http_200() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"result": -1, "traceId": "t", "message": "token expired", "data": []})

    with _client(handler) as client:
        with pytest.raises(MotamedAsaApiError) as error:
            client.send_invoices("customer-token", {"uuid": "u", "data": []})
    assert error.value.code == "UNAUTHORIZED"


def test_inquiry_keeps_request_order() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        ids = json.loads(request.content)["internalIds"]
        return httpx.Response(200, json=[{"internalId": value, "asatspId": index + 1, "status": 2} for index, value in enumerate(ids)])

    with _client(handler) as client:
        items = client.inquire_internal_ids("customer-token", ["hesabix-1", "hesabix-2"])
    assert [item["internalId"] for item in items] == ["hesabix-1", "hesabix-2"]


def test_inquiry_auth_failure_is_one_item_without_internal_id() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[{"status": 3, "error": ["توکن نامعتبر است"]}])

    with _client(handler) as client:
        with pytest.raises(MotamedAsaApiError) as error:
            client.inquire_internal_ids("customer-token", ["hesabix-1", "hesabix-2"])
    assert error.value.code == "UNAUTHORIZED"


def test_timeout_is_transient() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("slow", request=request)

    with _client(handler) as client:
        with pytest.raises(MotamedAsaApiError) as error:
            client.send_invoices("customer-token", {"uuid": "u", "data": []})
    assert error.value.code == "TIMEOUT"
    assert error.value.is_transient


def test_payment_routes_post_to_register_and_inquire() -> None:
    seen: list[tuple[str, dict]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append((request.url.path, json.loads(request.content)))
        return httpx.Response(200, json={"result": 1, "traceId": "t", "data": [{"internalId": "hesabix-1", "payments": []}]})

    with _client(handler) as client:
        client.register_payments("customer-token", {"uuid": "u", "internalId": "hesabix-1", "payments": [{"type": 6}]})
        answer = client.inquire_payments("customer-token", "hesabix-1")

    assert [path for path, _ in seen] == ["/api/invoice/registerPayment", "/api/invoice/inquiryPayment"]
    assert seen[1][1] == {"internalId": "hesabix-1"}
    assert answer["result"] == 1
