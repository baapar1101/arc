from __future__ import annotations

import copy
import json
import subprocess
import logging
import time
from typing import Dict, Any, List, Tuple
from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.core.permissions import require_app_permission

router = APIRouter(prefix="/admin/system-services", tags=["admin-system-services"])

logger = logging.getLogger(__name__)

# لیست سرویس‌های مجاز
ALLOWED_SERVICES = [
    "hesabix-api",
    "hesabix-rq-worker",
    "hesabix-notification-moderation"  # Worker بررسی قالب‌های نوتیفیکیشن
]

_LOGS_CACHE: Dict[Tuple[str, int], Tuple[float, Dict[str, Any]]] = {}
_LOGS_CACHE_TTL_SEC = 2.0


def _normalize_journal_message(message: Any) -> str:
	"""تبدیل MESSAGE ژورنال به رشتهٔ قابل‌نمایش (متن، بایت، آرایهٔ بایت و …)."""
	if message is None:
		return ""
	if isinstance(message, str):
		return message
	if isinstance(message, (bytes, bytearray)):
		try:
			return bytes(message).decode("utf-8", errors="replace")
		except Exception:
			return repr(message)
	if isinstance(message, list):
		try:
			if message and all(isinstance(x, int) for x in message):
				return bytes(message).decode("utf-8", errors="replace")
		except Exception:
			pass
		return "".join(_normalize_journal_message(x) for x in message)
	return str(message)


def _priority_to_str(value: Any) -> str:
	if value is None:
		return "6"
	if isinstance(value, int):
		return str(value)
	return str(value)


def _get_service_logs(service_name: str, lines: int = 100) -> Dict[str, Any]:
	"""دریافت لاگ‌های یک سرویس از journalctl"""
	if service_name not in ALLOWED_SERVICES:
		raise ApiError("INVALID_SERVICE", f"سرویس '{service_name}' مجاز نیست", http_status=400)

	cache_key = (service_name, lines)
	now_m = time.monotonic()
	cached = _LOGS_CACHE.get(cache_key)
	if cached and (now_m - cached[0]) < _LOGS_CACHE_TTL_SEC:
		return copy.deepcopy(cached[1])

	try:
		# دریافت لاگ‌ها با journalctl
		cmd = ["journalctl", "-u", service_name, "-n", str(lines), "--no-pager", "-o", "json"]
		result = subprocess.run(
			cmd,
			capture_output=True,
			text=True,
			timeout=10,
			check=False
		)

		if result.returncode != 0:
			out_preview = (result.stdout or "")[:500]
			logger.error(
				"journalctl failed for %s rc=%s stderr=%s stdout_preview=%s",
				service_name,
				result.returncode,
				(result.stderr or "").strip(),
				out_preview,
			)
			raise ApiError(
				"INTERNAL_ERROR",
				"خطا در دریافت لاگ‌ها از journalctl",
				http_status=500,
			)

		# Parse JSON lines
		logs: List[Dict[str, Any]] = []
		for line in result.stdout.strip().split('\n'):
			if line.strip():
				try:
					log_entry = json.loads(line)
					logs.append({
						"timestamp": str(log_entry.get("__REALTIME_TIMESTAMP", "") or ""),
						"level": _priority_to_str(log_entry.get("PRIORITY", "6")),
						"message": _normalize_journal_message(log_entry.get("MESSAGE")),
						"service": log_entry.get("_SYSTEMD_UNIT", "") or "",
						"pid": log_entry.get("_PID", "") or "",
					})
				except json.JSONDecodeError:
					continue

		# معکوس کردن برای نمایش جدیدترین اول
		logs.reverse()

		payload: Dict[str, Any] = {
			"service": service_name,
			"total_lines": len(logs),
			"logs": logs,
		}
		_LOGS_CACHE[cache_key] = (now_m, copy.deepcopy(payload))
		return copy.deepcopy(payload)
	except subprocess.TimeoutExpired:
		raise ApiError("TIMEOUT", "دریافت لاگ‌ها زمان‌بر شد", http_status=504)
	except ApiError:
		raise
	except Exception as e:
		logger.error(f"Error getting service logs: {e}", exc_info=True)
		raise ApiError("INTERNAL_ERROR", f"خطا در دریافت لاگ‌ها: {str(e)}", http_status=500)


def _restart_service(service_name: str) -> Dict[str, Any]:
	"""Restart کردن یک سرویس systemd"""
	if service_name not in ALLOWED_SERVICES:
		raise ApiError("INVALID_SERVICE", f"سرویس '{service_name}' مجاز نیست", http_status=400)
	
	try:
		# Restart کردن سرویس
		cmd = ["systemctl", "restart", service_name]
		result = subprocess.run(
			cmd,
			capture_output=True,
			text=True,
			timeout=30,
			check=False
		)
		
		if result.returncode != 0:
			logger.error(f"Error restarting {service_name}: {result.stderr}")
			raise ApiError("INTERNAL_ERROR", f"خطا در restart کردن سرویس: {result.stderr}", http_status=500)
		
		# بررسی وضعیت سرویس
		status_cmd = ["systemctl", "is-active", service_name]
		status_result = subprocess.run(
			status_cmd,
			capture_output=True,
			text=True,
			timeout=5,
			check=False
		)
		
		return {
			"service": service_name,
			"status": "restarted",
			"is_active": status_result.stdout.strip() == "active",
			"message": f"سرویس {service_name} با موفقیت restart شد"
		}
	except subprocess.TimeoutExpired:
		raise ApiError("TIMEOUT", "Restart کردن سرویس زمان‌بر شد", http_status=504)
	except Exception as e:
		logger.error(f"Error restarting service: {e}", exc_info=True)
		raise ApiError("INTERNAL_ERROR", f"خطا در restart کردن سرویس: {str(e)}", http_status=500)


