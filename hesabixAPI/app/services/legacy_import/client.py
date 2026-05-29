from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

import httpx

from app.core.responses import ApiError
from app.services.legacy_import.constants import (
    DEFAULT_LEGACY_SERVER_URL,
    LEGACY_ARCHIVE_CREATE_PATH,
    LEGACY_BUSINESS_INFO_PATH,
    LEGACY_BUSINESS_LIST_PATH,
    LEGACY_HTTP_CONNECT_TIMEOUT_SEC,
    LEGACY_HTTP_MAX_ARCHIVE_BYTES,
    LEGACY_HTTP_TIMEOUT_SEC,
    LEGACY_PERSON_TYPES_PATH,
)
from app.services.legacy_import.mappers import normalize_server_url

logger = logging.getLogger(__name__)


class LegacyApiClient:
    """HTTP client for Hesabix v1 (legacy) REST API."""

    def __init__(
        self,
        server_url: str,
        api_key: str,
        *,
        timeout_sec: float = LEGACY_HTTP_TIMEOUT_SEC,
        max_archive_bytes: int = LEGACY_HTTP_MAX_ARCHIVE_BYTES,
    ) -> None:
        self.base_url = normalize_server_url(server_url or DEFAULT_LEGACY_SERVER_URL)
        self.api_key = (api_key or "").strip()
        self.timeout_sec = timeout_sec
        self.max_archive_bytes = max_archive_bytes
        if not self.api_key:
            raise ApiError(
                "LEGACY_API_KEY_REQUIRED",
                "کلید API نسخه قدیم الزامی است",
                http_status=400,
            )
        self._validate_base_url()

    def _validate_base_url(self) -> None:
        parsed = urlparse(self.base_url)
        if parsed.scheme not in ("http", "https") or not parsed.netloc:
            raise ApiError(
                "LEGACY_INVALID_SERVER_URL",
                "آدرس سرور نسخه قدیم معتبر نیست",
                http_status=400,
            )

    def _headers(self) -> Dict[str, str]:
        return {
            "Api-Key": self.api_key,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "HesabixV2-LegacyImport/1.0",
        }

    def _client(self) -> httpx.Client:
        return httpx.Client(
            base_url=self.base_url,
            headers=self._headers(),
            timeout=httpx.Timeout(
                self.timeout_sec,
                connect=LEGACY_HTTP_CONNECT_TIMEOUT_SEC,
            ),
            follow_redirects=True,
        )

    def _raise_for_status(self, response: httpx.Response, *, context: str) -> None:
        if response.status_code < 400:
            return
        body_preview = (response.text or "")[:500]
        if response.status_code in (401, 403):
            raise ApiError(
                "LEGACY_API_UNAUTHORIZED",
                "کلید API نسخه قدیم نامعتبر است یا دسترسی ندارد",
                http_status=401,
                details={"context": context, "status": response.status_code},
            )
        if response.status_code == 404:
            raise ApiError(
                "LEGACY_API_NOT_FOUND",
                f"مسیر API نسخه قدیم یافت نشد ({context})",
                http_status=400,
                details={"path": str(response.request.url)},
            )
        raise ApiError(
            "LEGACY_API_ERROR",
            f"خطا در ارتباط با سرور نسخه قدیم: {context}",
            http_status=502,
            details={
                "status": response.status_code,
                "body": body_preview,
            },
        )

    def test_connection(self) -> Dict[str, Any]:
        """Validate API key and return active business summary."""
        with self._client() as client:
            resp = client.post(LEGACY_BUSINESS_LIST_PATH, json={})
            self._raise_for_status(resp, context="business/list")
            businesses = resp.json()
            if not isinstance(businesses, list) or not businesses:
                raise ApiError(
                    "LEGACY_NO_BUSINESS",
                    "هیچ کسب‌وکاری برای این کلید API یافت نشد",
                    http_status=400,
                )
            biz = businesses[0]
            bid = biz.get("id")
            info: Dict[str, Any] = dict(biz)
            if bid is not None:
                detail = self.get_business_info(int(bid))
                info.update(detail)
            return {
                "legacy_business_id": bid,
                "business": info,
                "businesses_count": len(businesses),
            }

    def get_business_info(self, business_id: int) -> Dict[str, Any]:
        path = LEGACY_BUSINESS_INFO_PATH.format(bid=business_id)
        with self._client() as client:
            resp = client.get(path)
            self._raise_for_status(resp, context="business/info")
            data = resp.json()
            if not isinstance(data, dict):
                raise ApiError(
                    "LEGACY_INVALID_RESPONSE",
                    "پاسخ نامعتبر از سرور نسخه قدیم",
                    http_status=502,
                )
            return data

    def fetch_person_type_map(self) -> Dict[int, str]:
        """Build id→label map from legacy API when available."""
        with self._client() as client:
            resp = client.get(LEGACY_PERSON_TYPES_PATH)
            if resp.status_code >= 400:
                return {}
            payload = resp.json()
        mapping: Dict[int, str] = {}
        items: List[Any]
        if isinstance(payload, list):
            items = payload
        elif isinstance(payload, dict):
            items = payload.get("items") or payload.get("data") or []
        else:
            return mapping
        for row in items:
            if not isinstance(row, dict):
                continue
            rid = row.get("id")
            label = row.get("label") or row.get("name")
            if rid is not None and label:
                mapping[int(rid)] = str(label)
        return mapping

    def get_document_detail(self, document_id: int) -> Dict[str, Any]:
        """جزئیات سند حسابداری شامل سطرها (hesabdari/direct/doc/get)."""
        path = f"/api/hesabdari/direct/doc/get/{int(document_id)}"
        with self._client() as client:
            resp = client.get(path)
            self._raise_for_status(resp, context="hesabdari/direct/doc/get")
            payload = resp.json()
        if isinstance(payload, dict) and payload.get("success") and isinstance(payload.get("data"), dict):
            return payload["data"]
        if isinstance(payload, dict):
            return payload
        raise ApiError(
            "LEGACY_INVALID_RESPONSE",
            "پاسخ نامعتبر از جزئیات سند",
            http_status=502,
        )

    def download_archive(self) -> bytes:
        """Download full business archive ZIP from legacy server."""
        with self._client() as client:
            resp = client.post(LEGACY_ARCHIVE_CREATE_PATH, json={})
            self._raise_for_status(resp, context="backup/archive/create")
            content = resp.content
            if len(content) > self.max_archive_bytes:
                raise ApiError(
                    "LEGACY_ARCHIVE_TOO_LARGE",
                    "حجم آرشیو نسخه قدیم بیش از حد مجاز است",
                    http_status=400,
                    details={"size_bytes": len(content), "max_bytes": self.max_archive_bytes},
                )
            if len(content) < 32:
                raise ApiError(
                    "LEGACY_ARCHIVE_EMPTY",
                    "آرشیو دریافتی از نسخه قدیم خالی است",
                    http_status=400,
                )
            return content
