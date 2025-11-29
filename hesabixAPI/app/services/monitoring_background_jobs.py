"""
Background jobs برای سیستم مانیتورینگ
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

from adapters.db.session import get_db_session
from app.services.monitoring_service import (
	HardwareMonitoringService,
	ServiceMonitoringService,
)
from app.services.monitoring_realtime import monitoring_realtime_manager
from app.services.alert_service import AlertService

logger = logging.getLogger(__name__)


async def monitoring_metrics_collection_loop(interval_seconds: int = 10) -> None:
	"""
	Background loop برای جمع‌آوری و ذخیره metrics
	هر interval_seconds ثانیه یکبار اجرا می‌شود (پیش‌فرض: 10 ثانیه)
	"""
	while True:
		try:
			def _collect_and_store_metrics() -> dict:
				"""جمع‌آوری و ذخیره metrics در thread جداگانه"""
				with get_db_session() as db:
					hardware_service = HardwareMonitoringService(db)
					alert_service = AlertService(db)
					try:
						metrics = hardware_service.collect_and_store_metrics()
						
						# بررسی هشدارها
						if metrics:
							alerts = alert_service.check_hardware_metrics(metrics)
							for alert_data in alerts:
								alert_service.save_alert(alert_data, cooldown_minutes=5)
						
						return metrics or {}
					except Exception as e:
						logger.error(f"Error collecting hardware metrics: {e}", exc_info=True)
						return {}
			
			# اجرا در thread جداگانه
			metrics = await asyncio.to_thread(_collect_and_store_metrics)
			
			# ارسال به WebSocket clients (در event loop اصلی)
			if metrics:
				try:
					await monitoring_realtime_manager.broadcast_hardware_metrics(metrics)
				except Exception as e:
					logger.error(f"Error broadcasting metrics: {e}", exc_info=True)
		except Exception as e:
			logger.error(f"Error in monitoring metrics collection loop: {e}", exc_info=True)
		
		await asyncio.sleep(interval_seconds)


async def monitoring_service_status_check_loop(interval_seconds: int = 30) -> None:
	"""
	Background loop برای بررسی وضعیت سرویس‌ها
	هر interval_seconds ثانیه یکبار اجرا می‌شود (پیش‌فرض: 30 ثانیه)
	"""
	while True:
		try:
			def _check_and_store_services() -> dict:
				"""بررسی و ذخیره وضعیت سرویس‌ها در thread جداگانه"""
				with get_db_session() as db:
					service_monitor = ServiceMonitoringService(db)
					alert_service = AlertService(db)
					try:
						services = service_monitor.check_all_services()
						# ذخیره وضعیت هر سرویس
						for service_name, status_data in services.items():
							service_monitor.store_service_status(service_name, status_data)
						
						# بررسی هشدارها
						if services:
							alerts = alert_service.check_service_status(services)
							for alert_data in alerts:
								alert_service.save_alert(alert_data, cooldown_minutes=5)
						
						return services
					except Exception as e:
						logger.error(f"Error checking services status: {e}", exc_info=True)
						return {}
			
			# اجرا در thread جداگانه
			services = await asyncio.to_thread(_check_and_store_services)
			
			# ارسال به WebSocket clients (در event loop اصلی)
			if services:
				try:
					await monitoring_realtime_manager.broadcast_service_status(services)
				except Exception as e:
					logger.error(f"Error broadcasting services: {e}", exc_info=True)
		except Exception as e:
			logger.error(f"Error in service status check loop: {e}", exc_info=True)
		
		await asyncio.sleep(interval_seconds)

