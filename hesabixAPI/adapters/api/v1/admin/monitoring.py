from typing import Dict, Any, Optional, List
from datetime import datetime
from fastapi import APIRouter, Depends, Request, Query, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.core.permissions import require_app_permission
from app.services.monitoring_service import HardwareMonitoringService, ServiceMonitoringService
from app.services.monitoring_realtime import monitoring_realtime_manager
from app.services.alert_service import AlertService
from app.core.monitoring import get_performance_monitor

router = APIRouter(prefix="/admin/monitoring", tags=["admin-monitoring"])


# Hardware Monitoring Endpoints

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
	db: Session = Depends(get_db),
):
	"""WebSocket endpoint برای دریافت داده‌های لحظه‌ای مانیتورینگ"""
	# بررسی احراز هویت از طریق query parameter
	api_key = websocket.query_params.get("api_key")
	if not api_key:
		await websocket.close(code=4401, reason="API key required")
		return
	
	# بررسی صحت API key
	from adapters.db.repositories.api_key_repo import ApiKeyRepository
	from app.core.security import hash_api_key
	from adapters.db.models.user import User
	
	key_hash = hash_api_key(api_key)
	repo = ApiKeyRepository(db)
	obj = repo.get_by_hash(key_hash)
	if not obj or obj.revoked_at is not None:
		await websocket.close(code=4401, reason="Invalid API key")
		return
	
	user = db.get(User, obj.user_id)
	if not user or not user.is_active:
		await websocket.close(code=4401, reason="User not found or inactive")
		return
	
	# بررسی مجوز admin
	if not (user.app_permissions and ("superadmin" in user.app_permissions or "system_settings" in user.app_permissions)):
		await websocket.close(code=4403, reason="Permission denied")
		return
	
	# اتصال WebSocket
	await monitoring_realtime_manager.connect(websocket)
	
	try:
		# ارسال داده‌های اولیه
		hardware_service = HardwareMonitoringService(db)
		service_monitor = ServiceMonitoringService(db)
		
		try:
			initial_hardware = hardware_service.get_current_metrics()
			await monitoring_realtime_manager.broadcast_hardware_metrics(initial_hardware)
		except:
			pass
		
		try:
			initial_services = service_monitor.check_all_services()
			await monitoring_realtime_manager.broadcast_service_status(initial_services)
		except:
			pass
		
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
	from sqlalchemy import and_
	
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

