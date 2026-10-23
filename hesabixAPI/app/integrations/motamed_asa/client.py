from __future__ import annotations

from typing import Any
from urllib.parse import quote

import httpx

DEFAULT_BASE_URL = "https://api-v2.asatsp.ir"

# Invoice routes answer HTTP 200 with a numeric «result»; -1 is an authentication failure.
_RESULT_UNAUTHORIZED = -1


class MotamedAsaApiError(RuntimeError):
    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = None,
        code: str | None = None,
        details: Any = None,
    ):
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.details = details

    @property
    def is_transient(self) -> bool:
        """The request may have been applied remotely: inquire before acting again."""
        return self.code in {"TIMEOUT", "NETWORK_ERROR"} or (self.status_code or 0) >= 500


def _envelope_error(payload: Any) -> tuple[str | None, str | None]:
    """First error of the partner envelope ({status, data, errors, fieldErrors, correlationId})."""
    if not isinstance(payload, dict):
        return None, None
    errors = payload.get("errors")
    if isinstance(errors, list):
        for item in errors:
            if isinstance(item, dict) and (item.get("message") or item.get("code")):
                return item.get("code"), item.get("message")
    field_errors = payload.get("fieldErrors")
    if isinstance(field_errors, list):
        for item in field_errors:
            if isinstance(item, dict) and item.get("errorMessage"):
                return "validation_failed", f"{item.get('field') or ''}: {item['errorMessage']}".strip(": ")
    error = payload.get("error")
    if isinstance(error, str) and error:
        return error, payload.get("message") or payload.get("error_description")
    message = payload.get("message")
    if isinstance(message, str) and message:
        return None, message
    return None, None


