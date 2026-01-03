from __future__ import annotations

from datetime import datetime
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session
from sqlalchemy import text

from adapters.api.v1.schemas import SuccessResponse
from adapters.db.session import get_db
from app.core.responses import success_response
from app.core.cache import get_cache
from app.core.monitoring import get_performance_monitor
from app.core.db_pool_monitor import ConnectionPoolMonitor

router = APIRouter(prefix="/health", tags=["health"]) 


@router.get("", 
	summary="بررسی وضعیت سرویس", 
	description="بررسی وضعیت کلی سرویس و در دسترس بودن آن",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "سرویس در دسترس است",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "سرویس در دسترس است",
						"data": {
							"status": "ok",
							"timestamp": "2024-01-01T00:00:00Z"
						}
					}
				}
			}
		}
	}
)
def health(request: Request, db: Session = Depends(get_db)) -> dict:
	"""Health check endpoint با بررسی دیتابیس و Redis"""
	from app.core.settings import get_settings
	
	settings = get_settings()
	cache = get_cache()
	
	# تست اتصال دیتابیس
	db_status = "ok"
	try:
		db.execute(text("SELECT 1"))
	except Exception:
		db_status = "error"
	
	# تست اتصال Redis
	redis_status = "disabled"
	if cache.enabled:
		try:
			cache.client.ping()
			redis_status = "ok"
		except Exception:
			redis_status = "error"
	
	# دریافت Connection Pool Stats
	pool_stats = None
	pool_health = None
	try:
		pool_stats = ConnectionPoolMonitor.get_pool_stats()
		pool_health = ConnectionPoolMonitor.get_pool_health()
	except Exception as e:
		# اگر خطا در دریافت Pool Stats بود، از آن صرف نظر می‌کنیم
		pass
	
	overall_status = "ok" if db_status == "ok" else "degraded"
	
	# اگر Pool در وضعیت Critical باشد، Overall Status را degraded می‌کنیم
	if pool_health and not pool_health.get("healthy", True):
		if pool_health.get("status") == "critical":
			overall_status = "degraded"
	
	response_data = {
		"status": overall_status,
		"timestamp": datetime.utcnow().isoformat(),
		"services": {
			"database": db_status,
			"redis": redis_status,
		},
		"version": settings.app_version,
	}
	
	# اضافه کردن Pool Stats به Response
	if pool_stats:
		response_data["connection_pool"] = {
			"status": pool_stats.get("status", "unknown"),
			"usage_percent": pool_stats.get("usage_percent", 0),
			"checked_out": pool_stats.get("checked_out", 0),
			"total_capacity": pool_stats.get("total_capacity", 0),
		}
	
	return success_response(response_data, request)


@router.get("/metrics",
	summary="دریافت Metrics عملکرد",
	description="دریافت آمار عملکرد endpoint ها (نیاز به مجوز admin)",
)
def get_metrics(
	request: Request,
	endpoint: str | None = None,
	db: Session = Depends(get_db),
) -> dict:
	"""دریافت metrics عملکرد"""
	from app.core.auth_dependency import get_current_user, AuthContext
	from app.core.responses import ApiError
	
	try:
		ctx: AuthContext = get_current_user(request, db)
		if not ctx.has_any_permission("system_settings", "superadmin"):
			raise ApiError("FORBIDDEN", "Missing permission", http_status=403)
	except Exception:
		# اگر احراز هویت نشد، metrics را نشان نمی‌دهیم
		raise ApiError("UNAUTHORIZED", "Authentication required", http_status=401)
	
	monitor = get_performance_monitor()
	
	if endpoint:
		# دریافت آمار یک endpoint خاص
		method, path = endpoint.split(" ", 1) if " " in endpoint else ("GET", endpoint)
		stats = monitor.get_endpoint_stats(method, path)
		return success_response({
			"endpoint": endpoint,
			"stats": stats,
		}, request)
	else:
		# دریافت لیست endpoint های کند
		# این نیاز به پیاده‌سازی بیشتر دارد
		return success_response({
			"message": "برای دریافت metrics یک endpoint خاص، از query parameter endpoint استفاده کنید",
			"example": "/api/v1/health/metrics?endpoint=GET /api/v1/products",
		}, request)


