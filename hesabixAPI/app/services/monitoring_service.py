from __future__ import annotations

import psutil
import logging
from typing import Dict, Any, List, Optional
from datetime import datetime, timedelta
from decimal import Decimal
from sqlalchemy.orm import Session
from sqlalchemy import and_, desc, text

from adapters.db.models.monitoring import MonitoringMetric, MonitoringServiceStatus, MonitoringAlert
from app.core.cache import get_cache
from app.core.settings import get_settings

logger = logging.getLogger(__name__)


class HardwareMonitoringService:
	"""سرویس مانیتورینگ منابع سخت‌افزاری"""
	
	def __init__(self, db: Session):
		self.db = db
		self.cache = get_cache()
	
	def get_current_metrics(self) -> Dict[str, Any]:
		"""دریافت metrics فعلی سخت‌افزار"""
		try:
			# CPU
			cpu_percent = psutil.cpu_percent(interval=1)
			cpu_count = psutil.cpu_count(logical=True)
			cpu_count_physical = psutil.cpu_count(logical=False)
			load_avg = psutil.getloadavg() if hasattr(psutil, 'getloadavg') else None
			
			# Memory
			memory = psutil.virtual_memory()
			swap = psutil.swap_memory()
			
			# Disk
			disk_usage = psutil.disk_usage('/')
			disk_io = psutil.disk_io_counters()
			
			# Network
			network_io = psutil.net_io_counters()
			network_interfaces = psutil.net_if_addrs()
			
			return {
				"cpu": {
					"percent": cpu_percent,
					"count": cpu_count,
					"count_physical": cpu_count_physical,
					"load_avg": {
						"1min": load_avg[0] if load_avg else None,
						"5min": load_avg[1] if load_avg and len(load_avg) > 1 else None,
						"15min": load_avg[2] if load_avg and len(load_avg) > 2 else None,
					} if load_avg else None,
				},
				"memory": {
					"total": memory.total,
					"available": memory.available,
					"used": memory.used,
					"percent": memory.percent,
					"free": memory.free,
				},
				"swap": {
					"total": swap.total,
					"used": swap.used,
					"free": swap.free,
					"percent": swap.percent,
				},
				"disk": {
					"total": disk_usage.total,
					"used": disk_usage.used,
					"free": disk_usage.free,
					"percent": (disk_usage.used / disk_usage.total) * 100 if disk_usage.total > 0 else 0,
					"io": {
						"read_bytes": disk_io.read_bytes if disk_io else 0,
						"write_bytes": disk_io.write_bytes if disk_io else 0,
						"read_count": disk_io.read_count if disk_io else 0,
						"write_count": disk_io.write_count if disk_io else 0,
					} if disk_io else None,
				},
				"network": {
					"bytes_sent": network_io.bytes_sent if network_io else 0,
					"bytes_recv": network_io.bytes_recv if network_io else 0,
					"packets_sent": network_io.packets_sent if network_io else 0,
					"packets_recv": network_io.packets_recv if network_io else 0,
					"interfaces": len(network_interfaces),
				},
				"timestamp": datetime.utcnow().isoformat(),
			}
		except Exception as e:
			logger.error(f"Error collecting hardware metrics: {e}")
			raise
	
	def collect_and_store_metrics(self):
		"""جمع‌آوری و ذخیره metrics در cache و database"""
		try:
			metrics = self.get_current_metrics()
			timestamp = datetime.utcnow()
			
			# ذخیره در cache برای دسترسی سریع
			if self.cache.enabled:
				self.cache.set("monitoring:hardware:current", metrics, ttl=30)
			
			# ذخیره در database
			metric_records = []
			
			# CPU
			if "cpu" in metrics:
				cpu = metrics["cpu"]
				metric_records.append(MonitoringMetric(
					metric_type="cpu",
					metric_name="cpu_percent",
					value=Decimal(str(cpu["percent"])),
					unit="percent",
					timestamp=timestamp,
				))
			
			# Memory
			if "memory" in metrics:
				mem = metrics["memory"]
				metric_records.append(MonitoringMetric(
					metric_type="memory",
					metric_name="memory_percent",
					value=Decimal(str(mem["percent"])),
					unit="percent",
					timestamp=timestamp,
				))
				metric_records.append(MonitoringMetric(
					metric_type="memory",
					metric_name="memory_used",
					value=Decimal(str(mem["used"])),
					unit="bytes",
					timestamp=timestamp,
				))
			
			# Disk
			if "disk" in metrics:
				disk = metrics["disk"]
				metric_records.append(MonitoringMetric(
					metric_type="disk",
					metric_name="disk_percent",
					value=Decimal(str(disk["percent"])),
					unit="percent",
					timestamp=timestamp,
				))
				metric_records.append(MonitoringMetric(
					metric_type="disk",
					metric_name="disk_used",
					value=Decimal(str(disk["used"])),
					unit="bytes",
					timestamp=timestamp,
				))
			
			# Network
			if "network" in metrics:
				net = metrics["network"]
				metric_records.append(MonitoringMetric(
					metric_type="network",
					metric_name="network_bytes_sent",
					value=Decimal(str(net["bytes_sent"])),
					unit="bytes",
					timestamp=timestamp,
				))
				metric_records.append(MonitoringMetric(
					metric_type="network",
					metric_name="network_bytes_recv",
					value=Decimal(str(net["bytes_recv"])),
					unit="bytes",
					timestamp=timestamp,
				))
			
			# Batch insert
			if metric_records:
				self.db.bulk_save_objects(metric_records)
				self.db.commit()
			
			return metrics
		except Exception as e:
			logger.error(f"Error storing hardware metrics: {e}")
			self.db.rollback()
			raise
	
	def get_historical_metrics(
		self,
		metric_type: str,
		metric_name: Optional[str] = None,
		start_time: Optional[datetime] = None,
		end_time: Optional[datetime] = None,
		interval_minutes: int = 1,
	) -> List[Dict[str, Any]]:
		"""دریافت تاریخچه metrics"""
		try:
			# Default: آخرین 1 ساعت
			if not end_time:
				end_time = datetime.utcnow()
			if not start_time:
				start_time = end_time - timedelta(hours=1)
			
			query = self.db.query(MonitoringMetric).filter(
				and_(
					MonitoringMetric.metric_type == metric_type,
					MonitoringMetric.timestamp >= start_time,
					MonitoringMetric.timestamp <= end_time,
				)
			)
			
			if metric_name:
				query = query.filter(MonitoringMetric.metric_name == metric_name)
			
			# Order by timestamp
			query = query.order_by(MonitoringMetric.timestamp)
			
			results = query.all()
			
			# Convert to dict
			return [
				{
					"metric_type": r.metric_type,
					"metric_name": r.metric_name,
					"value": float(r.value),
					"unit": r.unit,
					"timestamp": r.timestamp.isoformat(),
				}
				for r in results
			]
		except Exception as e:
			logger.error(f"Error getting historical metrics: {e}")
			raise


