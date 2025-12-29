from __future__ import annotations

import time
import json
import base64
import uuid
import os
import logging
from dataclasses import dataclass
from typing import Any, Dict, List, Optional
from datetime import datetime, timedelta

import httpx

logger = logging.getLogger(__name__)
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding as sympadding
from cryptography.hazmat.primitives import constant_time
from cryptography.hazmat.primitives import keywrap
from cryptography.hazmat.backends import default_backend
from cryptography.exceptions import InvalidSignature

from app.core.responses import ApiError
from app.core.settings import Settings
from adapters.db.models.tax_setting import TaxSetting
from app.integrations.moadian.dto import InvoiceDto, MoadianApiResponse
from app.integrations.moadian.utils import extract_moadian_error_message
from app.services.encryption_service import decrypt_private_key


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
            # فقط زمانی شبیه‌سازی می‌کنیم که صراحتاً در تنظیمات فعال شده باشد
            simulate=bool(settings.tax_system_force_simulation),
        )
        self._http_client: httpx.Client | None = None
        self.tax_memory_id = tax_setting.tax_memory_id
        self.economic_code = tax_setting.economic_code
        # کلید خصوصی ممکن است رمزگذاری شده باشد؛ تلاش برای رمزگشایی
        raw_private_key = tax_setting.private_key
        if raw_private_key:
            try:
                raw_private_key = decrypt_private_key(raw_private_key)
            except Exception:
                # اگر رمزگشایی ناموفق بود، همان مقدار ذخیره‌شده استفاده می‌شود
                pass
        self.private_key = raw_private_key
        self.public_key = tax_setting.public_key
        self.certificate = tax_setting.certificate
        
        # کلید عمومی و ID سرور مالیاتی
        # در محیط ابری: این کلید برای همه کسب‌وکارها یکسان است و از cache دریافت می‌شود
        self._server_public_key: Optional[str] = None
        self._server_key_id: Optional[str] = None
        self._fetching_server_info: bool = False  # Flag برای جلوگیری از حلقه بازگشتی
        
        # Token احراز هویت (مختص هر کسب‌وکار)
        self._auth_token: Optional[str] = None
        self._token_expiry: Optional[datetime] = None

    def send_invoice(self, invoice_dto: InvoiceDto) -> Dict[str, Any]:
        """
        ارسال فاکتور به سامانه مودیان (با استفاده از packet-based approach مطابق SDK PHP)
        
        Args:
            invoice_dto: DTO فاکتور آماده شده
        
        Returns:
            نتیجه ارسال شامل کد رهگیری و وضعیت
        """
        if self.config.simulate:
            return self._simulate_submission(invoice_dto.to_dict())

        if not self.private_key:
            raise ApiError("TAX_SETTINGS_INCOMPLETE", "کلید خصوصی برای ارسال الزامی است.", http_status=400)

        # دریافت اطلاعات سرور و اطمینان از توکن معتبر مشابه فلو SDK PHP
        self._ensure_server_information()
        self._ensure_authenticated()
        
        # تبدیل DTO به دیکشنری
        payload = invoice_dto.to_dict()
        
        # استفاده از packet-based approach مطابق SDK PHP
        # در کتابخانه PHP: path = 'req/api/self-tsp/async/normal-enqueue'
        # packet_type = PacketType::INVOICE_V01
        # packet_data = InvoiceDto (مستقیماً)
        try:
            # ارسال با async endpoint مطابق کتابخانه PHP
            response_data = self._send_async_packet(
                packet_type="INVOICE.V01",  # مطابق PacketType::INVOICE_V01 در PHP (که مقدار آن 'INVOICE.V01' است)
                packet_data=payload,  # مستقیماً InvoiceDto (نه درون object)
                fiscal_id=self.tax_memory_id or "",
                authorization_required=True,
            )
            
            # پردازش پاسخ مطابق کتابخانه PHP
            # پاسخ از async endpoint: { timestamp: <int>, result: [{ uid, referenceNumber, errorCode, errorDetail }] }
            if not isinstance(response_data, dict):
                raise ApiError(
                    "TAX_SUBMISSION_FAILED",
                    "فرمت پاسخ نامعتبر از سامانه",
                    http_status=502,
                    details={"raw_response": response_data},
                )
            
            result_list = response_data.get('result', [])
            if not isinstance(result_list, list) or not result_list:
                error_msg = extract_moadian_error_message(response_data.get("errors", {}))
                raise ApiError(
                    "TAX_SUBMISSION_FAILED",
                    error_msg or "پاسخ نامعتبر از سامانه",
                    http_status=502,
                    details={"raw_response": response_data},
                )
            
            first_result = result_list[0] if isinstance(result_list[0], dict) else {}
            
            # بررسی خطا در نتیجه
            if first_result.get('errorCode') or first_result.get('errorDetail'):
                error_msg = extract_moadian_error_message({
                    'code': first_result.get('errorCode'),
                    'message': first_result.get('errorDetail'),
                })
                raise ApiError(
                    "TAX_SUBMISSION_FAILED",
                    error_msg,
                    http_status=400,
                    details={"raw_response": response_data},
                )
            
            return {
                "mode": "live",
                "tracking_code": first_result.get('referenceNumber') or first_result.get('uid') or first_result.get('reference_number'),
                "uid": first_result.get('uid'),
                "status": "sent",
                "raw_response": response_data,
                "sent_at": datetime.utcnow().isoformat(),
            }
        except ApiError:
            raise
        except httpx.HTTPError as exc:
            raise ApiError(
                "TAX_NETWORK_ERROR",
                "خطا در ارتباط با سامانه مودیان",
                http_status=502,
                details={"message": str(exc)},
            ) from exc
        except Exception as exc:
            raise ApiError(
                "TAX_SUBMISSION_FAILED",
                f"خطا در ارسال فاکتور: {str(exc)}",
                http_status=500,
                details={"error": str(exc)},
            ) from exc

    def inquire_status(self, tracking_codes: List[str]) -> Dict[str, Any]:
        """
        استعلام وضعیت فاکتورها از سامانه (با استفاده از packet-based approach و parallel requests)
        
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

        # اطمینان از دریافت کلید سرور و احراز هویت
        self._ensure_server_information()
        self._ensure_authenticated()
        
        # استفاده از parallel requests برای بهبود کارایی
        from concurrent.futures import ThreadPoolExecutor, as_completed
        import threading
        
        aggregated: List[Dict[str, Any]] = []
        lock = threading.Lock()
        
        def inquire_single_code(code: str) -> Dict[str, Any]:
            """استعلام وضعیت یک کد رهگیری"""
            try:
                # استفاده از packet-based approach
                response_data = self._send_sync_packet(
                    packet_type="INQUIRY_BY_REFERENCE_NUMBER",
                    packet_data={"referenceNumber": [code]},
                    fiscal_id=self.tax_memory_id or "",
                    authorization_required=True,
                )
                
                # استخراج داده از پاسخ
                result_data = self._extract_packet_result_data(response_data)
                
                if result_data is None:
                    # Fallback به روش قدیمی
                    api_response = MoadianApiResponse.from_dict(response_data)
                    if api_response.success and api_response.result:
                        result_data = api_response.result.get('result', [{}])[0] if isinstance(api_response.result.get('result'), list) else {}
                        return {
                            "reference_number": code,
                            "status": result_data.get('status', 'unknown'),
                            "uid": result_data.get('uid'),
                            "confirmation_date": result_data.get('confirmationDate'),
                            "inquiry_at": datetime.utcnow().isoformat(),
                            "raw_data": result_data,
                        }
                    else:
                        error_msg = extract_moadian_error_message(api_response.error or {})
                        return {
                            "reference_number": code,
                            "status": "failed",
                            "error_message": error_msg,
                            "inquiry_at": datetime.utcnow().isoformat(),
                        }
                elif isinstance(result_data, list):
                    # اگر result_data به صورت list است، اولین آیتم را پردازش می‌کنیم
                    if result_data and isinstance(result_data[0], dict):
                        first_result = result_data[0]
                        # بررسی وجود errors
                        if first_result.get("errors") or first_result.get("errorCode") or first_result.get("errorDetail"):
                            error_msg = extract_moadian_error_message(
                                first_result.get("errors", [{}])[0] if isinstance(first_result.get("errors"), list) 
                                else first_result.get("errors", {}) or {
                                    'code': first_result.get('errorCode'),
                                    'message': first_result.get('errorDetail'),
                                }
                            )
                            return {
                                "reference_number": code,
                                "status": "failed",
                                "error_message": error_msg,
                                "inquiry_at": datetime.utcnow().isoformat(),
                            }
                        else:
                            return {
                                "reference_number": code,
                                "status": first_result.get('status', 'unknown'),
                                "uid": first_result.get('uid'),
                                "confirmation_date": first_result.get('confirmationDate') or first_result.get('confirmation_date'),
                                "inquiry_at": datetime.utcnow().isoformat(),
                                "raw_data": first_result,
                            }
                    else:
                        # اگر list خالی است یا آیتم‌ها dict نیستند
                        return {
                            "reference_number": code,
                            "status": "failed",
                            "error_message": "پاسخ خالی یا نامعتبر از سامانه",
                            "inquiry_at": datetime.utcnow().isoformat(),
                        }
                elif isinstance(result_data, dict):
                    # بررسی وجود errors
                    if result_data.get("errors"):
                        error_msg = extract_moadian_error_message(result_data.get("errors", [{}])[0] if isinstance(result_data.get("errors"), list) else result_data.get("errors", {}))
                        return {
                            "reference_number": code,
                            "status": "failed",
                            "error_message": error_msg,
                            "inquiry_at": datetime.utcnow().isoformat(),
                        }
                    else:
                        # استخراج نتیجه موفق
                        result_list = result_data.get('result', [])
                        if isinstance(result_list, list) and result_list:
                            first_result = result_list[0] if isinstance(result_list[0], dict) else {}
                        else:
                            first_result = result_data.get('result', {}) if isinstance(result_data.get('result'), dict) else {}
                        
                        return {
                            "reference_number": code,
                            "status": first_result.get('status', 'unknown'),
                            "uid": first_result.get('uid'),
                            "confirmation_date": first_result.get('confirmationDate') or first_result.get('confirmation_date'),
                            "inquiry_at": datetime.utcnow().isoformat(),
                            "raw_data": first_result,
                        }
                else:
                    # اگر result_data نوع غیرمنتظره‌ای داشت
                    return {
                        "reference_number": code,
                        "status": "failed",
                        "error_message": f"فرمت پاسخ نامعتبر از سامانه: نوع {type(result_data).__name__}",
                        "inquiry_at": datetime.utcnow().isoformat(),
                    }
                    
            except ApiError as e:
                return {
                    "reference_number": code,
                    "status": "failed",
                    "error_message": str(e),
                    "inquiry_at": datetime.utcnow().isoformat(),
                }
            except httpx.HTTPError as exc:
                return {
                    "reference_number": code,
                    "status": "failed",
                    "error_message": f"خطا در ارتباط: {str(exc)}",
                    "inquiry_at": datetime.utcnow().isoformat(),
                }
            except Exception as exc:
                return {
                    "reference_number": code,
                    "status": "failed",
                    "error_message": f"خطای نامشخص: {str(exc)}",
                    "inquiry_at": datetime.utcnow().isoformat(),
                }
        
        # استفاده از ThreadPoolExecutor برای parallel requests
        from app.core.settings import get_settings
        settings = get_settings()
        max_workers = min(len(tracking_codes), settings.tax_system_inquire_max_workers)
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # ارسال تمام درخواست‌ها
            future_to_code = {
                executor.submit(inquire_single_code, code): code 
                for code in tracking_codes
            }
            
            # جمع‌آوری نتایج
            for future in as_completed(future_to_code):
                code = future_to_code[future]
                try:
                    result = future.result()
                    with lock:
                        aggregated.append(result)
                except Exception as exc:
                    with lock:
                        aggregated.append({
                            "reference_number": code,
                            "status": "failed",
                            "error_message": f"خطا در پردازش: {str(exc)}",
                            "inquiry_at": datetime.utcnow().isoformat(),
                        })
        
        # مرتب‌سازی نتایج بر اساس ترتیب tracking_codes
        code_to_result = {r["reference_number"]: r for r in aggregated}
        aggregated = [code_to_result.get(code, {
            "reference_number": code,
            "status": "failed",
            "error_message": "نتیجه یافت نشد",
            "inquiry_at": datetime.utcnow().isoformat(),
        }) for code in tracking_codes]

        return {
            "mode": "live",
            "results": aggregated,
        }

    def get_server_information(self) -> Dict[str, Any]:
        """
        دریافت اطلاعات سرور شامل کلید عمومی سازمان مالیاتی
        مطابق نسخه قدیمی: $serverInfo['result']['data']['publicKeys'][0]
        
        Returns:
            اطلاعات سرور شامل publicKey و keyId
        """
        # مطابق SDK رسمی/کتابخانه Snapp: این درخواست باید به مسیر req/api/... و با packet امضا شده ارسال شود.
        try:
            logger.info("در حال دریافت اطلاعات سرور از سامانه مودیان...")
            response_data = self._send_sync_packet(
                packet_type="GET_SERVER_INFORMATION",
                packet_data=None,
                fiscal_id="",
                authorization_required=False,
            )
            
            logger.debug(f"پاسخ دریافت شده از سامانه: keys={list(response_data.keys()) if isinstance(response_data, dict) else None}")
            
            # مطابق نسخه قدیمی: $serverInfo['result']['data']['publicKeys'][0]
            # ساختار پاسخ: { timestamp: <int>, result: { data: { publicKeys: [...] } } }
            if not isinstance(response_data, dict):
                logger.error(f"پاسخ نامعتبر از سامانه: type={type(response_data).__name__}")
                raise ApiError(
                    "TAX_SERVER_PUBLIC_KEY_MISSING",
                    "پاسخ نامعتبر از سامانه",
                    http_status=502,
                    details={"raw_response": response_data},
                )
            
            # استخراج data از response_data
            # ساختار پاسخ: { timestamp: <int>, result: { data: { publicKeys: [...] } } }
            # مطابق نسخه قدیمی: $serverInfo['result']['data']['publicKeys'][0]
            
            # استفاده از _extract_packet_result_data برای استخراج data
            server_data = self._extract_packet_result_data(response_data)
            logger.debug(f"داده استخراج شده از _extract_packet_result_data: {type(server_data).__name__}")
            
            # اگر _extract_packet_result_data داده را استخراج کرد، از آن استفاده می‌کنیم
            if isinstance(server_data, dict):
                data = server_data
                logger.debug(f"استفاده از server_data: keys={list(data.keys())}")
            else:
                # fallback: استخراج دستی از response_data
                result = response_data.get("result", {})
                if isinstance(result, dict) and "data" in result:
                    data = result.get("data", {})
                    logger.debug(f"استفاده از result.data: keys={list(data.keys())}")
                elif isinstance(result, dict):
                    data = result
                    logger.debug(f"استفاده از result: keys={list(data.keys())}")
                else:
                    data = response_data
                    logger.debug(f"استفاده از response_data: keys={list(data.keys())}")
            
            # استخراج publicKeys
            public_keys = data.get("publicKeys") or []
            logger.debug(f"publicKeys استخراج شده: type={type(public_keys).__name__}, length={len(public_keys) if isinstance(public_keys, list) else 0}")
            if not isinstance(public_keys, list):
                # fallback: شاید publicKeys در سطح دیگری باشد
                public_keys = response_data.get("publicKeys", [])
                logger.debug(f"fallback publicKeys: type={type(public_keys).__name__}, length={len(public_keys) if isinstance(public_keys, list) else 0}")
            
            if isinstance(public_keys, list) and len(public_keys) > 0:
                first = public_keys[0]
                if isinstance(first, dict):
                    # استخراج کلید و ID
                    extracted_key = first.get("key")
                    extracted_id = first.get("id")
                    
                    # بررسی اینکه کلیدها استخراج شدند
                    if not extracted_key or not extracted_id:
                        raise ApiError(
                            "TAX_SERVER_PUBLIC_KEY_MISSING",
                            "کلید عمومی یا ID کلید در پاسخ موجود نیست.",
                            http_status=502,
                            details={
                                "raw_response": response_data,
                                "extracted_data": data,
                                "first_key": first,
                                "public_keys_count": len(public_keys),
                                "extracted_key_empty": not extracted_key,
                                "extracted_id_empty": not extracted_id,
                            },
                        )
                    
                    # ذخیره کلیدها
                    self._server_public_key = extracted_key
                    self._server_key_id = extracted_id
                    logger.info(f"کلید عمومی سازمان استخراج شد (key_id: {extracted_id}, key_length: {len(extracted_key) if extracted_key else 0})")
                else:
                    raise ApiError(
                        "TAX_SERVER_PUBLIC_KEY_MISSING",
                        "فرمت کلید عمومی در پاسخ نامعتبر است.",
                        http_status=502,
                        details={
                            "raw_response": response_data,
                            "extracted_data": data,
                            "first_key_type": type(first).__name__,
                            "first_key_value": str(first)[:200] if first else None,
                        },
                    )
            else:
                # اگر کلید برنگشت، خطای مشخص برگردانیم
                raise ApiError(
                    "TAX_SERVER_PUBLIC_KEY_MISSING",
                    "کلید عمومی سازمان در پاسخ وجود ندارد.",
                    http_status=502,
                    details={
                        "raw_response": response_data,
                        "extracted_data": data,
                        "result_structure": {
                            "has_result": "result" in response_data,
                            "result_type": type(response_data.get("result")).__name__ if "result" in response_data else None,
                            "has_data": isinstance(response_data.get("result"), dict) and "data" in response_data.get("result", {}),
                            "has_publicKeys": isinstance(response_data.get("result", {}).get("data", {}), dict) and "publicKeys" in response_data.get("result", {}).get("data", {}),
                            "public_keys_type": type(public_keys).__name__,
                            "public_keys_length": len(public_keys) if isinstance(public_keys, list) else 0,
                        }
                    },
                )
            
            return response_data
        except ApiError:
            raise
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
        # مطابق SDK رسمی: دریافت توکن با packet_type=GET_TOKEN و مسیر req/api/self-tsp/sync/GET_TOKEN
        if not self.private_key:
            raise ApiError("TAX_SETTINGS_INCOMPLETE", "کلید خصوصی برای لاگین الزامی است.", http_status=400)

        username = (self.tax_memory_id or "").strip()
        if not username:
            raise ApiError("TAX_SETTINGS_INCOMPLETE", "شناسه حافظه مالیاتی برای لاگین الزامی است.", http_status=400)

        try:
            response_data = self._send_sync_packet(
                packet_type="GET_TOKEN",
                packet_data={"username": username},
                fiscal_id=username,
                authorization_required=False,
            )

            token_data = self._extract_packet_result_data(response_data)
            if not isinstance(token_data, dict):
                raise ApiError(
                    "TAX_LOGIN_FAILED",
                    "پاسخ نامعتبر از سرویس احراز هویت مالیاتی",
                    # این 401 مربوط به سامانه مودیان است نه احراز هویت کاربر؛ 401 باعث ریدایرکت UI به صفحه ورود می‌شود.
                    http_status=502,
                    details={"raw_response": response_data},
                )

            token = token_data.get("token")
            if not token:
                raise ApiError(
                    "TAX_LOGIN_FAILED",
                    "توکن احراز هویت دریافت نشد",
                    # این 401 مربوط به سامانه مودیان است نه احراز هویت کاربر؛ 401 باعث ریدایرکت UI به صفحه ورود می‌شود.
                    http_status=502,
                    details={"raw_response": response_data},
                )

            self._auth_token = str(token)

            expires_in = token_data.get("expiresIn")
            now = datetime.utcnow()
            expiry = None
            if expires_in is not None:
                try:
                    v = int(expires_in)
                    # بعضی پیاده‌سازی‌ها expiresIn را به صورت timestamp میلی‌ثانیه می‌دهند (مثلاً 1766...).
                    if v > 10**11:
                        expiry = datetime.utcfromtimestamp(v / 1000.0)
                    # timestamp ثانیه
                    elif v > 10**9:
                        expiry = datetime.utcfromtimestamp(v)
                    # مدت اعتبار به ثانیه
                    elif v > 0:
                        expiry = now + timedelta(seconds=v)
                except (TypeError, ValueError, OverflowError):
                    expiry = None

            # fallback
            if not expiry or expiry <= now:
                expiry = now + timedelta(hours=24)
            self._token_expiry = expiry
            
            # ذخیره در cache
            from app.core.cache import get_cache
            cache = get_cache()
            if cache.enabled:
                cache_key = f"tax_token:{self.tax_memory_id}"
                ttl_seconds = int((expiry - now).total_seconds())
                if ttl_seconds > 0:
                    cache.set(cache_key, {
                        'token': self._auth_token,
                        'expiry': expiry.isoformat(),
                    }, ttl=ttl_seconds)

            return self._auth_token
        except ApiError:
            raise
        except httpx.HTTPError as exc:
            raise ApiError(
                "TAX_NETWORK_ERROR",
                "خطا در ارتباط با سرور احراز هویت",
                http_status=502,
                details={"message": str(exc)},
            ) from exc

    def _ensure_authenticated(self) -> None:
        """اطمینان از وجود token معتبر (با استفاده از cache)"""
        # بررسی cache برای token
        cache_key = f"tax_token:{self.tax_memory_id}"
        from app.core.cache import get_cache
        cache = get_cache()
        
        # تلاش برای دریافت از cache
        cached_token_data = cache.get(cache_key) if cache.enabled else None
        if cached_token_data and isinstance(cached_token_data, dict):
            token = cached_token_data.get('token')
            expiry_str = cached_token_data.get('expiry')
            if token and expiry_str:
                try:
                    expiry = datetime.fromisoformat(expiry_str)
                    # بررسی انقضا با buffer time (5 دقیقه)
                    buffer_time = timedelta(minutes=5)
                    if datetime.utcnow() < (expiry - buffer_time):
                        self._auth_token = token
                        self._token_expiry = expiry
                        return  # token از cache معتبر است
                except (ValueError, TypeError):
                    pass  # اگر expiry نامعتبر بود، ادامه می‌دهیم
        
        # بررسی token در memory (fallback)
        if self._auth_token and self._token_expiry:
            # بررسی انقضا با buffer time (5 دقیقه)
            buffer_time = timedelta(minutes=5)
            if datetime.utcnow() < (self._token_expiry - buffer_time):
                return  # token هنوز معتبر است
        
        # لاگین مجدد
        token = self.login()
        expiry = self._token_expiry
        
        # ذخیره در cache
        if cache.enabled and expiry:
            ttl_seconds = int((expiry - datetime.utcnow()).total_seconds())
            if ttl_seconds > 0:
                cache.set(cache_key, {
                    'token': token,
                    'expiry': expiry.isoformat(),
                }, ttl=ttl_seconds)

    def _ensure_server_information(self) -> None:
        """
        مشابه فلو کتابخانه PHP: یک بار اطلاعات سرور را می‌گیریم و
        کلید/ID را نگه می‌داریم تا در پکت‌ها استفاده شود.
        
        در محیط ابری: کلید عمومی سازمان برای همه کسب‌وکارها یکسان است
        و باید در cache ذخیره شود (بر اساس sandbox/production mode)
        """
        if self._server_public_key and self._server_key_id:
            return
        
        # جلوگیری از حلقه بازگشتی
        if self._fetching_server_info:
            logger.warning("در حال دریافت اطلاعات سرور، از فراخوانی مجدد جلوگیری می‌شود")
            return
        
        # استفاده از cache برای کلید عمومی سازمان (مشترک برای همه کسب‌وکارها)
        from app.core.cache import get_cache
        cache = get_cache()
        
        # کلید cache بر اساس sandbox/production mode (نه business_id)
        # کلید عمومی سازمان برای همه کسب‌وکارها یکسان است
        is_sandbox = 'sandbox' in self.config.base_url.lower() or self.config.simulate
        cache_key = f"tax_server_public_key:{'sandbox' if is_sandbox else 'production'}"
        
        # تلاش برای دریافت از cache
        cached_key_data = cache.get(cache_key) if cache.enabled else None
        if cached_key_data and isinstance(cached_key_data, dict):
            self._server_public_key = cached_key_data.get("public_key")
            self._server_key_id = cached_key_data.get("key_id")
            if self._server_public_key and self._server_key_id:
                logger.info(f"کلید عمومی سازمان از cache دریافت شد (key: {cache_key})")
                return  # کلید از cache دریافت شد
            else:
                logger.warning(f"داده cache موجود است اما کلیدها خالی هستند (key: {cache_key})")
        
        # اگر در cache نبود، از سامانه دریافت می‌کنیم
        try:
            self._fetching_server_info = True  # تنظیم flag برای جلوگیری از حلقه بازگشتی
            logger.info(f"دریافت کلید عمومی سازمان از سامانه (cache_key: {cache_key})")
            # فراخوانی get_server_information که خودش کلید را استخراج و در self._server_public_key و self._server_key_id ذخیره می‌کند
            server_info = self.get_server_information()
            
            # بررسی اینکه کلیدها استخراج شدند
            if not self._server_public_key or not self._server_key_id:
                logger.error(f"کلید عمومی سازمان پس از دریافت اطلاعات سرور استخراج نشد. server_info keys: {list(server_info.keys()) if isinstance(server_info, dict) else None}")
                raise ApiError(
                    "TAX_SERVER_PUBLIC_KEY_MISSING",
                    "کلید عمومی سازمان پس از دریافت اطلاعات سرور استخراج نشد.",
                    http_status=502,
                    details={
                        "server_info_keys": list(server_info.keys()) if isinstance(server_info, dict) else None,
                        "server_info_type": type(server_info).__name__,
                    },
                )
            
            logger.info(f"کلید عمومی سازمان با موفقیت دریافت شد (key_id: {self._server_key_id})")
            
            # ذخیره در cache برای استفاده سایر کسب‌وکارها (TTL: 24 ساعت)
            if cache.enabled:
                cache.set(cache_key, {
                    "public_key": self._server_public_key,
                    "key_id": self._server_key_id,
                }, ttl=86400)  # 24 ساعت
                logger.info(f"کلید عمومی سازمان در cache ذخیره شد (key: {cache_key})")
        except ApiError:
            # propagate همان خطا برای مدیریت بالادستی
            raise
        except Exception as exc:
            raise ApiError(
                "TAX_SERVER_INFO_FAILED",
                f"خطا در دریافت اطلاعات سرور مالیاتی: {str(exc)}",
                http_status=502,
            ) from exc
        finally:
            self._fetching_server_info = False  # بازنشانی flag

    # -----------------------------
    # Packet-based (SDK-compatible) transfer helpers
    # -----------------------------
    def _get_essential_transfer_headers(self, *, authorization_required: bool) -> Dict[str, str]:
        """
        هدرهای ضروری طبق SDK PHP:
        - timestamp: میلی‌ثانیه (string)
        - requestTraceId: uuid4 (string)
        - Authorization: Bearer <token> (در صورت نیاز)
        """
        headers: Dict[str, str] = {
            "timestamp": str(int(time.time() * 1000)),
            "requestTraceId": str(uuid.uuid4()),
        }
        if authorization_required:
            if not self._auth_token:
                self._ensure_authenticated()
            if not self._auth_token:
                # این خطا مربوط به توکن سامانه مودیان است نه سشن کاربر؛ 401 باعث logout در UI می‌شود.
                raise ApiError("TAX_LOGIN_FAILED", "توکن معتبر برای ارسال درخواست موجود نیست.", http_status=502)
            headers["Authorization"] = f"Bearer {self._auth_token}"
        return headers

    def _build_packet(
        self,
        *,
        packet_type: str,
        packet_data: Dict[str, Any] | None,
        fiscal_id: str,
    ) -> Dict[str, Any]:
        """
        ساخت Packet مطابق SDK PHP:
        - symmetricKey و iv تصادفی و با کلید عمومی سازمان رمز می‌شوند
        - dataSignature امضای RSA روی normalized(header+packet) است
        
        نکته: برای GET_SERVER_INFORMATION نیازی به رمزگذاری نیست
        """
        uid = str(uuid.uuid4())

        # برای GET_SERVER_INFORMATION نیازی به رمزگذاری نیست
        if packet_type == "GET_SERVER_INFORMATION":
            packet = {
                "uid": uid,
                "packetType": packet_type,
                "retry": False,
                "data": packet_data,
                "fiscalId": fiscal_id or "",
            }
            return packet

        # کلید متقارن و IV تصادفی
        symmetric_key = os.urandom(32)  # 256-bit AES
        iv = os.urandom(16)

        # رمزگذاری symmetric_key و iv با کلید عمومی سازمان
        enc_symmetric = self._encrypt_with_server_public_key(symmetric_key)
        enc_iv = self._encrypt_with_server_public_key(iv)

        packet = {
            "uid": uid,
            "packetType": packet_type,
            "retry": False,
            "data": packet_data,
            "encryptionKeyId": self._server_key_id or "",
            "symmetricKey": enc_symmetric,
            "iv": enc_iv,
            "fiscalId": fiscal_id or "",
            "dataSignature": "",
        }
        return packet

    def _php_flatten(self, value: Any, prefix: str = "") -> Dict[str, Any]:
        """
        معادل Normalizer::flattenArray در SDK PHP
        - dict: کلیدها با '.' ترکیب می‌شوند
        - list/tuple: اندیس‌ها (0,1,2,...) به عنوان کلید استفاده می‌شود
        """
        result: Dict[str, Any] = {}

        if isinstance(value, dict):
            items = value.items()
        elif isinstance(value, (list, tuple)):
            items = enumerate(value)
        else:
            if prefix:
                result[prefix] = value
            return result

        for k, v in items:
            key = str(k)
            new_prefix = f"{prefix}.{key}" if prefix else key
            if isinstance(v, (dict, list, tuple)):
                result.update(self._php_flatten(v, new_prefix))
            else:
                result[new_prefix] = v
        return result

    def _php_normalize_array(self, data: Dict[str, Any]) -> str:
        """
        معادل Normalizer::normalizeArray در SDK PHP:
        1) flatten
        2) ksort
        3) تبدیل مقادیر به رشته و join با '#'
        """
        flattened = self._php_flatten(data)
        parts: List[str] = []
        for key in sorted(flattened.keys()):
            value = flattened[key]
            if isinstance(value, bool):
                text_value = "true" if value else "false"
            elif value == "" or value is None:
                text_value = "#"
            else:
                text_value = str(value).replace("#", "##")
            parts.append(text_value)
        return "#".join(parts)

    def _php_sign_text(self, text: str) -> str:
        """امضای RSA-SHA256 مثل openssl_sign + base64 در PHP."""
        if not self.private_key:
            raise ApiError("TAX_SETTINGS_INCOMPLETE", "کلید خصوصی برای امضا الزامی است.", http_status=400)
        try:
            logger.debug(f"[TAX_DEBUG] Signing text (length: {len(text)}): {text}")
            logger.debug(f"[TAX_DEBUG] Private key (first 200 chars): {self.private_key[:200] if self.private_key else None}...")
            private_key_obj = self._load_private_key_obj()
            signature = private_key_obj.sign(
                text.encode("utf-8"),
                padding.PKCS1v15(),
                hashes.SHA256(),
            )
            signature_b64 = base64.b64encode(signature).decode("utf-8")
            logger.info(f"[TAX_DEBUG] Signature generated (FULL base64): {signature_b64}")
            return signature_b64
        except Exception as exc:
            logger.error(f"[TAX_DEBUG] Signature failed: {str(exc)}", exc_info=True)
            raise ApiError("TAX_SIGNATURE_FAILED", f"خطا در امضای درخواست: {str(exc)}", http_status=500) from exc

    def _encrypt_with_server_public_key(self, data: bytes) -> str:
        """
        رمزگذاری داده (symmetricKey/iv) با کلید عمومی سازمان مالیاتی.
        خروجی: base64
        
        نکته: این متد نباید در حین دریافت اطلاعات سرور فراخوانی شود
        (برای جلوگیری از حلقه بازگشتی)
        """
        # اگر در حال دریافت اطلاعات سرور هستیم، نباید دوباره فراخوانی کنیم
        if self._fetching_server_info:
            logger.error("در حال دریافت اطلاعات سرور، نمی‌توان کلید عمومی را استفاده کرد")
            raise ApiError("TAX_SERVER_PUBLIC_KEY_MISSING", "کلید عمومی سازمان در حال دریافت است، لطفاً صبر کنید.", http_status=502)
        
        # اطمینان از وجود کلید عمومی قبل از استفاده
        if not self._server_public_key or not self._server_key_id:
            logger.warning("کلید عمومی سازمان موجود نیست، تلاش برای دریافت...")
            self._ensure_server_information()
        
        if not self._server_public_key:
            logger.error("کلید عمومی سازمان پس از تلاش برای دریافت هنوز موجود نیست")
            raise ApiError("TAX_SERVER_PUBLIC_KEY_MISSING", "کلید عمومی سازمان دریافت نشده است.", http_status=502)
        try:
            pub_raw = self._server_public_key
            pub_raw = pub_raw.replace("\r\n", "\n").replace("\r", "\n")
            if "-----BEGIN" not in pub_raw:
                # اگر بدون هدر باشد، PEM را اضافه می‌کنیم
                pub_raw = "-----BEGIN PUBLIC KEY-----\n" + pub_raw + "\n-----END PUBLIC KEY-----"
            public_key_obj = serialization.load_pem_public_key(pub_raw.encode("utf-8"), backend=default_backend())
            encrypted = public_key_obj.encrypt(
                data,
                padding.PKCS1v15(),
            )
            return base64.b64encode(encrypted).decode("utf-8")
        except Exception as exc:
            raise ApiError("TAX_ENCRYPTION_FAILED", f"خطا در رمزگذاری کلید متقارن: {str(exc)}", http_status=500) from exc

    def _load_private_key_obj(self):
        """
        تلاش برای بارگذاری کلید خصوصی در فرمت‌های رایج:
        - PEM (با header/footer)
        - Base64 DER (بدون header/footer) که در برخی داده‌ها دیده می‌شود
        """
        if not self.private_key:
            raise ApiError("TAX_SETTINGS_INCOMPLETE", "کلید خصوصی برای امضا الزامی است.", http_status=400)

        raw = (self.private_key or "").strip()
        raw = raw.replace("\r\n", "\n").replace("\r", "\n")

        # حالت PEM
        if "-----BEGIN" in raw:
            return serialization.load_pem_private_key(
                raw.encode("utf-8"),
                password=None,
                backend=default_backend(),
            )

        # حالت Base64 DER (بدون header/footer) - حذف whitespace سپس decode
        compact = "".join(raw.split())
        der = base64.b64decode(compact)
        return serialization.load_der_private_key(
            der,
            password=None,
            backend=default_backend(),
        )

    def _send_sync_packet(
        self,
        *,
        packet_type: str,
        packet_data: Dict[str, Any] | None,
        fiscal_id: str,
        authorization_required: bool,
    ) -> Dict[str, Any]:
        """
        ارسال packet مطابق SDK PHP:
        POST /req/api/self-tsp/sync/<PACKET_TYPE>
        body: { packet: <Packet::toArray>, signature: <base64(openssl_sign(normalized))> }
        headers: timestamp, requestTraceId, Authorization(optional)
        """
        # Packet با کلید متقارن رمزگذاری‌شده
        packet = self._build_packet(packet_type=packet_type, packet_data=packet_data, fiscal_id=fiscal_id)
        transfer_headers = self._get_essential_transfer_headers(authorization_required=authorization_required)

        # داده‌ای که امضا می‌شود: normalizeArray(array_merge(packet, cloneHeader))
        clone_header = dict(transfer_headers)
        if "Authorization" in clone_header:
            clone_header["Authorization"] = str(clone_header["Authorization"]).replace("Bearer ", "", 1)
        normalized_text = self._php_normalize_array({**packet, **clone_header})
        signature_b64 = self._php_sign_text(normalized_text)

        client = self._get_http_client()
        http_headers: Dict[str, str] = {
            "User-Agent": self.config.user_agent,
            "Accept": "application/json",
            "Content-Type": "application/json",
            **transfer_headers,
        }
        response = client.post(
            f"/req/api/self-tsp/sync/{packet_type}",
            json={"packet": packet, "signature": signature_b64},
            headers=http_headers,
            timeout=self.config.timeout_seconds,
        )
        try:
            data = response.json()
        except Exception:
            data = {"raw_body": response.text}

        # خطاهای سامانه مودیان معمولاً به صورت HTTP 4xx/5xx + errors برمی‌گردند.
        if response.status_code >= 400:
            if isinstance(data, dict) and data.get("errors"):
                errs = data.get("errors") or []
                messages: List[str] = []
                if isinstance(errs, list):
                    for item in errs:
                        if isinstance(item, dict) and item.get("message"):
                            messages.append(str(item["message"]))
                msg = " / ".join(messages).strip() or "خطا از سمت سامانه مودیان"
                err_code = "TAX_LOGIN_FAILED" if packet_type == "GET_TOKEN" else "TAX_REMOTE_ERROR"
                # 401 برای «سامانه مودیان» نباید به UI پاس داده شود چون باعث هدایت به صفحه ورود می‌شود.
                if packet_type == "GET_TOKEN":
                    http_status = 502
                else:
                    http_status = response.status_code if response.status_code in (400, 403) else 502
                raise ApiError(
                    err_code,
                    msg,
                    http_status=http_status,
                    details={"raw_response": data, "status_code": response.status_code},
                )
            raise ApiError(
                "TAX_NETWORK_ERROR",
                "خطا در ارتباط با سامانه مودیان",
                http_status=502,
                details={"raw_response": data, "status_code": response.status_code},
            )

        return data

    def _send_async_packet(
        self,
        *,
        packet_type: str,
        packet_data: Dict[str, Any],
        fiscal_id: str,
        authorization_required: bool,
    ) -> Dict[str, Any]:
        """
        ارسال packet به async endpoint مطابق SDK PHP:
        POST /req/api/self-tsp/async/normal-enqueue
        body: { packets: [<Packet::toArray>], signature: <base64>, signatureKeyId: null }
        headers: timestamp, requestTraceId, Authorization
        
        در کتابخانه PHP:
        - packets را encrypt و sign می‌کند
        - signature روی normalized(packets + headers) است
        """
        # ساخت packet
        logger.info(f"[TAX_DEBUG] ========== BUILDING PACKET ==========")
        logger.info(f"[TAX_DEBUG] Packet type: {packet_type}, fiscal_id: {fiscal_id}")
        logger.info(f"[TAX_DEBUG] Packet data (FULL JSON):")
        logger.info(json.dumps(packet_data, ensure_ascii=False, indent=2))
        packet = self._build_packet(packet_type=packet_type, packet_data=packet_data, fiscal_id=fiscal_id)
        logger.info(f"[TAX_DEBUG] Packet after _build_packet (before encryption):")
        logger.info(json.dumps({k: (v[:200] + '...' if isinstance(v, str) and len(v) > 200 else v) for k, v in packet.items()}, ensure_ascii=False, indent=2))
        
        # امضای packet (data signature)
        normalized_data = self._php_normalize_array(packet_data)
        logger.info(f"[TAX_DEBUG] Normalized data for dataSignature (FULL): {normalized_data}")
        logger.info(f"[TAX_DEBUG] Normalized data length: {len(normalized_data)}")
        data_signature = self._php_sign_text(normalized_data)
        logger.info(f"[TAX_DEBUG] Data signature (FULL base64): {data_signature}")
        packet["dataSignature"] = data_signature
        
        # رمزگذاری packet (encrypt)
        # مطابق encryptPackets در PHP:
        # 1. تولید aesHex و iv به صورت hex
        # 2. رمزگذاری aesHex با کلید عمومی سازمان
        # 3. رمزگذاری data با AES-256-GCM (بعد از XOR)
        
        # اطمینان از دریافت کلید عمومی سازمان (مطابق نسخه قدیمی)
        if not self._server_public_key or not self._server_key_id:
            self._ensure_server_information()
        
        # تولید کلید متقارن و IV به صورت hex (مطابق PHP: bin2hex(random_bytes(...)))
        import os
        aes_hex = os.urandom(32).hex()  # 256-bit AES به صورت hex string
        iv_hex = os.urandom(16).hex()  # IV به صورت hex string
        
        # تبدیل hex به binary برای استفاده در رمزگذاری (مطابق PHP: hex2bin($aesHex))
        aes_binary = bytes.fromhex(aes_hex)
        iv_binary = bytes.fromhex(iv_hex)
        
        # رمزگذاری aesHex با کلید عمومی سازمان (مطابق encryptAesKey در PHP)
        # در PHP: encryptAesKey($aesHex) که $aesHex یک hex string است (64 کاراکتر)
        # و در encryptAesKey: RSA::encrypt($aesKey) که $aesKey همان hex string است
        # phpseclib RSA::encrypt احتمالاً hex string را به binary تبدیل می‌کند
        # در Python، باید hex string را encode کنیم و رمزگذاری کنیم
        # اما توجه: hex string encode شده با binary متفاوت است!
        # hex string "abcd" -> encode -> b"abcd" (4 bytes)
        # hex string "abcd" -> fromhex -> b"\xab\xcd" (2 bytes)
        # پس باید hex string را encode کنیم (مطابق PHP که hex string را می‌گیرد)
        logger.info(f"[TAX_DEBUG] Encrypting AES key - hex length: {len(aes_hex)}, IV hex length: {len(iv_hex)}")
        logger.info(f"[TAX_DEBUG] AES hex (FULL): {aes_hex}")
        logger.info(f"[TAX_DEBUG] IV hex (FULL): {iv_hex}")
        logger.info(f"[TAX_DEBUG] Server public key ID: {self._server_key_id}")
        logger.debug(f"[TAX_DEBUG] Server public key (first 200 chars): {self._server_public_key[:200] if self._server_public_key else None}...")
        enc_symmetric = self._encrypt_with_server_public_key(aes_hex.encode('utf-8'))
        logger.info(f"[TAX_DEBUG] Encrypted symmetric key (FULL base64): {enc_symmetric}")
        
        packet["symmetricKey"] = enc_symmetric
        packet["iv"] = iv_hex  # در PHP: iv به صورت hex string در packet ذخیره می‌شود
        packet["encryptionKeyId"] = self._server_key_id or ""
        
        # رمزگذاری data با AES-256-GCM
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        from cryptography.hazmat.backends import default_backend
        
        # تبدیل packet_data به JSON (مطابق PHP: json_encode($packet->getData()->toArray()))
        data_json = json.dumps(packet_data, ensure_ascii=False, separators=(',', ':'))
        data_bytes = data_json.encode('utf-8')
        
        # XOR با کلید متقارن (مطابق EncryptionService::xorStrings در PHP)
        # در PHP: xorStrings($text, $key) که $key binary است
        xor_data = bytes(data_bytes[i] ^ aes_binary[i % len(aes_binary)] for i in range(len(data_bytes)))
        
        # رمزگذاری با AES-256-GCM (مطابق EncryptionService::encrypt در PHP)
        # در PHP: openssl_encrypt با aes-256-gcm و tag length 16
        cipher = Cipher(algorithms.AES(aes_binary), modes.GCM(iv_binary), backend=default_backend())
        encryptor = cipher.encryptor()
        ciphertext = encryptor.update(xor_data) + encryptor.finalize()
        
        # ترکیب ciphertext + tag (مطابق PHP: base64_encode($cipherText . $tag))
        encrypted_data = ciphertext + encryptor.tag
        packet["data"] = base64.b64encode(encrypted_data).decode('utf-8')
        logger.debug(f"[TAX_DEBUG] Encrypted data (first 50 chars): {packet['data'][:50]}...")
        logger.debug(f"[TAX_DEBUG] Packet after encryption: {json.dumps({k: (v[:50] + '...' if isinstance(v, str) and len(v) > 50 else v) for k, v in packet.items()}, ensure_ascii=False, indent=2)}")
        
        # ساخت headers
        transfer_headers = self._get_essential_transfer_headers(authorization_required=authorization_required)
        logger.debug(f"[TAX_DEBUG] Transfer headers: {json.dumps({k: (v[:50] + '...' if isinstance(v, str) and len(v) > 50 else v) for k, v in transfer_headers.items()}, ensure_ascii=False)}")
        
        # امضای کل (packets + headers)
        clone_header = dict(transfer_headers)
        if "Authorization" in clone_header:
            clone_header["Authorization"] = str(clone_header["Authorization"]).replace("Bearer ", "", 1)
        
        # ساخت body مطابق sendPackets در PHP
        # در PHP: array_merge(['packets' => [array_map(fn ($p) => $p->toArray(), $packets)]], $cloneHeader)
        # نکته: packets باید به صورت array در array باشد: ['packets' => [packet1, packet2, ...]]
        packets_array = [packet]
        # ساختار normalize: {'packets': [packet1, packet2, ...], ...headers}
        data_for_normalize = {
            "packets": packets_array,
            **clone_header
        }
        logger.info(f"[TAX_DEBUG] Data for normalize (packets count: {len(packets_array)}, headers: {list(clone_header.keys())})")
        logger.debug(f"[TAX_DEBUG] Data for normalize (full): {json.dumps(data_for_normalize, ensure_ascii=False, indent=2)}")
        normalized = self._php_normalize_array(data_for_normalize)
        logger.info(f"[TAX_DEBUG] Normalized string for signature (FULL): {normalized}")
        logger.info(f"[TAX_DEBUG] Normalized string length: {len(normalized)}")
        signature_b64 = self._php_sign_text(normalized)
        logger.info(f"[TAX_DEBUG] Final signature (FULL base64): {signature_b64}")
        
        client = self._get_http_client()
        http_headers: Dict[str, str] = {
            "User-Agent": self.config.user_agent,
            "Accept": "application/json",
            "Content-Type": "application/json",
            **transfer_headers,
        }
        
        # ساخت body نهایی برای ارسال
        final_body = {
            "packets": packets_array,
            "signature": signature_b64,
            "signatureKeyId": None,
        }
        logger.info(f"[TAX_DEBUG] ========== FINAL REQUEST TO MOADIAN ==========")
        logger.info(f"[TAX_DEBUG] Endpoint: /req/api/self-tsp/async/normal-enqueue")
        logger.info(f"[TAX_DEBUG] Packets count: {len(packets_array)}")
        logger.info(f"[TAX_DEBUG] Signature length: {len(signature_b64)}")
        logger.info(f"[TAX_DEBUG] Final request body (full JSON):")
        logger.info(json.dumps(final_body, ensure_ascii=False, indent=2))
        logger.info(f"[TAX_DEBUG] ============================================")
        
        # لاگ اطلاعات کلیدی برای مقایسه با PHP
        logger.info(f"[TAX_DEBUG] ========== KEY INFO FOR PHP COMPARISON ==========")
        logger.info(f"  - AES Hex (64 chars): {aes_hex}")
        logger.info(f"  - IV Hex (32 chars): {iv_hex}")
        logger.info(f"  - Encrypted AES Key (base64): {enc_symmetric}")
        logger.info(f"  - Normalized string for signature: {normalized}")
        logger.info(f"  - Signature (base64): {signature_b64}")
        logger.info(f"  - Packet UID: {packet.get('uid')}")
        logger.info(f"  - Packet Type: {packet.get('packetType')}")
        logger.info(f"  - Fiscal ID: {packet.get('fiscalId')}")
        logger.info(f"  - Encryption Key ID: {packet.get('encryptionKeyId')}")
        logger.info(f"  - Data Signature: {packet.get('dataSignature', '')}")
        logger.info(f"  - Encrypted Data (base64): {packet.get('data', '')}")
        logger.info(f"  - Private Key (first 200 chars): {self.private_key[:200] if self.private_key else None}...")
        logger.info(f"  - Server Public Key (first 200 chars): {self._server_public_key[:200] if self._server_public_key else None}...")
        logger.info(f"[TAX_DEBUG] ===============================================")
        
        # ارسال به async endpoint
        response = client.post(
            "/req/api/self-tsp/async/normal-enqueue",
            json=final_body,
            headers=http_headers,
            timeout=self.config.timeout_seconds,
        )
        
        try:
            data = response.json()
        except Exception:
            data = {"raw_body": response.text}
        
        # خطاهای سامانه مودیان
        if response.status_code >= 400:
            if isinstance(data, dict) and data.get("errors"):
                errs = data.get("errors") or []
                messages: List[str] = []
                if isinstance(errs, list):
                    for item in errs:
                        if isinstance(item, dict) and item.get("message"):
                            messages.append(str(item["message"]))
                msg = " / ".join(messages).strip() or "خطا از سمت سامانه مودیان"
                raise ApiError(
                    "TAX_REMOTE_ERROR",
                    msg,
                    http_status=response.status_code if response.status_code in (400, 403) else 502,
                    details={"raw_response": data, "status_code": response.status_code},
                )
            raise ApiError(
                "TAX_NETWORK_ERROR",
                "خطا در ارتباط با سامانه مودیان",
                http_status=502,
                details={"raw_response": data, "status_code": response.status_code},
            )
        
        return data

    def _extract_packet_result_data(self, response_data: Dict[str, Any]) -> Any:
        """
        پاسخ‌های packet-based معمولاً این شکل‌اند:
        { timestamp: <int>, result: { ..., data: {...} } }
        یا ممکن است result.data به صورت list باشد
        """
        if not isinstance(response_data, dict):
            return None
        result = response_data.get("result")
        if isinstance(result, dict) and "data" in result:
            return result.get("data")
        # اگر result به صورت مستقیم list باشد
        if isinstance(result, list):
            return result
        return None

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
            
            private_key_obj = self._load_private_key_obj()
            
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

