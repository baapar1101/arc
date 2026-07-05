from __future__ import annotations

import base64
import json
import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

import httpx
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization

from adapters.db.models.tax_setting import TaxSetting
from app.core.cache import get_cache
from app.core.responses import ApiError
from app.core.settings import Settings
from app.integrations.moadian.certificate import (
    certificate_to_x5c_base64,
    resolve_signing_certificate_pem,
)
from app.integrations.moadian.dto import InvoiceDto
from app.integrations.moadian.utils import extract_moadian_error_message
from app.integrations.moadian.v2_crypto import build_v2_packet, encrypt_jwe, sign_jws
from app.services.encryption_service import decrypt_private_key

logger = logging.getLogger(__name__)

_V2_PATH = "/requestsmanager/api/v2"


@dataclass
class MoadianClientConfig:
    base_url: str
    timeout_seconds: int
    user_agent: str
    simulate: bool


class MoadianV2Client:
    """
    کلاینت سامانه مودیان — API نسخه ۲ (گواهی‌محور، سازگار با moadian2).

    احراز هویت: nonce + JWS با گواهی امضا (x5c)
    ارسال فاکتور: sign + JWE + POST /invoice
    استعلام: GET /inquiry-by-reference-id
    """

    def __init__(self, settings: Settings, tax_setting: TaxSetting) -> None:
        sandbox = bool(tax_setting.sandbox_mode)
        root = settings.tax_system_sandbox_base_url if sandbox else settings.tax_system_production_base_url
        self.config = MoadianClientConfig(
            base_url=root.rstrip("/"),
            timeout_seconds=settings.tax_system_timeout_seconds,
            user_agent=settings.tax_system_user_agent,
            simulate=bool(settings.tax_system_force_simulation),
        )
        self._http_client: httpx.Client | None = None
        self.tax_memory_id = tax_setting.tax_memory_id
        self.economic_code = tax_setting.economic_code

        raw_private_key = tax_setting.private_key
        if raw_private_key:
            try:
                raw_private_key = decrypt_private_key(raw_private_key)
            except Exception:
                pass
        self.private_key = raw_private_key
        self.certificate = tax_setting.certificate

        self._signing_cert_pem: Optional[str] = None
        self._cert_x5c: Optional[str] = None
        self._private_key_obj = None

        if not self.config.simulate and self.private_key:
            self._signing_cert_pem = resolve_signing_certificate_pem(
                certificate=tax_setting.certificate,
            )
            self._cert_x5c = certificate_to_x5c_base64(self._signing_cert_pem)
            self._private_key_obj = self._load_private_key_obj(self.private_key)

        self._server_public_key: Optional[str] = None
        self._server_key_id: Optional[str] = None

        self._auth_token: Optional[str] = None
        self._token_expiry: Optional[datetime] = None

    def send_invoice(self, invoice_dto: InvoiceDto) -> Dict[str, Any]:
        if self.config.simulate:
            return self._simulate_submission(invoice_dto.to_dict())

        self._require_key_material()
        self._ensure_authenticated()

        payload_json = invoice_dto.to_json()
        server_public_pem = self._get_server_public_key_pem()

        signed = sign_jws(payload_json, self._private_key_obj, self._cert_x5c or "")
        encrypted = encrypt_jwe(signed, server_public_pem)
        packet = build_v2_packet(encrypted, self.tax_memory_id or "")

        response_data = self._request_json(
            "POST",
            "invoice",
            json_body=[packet],
            authorized=True,
        )
        return self._normalize_send_response(response_data)

    def inquire_status(self, tracking_codes: List[str]) -> Dict[str, Any]:
        if not tracking_codes:
            raise ApiError("INVALID_REQUEST", "شناسه رهگیری لازم است.", http_status=400)

        if self.config.simulate:
            return self._simulate_inquiry(tracking_codes)

        self._require_key_material()
        self._ensure_authenticated()

        aggregated: List[Dict[str, Any]] = []
        lock = threading.Lock()
        max_workers = min(len(tracking_codes), 5)

        def inquire_one(code: str) -> Dict[str, Any]:
            try:
                data = self._request_json(
                    "GET",
                    "inquiry-by-reference-id",
                    params={"referenceIds": [code]},
                    authorized=True,
                )
                return self._normalize_inquiry_response(code, data)
            except ApiError as exc:
                return {
                    "reference_number": code,
                    "status": "failed",
                    "error_message": str(exc),
                    "inquiry_at": datetime.utcnow().isoformat(),
                }
            except httpx.HTTPError as exc:
                return {
                    "reference_number": code,
                    "status": "failed",
                    "error_message": f"خطا در ارتباط: {exc}",
                    "inquiry_at": datetime.utcnow().isoformat(),
                }

        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            futures = {pool.submit(inquire_one, code): code for code in tracking_codes}
            for future in as_completed(futures):
                try:
                    result = future.result()
                except Exception as exc:
                    code = futures[future]
                    result = {
                        "reference_number": code,
                        "status": "failed",
                        "error_message": str(exc),
                        "inquiry_at": datetime.utcnow().isoformat(),
                    }
                with lock:
                    aggregated.append(result)

        order = {code: i for i, code in enumerate(tracking_codes)}
        aggregated.sort(key=lambda item: order.get(item.get("reference_number", ""), 999))
        return {"mode": "live", "results": aggregated}

    def get_server_information(self) -> Dict[str, Any]:
        if self.config.simulate:
            return {"publicKeys": [{"id": "sim", "key": "SIMKEY", "algorithm": "RSA"}]}

        self._require_key_material()
        data = self._request_json("GET", "server-information", authorized=True)
        self._extract_server_public_key(data)
        return data

    def login(self) -> str:
        if self.config.simulate:
            token = f"SIM-TOKEN-{self.tax_memory_id}-{int(time.time())}"
            self._auth_token = token
            self._token_expiry = datetime.utcnow() + timedelta(hours=1)
            return token

        self._require_key_material()
        token = self._fetch_auth_token()
        self._auth_token = token
        self._token_expiry = datetime.utcnow() + timedelta(minutes=25)
        self._cache_token(token, self._token_expiry)
        return token

    def close(self) -> None:
        if self._http_client is not None:
            self._http_client.close()
            self._http_client = None

    def _ensure_authenticated(self) -> None:
        cache_key = f"tax_token_v2:{self.tax_memory_id}"
        cache = get_cache()
        cached = cache.get(cache_key) if cache.enabled else None
        if cached and isinstance(cached, dict):
            token = cached.get("token")
            expiry_str = cached.get("expiry")
            if token and expiry_str:
                try:
                    expiry = datetime.fromisoformat(expiry_str)
                    if datetime.utcnow() < expiry - timedelta(minutes=2):
                        self._auth_token = token
                        self._token_expiry = expiry
                        return
                except (TypeError, ValueError):
                    pass

        if self._auth_token and self._token_expiry:
            if datetime.utcnow() < self._token_expiry - timedelta(minutes=2):
                return

        token = self._fetch_auth_token()
        expiry = datetime.utcnow() + timedelta(minutes=25)
        self._auth_token = token
        self._token_expiry = expiry
        self._cache_token(token, expiry)

    def _ensure_server_information(self) -> None:
        if self._server_public_key:
            return

        cache = get_cache()
        is_sandbox = "sandbox" in self.config.base_url.lower()
        cache_key = f"tax_server_public_key_v2:{'sandbox' if is_sandbox else 'production'}"
        cached = cache.get(cache_key) if cache.enabled else None
        if cached and isinstance(cached, dict):
            self._server_public_key = cached.get("public_key")
            self._server_key_id = cached.get("key_id")
            if self._server_public_key:
                return

        self.get_server_information()
        if cache.enabled and self._server_public_key:
            cache.set(
                cache_key,
                {"public_key": self._server_public_key, "key_id": self._server_key_id},
                ttl=86400,
            )

    def _v2_url(self, endpoint: str) -> str:
        return f"{self.config.base_url}{_V2_PATH}/{endpoint.lstrip('/')}"

    def _fetch_auth_token(self) -> str:
        nonce_data = self._request_json("GET", "nonce", authorized=False)
        nonce = nonce_data.get("nonce")
        if not nonce:
            raise ApiError(
                "TAX_LOGIN_FAILED",
                "nonce از سامانه مودیان دریافت نشد.",
                http_status=502,
                details={"raw_response": nonce_data},
            )
        payload = json.dumps(
            {"nonce": nonce, "clientId": self.tax_memory_id or ""},
            ensure_ascii=False,
            separators=(",", ":"),
        )
        return sign_jws(payload, self._private_key_obj, self._cert_x5c or "")

    def _request_json(
        self,
        method: str,
        endpoint: str,
        *,
        params: Dict[str, Any] | None = None,
        json_body: Any = None,
        authorized: bool = False,
    ) -> Dict[str, Any]:
        headers: Dict[str, str] = {
            "User-Agent": self.config.user_agent,
            "Accept": "application/json",
        }
        if json_body is not None:
            headers["Content-Type"] = "application/json"
        if authorized:
            if not self._auth_token:
                self._auth_token = self._fetch_auth_token()
            headers["Authorization"] = f"Bearer {self._auth_token}"

        client = self._get_http_client()
        response = client.request(
            method,
            self._v2_url(endpoint),
            params=params,
            json=json_body,
            headers=headers,
            timeout=self.config.timeout_seconds,
        )
        try:
            data = response.json()
        except Exception:
            data = {"raw_body": response.text}

        if response.status_code >= 400 or (isinstance(data, dict) and data.get("errors")):
            self._raise_remote_error(data, response.status_code, endpoint)

        return data if isinstance(data, dict) else {"raw": data}

    def _raise_remote_error(self, data: Dict[str, Any], status_code: int, endpoint: str) -> None:
        errors = data.get("errors") or []
        messages: List[str] = []
        if isinstance(errors, list):
            for item in errors:
                if isinstance(item, dict) and item.get("message"):
                    messages.append(str(item["message"]))
        msg = " / ".join(messages).strip() or "خطا از سمت سامانه مودیان"
        err_code = "TAX_REMOTE_ERROR"
        if endpoint == "nonce":
            err_code = "TAX_LOGIN_FAILED"
        elif "گواهی" in msg:
            err_code = "TAX_CERTIFICATE_INVALID"
        http_status = 502
        if status_code in (400, 401, 403) and err_code != "TAX_LOGIN_FAILED":
            http_status = 400
        raise ApiError(
            err_code,
            msg,
            http_status=http_status,
            details={"raw_response": data, "status_code": status_code, "endpoint": endpoint},
        )

    def _get_server_public_key_pem(self) -> str:
        self._ensure_server_information()
        if not self._server_public_key:
            raise ApiError(
                "TAX_SERVER_PUBLIC_KEY_MISSING",
                "کلید عمومی سازمان مالیاتی دریافت نشد.",
                http_status=502,
            )
        raw = self._server_public_key.replace("\r\n", "\n").replace("\r", "\n")
        if "-----BEGIN" not in raw:
            raw = f"-----BEGIN PUBLIC KEY-----\n{raw}\n-----END PUBLIC KEY-----"
        return raw

    def _extract_server_public_key(self, data: Dict[str, Any]) -> None:
        public_keys = data.get("publicKeys")
        if not isinstance(public_keys, list) or not public_keys:
            result = data.get("result")
            if isinstance(result, dict):
                public_keys = result.get("publicKeys")
        if not isinstance(public_keys, list) or not public_keys:
            raise ApiError(
                "TAX_SERVER_PUBLIC_KEY_MISSING",
                "کلید عمومی سازمان در پاسخ server-information یافت نشد.",
                http_status=502,
                details={"raw_response": data},
            )
        first = public_keys[0]
        if not isinstance(first, dict) or not first.get("key"):
            raise ApiError(
                "TAX_SERVER_PUBLIC_KEY_MISSING",
                "فرمت کلید عمومی سازمان نامعتبر است.",
                http_status=502,
                details={"raw_response": data},
            )
        self._server_public_key = str(first["key"])
        self._server_key_id = str(first.get("id") or "")

    def _normalize_send_response(self, data: Dict[str, Any]) -> Dict[str, Any]:
        result_list = data.get("result")
        if not isinstance(result_list, list) or not result_list:
            raise ApiError(
                "TAX_SUBMISSION_FAILED",
                extract_moadian_error_message(data.get("errors", {})) or "پاسخ نامعتبر از سامانه",
                http_status=502,
                details={"raw_response": data},
            )
        first = result_list[0] if isinstance(result_list[0], dict) else {}
        if first.get("errorCode") or first.get("errorDetail"):
            raise ApiError(
                "TAX_SUBMISSION_FAILED",
                extract_moadian_error_message(
                    {"code": first.get("errorCode"), "message": first.get("errorDetail")}
                ),
                http_status=400,
                details={"raw_response": data},
            )
        tracking = (
            first.get("referenceNumber")
            or first.get("reference_number")
            or first.get("uid")
        )
        return {
            "mode": "live",
            "tracking_code": tracking,
            "uid": first.get("uid"),
            "status": "sent",
            "raw_response": data,
            "sent_at": datetime.utcnow().isoformat(),
        }

    def _normalize_inquiry_response(self, code: str, data: Dict[str, Any]) -> Dict[str, Any]:
        now = datetime.utcnow().isoformat()
        items = data.get("result") or data.get("data") or data.get("results")
        if isinstance(items, dict):
            items = [items]
        if not isinstance(items, list):
            items = []

        matched: Dict[str, Any] | None = None
        for item in items:
            if not isinstance(item, dict):
                continue
            ref = item.get("referenceNumber") or item.get("reference_number") or item.get("referenceId")
            if ref is None or str(ref) == str(code):
                matched = item
                break
        if matched is None and items and isinstance(items[0], dict):
            matched = items[0]

        if matched is None:
            return {
                "reference_number": code,
                "status": "failed",
                "error_message": "پاسخ استعلام یافت نشد",
                "inquiry_at": now,
                "raw_data": data,
            }

        status = matched.get("status") or matched.get("invoiceStatus")
        inner = matched.get("data") if isinstance(matched.get("data"), dict) else {}
        errors = inner.get("error") if isinstance(inner.get("error"), list) else []
        error_msg = None
        if errors and isinstance(errors[0], dict):
            error_msg = extract_moadian_error_message(errors[0])

        if str(status or "").upper() == "FAILED" or errors:
            return {
                "reference_number": code,
                "status": "failed",
                "uid": matched.get("uid"),
                "error_message": error_msg,
                "inquiry_at": now,
                "raw_data": matched,
            }

        return {
            "reference_number": code,
            "status": str(status or "unknown").lower(),
            "uid": matched.get("uid"),
            "confirmation_date": matched.get("confirmationDate") or matched.get("confirmation_date"),
            "inquiry_at": now,
            "raw_data": matched,
        }

    def _require_key_material(self) -> None:
        if not self.private_key:
            raise ApiError("TAX_SETTINGS_INCOMPLETE", "کلید خصوصی برای ارسال الزامی است.", http_status=400)
        if not self._signing_cert_pem or not self._private_key_obj:
            resolve_signing_certificate_pem(certificate=self.certificate)

    def _cache_token(self, token: str, expiry: datetime) -> None:
        cache = get_cache()
        if not cache.enabled:
            return
        ttl = int((expiry - datetime.utcnow()).total_seconds())
        if ttl > 0:
            cache.set(
                f"tax_token_v2:{self.tax_memory_id}",
                {"token": token, "expiry": expiry.isoformat()},
                ttl=ttl,
            )

    def _load_private_key_obj(self, raw: str):
        pem = (raw or "").strip().replace("\r\n", "\n").replace("\r", "\n")
        if "-----BEGIN" in pem:
            return serialization.load_pem_private_key(
                pem.encode("utf-8"),
                password=None,
                backend=default_backend(),
            )
        der = base64.b64decode("".join(pem.split()))
        return serialization.load_der_private_key(der, password=None, backend=default_backend())

    def _get_http_client(self) -> httpx.Client:
        if self._http_client is None:
            self._http_client = httpx.Client(timeout=self.config.timeout_seconds)
        return self._http_client

    def _simulate_submission(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        document_id = payload.get("id") or payload.get("document_id") or "DOC"
        tracking = f"SIM-{document_id}-{int(time.time())}"
        return {
            "mode": "simulation",
            "tracking_code": tracking,
            "status": "sent",
            "sent_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "raw_response": {
                "echo": payload,
                "tax_memory_id": self.tax_memory_id,
                "economic_code": self.economic_code,
            },
        }

    def _simulate_inquiry(self, tracking_codes: List[str]) -> Dict[str, Any]:
        results = []
        for code in tracking_codes:
            status = "sent"
            if "FAIL" in code:
                status = "failed"
            elif "FINAL" in code:
                status = "finalized"
            results.append(
                {
                    "reference_number": code,
                    "status": status,
                    "inquiry_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                }
            )
        return {"mode": "simulation", "results": results}

    def __del__(self) -> None:
        try:
            self.close()
        except Exception:
            pass