class ServiceMonitoringService:
	"""سرویس مانیتورینگ وضعیت سرویس‌ها"""
	
	def __init__(self, db: Session):
		self.db = db
		self.cache = get_cache()
		self.settings = get_settings()
	
	def check_all_services(self) -> Dict[str, Any]:
		"""بررسی وضعیت همه سرویس‌ها"""
		services = {}
		
		# API Server
		services["api_server"] = self.check_api_server()
		
		# Database
		services["database"] = self.check_database()
		
		# Redis
		services["redis"] = self.check_redis()
		
		# Background Workers (RQ)
		services["workers"] = self.check_workers()
		
		# Notification Moderation Worker
		services["notification_moderation"] = self.check_notification_moderation_worker()
		
		return services
	
	def check_api_server(self) -> Dict[str, Any]:
		"""بررسی وضعیت API Server"""
		try:
			uptime_seconds = None
			try:
				# سعی در محاسبه uptime از طریق boot time
				boot_time = datetime.fromtimestamp(psutil.boot_time())
				uptime_seconds = int((datetime.now() - boot_time).total_seconds())
			except:
				pass
			
			return {
				"status": "online",
				"uptime_seconds": uptime_seconds,
				"version": self.settings.app_version,
				"last_check": datetime.utcnow().isoformat(),
			}
		except Exception as e:
			logger.error(f"Error checking API server: {e}")
			return {
				"status": "unknown",
				"error": str(e),
				"last_check": datetime.utcnow().isoformat(),
			}
	
	def check_database(self) -> Dict[str, Any]:
		"""بررسی وضعیت Database"""
		try:
			# تست اتصال دیتابیس
			self.db.execute(text("SELECT 1"))
			
			# محاسبه حجم دیتابیس (PostgreSQL)
			db_size = None
			try:
				result = self.db.execute(
					text(
						"SELECT ROUND(pg_database_size(current_database()) / 1024.0 / 1024.0, 1) AS db_size_mb"
					)
				).fetchone()
				if result:
					db_size = float(result[0]) if result[0] else None
			except:
				pass
			
			return {
				"status": "online",
				"database_size_mb": db_size,
				"last_check": datetime.utcnow().isoformat(),
			}
		except Exception as e:
			logger.error(f"Error checking database: {e}")
			return {
				"status": "offline",
				"error": str(e),
				"last_check": datetime.utcnow().isoformat(),
			}
	
	def check_redis(self) -> Dict[str, Any]:
		"""بررسی وضعیت Redis"""
		try:
			if not self.cache.enabled:
				return {
					"status": "disabled",
					"last_check": datetime.utcnow().isoformat(),
				}
			
			# تست ping
			self.cache.client.ping()
			
			# اطلاعات اضافی
			info = self.cache.client.info()
			
			return {
				"status": "online",
				"memory_used_mb": info.get("used_memory", 0) / (1024 * 1024) if info.get("used_memory") else None,
				"keys": info.get("db0", {}).get("keys", 0) if "db0" in info else 0,
				"connected_clients": info.get("connected_clients", 0),
				"last_check": datetime.utcnow().isoformat(),
			}
		except Exception as e:
			logger.error(f"Error checking Redis: {e}")
			return {
				"status": "offline",
				"error": str(e),
				"last_check": datetime.utcnow().isoformat(),
			}
	
	def check_workers(self) -> Dict[str, Any]:
		"""بررسی وضعیت Background Workers"""
		try:
			# بررسی RQ workers
			from rq import Queue, Worker
			from redis import Redis
			
			if not self.cache.enabled:
				return {
					"status": "disabled",
					"last_check": datetime.utcnow().isoformat(),
				}
			
			redis_conn = self.cache.client
			
			# در RQ 2.x، Worker.all() از پارامتر connection استفاده می‌کند (نه redis)
			try:
				workers = Worker.all(connection=redis_conn)
			except Exception:
				# اگر روش بالا کار نکرد، سعی می‌کنیم از queue استفاده کنیم
				try:
					default_queue = Queue('default', connection=redis_conn)
					workers = Worker.all(queue=default_queue)
				except Exception:
					workers = []
			
			# تعداد queue ها
			queues = []
			queue_names = ['default', 'high', 'low']
			for queue_name in queue_names:
				try:
					queue = Queue(queue_name, connection=redis_conn)
					queues.append({
						"name": queue_name,
						"length": len(queue),
					})
				except Exception:
					pass
			
			return {
				"status": "online" if len(workers) > 0 else "offline",
				"worker_count": len(workers),
				"queues": queues,
				"last_check": datetime.utcnow().isoformat(),
			}
		except Exception as e:
			logger.error(f"Error checking workers: {e}")
			return {
				"status": "unknown",
				"error": str(e),
				"last_check": datetime.utcnow().isoformat(),
			}
	
	def check_notification_moderation_worker(self) -> Dict[str, Any]:
		"""بررسی وضعیت Notification Moderation Worker"""
		try:
			import subprocess
			
			service_name = "hesabix-notification-moderation"
			
			# بررسی فعال بودن سرویس
			is_active_cmd = ["systemctl", "is-active", service_name]
			is_active_result = subprocess.run(
				is_active_cmd,
				capture_output=True,
				text=True,
				timeout=5,
				check=False
			)
			
			is_active = is_active_result.stdout.strip() == "active"
			
			# دریافت آمار از دیتابیس
			from adapters.db.models.business_notification import NotificationModerationQueue
			from sqlalchemy import func, and_
			
			# تعداد در صف
			pending_count = self.db.query(func.count(NotificationModerationQueue.id)).filter(
				NotificationModerationQueue.status.in_(['pending', 'ai_reviewing'])
			).scalar() or 0
			
			# تعداد بررسی شده امروز
			today = datetime.utcnow().date()
			reviewed_today = self.db.query(func.count(NotificationModerationQueue.id)).filter(
				and_(
					NotificationModerationQueue.status == 'completed',
					func.date(NotificationModerationQueue.completed_at) == today
				)
			).scalar() or 0
			
			# آخرین فعالیت
			last_review = self.db.query(NotificationModerationQueue).filter(
				NotificationModerationQueue.ai_reviewed_at.isnot(None)
			).order_by(NotificationModerationQueue.ai_reviewed_at.desc()).first()
			
			last_activity = None
			if last_review and last_review.ai_reviewed_at:
				last_activity = last_review.ai_reviewed_at.isoformat()
			
			return {
				"status": "online" if is_active else "offline",
				"is_active": is_active,
				"queue": {
					"pending": pending_count,
					"reviewed_today": reviewed_today
				},
				"last_activity": last_activity,
				"service_name": service_name,
				"last_check": datetime.utcnow().isoformat(),
			}
		except Exception as e:
			logger.error(f"Error checking notification moderation worker: {e}")
			return {
				"status": "unknown",
				"error": str(e),
				"last_check": datetime.utcnow().isoformat(),
			}
	
	def store_service_status(self, service_name: str, status_data: Dict[str, Any]):
		"""ذخیره وضعیت سرویس در دیتابیس"""
		try:
			status_record = MonitoringServiceStatus(
				service_name=service_name,
				status=status_data.get("status", "unknown"),
				uptime_seconds=status_data.get("uptime_seconds"),
				version=status_data.get("version"),
				extra_data=status_data,
				last_check=datetime.utcnow(),
			)
			self.db.add(status_record)
			self.db.commit()
		except Exception as e:
			logger.error(f"Error storing service status: {e}")
			self.db.rollback()
			raise

