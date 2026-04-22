from typing import Dict, Any, Optional, List
from datetime import datetime
from fastapi import APIRouter, Depends, Request, Query, WebSocket, WebSocketDisconnect, Body
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from sqlalchemy import desc

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.core.permissions import require_app_permission
from app.services.monitoring_service import HardwareMonitoringService, ServiceMonitoringService
from app.services.monitoring_realtime import monitoring_realtime_manager
from app.services.alert_service import AlertService
from app.core.monitoring import get_performance_monitor
from app.services.notification_outbox_monitoring_service import (
	get_notification_outbox_summary,
	abandon_outbox_rows,
)

router = APIRouter(prefix="/admin/monitoring", tags=["admin-monitoring"])


class AbandonNotificationOutboxBody(BaseModel):
	confirm_phrase: str = Field(..., description="باید دقیقاً مقدار abandon_confirm_phrase از خلاصهٔ outbox باشد")
	statuses: List[str] = Field(default_factory=lambda: ["failed"], description="فقط failed و/یا pending")
	channel: Optional[str] = Field(None, description="مثلاً sms — خالی یعنی همه کانال‌ها")
	event_key: Optional[str] = Field(None, description="مثلاً auth.password_reset")
	user_id: Optional[int] = Field(None, description="محدود به یک کاربر")
	only_retry_scheduled: bool = Field(True, description="فقط ردیف‌هایی که next_attempt_at دارند")
	max_rows: int = Field(50_000, ge=1, le=500_000)
	admin_note: Optional[str] = Field(None, max_length=120, description="یادداشت کوتاه در لاگ خطا")


# Hardware Monitoring Endpoints

@router.get(
	"/notifications/outbox/summary",
	summary="خلاصه صف اعلان‌ها و پیامک",
	description="آمار outbox، آستانه‌ها، Redis و سقف SMS به‌ازای مقصد — برای مانیتورینگ توسط مدیر",
)
@require_app_permission("system_settings")
def get_notification_outbox_summary_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	try:
		data = get_notification_outbox_summary(db)
		return success_response(data, request)
	except Exception as e:
		raise ApiError("INTERNAL_ERROR", f"خطا در خلاصه outbox: {str(e)}", http_status=500)


