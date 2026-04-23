"""
Actionهای کمکی (log, set variable, etc)
"""

from typing import Any, Dict
import logging
from app.services.workflow.action_registry import ActionHandler
from app.services.workflow.logging_decorators import log_action_execution

logger = logging.getLogger(__name__)


class SetVariableAction(ActionHandler):
    """تنظیم متغیر در context"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "تنظیم متغیر",
            "description": "تنظیم یک متغیر در context برای استفاده در nodeهای بعدی",
            "config_schema": {
                "variable_name": {
                    "type": "string",
                    "description": "نام متغیر",
                    "required": True
                },
                "value": {
                    "type": "any",
                    "description": "مقدار متغیر (می‌تواند از nodeهای قبلی باشد)",
                    "required": True
                }
            }
        }
    
    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        from app.services.workflow.workflow_engine import WorkflowEngine
        
        # حل کردن مقدار
        variable_name = config.get("variable_name")
        value = WorkflowEngine._resolve_value_static(config.get("value"), context, node_results)
        
        # تنظیم در context
        if "variables" not in context:
            context["variables"] = {}
        context["variables"][variable_name] = value
        
        return {
            "success": True,
            "variable_name": variable_name,
            "value": value
        }


class LogAction(ActionHandler):
    """ثبت لاگ"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ثبت لاگ",
            "description": "ثبت یک لاگ در workflow execution",
            "config_schema": {
                "level": {
                    "type": "string",
                    "description": "سطح لاگ",
                    "default": "info",
                    "required": False,
                    "enum": ["debug", "info", "warning", "error", "critical"],
                    "ui_config": {
                        "labels": {
                            "debug": "Debug",
                            "info": "Info",
                            "warning": "هشدار",
                            "error": "خطا",
                            "critical": "بحرانی"
                        }
                    }
                },
                "message": {
                    "type": "string",
                    "description": "پیام لاگ",
                    "required": True
                },
                "data": {
                    "type": "object",
                    "description": "داده‌های اضافی (اختیاری)",
                    "required": False
                }
            }
        }
    
    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        from app.services.workflow.workflow_engine import WorkflowEngine
        from adapters.db.models.workflow import WorkflowLog, WorkflowLogLevel
        from sqlalchemy.orm import Session
        
        # حل کردن مقادیر
        level_str = config.get("level", "info").upper()
        message = WorkflowEngine._resolve_value_static(config.get("message"), context, node_results)
        data = config.get("data", {})
        
        # تبدیل به WorkflowLogLevel
        level = WorkflowLogLevel.INFO
        if level_str == "DEBUG":
            level = WorkflowLogLevel.DEBUG
        elif level_str == "WARNING":
            level = WorkflowLogLevel.WARNING
        elif level_str == "ERROR":
            level = WorkflowLogLevel.ERROR
        
        # ثبت لاگ
        db = context.get("db")
        if db and isinstance(db, Session):
            log = WorkflowLog(
                execution_id=context.get("execution_id"),
                level=level,
                message=str(message),
                data=data if data else None
            )
            db.add(log)
            db.commit()
        
        # همچنین در logger معمولی هم ثبت می‌کنیم
        logger.log(
            getattr(logging, level_str, logging.INFO),
            f"Workflow Log: {message}"
        )
        
        return {
            "success": True,
            "level": level_str,
            "message": message
        }


