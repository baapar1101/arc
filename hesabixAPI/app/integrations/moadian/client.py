"""
Facade for Moadian tax API clients.

- API v2 (certificate + private key): moadian2-compatible JWS flow
- API v1 (private key only): packet-based flow when no PEM certificate is stored
  (typical when only the public key is registered in the Moadian portal)
"""
from __future__ import annotations

from typing import Any, Dict, List

from adapters.db.models.tax_setting import TaxSetting
from app.core.settings import Settings
from app.integrations.moadian.dto import InvoiceDto
from app.integrations.moadian.certificate import is_usable_signing_certificate_pem
from app.integrations.moadian.v1_client import MoadianV1Client
from app.integrations.moadian.v2_client import MoadianV2Client
from app.services.encryption_service import decrypt_private_key


def uses_moadian_v2(tax_setting: TaxSetting | None) -> bool:
    """
    API v2 فقط وقتی فعال است که گواهی X.509 معتبر (و هم‌جفت با کلید خصوصی) داشته باشیم.
    در غیر این صورت v1 (مشابه SDK قدیمی PHP / Snapp-Market moadian) استفاده می‌شود.
    """
    if not tax_setting:
        return False
    private_key = (tax_setting.private_key or "").strip()
    if private_key:
        try:
            private_key = decrypt_private_key(private_key)
        except Exception:
            pass
    return is_usable_signing_certificate_pem(
        tax_setting.certificate,
        private_key_pem=private_key or None,
    )


class MoadianClient:
    """Unified client — picks v1 or v2 based on stored certificate."""

    def __init__(self, settings: Settings, tax_setting: TaxSetting) -> None:
        self.api_version = "v2" if uses_moadian_v2(tax_setting) else "v1"
        self.tax_memory_id = tax_setting.tax_memory_id
        self.economic_code = tax_setting.economic_code
        self.certificate = tax_setting.certificate
        if self.api_version == "v2":
            self._inner: MoadianV1Client | MoadianV2Client = MoadianV2Client(
                settings, tax_setting
            )
        else:
            self._inner = MoadianV1Client(settings, tax_setting)

    @property
    def config(self):
        return self._inner.config

    def send_invoice(self, invoice_dto: InvoiceDto) -> Dict[str, Any]:
        result = self._inner.send_invoice(invoice_dto)
        if isinstance(result, dict):
            result.setdefault("api_version", self.api_version)
        return result

    def inquire_status(self, tracking_codes: List[str]) -> Dict[str, Any]:
        result = self._inner.inquire_status(tracking_codes)
        if isinstance(result, dict):
            result.setdefault("api_version", self.api_version)
        return result

    def get_server_information(self) -> Dict[str, Any]:
        return self._inner.get_server_information()

    def login(self) -> str:
        return self._inner.login()

    def close(self) -> None:
        self._inner.close()

    def __del__(self) -> None:
        try:
            self.close()
        except Exception:
            pass
