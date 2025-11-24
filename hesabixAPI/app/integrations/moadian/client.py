from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Dict

import httpx

from app.core.responses import ApiError
from app.core.settings import Settings
from adapters.db.models.tax_setting import TaxSetting


@dataclass
class MoadianClientConfig:
    base_url: str
    timeout_seconds: int
    user_agent: str
    simulate: bool


class MoadianClient:
    """
    Wrapper around سامانه مودیان HTTP APIs.

    Notes:
        - در حال حاضر فقط حالت شبیه‌سازی فعال است.
        - ساختار کلاس به شکلی طراحی شده که به‌محض آماده شدن پیاده‌سازی واقعی،
          تنها منطق درونی متدهای send_invoice/inquire_status تغییر کند.
    """

    def __init__(self, settings: Settings, tax_setting: TaxSetting) -> None:
        sandbox = bool(tax_setting.sandbox_mode)
        base_url = settings.tax_system_sandbox_base_url if sandbox else settings.tax_system_production_base_url
        self.config = MoadianClientConfig(
            base_url=base_url.rstrip("/"),
            timeout_seconds=settings.tax_system_timeout_seconds,
            user_agent=settings.tax_system_user_agent,
            simulate=bool(settings.tax_system_force_simulation or sandbox),
        )
        self._http_client: httpx.Client | None = None

    def send_invoice(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        if self.config.simulate:
            return self._simulate_submission(payload)

        client = self._get_http_client()
        try:
            response = client.post(
                "/api/v2/invoices",
                json=payload,
                timeout=self.config.timeout_seconds,
                headers={"User-Agent": self.config.user_agent},
            )
            response.raise_for_status()
            data = response.json()
            return {
                "mode": "live",
                "tracking_code": data.get("tracking_code"),
                "status": data.get("status") or "pending",
                "raw_response": data,
            }
        except httpx.HTTPError as exc:
            raise ApiError(
                "TAX_NETWORK_ERROR",
                "خطا در ارتباط با سامانه مودیان",
                http_status=502,
                details={"message": str(exc)},
            ) from exc

    def inquire_status(self, tracking_code: str) -> Dict[str, Any]:
        if self.config.simulate:
            return {
                "mode": "simulation",
                "tracking_code": tracking_code,
                "status": "sent",
            }
        client = self._get_http_client()
        try:
            response = client.get(
                f"/api/v2/invoices/{tracking_code}",
                timeout=self.config.timeout_seconds,
                headers={"User-Agent": self.config.user_agent},
            )
            response.raise_for_status()
            return response.json()
        except httpx.HTTPError as exc:
            raise ApiError(
                "TAX_NETWORK_ERROR",
                "خطا در استعلام وضعیت از سامانه مودیان",
                http_status=502,
                details={"message": str(exc)},
            ) from exc

    def close(self) -> None:
        if self._http_client is not None:
            self._http_client.close()
            self._http_client = None

    def _get_http_client(self) -> httpx.Client:
        if self._http_client is None:
            self._http_client = httpx.Client(
                base_url=self.config.base_url,
                timeout=self.config.timeout_seconds,
            )
        return self._http_client

    def _simulate_submission(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        document_id = payload.get("id") or payload.get("document_id") or "DOC"
        tracking = f"SIM-{document_id}-{int(time.time())}"
        return {
            "mode": "simulation",
            "tracking_code": tracking,
            "status": "sent",
            "sent_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "raw_payload": payload,
        }

    def __del__(self) -> None:
        try:
            self.close()
        except Exception:
            pass

