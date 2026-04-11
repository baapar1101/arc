"""
Triggerهای Webhook
"""

import logging
import hashlib
import hmac
import time
import threading
from typing import Any, Dict, Tuple
from app.services.workflow.trigger_registry import TriggerHandler

logger = logging.getLogger(__name__)

# نرخ درخواست وب‌هوک به‌ازای workflow (پنجرهٔ ۶۰ ثانیه)
_webhook_rate_lock = threading.Lock()
_webhook_rate_state: Dict[str, Tuple[float, int]] = {}


def _webhook_rate_allow(workflow_id: Any, limit_per_minute: int) -> bool:
    if limit_per_minute <= 0:
        return True
    key = str(workflow_id)
    now = time.time()
    with _webhook_rate_lock:
        window_start, count = _webhook_rate_state.get(key, (now, 0))
        if now - window_start >= 60.0:
            window_start, count = now, 0
        count += 1
        _webhook_rate_state[key] = (window_start, count)
        return count <= limit_per_minute


class WebhookTrigger(TriggerHandler):
    """Trigger برای webhook (دریافت HTTP request)"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "Webhook",
            "description": "اجرای workflow با دریافت HTTP request",
            "config_schema": {
                "webhook_path": {
                    "type": "string",
                    "description": "مسیر webhook (اختیاری - اگر مشخص نشود از workflow ID استفاده می‌شود)",
                    "required": False
                },
                "method": {
                    "type": "string",
                    "description": "روش HTTP",
                    "default": "POST",
                    "enum": ["GET", "POST", "PUT", "DELETE", "PATCH"],
                    "ui_config": {
                        "labels": {
                            "GET": "GET - دریافت",
                            "POST": "POST - ارسال",
                            "PUT": "PUT - به‌روزرسانی کامل",
                            "DELETE": "DELETE - حذف",
                            "PATCH": "PATCH - به‌روزرسانی جزئی"
                        }
                    },
                    "required": False
                },
                "authentication_type": {
                    "type": "string",
                    "description": "نوع احراز هویت (none/api_key/bearer/signature)",
                    "enum": ["none", "api_key", "bearer", "signature"],
                    "default": "none",
                    "required": False
                },
                "api_key": {
                    "type": "string",
                    "description": "کلید API",
                    "required": False
                },
                "api_key_header": {
                    "type": "string",
                    "description": "نام header برای API key",
                    "default": "X-API-Key",
                    "required": False
                },
                "bearer_token": {
                    "type": "string",
                    "description": "توکن Bearer",
                    "required": False
                },
                "signature_secret": {
                    "type": "string",
                    "description": "رمز امضا",
                    "required": False
                },
                "signature_header": {
                    "type": "string",
                    "description": "نام header برای امضا",
                    "default": "X-Signature",
                    "required": False
                },
                "rate_limit": {
                    "type": "integer",
                    "description": "حداکثر درخواست در دقیقه",
                    "required": False
                },
                "validate_payload": {
                    "type": "boolean",
                    "description": "اعتبارسنجی payload",
                    "default": False,
                    "required": False
                },
                "timeout_seconds": {
                    "type": "integer",
                    "description": "Timeout برای پردازش (ثانیه)",
                    "default": 30,
                    "required": False
                }
            }
        }
    
    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        """
        برای webhook trigger، داده‌ها از HTTP request می‌آیند
        """
        trigger_data = context.get("trigger_data", {})
        headers = trigger_data.get("headers", {})
        method = trigger_data.get("method", "POST")

        wf_id = context.get("workflow_id")
        is_preview = bool(context.get("__workflow_trigger_preview__"))
        rate_limit = config.get("rate_limit")
        if not is_preview and rate_limit is not None and wf_id is not None:
            try:
                lim = int(rate_limit)
            except (TypeError, ValueError):
                lim = 0
            if lim > 0 and not _webhook_rate_allow(wf_id, lim):
                logger.warning("Webhook rate limit exceeded workflow_id=%s", wf_id)
                return {}

        if config.get("validate_payload"):
            body = trigger_data.get("body")
            if body is None or body == "" or body == {}:
                logger.warning("Webhook validate_payload failed: empty body")
                return {}

        # بررسی احراز هویت
        auth_type = config.get("authentication_type", "none")
        
        if auth_type == "api_key":
            api_key = config.get("api_key")
            api_key_header = config.get("api_key_header", "X-API-Key")
            provided_key = headers.get(api_key_header)
            if not api_key or provided_key != api_key:
                logger.warning("Webhook authentication failed: Invalid API key")
                return {}
        
        elif auth_type == "bearer":
            bearer_token = config.get("bearer_token")
            auth_header = headers.get("Authorization", "")
            if not auth_header.startswith("Bearer "):
                logger.warning("Webhook authentication failed: Missing Bearer token")
                return {}
            provided_token = auth_header.replace("Bearer ", "")
            if not bearer_token or provided_token != bearer_token:
                logger.warning("Webhook authentication failed: Invalid Bearer token")
                return {}
        
        elif auth_type == "signature":
            signature_secret = config.get("signature_secret")
            signature_header = config.get("signature_header", "X-Signature")
            provided_signature = headers.get(signature_header)
            
            if not signature_secret or not provided_signature:
                logger.warning("Webhook authentication failed: Missing signature")
                return {}
            
            # محاسبه امضا از body
            body = trigger_data.get("body", {})
            import json
            body_str = json.dumps(body, sort_keys=True) if isinstance(body, dict) else str(body)
            expected_signature = hmac.new(
                signature_secret.encode(),
                body_str.encode(),
                hashlib.sha256
            ).hexdigest()
            
            if not hmac.compare_digest(provided_signature, expected_signature):
                logger.warning("Webhook authentication failed: Invalid signature")
                return {}
        
        # بررسی method
        expected_method = config.get("method", "POST")
        if method.upper() != expected_method.upper():
            logger.warning(f"Webhook method mismatch: expected {expected_method}, got {method}")
            return {}
        
        return {
            "webhook_data": trigger_data.get("body", {}),
            "headers": headers,
            "query_params": trigger_data.get("query_params", {}),
            "method": method,
            "business_id": context.get("business_id")
        }

