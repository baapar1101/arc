"""کلاینت REST درگاه یکپارچه دیجی‌پی (UPG)."""

from __future__ import annotations

import base64
import time
from typing import Any, Callable, Optional
from urllib.parse import urlencode

import httpx

from app.core.responses import ApiError

STAGING_BASE = "https://uat.mydigipay.info/digipay/api"
LIVE_BASE = "https://api.mydigipay.com/digipay/api"
DIGIPAY_VERSION = "2022-02-02"
AGENT = "WEB"
TICKET_TYPE_UPG = 11

TYPE_IPG = 0
TYPE_CREDIT = 5
TYPE_WALLET = 11
TYPE_BNPL = 13
TYPE_CREDIT_CARD = 24

CREDIT_TYPES = {TYPE_CREDIT, TYPE_BNPL, TYPE_CREDIT_CARD}


class DigipayClientError(ApiError):
	def __init__(self, code: str, message: str, http_status: int = 502, details: dict | None = None):
		super().__init__(code, message, http_status=http_status, details=details or {})


class DigipayClient:
	def __init__(
		self,
		*,
		username: str,
		password: str,
		client_id: str,
		client_secret: str,
		environment: str = "sandbox",
		http_post: Optional[Callable[..., httpx.Response]] = None,
	) -> None:
		self.username = username
		self.password = password
		self.client_id = client_id
		self.client_secret = client_secret
		self.base_url = LIVE_BASE if environment == "live" else STAGING_BASE
		self._http_post = http_post
		self._access_token: str | None = None
		self._token_expires_at: float = 0.0

	def _post(
		self,
		path: str,
		*,
		json_body: dict | None = None,
		form: dict | None = None,
		headers: dict | None = None,
		auth_basic: bool = False,
	) -> httpx.Response:
		url = path if path.startswith("http") else f"{self.base_url.rstrip('/')}/{path.lstrip('/')}"
		req_headers = dict(headers or {})
		if auth_basic:
			raw = f"{self.client_id}:{self.client_secret}".encode("utf-8")
			req_headers["Authorization"] = f"Basic {base64.b64encode(raw).decode('ascii')}"
		if self._http_post is not None:
			return self._http_post(url, json_body=json_body, form=form, headers=req_headers)
		timeout = httpx.Timeout(30.0)
		if form is not None:
			# UPG login docs require multipart form-data (curl --form / PHP array POSTFIELDS).
			files = {str(key): (None, str(value)) for key, value in form.items()}
			headers = {k: v for k, v in req_headers.items() if str(k).lower() != "content-type"}
			return httpx.post(url, files=files, headers=headers, timeout=timeout, follow_redirects=True)
		return httpx.post(url, json=json_body, headers=req_headers, timeout=timeout, follow_redirects=True)

	def login(self) -> str:
		resp = self._post(
			"oauth/token",
			form={"username": self.username, "password": self.password, "grant_type": "password"},
			auth_basic=True,
		)
		if resp.status_code != 200:
			raise DigipayClientError(
				"DIGIPAY_AUTH_FAILED",
				"DigiPay authentication failed",
				http_status=401,
				details={"status_code": resp.status_code},
			)
		data = resp.json()
		token = str(data.get("access_token") or "")
		if not token:
			raise DigipayClientError("DIGIPAY_AUTH_FAILED", "DigiPay token missing", http_status=401)
		expires = int(data.get("expires_in") or 3599)
		self._access_token = token
		self._token_expires_at = time.time() + max(expires - 60, 30)
		return token

	def _bearer(self) -> str:
		if not self._access_token or time.time() >= self._token_expires_at:
			self.login()
		assert self._access_token
		return self._access_token

	def _auth_headers(self, extra: dict | None = None) -> dict[str, str]:
		headers = {
			"Authorization": f"Bearer {self._bearer()}",
			"Content-Type": "application/json; charset=UTF-8",
			"Agent": AGENT,
			"Digipay-Version": DIGIPAY_VERSION,
		}
		if extra:
			headers.update(extra)
		return headers

	def _parse_result(self, resp: httpx.Response) -> dict[str, Any]:
		try:
			data = resp.json()
		except Exception as exc:
			raise DigipayClientError(
				"DIGIPAY_BAD_RESPONSE",
				"DigiPay returned a non-JSON response",
				http_status=502,
				details={"status_code": resp.status_code},
			) from exc
		if resp.status_code == 401:
			raise DigipayClientError("DIGIPAY_AUTH_FAILED", "DigiPay token rejected", http_status=401)
		result = data.get("result") if isinstance(data, dict) else None
		status = None
		if isinstance(result, dict):
			status = result.get("status")
		if resp.status_code >= 400 or (status not in (None, 0)):
			message = ""
			if isinstance(result, dict):
				message = str(result.get("message") or "")
			raise DigipayClientError(
				"DIGIPAY_API_ERROR",
				message or "DigiPay request failed",
				http_status=422 if resp.status_code == 422 else 502,
				details={"status_code": resp.status_code, "result": result, "body": data},
			)
		return data if isinstance(data, dict) else {"raw": data}

	def create_ticket(self, payload: dict[str, Any]) -> dict[str, Any]:
		resp = self._post(
			f"tickets/business?{urlencode({'type': TICKET_TYPE_UPG})}",
			json_body=payload,
			headers=self._auth_headers(),
		)
		return self._parse_result(resp)

	def verify(self, *, tracking_code: str, provider_id: str, ticket_type: int) -> dict[str, Any]:
		resp = self._post(
			f"purchases/verify?{urlencode({'type': int(ticket_type)})}",
			json_body={"trackingCode": tracking_code, "providerId": provider_id},
			headers=self._auth_headers(),
		)
		return self._parse_result(resp)

	def deliver(self, *, ticket_type: int, body: dict[str, Any]) -> dict[str, Any]:
		resp = self._post(
			f"purchases/deliver?{urlencode({'type': int(ticket_type)})}",
			json_body=body,
			headers=self._auth_headers(),
		)
		return self._parse_result(resp)

	def refund(self, *, ticket_type: int, body: dict[str, Any]) -> dict[str, Any]:
		resp = self._post(
			f"refunds?{urlencode({'type': int(ticket_type)})}",
			json_body=body,
			headers=self._auth_headers(),
		)
		return self._parse_result(resp)

	def refund_inquiry(self, inquiry_id: str, *, ticket_type: int) -> dict[str, Any]:
		resp = self._post(
			f"refunds/{inquiry_id}?{urlencode({'type': int(ticket_type)})}",
			json_body={},
			headers=self._auth_headers(),
		)
		return self._parse_result(resp)
