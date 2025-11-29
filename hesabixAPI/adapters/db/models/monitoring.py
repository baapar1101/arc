from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from sqlalchemy import String, Integer, DateTime, Text, Numeric, Boolean, JSON, Index
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class MonitoringMetric(Base):
	"""جدول metrics مانیتورینگ"""
	__tablename__ = "monitoring_metrics"
	
	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	
	# نوع metric (cpu, memory, disk, network, api)
	metric_type: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
	
	# نام metric (cpu_percent, memory_used, disk_usage, etc.)
	metric_name: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
	
	# مقدار metric
	value: Mapped[Decimal] = mapped_column(Numeric(15, 2), nullable=False)
	
	# واحد اندازه‌گیری (percent, bytes, seconds, etc.)
	unit: Mapped[str | None] = mapped_column(String(20), nullable=True)
	
	# زمان ثبت
	timestamp: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
	
	# اطلاعات اضافی (JSON)
	extra_data: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	
	# ایندکس مرکب برای جستجوی سریع
	__table_args__ = (
		Index('ix_monitoring_metrics_type_timestamp', 'metric_type', 'timestamp'),
		Index('ix_monitoring_metrics_name_timestamp', 'metric_name', 'timestamp'),
	)


class MonitoringServiceStatus(Base):
	"""جدول وضعیت سرویس‌ها"""
	__tablename__ = "monitoring_service_status"
	
	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	
	# نام سرویس (api_server, database, redis, worker)
	service_name: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
	
	# وضعیت (online, offline, degraded)
	status: Mapped[str] = mapped_column(String(20), nullable=False)
	
	# مدت زمان فعالیت (ثانیه)
	uptime_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
	
	# نسخه
	version: Mapped[str | None] = mapped_column(String(50), nullable=True)
	
	# اطلاعات اضافی (JSON)
	extra_data: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	
	# زمان آخرین بررسی
	last_check: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
	
	__table_args__ = (
		Index('ix_monitoring_service_name_check', 'service_name', 'last_check'),
	)


class MonitoringAlert(Base):
	"""جدول هشدارها و آلارم‌ها"""
	__tablename__ = "monitoring_alerts"
	
	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	
	# نوع هشدار (hardware_cpu, hardware_memory, service_api, etc.)
	alert_type: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
	
	# سطح اهمیت (info, warning, critical)
	severity: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
	
	# عنوان
	title: Mapped[str] = mapped_column(String(200), nullable=False)
	
	# پیام
	message: Mapped[str | None] = mapped_column(Text, nullable=True)
	
	# نام metric مرتبط
	metric_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
	
	# مقدار آستانه
	threshold_value: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
	
	# مقدار فعلی
	current_value: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
	
	# وضعیت (active, acknowledged, resolved)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default='active', index=True)
	
	# زمان ایجاد
	created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
	
	# زمان تایید
	acknowledged_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	
	# کاربر تایید کننده
	acknowledged_by: Mapped[int | None] = mapped_column(Integer, nullable=True)
	
	# زمان حل شدن
	resolved_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	
	__table_args__ = (
		Index('ix_monitoring_alert_status_created', 'status', 'created_at'),
	)

