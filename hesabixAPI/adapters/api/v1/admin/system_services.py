"""API لاگ و وضعیت واحدهای systemd (پنل ادمین: «لاگ‌های سرویس‌ها»).

پیش‌نیاز میزبان: لینوکس با systemd؛ دستورهای ``journalctl`` و ``systemctl`` در ``PATH``.

**Docker:** پروسس API باید به ژورنال همان میزبانی دسترسی داشته باشد که واحدهای
``hesabix-*`` را اجرا می‌کند. معمولاً سوکت systemd-journal را mount می‌کنند، برای مثال
``/run/systemd/journal/socket`` (گزینه‌های جایگزین بسته به توزیع در سند docs ذکر شده‌اند).

**دسترسی:** خواندن ژورنال ممکن است نیازمند عضویت کاربر اجرای API در گروه
``systemd-journal`` (یا معادل) باشد. ری‌استارت واحد معمولاً نیاز به مجوز مدیریت systemd
(مثلاً اجرای سرویس API با sudoers محدود یا capability) دارد.

راهنمای استقرار: ``hesabixAPI/docs/SERVICE_LOGS_ADMIN_API.md``.
"""
from __future__ import annotations

import copy
import json
import logging
import os
import re
import shutil
import subprocess
import time
from typing import Dict, Any, List, Set, Tuple
from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.core.permissions import require_app_permission
from app.core.logging import get_logging_diagnostics
from app.core.settings import get_settings

router = APIRouter(
	prefix="/admin/system-services",
	tags=["admin-system-services"],
)

logger = logging.getLogger(__name__)

# لیست پیش‌فرض سرویس‌های مجاز
DEFAULT_ALLOWED_SERVICES = [
	"hesabix-api",
	"hesabix-rq-worker",
	"hesabix-notification-moderation",  # Worker بررسی قالب‌های نوتیفیکیشن
]


def _normalize_service_name(service_name: str) -> str:
	"""یکپارچه‌سازی نام واحد systemd (حذف پسوند .service)."""
	value = (service_name or "").strip()
	if value.endswith(".service"):
		return value[:-8]
	return value


def _extract_unit_from_cgroup_line(line: str) -> str | None:
	"""
	استخراج نام یونیت از خط cgroup.
	نمونه: /system.slice/hesabix-api.service -> hesabix-api
	"""
	if ".service" not in line:
		return None
	match = re.search(r"/([^/\s]+)\.service(?:$|[/:])", line.strip())
	if not match:
		return None
	return _normalize_service_name(match.group(1))


def _detect_current_systemd_unit_candidates() -> List[str]:
	"""
	تشخیص سرویس systemd مربوط به پروسس فعلی API.
	اولویت:
	1) ENV: HESABIX_CURRENT_SYSTEMD_SERVICE
	2) /proc/self/cgroup
	3) systemctl show --pid <pid>
	"""
	candidates: List[str] = []

	env_service = _normalize_service_name(os.getenv("HESABIX_CURRENT_SYSTEMD_SERVICE", ""))
	if env_service:
		candidates.append(env_service)

	try:
		with open("/proc/self/cgroup", "r", encoding="utf-8") as fh:
			for line in fh:
				unit = _extract_unit_from_cgroup_line(line)
				if unit:
					candidates.append(unit)
	except Exception:
		pass

	if shutil.which("systemctl"):
		try:
			proc = subprocess.run(
				["systemctl", "show", f"--pid={os.getpid()}", "--property=Id", "--value"],
				capture_output=True,
				text=True,
				timeout=2,
				check=False,
			)
			if proc.returncode == 0:
				unit = _normalize_service_name(proc.stdout.strip())
				if unit:
					candidates.append(unit)
		except Exception:
			pass

	# حفظ ترتیب و حذف تکراری
	seen: Set[str] = set()
	uniq: List[str] = []
	for item in candidates:
		if not item or item in seen:
			continue
		seen.add(item)
		uniq.append(item)
	return uniq


def _allowed_services() -> List[str]:
	"""ساخت لیست سرویس‌های مجاز با پشتیبانی از ENV و کشف خودکار سرویس فعلی."""
	raw = list(DEFAULT_ALLOWED_SERVICES)
	extra = os.getenv("HESABIX_ALLOWED_SYSTEMD_SERVICES", "").strip()
	if extra:
		for part in extra.split(","):
			name = _normalize_service_name(part)
			if name:
				raw.append(name)

	raw.extend(_detect_current_systemd_unit_candidates())

	seen: Set[str] = set()
	final_list: List[str] = []
	for service in raw:
		name = _normalize_service_name(service)
		if not name or name in seen:
			continue
		seen.add(name)
		final_list.append(name)
	return final_list

_LOGS_CACHE: Dict[Tuple[str, int], Tuple[float, Dict[str, Any]]] = {}
_LOGS_CACHE_TTL_SEC = 2.0


def _require_journalctl() -> None:
	if not shutil.which("journalctl"):
		raise ApiError(
			"SERVICE_LOGS_UNAVAILABLE",
			"ابزار journalctl روی این میزبان در دسترس نیست؛ مشاهدهٔ لاگ سرویس فقط روی لینوکس با systemd پشتیبانی می‌شود.",
			http_status=503,
		)