@router.post(
	"/notifications/outbox/abandon",
	summary="رها کردن دسته‌ای ردیف‌های outbox",
	description="خالی کردن صف retry/pending مطابق فیلتر؛ نیاز به عبارت تأیید از خلاصه outbox",
)
@require_app_permission("system_settings")
def abandon_notification_outbox_endpoint(
	request: Request,
	payload: AbandonNotificationOutboxBody = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	try:
		n = abandon_outbox_rows(
			db,
			confirm_phrase=payload.confirm_phrase,
			statuses=payload.statuses,
			channel=payload.channel,
			event_key=payload.event_key,
			user_id=payload.user_id,
			only_retry_scheduled=payload.only_retry_scheduled,
			max_rows=payload.max_rows,
			admin_note=payload.admin_note,
		)
		return success_response({"abandoned_count": n, "message": f"{n} ردیف به وضعیت abandoned منتقل شد"}, request)
	except ApiError:
		raise
	except Exception as e:
		raise ApiError("INTERNAL_ERROR", f"خطا در abandon outbox: {str(e)}", http_status=500)


@router.get(
	"/hardware/current",
	summary="دریافت وضعیت فعلی منابع سخت‌افزاری",
	description="دریافت metrics فعلی CPU، Memory، Disk و Network",
)
@require_app_permission("system_settings")
def get_hardware_current(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""دریافت وضعیت فعلی منابع سخت‌افزاری"""
	service = HardwareMonitoringService(db)
	try:
		metrics = service.get_current_metrics()
		return success_response(metrics, request)
	except Exception as e:
		raise ApiError("INTERNAL_ERROR", f"خطا در دریافت metrics: {str(e)}", http_status=500)


@router.get(
	"/hardware/history",
	summary="دریافت تاریخچه منابع سخت‌افزاری",
	description="دریافت تاریخچه metrics در بازه زمانی مشخص",
)
@require_app_permission("system_settings")
def get_hardware_history(
	request: Request,
	metric_type: str = Query(..., description="نوع metric (cpu, memory, disk, network)"),
	metric_name: Optional[str] = Query(None, description="نام metric خاص (اختیاری)"),
	start_time: Optional[str] = Query(None, description="زمان شروع (ISO format)"),
	end_time: Optional[str] = Query(None, description="زمان پایان (ISO format)"),
	interval_minutes: int = Query(1, ge=1, le=60, description="فاصله زمانی بر حسب دقیقه"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""دریافت تاریخچه metrics"""
	service = HardwareMonitoringService(db)
	try:
		start_dt = datetime.fromisoformat(start_time.replace('Z', '+00:00')) if start_time else None
		end_dt = datetime.fromisoformat(end_time.replace('Z', '+00:00')) if end_time else None
		
		metrics = service.get_historical_metrics(
			metric_type=metric_type,
			metric_name=metric_name,
			start_time=start_dt,
			end_time=end_dt,
			interval_minutes=interval_minutes,
		)
		
		return success_response({
			"metric_type": metric_type,
			"metric_name": metric_name,
			"data": metrics,
			"count": len(metrics),
		}, request)
	except ValueError as e:
		raise ApiError("INVALID_INPUT", f"فرمت تاریخ نامعتبر: {str(e)}", http_status=400)
	except Exception as e:
		raise ApiError("INTERNAL_ERROR", f"خطا در دریافت تاریخچه: {str(e)}", http_status=500)


# Services Monitoring Endpoints

@router.get(
	"/services/status",
	summary="دریافت وضعیت همه سرویس‌ها",
	description="بررسی وضعیت API Server، Database، Redis و Workers",
)
@require_app_permission("system_settings")
def get_services_status(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""دریافت وضعیت همه سرویس‌ها"""
	service = ServiceMonitoringService(db)
	try:
		services = service.check_all_services()
		return success_response(services, request)
	except Exception as e:
		raise ApiError("INTERNAL_ERROR", f"خطا در بررسی سرویس‌ها: {str(e)}", http_status=500)


@router.get(
	"/services/{service_name}/status",
	summary="دریافت وضعیت یک سرویس خاص",
	description="بررسی وضعیت یک سرویس مشخص",
)
@require_app_permission("system_settings")
def get_service_status(
	request: Request,
	service_name: str,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""دریافت وضعیت یک سرویس خاص"""
	service = ServiceMonitoringService(db)
	try:
		if service_name == "api_server":
			status = service.check_api_server()
		elif service_name == "database":
			status = service.check_database()
		elif service_name == "redis":
			status = service.check_redis()
		elif service_name == "workers":
			status = service.check_workers()
		elif service_name == "notification_moderation":
			status = service.check_notification_moderation_worker()
		else:
			raise ApiError("NOT_FOUND", f"سرویس '{service_name}' یافت نشد", http_status=404)
		
		return success_response(status, request)
	except ApiError:
		raise
	except Exception as e:
		raise ApiError("INTERNAL_ERROR", f"خطا در بررسی سرویس: {str(e)}", http_status=500)


# Performance Monitoring Endpoints

@router.get(
	"/performance/overview",
	summary="دریافت خلاصه عملکرد",
	description="دریافت آمار کلی عملکرد API",
)
@require_app_permission("system_settings")
def get_performance_overview(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""دریافت خلاصه عملکرد"""
	monitor = get_performance_monitor()
	
	# این endpoint می‌تواند در آینده کامل‌تر شود
	# فعلاً فقط یک placeholder است
	return success_response({
		"message": "Performance overview endpoint - به زودی تکمیل می‌شود",
		"cache_enabled": monitor.cache.enabled if monitor.cache else False,
	}, request)


@router.get(
	"/performance/endpoints",
	summary="دریافت آمار endpoint ها",
	description="دریافت آمار عملکرد endpoint های مختلف",
)
@require_app_permission("system_settings")
def get_endpoint_performance(
	request: Request,
	method: Optional[str] = Query(None, description="HTTP Method"),
	path: Optional[str] = Query(None, description="Path endpoint"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""دریافت آمار endpoint ها"""
	monitor = get_performance_monitor()
	
	if method and path:
		stats = monitor.get_endpoint_stats(method, path)
		return success_response({
			"endpoint": f"{method} {path}",
			"stats": stats,
		}, request)
	else:
		# در آینده می‌توان لیست همه endpoint ها را برگرداند
		return success_response({
			"message": "برای دریافت آمار یک endpoint خاص، method و path را مشخص کنید",
			"example": "/api/v1/admin/monitoring/performance/endpoints?method=GET&path=/api/v1/products",
		}, request)


@router.get(
	"/performance/slow-endpoints",
	summary="دریافت endpoint های کند",
	description="دریافت لیست endpoint هایی که زمان پاسخ بالایی دارند",
)
@require_app_permission("system_settings")
def get_slow_endpoints(
	request: Request,
	threshold_ms: int = Query(1000, ge=100, description="آستانه زمان پاسخ بر حسب میلی‌ثانیه"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""دریافت endpoint های کند"""
	# این endpoint در آینده کامل می‌شود
	return success_response({
		"message": "Slow endpoints endpoint - به زودی تکمیل می‌شود",
		"threshold_ms": threshold_ms,
	}, request)


# WebSocket Endpoint

@router.websocket("/stream")
async def monitoring_stream(
	websocket: WebSocket,
):
	"""
	WebSocket endpoint برای دریافت داده‌های لحظه‌ای مانیتورینگ

	احراز هویت: اولین فریم متنی JSON پس از TLS:
	{"type":"auth","api_key":"..."}
	(api_key در query string پشتیبانی نمی‌شود.)

	⚠️ مهم: Session را فقط برای authentication و داده‌های اولیه استفاده می‌کنیم
	و سپس می‌بندیم تا از connection leak جلوگیری کنیم.
	"""
	from adapters.db.repositories.api_key_repo import ApiKeyRepository
	from app.core.security import hash_api_key
	from adapters.db.models.user import User
	from adapters.db.session import SessionLocal
	from app.services.ws_api_key_handshake import (
		WsAuthClientDisconnected,
		WsAuthRejected,
		WsAuthTimeout,
		close_ws_safe,
		read_api_key_from_first_text_message,
	)

	await websocket.accept()
	try:
		api_key = await read_api_key_from_first_text_message(websocket)
	except WsAuthClientDisconnected:
		return
	except WsAuthTimeout:
		await close_ws_safe(websocket, 4408)
		return
	except WsAuthRejected as e:
		await close_ws_safe(websocket, e.close_code)
		return

	# ایجاد session موقت فقط برای authentication و داده‌های اولیه
	db: Session = SessionLocal()
	user = None
	try:
		key_hash = hash_api_key(api_key)
		repo = ApiKeyRepository(db)
		obj = repo.get_by_hash(key_hash)
		if not obj or obj.revoked_at is not None:
			await close_ws_safe(websocket, 4401)
			return

		user = db.get(User, obj.user_id)
		if not user or not user.is_active:
			await close_ws_safe(websocket, 4401)
			return

		# بررسی مجوز admin
		if not (user.app_permissions and ("superadmin" in user.app_permissions or "system_settings" in user.app_permissions)):
			await close_ws_safe(websocket, 4403)
			return

		# ارسال داده‌های اولیه قبل از بستن session
		hardware_service = HardwareMonitoringService(db)
		service_monitor = ServiceMonitoringService(db)

		try:
			initial_hardware = hardware_service.get_current_metrics()
			await monitoring_realtime_manager.broadcast_hardware_metrics(initial_hardware)
		except Exception:
			pass

		try:
			initial_services = service_monitor.check_all_services()
			await monitoring_realtime_manager.broadcast_service_status(initial_services)
		except Exception:
			pass
	finally:
		# بستن session بلافاصله بعد از authentication و داده‌های اولیه
		db.close()

	# اتصال WebSocket (بدون session؛ accept قبلاً انجام شده)
	await monitoring_realtime_manager.connect(websocket, already_accepted=True)
	
	try:
		# نگه داشتن اتصال
		while True:
			# دریافت پیام از کلاینت (heartbeat)
			try:
				_ = await websocket.receive_text()
			except WebSocketDisconnect:
				break
	except WebSocketDisconnect:
		pass
	except Exception as e:
		print(f"WebSocket error: {e}")
	finally:
		await monitoring_realtime_manager.disconnect(websocket)


# Alerts Endpoints

@router.get(
	"/alerts",
	summary="دریافت لیست هشدارها",
	description="دریافت لیست هشدارهای سیستم (فعال، تایید شده، حل شده)",
)
@require_app_permission("system_settings")
def get_alerts(
	request: Request,
	status: Optional[str] = Query(None, description="فیلتر بر اساس وضعیت (active, acknowledged, resolved)"),
	limit: int = Query(50, ge=1, le=200, description="تعداد هشدارها"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""دریافت لیست هشدارها"""
	from adapters.db.models.monitoring import MonitoringAlert
	
	try:
		query = db.query(MonitoringAlert)
		
		if status:
			query = query.filter(MonitoringAlert.status == status)
		
		alerts = query.order_by(desc(MonitoringAlert.created_at)).limit(limit).all()
		
		alerts_data = [
			{
				"id": alert.id,
				"alert_type": alert.alert_type,
				"severity": alert.severity,
				"title": alert.title,
				"message": alert.message,
				"metric_name": alert.metric_name,
				"threshold_value": float(alert.threshold_value) if alert.threshold_value else None,
				"current_value": float(alert.current_value) if alert.current_value else None,
				"status": alert.status,
				"created_at": alert.created_at.isoformat(),
				"acknowledged_at": alert.acknowledged_at.isoformat() if alert.acknowledged_at else None,
				"resolved_at": alert.resolved_at.isoformat() if alert.resolved_at else None,
			}
			for alert in alerts
		]
		
		return success_response({
			"alerts": alerts_data,
			"count": len(alerts_data),
		}, request)
	except Exception as e:
		raise ApiError("INTERNAL_ERROR", f"خطا در دریافت هشدارها: {str(e)}", http_status=500)


@router.get(
	"/alerts/active",
	summary="دریافت هشدارهای فعال",
	description="دریافت لیست هشدارهای فعال (نیاز به توجه)",
)
@require_app_permission("system_settings")
def get_active_alerts(
	request: Request,
	limit: int = Query(50, ge=1, le=200),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""دریافت هشدارهای فعال"""
	service = AlertService(db)
	try:
		alerts = service.get_active_alerts(limit=limit)
		
		alerts_data = [
			{
				"id": alert.id,
				"alert_type": alert.alert_type,
				"severity": alert.severity,
				"title": alert.title,
				"message": alert.message,
				"metric_name": alert.metric_name,
				"threshold_value": float(alert.threshold_value) if alert.threshold_value else None,
				"current_value": float(alert.current_value) if alert.current_value else None,
				"created_at": alert.created_at.isoformat(),
			}
			for alert in alerts
		]
		
		return success_response({
			"alerts": alerts_data,
			"count": len(alerts_data),
		}, request)
	except Exception as e:
		raise ApiError("INTERNAL_ERROR", f"خطا در دریافت هشدارهای فعال: {str(e)}", http_status=500)


@router.post(
	"/alerts/{alert_id}/acknowledge",
	summary="تایید هشدار",
	description="تایید یک هشدار توسط مدیر",
)
@require_app_permission("system_settings")
def acknowledge_alert(
	request: Request,
	alert_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""تایید یک هشدار"""
	service = AlertService(db)
	try:
		user_id = ctx.get_user_id()
		success = service.acknowledge_alert(alert_id, user_id)
		
		if not success:
			raise ApiError("NOT_FOUND", "هشدار یافت نشد", http_status=404)
		
		return success_response({
			"message": "هشدار تایید شد",
			"alert_id": alert_id,
		}, request)
	except ApiError:
		raise
	except Exception as e:
		raise ApiError("INTERNAL_ERROR", f"خطا در تایید هشدار: {str(e)}", http_status=500)


@router.post(
	"/alerts/{alert_id}/resolve",
	summary="حل کردن هشدار",
	description="حل کردن یک هشدار (به معنای حل شدن مشکل)",
)
@require_app_permission("system_settings")
def resolve_alert(
	request: Request,
	alert_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""حل کردن یک هشدار"""
	service = AlertService(db)
	try:
		success = service.resolve_alert(alert_id)
		
		if not success:
			raise ApiError("NOT_FOUND", "هشدار یافت نشد", http_status=404)
		
		return success_response({
			"message": "هشدار حل شد",
			"alert_id": alert_id,
		}, request)
	except ApiError:
		raise
	except Exception as e:
		raise ApiError("INTERNAL_ERROR", f"خطا در حل کردن هشدار: {str(e)}", http_status=500)

