from __future__ import annotations

import time
import json
import base64
from dataclasses import dataclass
from typing import Any, Dict, List, Optional
from datetime import datetime

import httpx
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.backends import default_backend
from cryptography.exceptions import InvalidSignature

from app.core.responses import ApiError
from app.core.settings import Settings
from adapters.db.models.tax_setting import TaxSetting
from app.integrations.moadian.dto import InvoiceDto, MoadianApiResponse
from app.integrations.moadian.utils import extract_moadian_error_message


@dataclass
class MoadianClientConfig:
    base_url: str
    timeout_seconds: int
    user_agent: str
    simulate: bool


class MoadianClient:
    """
    کلاینت ارتباط با سامانه مودیان مالیاتی
    
    ویژگی‌ها:
    - پشتیبانی از Sandbox و Production
    - امضای دیجیتال payloadها
    - مدیریت token و session
    - دریافت کلید عمومی سرور
    - ارسال و استعلام فاکتورها
    """

    def __init__(self, settings: Settings, tax_setting: TaxSetting) -> None:
        sandbox = bool(tax_setting.sandbox_mode)
        base_url = settings.tax_system_sandbox_base_url if sandbox else settings.tax_system_production_base_url
        self.config = MoadianClientConfig(
            base_url=base_url.rstrip("/"),
            timeout_seconds=settings.tax_system_timeout_seconds,
            user_agent=settings.tax_system_user_agent,
            simulate=bool(settings.tax_system_force_simulation),  # حذف شرط sandbox
        )
        self._http_client: httpx.Client | None = None
        self.tax_memory_id = tax_setting.tax_memory_id
        self.economic_code = tax_setting.economic_code
        self.private_key = tax_setting.private_key
        self.public_key = tax_setting.public_key
        self.certificate = tax_setting.certificate
        
        # کلید عمومی و ID سرور مالیاتی
        self._server_public_key: Optional[str] = None
        self._server_key_id: Optional[str] = None
        
        # Token احراز هویت
        self._auth_token: Optional[str] = None
        self._token_expiry: Optional[datetime] = None

    def send_invoice(self, invoice_dto: InvoiceDto) -> Dict[str, Any]:
        """
        ارسال فاکتور به سامانه مودیان
        
        Args:
            invoice_dto: DTO فاکتور آماده شده
        
        Returns:
            نتیجه ارسال شامل کد رهگیری و وضعیت
        """
        if self.config.simulate:
            return self._simulate_submission(invoice_dto.to_dict())

        if not self.private_key:
            raise ApiError("TAX_SETTINGS_INCOMPLETE", "کلید خصوصی برای ارسال الزامی است.", http_status=400)

        # اطمینان از لاگین
        self._ensure_authenticated()
        
        # تبدیل DTO به دیکشنری
        payload = invoice_dto.to_dict()
        
        # امضای دیجیتال payload
        signed_payload = self._sign_payload(payload)
        
        client = self._get_http_client()
        
        try:
            response = client.post(
                "/api/self-tsp/sync/SEND_INVOICE",
                json={"body": [signed_payload]},
                timeout=self.config.timeout_seconds,
                headers=self._get_auth_headers(),
            )
            response.raise_for_status()
            data = response.json()
            
            # پردازش پاسخ
            api_response = MoadianApiResponse.from_dict(data)
            
            if not api_response.success:
                error_msg = extract_moadian_error_message(api_response.error or {})
                raise ApiError(
                    "TAX_SUBMISSION_FAILED",
                    error_msg,
                    http_status=400,
                    details={"raw_response": data},
                )
            
            # استخراج نتیجه
            result = api_response.result or {}
            first_result = result.get('result', [{}])[0] if isinstance(result.get('result'), list) else {}
            
            return {
                "mode": "live",
                "tracking_code": first_result.get('referenceNumber') or first_result.get('uid'),
                "uid": first_result.get('uid'),
                "status": "sent",
                "raw_response": data,
                "sent_at": datetime.utcnow().isoformat(),
            }
        except httpx.HTTPError as exc:
            raise ApiError(
                "TAX_NETWORK_ERROR",
                "خطا در ارتباط با سامانه مودیان",
                http_status=502,
                details={"message": str(exc)},
            ) from exc

    def inquire_status(self, tracking_codes: List[str]) -> Dict[str, Any]:
        """
        استعلام وضعیت فاکتورها از سامانه
        
        Args:
            tracking_codes: لیست کدهای رهگیری
        
        Returns:
            نتایج استعلام
        """
        if not tracking_codes:
            raise ApiError("INVALID_REQUEST", "شناسه رهگیری لازم است.", http_status=400)

        if self.config.simulate:
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
            return {
                "mode": "simulation",
                "results": results,
            }

        # اطمینان از احراز هویت
        self._ensure_authenticated()
        
        client = self._get_http_client()
        aggregated: List[Dict[str, Any]] = []
        
        for code in tracking_codes:
            try:
                # ساخت payload استعلام
                inquiry_payload = {
                    "referenceNumber": [code]
                }
                
                # امضای payload
                signed_payload = self._sign_payload(inquiry_payload)
                
                response = client.post(
                    "/api/self-tsp/sync/INQUIRY_BY_REFERENCE_NUMBER",
                    json={"body": [signed_payload]},
                    timeout=self.config.timeout_seconds,
                    headers=self._get_auth_headers(),
                )
                response.raise_for_status()
                data = response.json()
                
                api_response = MoadianApiResponse.from_dict(data)
                
                if api_response.success and api_response.result:
                    result_data = api_response.result.get('result', [{}])[0] if isinstance(api_response.result.get('result'), list) else {}
                    aggregated.append({
                        "reference_number": code,
                        "status": result_data.get('status', 'unknown'),
                        "uid": result_data.get('uid'),
                        "confirmation_date": result_data.get('confirmationDate'),
                        "inquiry_at": datetime.utcnow().isoformat(),
                        "raw_data": result_data,
                    })
                else:
                    error_msg = extract_moadian_error_message(api_response.error or {})
                    aggregated.append({
                        "reference_number": code,
                        "status": "failed",
                        "error_message": error_msg,
                        "inquiry_at": datetime.utcnow().isoformat(),
                    })
                    
            except httpx.HTTPError as exc:
                aggregated.append({
                    "reference_number": code,
                    "status": "failed",
                    "error_message": f"خطا در ارتباط: {str(exc)}",
                    "inquiry_at": datetime.utcnow().isoformat(),
                })

        return {
            "mode": "live",
            "results": aggregated,
        }

    def get_server_information(self) -> Dict[str, Any]:
        """
        دریافت اطلاعات سرور شامل کلید عمومی سازمان مالیاتی
        
        Returns:
            اطلاعات سرور شامل publicKey و keyId
        """
        client = self._get_http_client()
        
        try:
            response = client.get(
                "/api/self-tsp/GET_SERVER_INFORMATION",
                timeout=self.config.timeout_seconds,
            )
            response.raise_for_status()
            data = response.json()
            
            api_response = MoadianApiResponse.from_dict(data)
            
            if not api_response.success or not api_response.result:
                raise ApiError(
                    "TAX_SERVER_INFO_FAILED",
                    "خطا در دریافت اطلاعات سرور مالیاتی",
                    http_status=502,
                )
            
            # ذخیره کلید عمومی سرور
            public_keys = api_response.result.get('publicKeys', [])
            if public_keys:
                self._server_public_key = public_keys[0].get('key')
                self._server_key_id = public_keys[0].get('id')
            
            return api_response.result
            
        except httpx.HTTPError as exc:
            raise ApiError(
                "TAX_NETWORK_ERROR",
                "خطا در اتصال به سرور مالیاتی",
                http_status=502,
                details={"message": str(exc)},
            ) from exc

    def login(self) -> str:
        """
        لاگین به سامانه و دریافت token
        
        Returns:
            Authentication token
        """
        # ابتدا اطلاعات سرور را دریافت می‌کنیم (اگر قبلا دریافت نشده)
        if not self._server_public_key:
            self.get_server_information()
        
        if not self.private_key:
            raise ApiError("TAX_SETTINGS_INCOMPLETE", "کلید خصوصی برای لاگین الزامی است.", http_status=400)
        
        # ساخت payload لاگین
        username = self.tax_memory_id
        
        client = self._get_http_client()
        
        try:
            response = client.post(
                "/api/self-tsp/LOGIN",
                json={"username": username},
                timeout=self.config.timeout_seconds,
            )
            response.raise_for_status()
            data = response.json()
            
            api_response = MoadianApiResponse.from_dict(data)
            
            if not api_response.success or not api_response.result:
                error_msg = extract_moadian_error_message(api_response.error or {})
                raise ApiError(
                    "TAX_LOGIN_FAILED",
                    f"خطا در احراز هویت: {error_msg}",
                    http_status=401,
                )
            
            # استخراج token
            token = api_response.result.get('token')
            if not token:
                raise ApiError("TAX_LOGIN_FAILED", "توکن احراز هویت دریافت نشد", http_status=401)
            
            # ذخیره token
            self._auth_token = token
            # فرض: token 24 ساعت اعتبار دارد
            from datetime import timedelta
            self._token_expiry = datetime.utcnow() + timedelta(hours=24)
            
            return token
            
        except httpx.HTTPError as exc:
            raise ApiError(
                "TAX_NETWORK_ERROR",
                "خطا در ارتباط با سرور احراز هویت",
                http_status=502,
                details={"message": str(exc)},
            ) from exc

    def _ensure_authenticated(self) -> None:
        """اطمینان از وجود token معتبر"""
        # بررسی انقضای token
        if self._auth_token and self._token_expiry:
            if datetime.utcnow() < self._token_expiry:
                return  # token هنوز معتبر است
        
        # لاگین مجدد
        self.login()

    def _sign_payload(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """
        امضای دیجیتال payload با کلید خصوصی
        
        Args:
            payload: داده برای امضا
        
        Returns:
            payload امضا شده
        """
        if not self.private_key:
            raise ApiError("TAX_SETTINGS_INCOMPLETE", "کلید خصوصی برای امضا الزامی است.", http_status=400)
        
        try:
            # تبدیل payload به JSON string
            json_str = json.dumps(payload, ensure_ascii=False, separators=(',', ':'))
            json_bytes = json_str.encode('utf-8')
            
            # بارگذاری کلید خصوصی
            private_key_obj = serialization.load_pem_private_key(
                self.private_key.encode('utf-8'),
                password=None,
                backend=default_backend()
            )
            
            # امضا کردن
            signature = private_key_obj.sign(
                json_bytes,
                padding.PKCS1v15(),
                hashes.SHA256()
            )
            
            # تبدیل امضا به base64
            signature_b64 = base64.b64encode(signature).decode('utf-8')
            
            # برگرداندن payload با امضا
            return {
                "data": payload,
                "signature": signature_b64,
                "signatureType": "SHA256withRSA",
            }
            
        except Exception as exc:
            raise ApiError(
                "TAX_SIGNATURE_FAILED",
                f"خطا در امضای دیجیتال: {str(exc)}",
                http_status=500,
            ) from exc

    def _get_auth_headers(self) -> Dict[str, str]:
        """ساخت هدرهای HTTP برای درخواست‌ها"""
        headers = {
            "User-Agent": self.config.user_agent,
            "Content-Type": "application/json",
        }
        
        if self._auth_token:
            headers["Authorization"] = f"Bearer {self._auth_token}"
        
        return headers

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
            "raw_response": {
                "echo": payload,
                "tax_memory_id": self.tax_memory_id,
                "economic_code": self.economic_code,
            },
        }

    def __del__(self) -> None:
        try:
            self.close()
        except Exception:
            pass

