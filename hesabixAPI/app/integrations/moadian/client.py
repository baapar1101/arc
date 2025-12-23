from __future__ import annotations

import time
import json
import base64
import uuid
from dataclasses import dataclass
from typing import Any, Dict, List, Optional
from datetime import datetime, timedelta

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

        # اطمینان از لاگین
        self._ensure_authenticated()
        
        # تبدیل DTO به دیکشنری
        payload = invoice_dto.to_dict()
        
        # استفاده از packet-based approach مطابق SDK PHP
        try:
            response_data = self._send_sync_packet(
                packet_type="SEND_INVOICE",
                packet_data={"body": [payload]},
                fiscal_id=self.tax_memory_id or "",
                authorization_required=True,
            )
            
            # استخراج داده از پاسخ packet-based
            result_data = self._extract_packet_result_data(response_data)
            
            # پردازش پاسخ
            if isinstance(result_data, dict):
                # بررسی وجود errors در پاسخ
                if result_data.get("errors"):
                    error_msg = extract_moadian_error_message(result_data.get("errors", [{}])[0] if isinstance(result_data.get("errors"), list) else result_data.get("errors", {}))
                    raise ApiError(
                        "TAX_SUBMISSION_FAILED",
                        error_msg,
                        http_status=400,
                        details={"raw_response": response_data},
                    )
                
                # استخراج نتیجه موفق
                result_list = result_data.get('result', [])
                if isinstance(result_list, list) and result_list:
                    first_result = result_list[0] if isinstance(result_list[0], dict) else {}
                else:
                    first_result = result_data.get('result', {}) if isinstance(result_data.get('result'), dict) else {}
            else:
                # اگر result_data dict نبود، از response_data مستقیماً استفاده می‌کنیم
                api_response = MoadianApiResponse.from_dict(response_data)
                if not api_response.success:
                    error_msg = extract_moadian_error_message(api_response.error or {})
                    raise ApiError(
                        "TAX_SUBMISSION_FAILED",
                        error_msg,
                        http_status=400,
                        details={"raw_response": response_data},
                    )
                result = api_response.result or {}
                first_result = result.get('result', [{}])[0] if isinstance(result.get('result'), list) else {}
            
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

        # اطمینان از احراز هویت
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
                
                if isinstance(result_data, dict):
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
        max_workers = min(len(tracking_codes), 5)  # حداکثر 5 thread همزمان
        
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
        
        Returns:
            اطلاعات سرور شامل publicKey و keyId
        """
        # مطابق SDK رسمی/کتابخانه Snapp: این درخواست باید به مسیر req/api/... و با packet امضا شده ارسال شود.
        try:
            response_data = self._send_sync_packet(
                packet_type="GET_SERVER_INFORMATION",
                packet_data=None,
                fiscal_id="",
                authorization_required=False,
            )
            server_data = self._extract_packet_result_data(response_data)
            if not isinstance(server_data, dict):
                raise ApiError(
                    "TAX_SERVER_INFO_FAILED",
                    "پاسخ نامعتبر از سرویس اطلاعات سرور مالیاتی",
                    http_status=502,
                    details={"raw_response": response_data},
                )

            public_keys = server_data.get("publicKeys") or []
            if isinstance(public_keys, list) and public_keys:
                first = public_keys[0] if isinstance(public_keys[0], dict) else {}
                self._server_public_key = first.get("key")
                self._server_key_id = first.get("id")

            return server_data
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
        # این ساختار مطابق Packet::toArray در SDK PHP است.
        return {
            "uid": str(uuid.uuid4()),
            "packetType": packet_type,
            "retry": False,
            "data": packet_data,
            "encryptionKeyId": "",
            "symmetricKey": "",
            "iv": "",
            "fiscalId": fiscal_id or "",
            "dataSignature": "",
        }

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
            private_key_obj = self._load_private_key_obj()
            signature = private_key_obj.sign(
                text.encode("utf-8"),
                padding.PKCS1v15(),
                hashes.SHA256(),
            )
            return base64.b64encode(signature).decode("utf-8")
        except Exception as exc:
            raise ApiError("TAX_SIGNATURE_FAILED", f"خطا در امضای درخواست: {str(exc)}", http_status=500) from exc

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

    def _extract_packet_result_data(self, response_data: Dict[str, Any]) -> Any:
        """
        پاسخ‌های packet-based معمولاً این شکل‌اند:
        { timestamp: <int>, result: { ..., data: {...} } }
        """
        if not isinstance(response_data, dict):
            return None
        result = response_data.get("result")
        if isinstance(result, dict) and "data" in result:
            return result.get("data")
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

