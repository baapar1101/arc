from __future__ import annotations

import logging
from typing import Dict, Any, List, Optional
from datetime import datetime, timedelta
from decimal import Decimal
from sqlalchemy.orm import Session
from sqlalchemy import and_, desc

from adapters.db.models.monitoring import MonitoringAlert
from app.services.monitoring_realtime import monitoring_realtime_manager

logger = logging.getLogger(__name__)


class AlertService:
	"""سرویس مدیریت هشدارها"""
	
	def __init__(self, db: Session):
		self.db = db
		
		# آستانه‌های پیش‌فرض
		self.thresholds = {
			"cpu": {"warning": 70.0, "critical": 90.0},
			"memory": {"warning": 70.0, "critical": 85.0},
			"disk": {"warning": 80.0, "critical": 90.0},
			"disk_free_gb": {"warning": 10.0, "critical": 5.0},  # GB
			"response_time_ms": {"warning": 1000.0, "critical": 2000.0},
			"error_rate": {"warning": 1.0, "critical": 5.0},  # درصد
		}
	
	def check_hardware_metrics(self, metrics: Dict[str, Any]) -> List[Dict[str, Any]]:
		"""بررسی metrics سخت‌افزاری و ایجاد هشدار در صورت نیاز"""
		alerts = []
		
		# بررسی CPU
		if "cpu" in metrics:
			cpu = metrics["cpu"]
			cpu_percent = cpu.get("percent", 0)
			if cpu_percent >= self.thresholds["cpu"]["critical"]:
				alerts.append(self._create_alert(
					alert_type="hardware_cpu",
					severity="critical",
					title="استفاده بالای CPU",
					message=f"استفاده CPU به {cpu_percent:.1f}% رسیده است (آستانه: {self.thresholds['cpu']['critical']}%)",
					metric_name="cpu_percent",
					threshold_value=Decimal(str(self.thresholds["cpu"]["critical"])),
					current_value=Decimal(str(cpu_percent)),
				))
			elif cpu_percent >= self.thresholds["cpu"]["warning"]:
				alerts.append(self._create_alert(
					alert_type="hardware_cpu",
					severity="warning",
					title="استفاده بالای CPU",
					message=f"استفاده CPU به {cpu_percent:.1f}% رسیده است (آستانه: {self.thresholds['cpu']['warning']}%)",
					metric_name="cpu_percent",
					threshold_value=Decimal(str(self.thresholds["cpu"]["warning"])),
					current_value=Decimal(str(cpu_percent)),
				))
		
		# بررسی Memory
		if "memory" in metrics:
			memory = metrics["memory"]
			memory_percent = memory.get("percent", 0)
			if memory_percent >= self.thresholds["memory"]["critical"]:
				alerts.append(self._create_alert(
					alert_type="hardware_memory",
					severity="critical",
					title="استفاده بالای حافظه",
					message=f"استفاده حافظه به {memory_percent:.1f}% رسیده است (آستانه: {self.thresholds['memory']['critical']}%)",
					metric_name="memory_percent",
					threshold_value=Decimal(str(self.thresholds["memory"]["critical"])),
					current_value=Decimal(str(memory_percent)),
				))
			elif memory_percent >= self.thresholds["memory"]["warning"]:
				alerts.append(self._create_alert(
					alert_type="hardware_memory",
					severity="warning",
					title="استفاده بالای حافظه",
					message=f"استفاده حافظه به {memory_percent:.1f}% رسیده است (آستانه: {self.thresholds['memory']['warning']}%)",
					metric_name="memory_percent",
					threshold_value=Decimal(str(self.thresholds["memory"]["warning"])),
					current_value=Decimal(str(memory_percent)),
				))
		
		# بررسی Disk
		if "disk" in metrics:
			disk = metrics["disk"]
			disk_percent = disk.get("percent", 0)
			disk_free_gb = (disk.get("free", 0) / (1024 ** 3)) if disk.get("free") else 0
			
			if disk_percent >= self.thresholds["disk"]["critical"]:
				alerts.append(self._create_alert(
					alert_type="hardware_disk",
					severity="critical",
					title="فضای دیسک پر شده",
					message=f"فضای دیسک به {disk_percent:.1f}% استفاده رسیده است (آستانه: {self.thresholds['disk']['critical']}%)",
					metric_name="disk_percent",
					threshold_value=Decimal(str(self.thresholds["disk"]["critical"])),
					current_value=Decimal(str(disk_percent)),
				))
			elif disk_percent >= self.thresholds["disk"]["warning"]:
				alerts.append(self._create_alert(
					alert_type="hardware_disk",
					severity="warning",
					title="فضای دیسک در حال پر شدن",
					message=f"فضای دیسک به {disk_percent:.1f}% استفاده رسیده است (آستانه: {self.thresholds['disk']['warning']}%)",
					metric_name="disk_percent",
					threshold_value=Decimal(str(self.thresholds["disk"]["warning"])),
					current_value=Decimal(str(disk_percent)),
				))
			
			# بررسی فضای خالی
			if disk_free_gb > 0 and disk_free_gb <= self.thresholds["disk_free_gb"]["critical"]:
				alerts.append(self._create_alert(
					alert_type="hardware_disk_free",
					severity="critical",
					title="فضای خالی دیسک کم است",
					message=f"فقط {disk_free_gb:.1f} GB فضای خالی باقی مانده است (آستانه: {self.thresholds['disk_free_gb']['critical']} GB)",
					metric_name="disk_free_gb",
					threshold_value=Decimal(str(self.thresholds["disk_free_gb"]["critical"])),
					current_value=Decimal(str(disk_free_gb)),
				))
		
		return alerts
	
	def check_service_status(self, services: Dict[str, Any]) -> List[Dict[str, Any]]:
		"""بررسی وضعیت سرویس‌ها و ایجاد هشدار در صورت نیاز"""
		alerts = []
		
		for service_name, status_data in services.items():
			status = status_data.get("status", "unknown")
			
			if status == "offline":
				alerts.append(self._create_alert(
					alert_type=f"service_{service_name}",
					severity="critical",
					title=f"سرویس {service_name} قطع شده",
					message=f"سرویس {service_name} در حال حاضر در دسترس نیست",
					metric_name=f"service_{service_name}_status",
					current_value=None,
				))
			elif status == "degraded":
				alerts.append(self._create_alert(
					alert_type=f"service_{service_name}",
					severity="warning",
					title=f"سرویس {service_name} کاهش عملکرد",
					message=f"سرویس {service_name} در حال کاهش عملکرد است",
					metric_name=f"service_{service_name}_status",
					current_value=None,
				))
		
		return alerts
	
	def _create_alert(
		self,
		alert_type: str,
		severity: str,
		title: str,
		message: str,
		metric_name: Optional[str] = None,
		threshold_value: Optional[Decimal] = None,
		current_value: Optional[Decimal] = None,
	) -> Dict[str, Any]:
		"""ایجاد یک هشدار جدید"""
		return {
			"alert_type": alert_type,
			"severity": severity,
			"title": title,
			"message": message,
			"metric_name": metric_name,
			"threshold_value": threshold_value,
			"current_value": current_value,
		}
	
	def save_alert(self, alert_data: Dict[str, Any], cooldown_minutes: int = 5) -> Optional[MonitoringAlert]:
		"""ذخیره هشدار در دیتابیس (با cooldown)"""
		try:
			# بررسی cooldown - آیا هشدار مشابهی در cooldown period وجود دارد؟
			cooldown_start = datetime.utcnow() - timedelta(minutes=cooldown_minutes)
			existing = self.db.query(MonitoringAlert).filter(
				and_(
					MonitoringAlert.alert_type == alert_data["alert_type"],
					MonitoringAlert.status == "active",
					MonitoringAlert.created_at >= cooldown_start,
				)
			).first()
			
			if existing:
				# هشدار مشابهی در cooldown period وجود دارد
				return None
			
			# ایجاد هشدار جدید
			alert = MonitoringAlert(
				alert_type=alert_data["alert_type"],
				severity=alert_data["severity"],
				title=alert_data["title"],
				message=alert_data.get("message"),
				metric_name=alert_data.get("metric_name"),
				threshold_value=alert_data.get("threshold_value"),
				current_value=alert_data.get("current_value"),
				status="active",
				created_at=datetime.utcnow(),
			)
			
			self.db.add(alert)
			self.db.commit()
			self.db.refresh(alert)
			
			# ارسال به WebSocket clients
			# Note: این باید از یک async context فراخوانی شود
			# برای حال حاضر، این را در background task انجام می‌دهیم
			
			return alert
		except Exception as e:
			logger.error(f"Error saving alert: {e}")
			self.db.rollback()
			return None
	
	def get_active_alerts(self, limit: int = 50) -> List[MonitoringAlert]:
		"""دریافت هشدارهای فعال"""
		return self.db.query(MonitoringAlert).filter(
			MonitoringAlert.status == "active"
		).order_by(desc(MonitoringAlert.created_at)).limit(limit).all()
	
	def acknowledge_alert(self, alert_id: int, user_id: int) -> bool:
		"""تایید یک هشدار"""
		try:
			alert = self.db.query(MonitoringAlert).filter(
				MonitoringAlert.id == alert_id
			).first()
			
			if not alert:
				return False
			
			alert.status = "acknowledged"
			alert.acknowledged_at = datetime.utcnow()
			alert.acknowledged_by = user_id
			
			self.db.commit()
			return True
		except Exception as e:
			logger.error(f"Error acknowledging alert: {e}")
			self.db.rollback()
			return False
	
	def resolve_alert(self, alert_id: int) -> bool:
		"""حل کردن یک هشدار"""
		try:
			alert = self.db.query(MonitoringAlert).filter(
				MonitoringAlert.id == alert_id
			).first()
			
			if not alert:
				return False
			
			alert.status = "resolved"
			alert.resolved_at = datetime.utcnow()
			
			self.db.commit()
			return True
		except Exception as e:
			logger.error(f"Error resolving alert: {e}")
			self.db.rollback()
			return False

