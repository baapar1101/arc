from __future__ import annotations

import base64
from typing import Any
from urllib.parse import quote

import httpx


class FanavaApiError(RuntimeError):
    def __init__(self, message: str, *, status_code: int | None = None, code: str | None = None):
        super().__init__(message)
        self.status_code = status_code
        self.code = code


class FanavaClient:
    """Small HTTP client for the documented Fanava TSP API."""

    def __init__(
        self,
        base_url: str,
        *,
        username: str | None = None,
        password: str | None = None,
        timeout_seconds: float = 25,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.username = username or ""
        self.password = password or ""
        self._http = httpx.Client(
            timeout=httpx.Timeout(timeout_seconds, connect=min(timeout_seconds, 8)),
            transport=transport,
            follow_redirects=False,
            headers={"Accept": "application/json", "User-Agent": "Hesabix-TaxProvider/1.0"},
        )

    def close(self) -> None:
        self._http.close()

    def __enter__(self) -> "FanavaClient":
        return self

    def __exit__(self, *_: Any) -> None:
        self.close()

    def _authorization(self, mode: str | None, token: str | None = None) -> str | None:
        if mode == "basic":
            if not self.username or not self.password:
                raise FanavaApiError("اعتبارنامه بروکر فن‌آوا تنظیم نشده است.", code="CONFIG_MISSING")
            pair = f"{self.username}:{self.password}".encode("utf-8")
            return "Basic " + base64.b64encode(pair).decode("ascii")
        if mode == "bearer":
            if not token:
                raise FanavaApiError("توکن کاربر فن‌آوا موجود نیست.", code="TOKEN_MISSING")
            return f"Bearer {token}"
        return None

    def request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, Any] | None = None,
        body: dict[str, Any] | None = None,
        auth: str | None = None,
        token: str | None = None,
    ) -> Any:
        headers: dict[str, str] = {}
        authorization = self._authorization(auth, token)
        if authorization:
            headers["Authorization"] = authorization
        try:
            response = self._http.request(
                method,
                f"{self.base_url}{path}",
                params=params,
                json=body,
                headers=headers,
            )
        except httpx.TimeoutException as exc:
            raise FanavaApiError("پاسخی از فن‌آوا دریافت نشد؛ وضعیت عملیات باید استعلام شود.", code="TIMEOUT") from exc
        except httpx.HTTPError as exc:
            raise FanavaApiError("ارتباط با فن‌آوا برقرار نشد.", code="NETWORK_ERROR") from exc

        try:
            payload = response.json() if response.content else None
        except ValueError:
            payload = None
        if response.is_error:
            message = payload.get("message") if isinstance(payload, dict) else None
            if not message:
                message = f"پاسخ ناموفق فن‌آوا ({response.status_code})."
            raise FanavaApiError(
                str(message)[:500],
                status_code=response.status_code,
                code="HTTP_ERROR",
            )
        return payload

    @staticmethod
    def unwrap_data(payload: Any) -> Any:
        if isinstance(payload, dict) and "data" in payload:
            return payload["data"]
        return payload

    def login(self, username: str, password: str) -> str:
        payload = self.request("POST", "/api/auth/login", body={"username": username, "password": password})
        data = self.unwrap_data(payload)
        token = data.get("token") if isinstance(data, dict) else None
        if not token:
            raise FanavaApiError("فن‌آوا توکن ورود برنگرداند.", code="TOKEN_MISSING")
        return str(token)

    def register_user(self, body: dict[str, Any]) -> dict[str, Any]:
        payload = self.request("POST", "/api/v1/register-user", body=body, auth="basic")
        data = self.unwrap_data(payload)
        if not isinstance(data, dict):
            raise FanavaApiError("پاسخ ثبت‌نام فن‌آوا ساختار معتبری ندارد.", code="INVALID_RESPONSE")
        return data

    def broker_list(self, token: str, *, page: int = 0, size: int = 50) -> dict[str, Any]:
        payload = self.request("GET", "/api/v1/brokers", params={"page": page, "size": size}, auth="bearer", token=token)
        data = self.unwrap_data(payload)
        return data if isinstance(data, dict) else {"data": data if isinstance(data, list) else []}

    def list_cartables(self, token: str, *, page: int = 0, size: int = 50) -> dict[str, Any]:
        payload = self.request("GET", "/api/v1/cartables", params={"page": page, "size": size}, auth="bearer", token=token)
        data = self.unwrap_data(payload)
        return data if isinstance(data, dict) else {"data": data if isinstance(data, list) else []}

    def list_memories(self, token: str, cartable_id: int, *, page: int = 0, size: int = 50) -> dict[str, Any]:
        payload = self.request(
            "GET", "/api/v1/memories",
            params={"cartableId": cartable_id, "page": page, "size": size},
            auth="bearer", token=token,
        )
        data = self.unwrap_data(payload)
        return data if isinstance(data, dict) else {"data": data if isinstance(data, list) else []}

    def list_broker_users(self, token: str, broker_cartable_id: int, *, page: int = 0, size: int = 50) -> dict[str, Any]:
        payload = self.request(
            "GET", "/api/v1/broker-users",
            params={"brokerCartableId": broker_cartable_id, "page": page, "size": size},
            auth="bearer", token=token,
        )
        data = self.unwrap_data(payload)
        return data if isinstance(data, dict) else {"data": data if isinstance(data, list) else []}

    def save_invoice(self, token: str, body: dict[str, Any]) -> int:
        payload = self.request("POST", "/api/v1/invoice", body=body, auth="bearer", token=token)
        data = self.unwrap_data(payload)
        if isinstance(data, dict):
            data = data.get("id") or data.get("invoiceId")
        try:
            return int(data)
        except (TypeError, ValueError) as exc:
            raise FanavaApiError("شناسه صورتحساب در پاسخ ثبت فن‌آوا موجود نیست.", code="INVOICE_ID_MISSING") from exc

    def send_invoice(self, token: str, cartable_id: int, invoice_id: int) -> Any:
        payload = self.request(
            "POST", "/api/v1/invoice/send",
            params={"cartableId": cartable_id, "invoiceId": invoice_id},
            auth="bearer", token=token,
        )
        return self.unwrap_data(payload)

    def get_invoice(self, token: str, cartable_id: int, invoice_id: int) -> Any:
        payload = self.request(
            "GET", "/api/v1/invoice/get-by-id",
            params={"cartableId": cartable_id, "invoiceId": invoice_id},
            auth="bearer", token=token,
        )
        return self.unwrap_data(payload)

    def list_invoices(self, token: str, cartable_id: int, *, page: int = 0, size: int = 50) -> dict[str, Any]:
        payload = self.request(
            "GET", "/api/v1/invoice",
            params={"cartableId": cartable_id, "page": page, "size": min(max(size, 1), 50)},
            auth="bearer", token=token,
        )
        data = self.unwrap_data(payload)
        return data if isinstance(data, dict) else {"data": data if isinstance(data, list) else []}

    def check_status(self, token: str, cartable_id: int, invoice_id: int) -> list[dict[str, Any]]:
        payload = self.request(
            "POST", "/api/v1/invoice/check-status",
            params={"cartableId": cartable_id, "invoiceId": invoice_id},
            auth="bearer", token=token,
        )
        data = self.unwrap_data(payload)
        return [item for item in data if isinstance(item, dict)] if isinstance(data, list) else []

    def inquiry_status(self, token: str, cartable_id: int, invoice_id: int) -> Any:
        payload = self.request(
            "POST", "/api/v1/invoice/inquiry-status",
            params={"cartableId": cartable_id, "invoiceId": invoice_id},
            auth="bearer", token=token,
        )
        return self.unwrap_data(payload)

    def delete_invoice(self, token: str, cartable_id: int, invoice_id: int) -> Any:
        payload = self.request(
            "DELETE", "/api/v1/invoice",
            params={"cartableId": cartable_id, "invoiceId": invoice_id},
            auth="bearer", token=token,
        )
        return self.unwrap_data(payload)

    def invoice_fields_format(self, token: str, code: str, subject: str) -> Any:
        path = f"/api/invoice-fields/format/{quote(str(code), safe='')}/subject/{quote(str(subject), safe='')}"
        payload = self.request("GET", path, auth="bearer", token=token)
        return self.unwrap_data(payload)