class MotamedAsaClient:
    """HTTP client for the «معتمد آسا» API v2: partner onboarding, invoice sending and inquiry."""

    def __init__(
        self,
        base_url: str = DEFAULT_BASE_URL,
        *,
        timeout_seconds: float = 60,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        self.base_url = (base_url or DEFAULT_BASE_URL).rstrip("/")
        self._http = httpx.Client(
            timeout=httpx.Timeout(timeout_seconds, connect=min(timeout_seconds, 10)),
            transport=transport,
            follow_redirects=False,
            headers={"Accept": "application/json", "User-Agent": "Hesabix-TaxProvider/1.0"},
        )

    def close(self) -> None:
        self._http.close()

    def __enter__(self) -> "MotamedAsaClient":
        return self

    def __exit__(self, *_: Any) -> None:
        self.close()

    def request(
        self,
        method: str,
        path: str,
        *,
        body: Any = None,
        params: dict[str, Any] | None = None,
        token: str | None = None,
    ) -> Any:
        headers: dict[str, str] = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        try:
            response = self._http.request(
                method,
                f"{self.base_url}{path}",
                params=params,
                json=body,
                headers=headers,
            )
        except httpx.TimeoutException as exc:
            raise MotamedAsaApiError(
                "پاسخی از معتمد آسا دریافت نشد؛ وضعیت عملیات باید استعلام شود.", code="TIMEOUT"
            ) from exc
        except httpx.HTTPError as exc:
            raise MotamedAsaApiError("ارتباط با معتمد آسا برقرار نشد.", code="NETWORK_ERROR") from exc

        try:
            payload = response.json() if response.content else None
        except ValueError:
            payload = None
        if response.is_error:
            code, message = _envelope_error(payload)
            if response.status_code == 401:
                code = code or "UNAUTHORIZED"
                message = message or "دسترسی به معتمد آسا تأیید نشد."
            raise MotamedAsaApiError(
                str(message or f"پاسخ ناموفق معتمد آسا ({response.status_code}).")[:500],
                status_code=response.status_code,
                code=str(code or "HTTP_ERROR"),
                details=payload,
            )
        return payload

    # --- OAuth2 client credentials -------------------------------------------------------

    def issue_token(self, client_id: str, client_secret: str) -> tuple[str, int]:
        """POST /api/auth/v2/token → (access_token, expires_in seconds)."""
        payload = self.request(
            "POST",
            "/api/auth/v2/token",
            body={"grant_type": "client_credentials", "client_id": client_id, "client_secret": client_secret},
        )
        token = payload.get("access_token") if isinstance(payload, dict) else None
        if not token:
            raise MotamedAsaApiError("معتمد آسا توکن دسترسی برنگرداند.", code="TOKEN_MISSING")
        try:
            expires_in = int(payload.get("expires_in") or 3600)
        except (TypeError, ValueError):
            expires_in = 3600
        return str(token), expires_in

    # --- Partner routes (partner token, scope v2.register) --------------------------------

    @staticmethod
    def _envelope_data(payload: Any) -> Any:
        if isinstance(payload, dict) and "data" in payload:
            return payload["data"]
        return payload

    def partner_profile(self, token: str) -> dict[str, Any]:
        data = self._envelope_data(self.request("GET", "/api/v2/partner/profile", token=token))
        return data if isinstance(data, dict) else {}

    def create_onboarding_session(self, token: str, body: dict[str, Any]) -> dict[str, Any]:
        data = self._envelope_data(
            self.request("POST", "/api/v2/partner/onboarding-sessions", body=body, token=token)
        )
        if not isinstance(data, dict) or not data.get("sessionId"):
            raise MotamedAsaApiError("پاسخ ساخت لینک ثبت‌نام معتمد آسا ساختار معتبری ندارد.", code="INVALID_RESPONSE")
        return data

    def list_onboarding_sessions(self, token: str, *, reference: str, page_size: int = 20) -> list[dict[str, Any]]:
        data = self._envelope_data(
            self.request(
                "GET",
                "/api/v2/partner/onboarding-sessions",
                params={"reference": reference, "page": 1, "pageSize": page_size},
                token=token,
            )
        )
        items = data.get("items") if isinstance(data, dict) else None
        return [item for item in items if isinstance(item, dict)] if isinstance(items, list) else []

    def get_onboarding_session(self, token: str, session_id: str) -> dict[str, Any]:
        path = f"/api/v2/partner/onboarding-sessions/{quote(str(session_id), safe='')}"
        data = self._envelope_data(self.request("GET", path, token=token))
        return data if isinstance(data, dict) else {}

    def renew_onboarding_link(self, token: str, session_id: str) -> dict[str, Any]:
        path = f"/api/v2/partner/onboarding-sessions/{quote(str(session_id), safe='')}/link"
        data = self._envelope_data(self.request("POST", path, body={}, token=token))
        return data if isinstance(data, dict) else {}

    def claim_credentials(self, token: str, session_id: str) -> dict[str, Any]:
        """One-shot: the secret is shown once and a repeated call answers 409 credentials_already_claimed."""
        path = f"/api/v2/partner/onboarding-sessions/{quote(str(session_id), safe='')}/credentials"
        data = self._envelope_data(self.request("POST", path, body={}, token=token))
        return data if isinstance(data, dict) else {}

    # --- Invoice routes (the business's customer token) -----------------------------------

    @staticmethod
    def _invoice_result(payload: Any) -> dict[str, Any]:
        if not isinstance(payload, dict):
            raise MotamedAsaApiError("پاسخ صورتحساب معتمد آسا ساختار معتبری ندارد.", code="INVALID_RESPONSE")
        if payload.get("result") == _RESULT_UNAUTHORIZED:
            raise MotamedAsaApiError(
                str(payload.get("message") or "دسترسی به معتمد آسا تأیید نشد."),
                status_code=401,
                code="UNAUTHORIZED",
                details=payload,
            )
        return payload

    def send_invoices(self, token: str, body: dict[str, Any]) -> dict[str, Any]:
        return self._invoice_result(self.request("POST", "/api/invoice/send", body=body, token=token))

    def edit_invoice(self, token: str, body: dict[str, Any]) -> dict[str, Any]:
        return self._invoice_result(self.request("POST", "/api/invoice/editInvoice", body=body, token=token))

    def cancel_invoice(self, token: str, body: dict[str, Any]) -> dict[str, Any]:
        return self._invoice_result(self.request("POST", "/api/invoice/cancelInvoice", body=body, token=token))

    def register_payments(self, token: str, body: dict[str, Any]) -> dict[str, Any]:
        """POST /api/invoice/registerPayment: new payment rows of a sent invoice, registered in the کارپوشه."""
        return self._invoice_result(self.request("POST", "/api/invoice/registerPayment", body=body, token=token))

    def inquire_payments(self, token: str, internal_id: str) -> dict[str, Any]:
        """POST /api/invoice/inquiryPayment: every payment row of the chain's latest invoice and its registration."""
        return self._invoice_result(
            self.request("POST", "/api/invoice/inquiryPayment", body={"internalId": internal_id}, token=token)
        )

    def queue_invoices(self, token: str, internal_ids: list[str]) -> dict[str, Any]:
        return self._invoice_result(
            self.request("POST", "/api/invoice/sendInvoice", body={"internalIds": internal_ids}, token=token)
        )

    def inquire_internal_ids(self, token: str, internal_ids: list[str]) -> list[dict[str, Any]]:
        """Each item is the latest invoice of the chain the internalId belongs to, in request order."""
        if not internal_ids:
            return []
        payload = self.request(
            "POST", "/api/invoice/inquiryInternalIds", body={"internalIds": internal_ids}, token=token
        )
        items = [item for item in payload if isinstance(item, dict)] if isinstance(payload, list) else []
        if len(items) != len(internal_ids) or any(
            not item.get("internalId") and not item.get("asatspId") for item in items
        ):
            # Authentication and batch failures come back as one item without an internalId.
            first = items[0] if items else {}
            errors = first.get("error") if isinstance(first.get("error"), list) else []
            raise MotamedAsaApiError(
                str(errors[0] if errors else "استعلام صورتحساب از معتمد آسا پذیرفته نشد."),
                status_code=401,
                code="UNAUTHORIZED" if errors else "INQUIRY_REJECTED",
                details=payload,
            )
        return items