class HttpRequestAction(ActionHandler):
    """ارسال HTTP Request"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "HTTP Request",
            "description": "ارسال یک درخواست HTTP به URL مشخص",
            "config_schema": {
                "url": {
                    "type": "string",
                    "description": "URL مقصد",
                    "required": True
                },
                "method": {
                    "type": "string",
                    "description": "روش HTTP (GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS)",
                    "enum": ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"],
                    "default": "POST",
                    "required": False
                },
                "headers": {
                    "type": "object",
                    "description": "هدرهای HTTP (اختیاری)",
                    "required": False
                },
                "query_params": {
                    "type": "object",
                    "description": "پارامترهای query string",
                    "required": False
                },
                "body": {
                    "type": "any",
                    "description": "بدنه درخواست (اختیاری)",
                    "required": False
                },
                "body_type": {
                    "type": "string",
                    "description": "نوع بدنه (json/form/raw)",
                    "enum": ["json", "form", "raw"],
                    "default": "json",
                    "required": False
                },
                "auth_type": {
                    "type": "string",
                    "description": "نوع احراز هویت (none/basic/bearer)",
                    "enum": ["none", "basic", "bearer"],
                    "default": "none",
                    "required": False
                },
                "auth_config": {
                    "type": "object",
                    "description": "تنظیمات احراز هویت",
                    "required": False
                },
                "timeout_seconds": {
                    "type": "integer",
                    "description": "Timeout (ثانیه)",
                    "default": 30,
                    "required": False
                },
                "retry_on_failure": {
                    "type": "boolean",
                    "description": "تلاش مجدد در صورت خطا",
                    "default": True,
                    "required": False
                },
                "retry_attempts": {
                    "type": "integer",
                    "description": "تعداد تلاش‌های مجدد",
                    "default": 3,
                    "required": False
                },
                "retry_delay_seconds": {
                    "type": "integer",
                    "description": "تاخیر پایه (ثانیه)",
                    "default": 1,
                    "required": False
                },
                "exponential_backoff": {
                    "type": "boolean",
                    "description": "استفاده از تاخیر نمایی",
                    "default": True,
                    "required": False
                },
                "retryable_status_codes": {
                    "type": "array",
                    "description": "کدهای وضعیت قابل retry",
                    "items": {"type": "integer"},
                    "default": [500, 502, 503, 504],
                    "required": False
                },
                "circuit_breaker_enabled": {
                    "type": "boolean",
                    "description": "فعال کردن circuit breaker",
                    "default": False,
                    "required": False
                },
                "circuit_breaker_threshold": {
                    "type": "integer",
                    "description": "آستانه خطا برای باز کردن مدار",
                    "default": 5,
                    "required": False
                }
            }
        }
    
    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        import httpx
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.services.workflow.utils import execute_with_retry, get_retry_config_from_action_config
        from app.services.workflow.utils.circuit_breaker import get_circuit_breaker, CircuitBreakerOpenError

        sk = dry_run_skip(context, "درخواست HTTP")
        if sk is not None:
            return sk
        
        # حل کردن مقادیر
        url = str(WorkflowEngine._resolve_value_static(config.get("url"), context, node_results))
        method = config.get("method", "POST").upper()
        headers = config.get("headers", {}) or {}
        query_params = config.get("query_params", {}) or {}
        body = config.get("body")
        body_type = config.get("body_type", "json")
        timeout_seconds = config.get("timeout_seconds", 30)
        auth_type = config.get("auth_type", "none")
        auth_config = config.get("auth_config", {}) or {}
        
        # اضافه کردن احراز هویت به headers
        if auth_type == "basic":
            import base64
            username = auth_config.get("username", "")
            password = auth_config.get("password", "")
            credentials = base64.b64encode(f"{username}:{password}".encode()).decode()
            headers["Authorization"] = f"Basic {credentials}"
        elif auth_type == "bearer":
            token = auth_config.get("token", "")
            headers["Authorization"] = f"Bearer {token}"
        
        # حل کردن query params اگر از nodeهای قبلی باشند
        resolved_query_params = {}
        for key, value in query_params.items():
            resolved_query_params[key] = WorkflowEngine._resolve_value_static(value, context, node_results)
        
        def _make_request():
            """تابع داخلی برای ارسال درخواست"""
            timeout = httpx.Timeout(timeout_seconds)
            
            with httpx.Client(timeout=timeout) as client:
                # آماده‌سازی body بر اساس body_type
                request_kwargs = {
                    "headers": headers,
                    "params": resolved_query_params if resolved_query_params else None,
                }
                
                if body and method not in ["GET", "HEAD", "OPTIONS"]:
                    if body_type == "json":
                        request_kwargs["json"] = body
                    elif body_type == "form":
                        request_kwargs["data"] = body
                    elif body_type == "raw":
                        request_kwargs["content"] = body if isinstance(body, bytes) else str(body).encode()
                
                # ارسال درخواست
                if method == "GET":
                    response = client.get(url, **request_kwargs)
                elif method == "POST":
                    response = client.post(url, **request_kwargs)
                elif method == "PUT":
                    response = client.put(url, **request_kwargs)
                elif method == "PATCH":
                    response = client.patch(url, **request_kwargs)
                elif method == "DELETE":
                    response = client.delete(url, **request_kwargs)
                elif method == "HEAD":
                    response = client.head(url, **request_kwargs)
                elif method == "OPTIONS":
                    response = client.options(url, **request_kwargs)
                else:
                    raise ValueError(f"Unsupported HTTP method: {method}")
                
                # بررسی status code برای retry
                retryable_status_codes = config.get("retryable_status_codes", [500, 502, 503, 504])
                if response.status_code in retryable_status_codes:
                    raise httpx.HTTPStatusError(
                        f"Retryable status code: {response.status_code}",
                        request=response.request,
                        response=response
                    )
                
                # پردازش پاسخ
                content_type = response.headers.get("content-type", "")
                if content_type.startswith("application/json"):
                    try:
                        response_data = response.json()
                    except Exception:
                        response_data = response.text
                else:
                    response_data = response.text
                
                return {
                    "success": response.is_success,
                    "status_code": response.status_code,
                    "response": response_data,
                    "headers": dict(response.headers)
                }
        
        # استفاده از circuit breaker اگر فعال باشد
        circuit_breaker_enabled = config.get("circuit_breaker_enabled", False)
        circuit_breaker = None
        
        if circuit_breaker_enabled:
            circuit_breaker_threshold = config.get("circuit_breaker_threshold", 5)
            circuit_breaker = get_circuit_breaker(
                key=url,
                failure_threshold=circuit_breaker_threshold,
                timeout=60.0
            )
        
        def _execute_with_circuit_breaker():
            """اجرای درخواست با circuit breaker"""
            if circuit_breaker:
                return circuit_breaker.call(_make_request)
            else:
                return _make_request()
        
        # اجرا با retry mechanism
        retry_on_failure = config.get("retry_on_failure", True)
        
        try:
            if retry_on_failure:
                retry_config = get_retry_config_from_action_config(config)
                # فقط exceptionهای HTTP را retry کن
                retry_config["retryable_exceptions"] = [
                    httpx.RequestError,
                    httpx.TimeoutException,
                    httpx.HTTPStatusError,
                ]
                result = execute_with_retry(
                    _execute_with_circuit_breaker,
                    **retry_config
                )
            else:
                result = _execute_with_circuit_breaker()
            
            return result
            
        except CircuitBreakerOpenError as e:
            logger.error(f"Circuit breaker is OPEN for {url}: {e}")
            return {
                "success": False,
                "error": f"Circuit breaker is OPEN: {str(e)}",
                "circuit_breaker_open": True
            }
        except Exception as e:
            logger.error(f"HTTP request failed: {e}", exc_info=True)
            return {
                "success": False,
                "error": str(e)
            }