def _get_service_status(service_name: str) -> Dict[str, Any]:
	"""دریافت وضعیت یک سرویس"""
	if service_name not in ALLOWED_SERVICES:
		raise ApiError("INVALID_SERVICE", f"سرویس '{service_name}' مجاز نیست", http_status=400)
	
	try:
		# دریافت وضعیت سرویس
		cmd = ["systemctl", "status", service_name, "--no-pager", "-l"]
		result = subprocess.run(
			cmd,
			capture_output=True,
			text=True,
			timeout=5,
			check=False
		)
		
		# بررسی فعال بودن
		is_active_cmd = ["systemctl", "is-active", service_name]
		is_active_result = subprocess.run(
			is_active_cmd,
			capture_output=True,
			text=True,
			timeout=5,
			check=False
		)
		
		# بررسی فعال بودن در startup
		is_enabled_cmd = ["systemctl", "is-enabled", service_name]
		is_enabled_result = subprocess.run(
			is_enabled_cmd,
			capture_output=True,
			text=True,
			timeout=5,
			check=False
		)
		
		return {
			"service": service_name,
			"is_active": is_active_result.stdout.strip() == "active",
			"is_enabled": is_enabled_result.stdout.strip() == "enabled",
			"status_output": result.stdout[:2000] if result.returncode == 0 else None,
		}
	except subprocess.TimeoutExpired:
		raise ApiError("TIMEOUT", "دریافت وضعیت سرویس زمان‌بر شد", http_status=504)
	except Exception as e:
		logger.error(f"Error getting service status: {e}", exc_info=True)
		raise ApiError("INTERNAL_ERROR", f"خطا در دریافت وضعیت سرویس: {str(e)}", http_status=500)


@router.get(
	"/allowed-services",
	summary="نام سرویس‌های مجاز",
	description="لیست واحدهای systemd مجاز برای مشاهده لاگ و restart",
)
@require_app_permission("system_settings")
def list_allowed_services(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	return success_response({"services": list(ALLOWED_SERVICES)}, request)


@router.get(
	"/logs",
	summary="دریافت لاگ‌های سرویس‌های سیستم",
	description="دریافت لاگ از journalctl برای سرویس‌های مجاز (لیست در /allowed-services)",
)
@require_app_permission("system_settings")
def get_service_logs(
	request: Request,
	service_name: str = Query(..., description="نام واحد systemd (مثلاً hesabix-api)"),
	lines: int = Query(100, ge=1, le=1000, description="تعداد خطوط لاگ"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""دریافت لاگ‌های یک سرویس"""
	try:
		logs_data = _get_service_logs(service_name, lines)
		return success_response(logs_data, request)
	except ApiError:
		raise
	except Exception as e:
		logger.error(f"Unexpected error getting service logs: {e}", exc_info=True)
		raise ApiError("INTERNAL_ERROR", f"خطای غیرمنتظره: {str(e)}", http_status=500)


@router.get(
	"/status",
	summary="دریافت وضعیت سرویس‌های سیستم",
	description="دریافت وضعیت فعال/غیرفعال بودن سرویس‌ها",
)
@require_app_permission("system_settings")
def get_service_status(
	request: Request,
	service_name: str = Query(..., description="نام واحد systemd مجاز"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""دریافت وضعیت یک سرویس"""
	try:
		status_data = _get_service_status(service_name)
		return success_response(status_data, request)
	except ApiError:
		raise
	except Exception as e:
		logger.error(f"Unexpected error getting service status: {e}", exc_info=True)
		raise ApiError("INTERNAL_ERROR", f"خطای غیرمنتظره: {str(e)}", http_status=500)


@router.get(
	"/status/all",
	summary="دریافت وضعیت همه سرویس‌ها",
	description="دریافت وضعیت همه سرویس‌های مجاز",
)
@require_app_permission("system_settings")
def get_all_services_status(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""دریافت وضعیت همه سرویس‌ها"""
	try:
		services_status = {}
		for service in ALLOWED_SERVICES:
			try:
				services_status[service] = _get_service_status(service)
			except Exception as e:
				logger.warning(f"Error getting status for {service}: {e}")
				services_status[service] = {
					"service": service,
					"is_active": False,
					"error": str(e)
				}
		
		return success_response({"services": services_status}, request)
	except Exception as e:
		logger.error(f"Unexpected error getting all services status: {e}", exc_info=True)
		raise ApiError("INTERNAL_ERROR", f"خطای غیرمنتظره: {str(e)}", http_status=500)


@router.post(
	"/restart",
	summary="Restart کردن سرویس سیستم",
	description="Restart یک واحد systemd از لیست سرویس‌های مجاز",
)
@require_app_permission("system_settings")
def restart_service(
	request: Request,
	service_name: str = Query(..., description="نام واحد systemd مجاز"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""Restart کردن یک سرویس"""
	try:
		restart_result = _restart_service(service_name)
		
		# ثبت لاگ فعالیت
		from app.services.activity_log_service import log_activity
		log_activity(
			db=db,
			user_id=ctx.get_user_id(),
			category="settings",
			action="restart_service",
			description=f"Restart کردن سرویس {service_name}",
			extra_info={"service_name": service_name}
		)
		
		return success_response(restart_result, request)
	except ApiError:
		raise
	except Exception as e:
		logger.error(f"Unexpected error restarting service: {e}", exc_info=True)
		raise ApiError("INTERNAL_ERROR", f"خطای غیرمنتظره: {str(e)}", http_status=500)