def _require_systemctl() -> None:
	if not shutil.which("systemctl"):
		raise ApiError(
			"SERVICE_CONTROL_UNAVAILABLE",
			"ابزار systemctl روی این میزبان در دسترس نیست؛ مدیریت وضعیت/ری‌استارت واحد systemd فقط روی لینوکس با systemd پشتیبانی می‌شود.",
			http_status=503,
		)


def _combine_cmd_output(stdout: str | None, stderr: str | None) -> str:
	out = (stdout or "").strip()
	err = (stderr or "").strip()
	if err and out:
		return f"{out}\n{err}".strip()
	if err:
		return err
	return out


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


def _run_journalctl_with_optional_sudo(cmd: List[str]) -> subprocess.CompletedProcess[str]:
	"""
	اجرای journalctl با fallback اختیاری به sudo -n در خطای permission.
	برای فعال‌سازی صریح fallback می‌توان ENV زیر را 1/true/yes کرد:
	HESABIX_ALLOW_SUDO_JOURNALCTL=1
	"""
	result = subprocess.run(
		cmd,
		capture_output=True,
		text=True,
		timeout=10,
		check=False,
	)
	if result.returncode == 0:
		return result

	combined = _combine_cmd_output(result.stdout, result.stderr).lower()
	perm_denied = (
		"insufficient permissions" in combined
		or "permission denied" in combined
		or "access denied" in combined
	)
	allow_sudo_env = os.getenv("HESABIX_ALLOW_SUDO_JOURNALCTL", "").strip().lower() in {
		"1",
		"true",
		"yes",
		"on",
	}
	if not perm_denied and not allow_sudo_env:
		return result
	if not shutil.which("sudo"):
		return result

	return subprocess.run(
		["sudo", "-n", *cmd],
		capture_output=True,
		text=True,
		timeout=10,
		check=False,
	)


def _get_service_logs(service_name: str, lines: int = 100) -> Dict[str, Any]:
	"""دریافت لاگ‌های یک سرویس از journalctl"""
	service_name = _normalize_service_name(service_name)
	if service_name not in _allowed_services():
		raise ApiError("INVALID_SERVICE", f"سرویس '{service_name}' مجاز نیست", http_status=400)

	_require_journalctl()

	cache_key = (service_name, lines)
	now_m = time.monotonic()
	cached = _LOGS_CACHE.get(cache_key)
	if cached and (now_m - cached[0]) < _LOGS_CACHE_TTL_SEC:
		return copy.deepcopy(cached[1])

	try:
		# دریافت لاگ‌ها با journalctl
		cmd = ["journalctl", "-u", service_name, "-n", str(lines), "--no-pager", "-o", "json"]
		result = _run_journalctl_with_optional_sudo(cmd)

		if result.returncode != 0:
			combined = _combine_cmd_output(result.stdout, result.stderr)
			out_preview = combined[:800]
			logger.error(
				"journalctl failed for %s rc=%s preview=%s",
				service_name,
				result.returncode,
				out_preview,
			)
			hint = (result.stderr or "").strip()[:400]
			msg = (
				"journalctl خطا بازگرداند؛ معمولاً به‌دلیل نبودن واحد systemd روی همین میزبان، عدم دسترسی به ژورنال "
				"یا اجرای API خارج از میزبان اصلی سرویس (مثل ویندوز یا کانتینر بدون mount ژورنال)."
			)
			details = {"journalctl_preview": hint or out_preview[:400]} if (hint or out_preview) else None
			raise ApiError(
				"JOURNALCTL_FAILED",
				msg,
				http_status=503,
				details=details,
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
	service_name = _normalize_service_name(service_name)
	if service_name not in _allowed_services():
		raise ApiError("INVALID_SERVICE", f"سرویس '{service_name}' مجاز نیست", http_status=400)

	_require_systemctl()

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
	service_name = _normalize_service_name(service_name)
	if service_name not in _allowed_services():
		raise ApiError("INVALID_SERVICE", f"سرویس '{service_name}' مجاز نیست", http_status=400)

	_require_systemctl()

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
		
		status_text = _combine_cmd_output(result.stdout, result.stderr)[:2000]
		status_text = status_text if status_text else None
		return {
			"service": service_name,
			"is_active": is_active_result.stdout.strip() == "active",
			"is_enabled": is_enabled_result.stdout.strip() == "enabled",
			"status_output": status_text,
		}
	except subprocess.TimeoutExpired:
		raise ApiError("TIMEOUT", "دریافت وضعیت سرویس زمان‌بر شد", http_status=504)
	except Exception as e:
		logger.error(f"Error getting service status: {e}", exc_info=True)
		raise ApiError("INTERNAL_ERROR", f"خطا در دریافت وضعیت سرویس: {str(e)}", http_status=500)


@router.get(
	"/logging-diagnostics",
	summary="وضعیت پیکربندی لاگ API",
	description=(
		"سطح لاگ مؤثر، لاگرهای اصلی (uvicorn/sqlalchemy/…) و راهنمای فعال‌سازی DEBUG. "
		"تغییر LOG_LEVEL نیازمند ری‌استارت سرویس است (به‌ویژه با چند worker)."
	),
)
@require_app_permission("system_settings")
def get_logging_diagnostics_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	data = get_logging_diagnostics()
	data["app_environment"] = get_settings().environment
	return success_response(data, request)


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
	return success_response({"services": _allowed_services()}, request)


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
		for service in _allowed_services():
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

