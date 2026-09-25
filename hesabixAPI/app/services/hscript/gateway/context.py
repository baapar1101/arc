"""زمینه اجرای Gateway — همیشه از سرور تزریق می‌شود."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional

from sqlalchemy.orm.session import Session

from app.services.hscript.errors import ResourceLimitErrorHS, SecurityErrorHS
from app.services.hscript.limits import ResourceLimits


@dataclass
class GatewayContext:
	"""Context قفل‌شده؛ اسکریپت نمی‌تواند business_id را عوض کند."""

	db: Session
	business_id: int
	user_id: int
	fiscal_year_id: Optional[int] = None
	limits: ResourceLimits = field(default_factory=ResourceLimits.default)
	gateway_calls: int = 0
	params: dict[str, Any] = field(default_factory=dict)
	calendar_type: str = "jalali"

	def bump_call(self) -> None:
		self.gateway_calls += 1
		if self.gateway_calls > self.limits.max_gateway_calls:
			raise ResourceLimitErrorHS("تعداد فراخوانی‌های داده بیش از حد مجاز است")

	def assert_same_business(self, business_id: int) -> None:
		if int(business_id) != int(self.business_id):
			raise SecurityErrorHS("تلاش برای دسترسی به کسب‌وکار دیگر مسدود شد")

	def row_limit(self, requested: Optional[int] = None) -> int:
		cap = self.limits.max_gateway_rows_per_call
		if requested is None:
			return min(100, cap)
		return max(1, min(int(requested), cap))