@router.get("/database",
	summary="بررسی سلامت پایگاه داده",
	description="بررسی سلامت پایگاه داده و Connection Pool با جزئیات کامل",
)
def database_health(request: Request, db: Session = Depends(get_db)) -> dict:
	"""بررسی سلامت پایگاه داده و Connection Pool"""
	from fastapi.responses import JSONResponse
	from sqlalchemy import text
	import time
	
	health_status = {
		"status": "healthy",
		"timestamp": datetime.utcnow().isoformat(),
		"checks": {}
	}
	
	# 1. Check Master Connection
	try:
		start_time = time.perf_counter()
		result = db.execute(text("SELECT 1")).scalar()
		response_time_ms = (time.perf_counter() - start_time) * 1000
		
		health_status["checks"]["master"] = {
			"status": "ok" if result == 1 else "error",
			"response_time_ms": round(response_time_ms, 2),
		}
	except Exception as e:
		health_status["checks"]["master"] = {
			"status": "error",
			"error": str(e)
		}
		health_status["status"] = "unhealthy"
	
	# 2. Check Connection Pool
	try:
		pool_stats = ConnectionPoolMonitor.get_pool_stats()
		pool_health = ConnectionPoolMonitor.get_pool_health()
		
		health_status["checks"]["connection_pool"] = {
			"status": pool_stats.get("status", "unknown"),
			"stats": pool_stats,
			"healthy": pool_health.get("healthy", True),
			"recommendations": pool_health.get("recommendations", [])
		}
		
		# Alert اگر Pool در وضعیت Critical باشد
		if pool_stats.get("status") == "critical":
			health_status["status"] = "degraded"
		elif pool_stats.get("status") == "warning" and health_status["status"] == "healthy":
			health_status["status"] = "degraded"
	except Exception as e:
		health_status["checks"]["connection_pool"] = {
			"status": "error",
			"error": str(e)
		}
	
	# 3. Check Database Size
	try:
		result = db.execute(text("""
			SELECT 
				pg_database.datname AS database,
				ROUND(pg_database_size(pg_database.datname) / 1024.0 / 1024.0, 2) AS size_mb
			FROM pg_database
			WHERE pg_database.datname = current_database()
		"""))
		size_info = result.fetchone()
		health_status["checks"]["database_size"] = {
			"size_mb": float(size_info[1]) if size_info else 0
		}
	except Exception as e:
		health_status["checks"]["database_size"] = {
			"error": str(e)
		}
	
	# 4. Check Active Connections
	try:
		result = db.execute(text("""
			SELECT 
				COUNT(*) as active_connections,
				SUM(CASE WHEN state != 'idle' THEN 1 ELSE 0 END) as running_queries
			FROM pg_stat_activity
			WHERE datname = current_database()
		"""))
		conn_info = result.fetchone()
		health_status["checks"]["active_connections"] = {
			"total": conn_info[0] if conn_info else 0,
			"running_queries": conn_info[1] if conn_info else 0
		}
	except Exception as e:
		health_status["checks"]["active_connections"] = {
			"error": str(e)
		}
	
	# 5. Check Slow Queries Count
	try:
		result = db.execute(text("""
			SELECT COUNT(*) 
			FROM pg_stat_activity 
			WHERE datname = current_database()
			AND state != 'idle'
			AND now() - query_start > interval '5 seconds'
		"""))
		slow_queries = result.scalar()
		health_status["checks"]["slow_queries"] = {
			"count": slow_queries or 0
		}
		if slow_queries and slow_queries > 10:
			health_status["status"] = "degraded"
	except Exception:
		pass  # ممکن است دسترسی نداشته باشیم
	
	status_code = 200 if health_status["status"] == "healthy" else 503
	return JSONResponse(status_code=status_code, content=health_status)
