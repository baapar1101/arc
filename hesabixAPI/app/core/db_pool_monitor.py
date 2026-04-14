"""
Connection Pool Monitoring
برای مانیتورینگ وضعیت Connection Pool و آمار آن
"""

from __future__ import annotations

import logging
from typing import Dict, Optional
from datetime import datetime

from adapters.db.session import engine

logger = logging.getLogger(__name__)


class ConnectionPoolMonitor:
	"""Monitor برای Connection Pool"""
	
	@staticmethod
	def get_pool_stats() -> Dict[str, any]:
		"""
		دریافت آمار Connection Pool
		
		Returns:
			Dict شامل آمار Pool
		"""
		pool = engine.pool
		total_capacity = pool.size() + pool.overflow()
		checked_out = pool.checkedout()
		available = pool.size() - checked_out
		overflow_used = pool.overflow()
		
		usage_percent = (checked_out / total_capacity * 100) if total_capacity > 0 else 0
		
		return {
			"pool_size": pool.size(),
			"max_overflow": pool.overflow(),  # این max_overflow است، نه overflow فعلی
			"checked_out": checked_out,
			"available": available,
			"overflow_used": overflow_used,
			"total_capacity": total_capacity,
			"usage_percent": round(usage_percent, 2),
			"status": ConnectionPoolMonitor._get_status(usage_percent),
		}
	
	@staticmethod
	def _get_status(usage_percent: float) -> str:
		"""تعیین وضعیت Pool بر اساس درصد استفاده"""
		if usage_percent >= 90:
			return "critical"
		elif usage_percent >= 75:
			return "warning"
		elif usage_percent >= 50:
			return "moderate"
		else:
			return "healthy"
	
	@staticmethod
	def log_pool_stats(level: str = "info"):
		"""
		Log آمار Connection Pool
		
		Args:
			level: سطح Logging (info, warning, error)
		"""
		stats = ConnectionPoolMonitor.get_pool_stats()
		
		log_message = (
			f"Connection Pool Stats - "
			f"Status: {stats['status']}, "
			f"Usage: {stats['usage_percent']:.1f}%, "
			f"Checked out: {stats['checked_out']}/{stats['total_capacity']}, "
			f"Available: {stats['available']}, "
			f"Overflow: {stats['overflow_used']}"
		)
		
		if level.lower() == "warning":
			logger.warning(log_message)
		elif level.lower() == "error":
			logger.error(log_message)
		else:
			logger.info(log_message)
		
		# Alert در صورت Full Pool
		if stats["usage_percent"] >= 90:
			logger.error(
				f"🚨 CRITICAL: Connection Pool nearly exhausted! "
				f"Usage: {stats['usage_percent']:.1f}%, "
				f"Available: {stats['available']}"
			)
	
	@staticmethod
	def get_pool_health() -> Dict[str, any]:
		"""
		دریافت وضعیت سلامت Connection Pool
		
		Returns:
			Dict شامل وضعیت سلامت Pool
		"""
		stats = ConnectionPoolMonitor.get_pool_stats()
		
		health = {
			"healthy": stats["status"] in ["healthy", "moderate"],
			"status": stats["status"],
			"stats": stats,
			"timestamp": datetime.utcnow().isoformat(),
			"recommendations": ConnectionPoolMonitor._get_recommendations(stats),
		}
		
		return health
	
	@staticmethod
	def _get_recommendations(stats: Dict) -> list[str]:
		"""دریافت توصیه‌های بهینه‌سازی بر اساس آمار"""
		recommendations = []
		
		if stats["usage_percent"] >= 90:
			recommendations.append(
				"⚠️ Connection pool usage is critical. Consider increasing pool_size or max_overflow."
			)
			recommendations.append(
				"🔍 Check for connection leaks or long-running queries."
			)
		elif stats["usage_percent"] >= 75:
			recommendations.append(
				"⚠️ Connection pool usage is high. Monitor closely."
			)
		
		if stats["overflow_used"] > 0:
			recommendations.append(
				f"ℹ️ {stats['overflow_used']} connections are using overflow pool. "
				"Consider increasing base pool_size if this is frequent."
			)
		
		return recommendations

