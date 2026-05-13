"""محدودیت نرخ درخواست پل ووکامرس به‌ازای هر کسب‌وکار (حافظهٔ فرآیند)."""

from __future__ import annotations

import os
import threading
import time
from collections import defaultdict, deque
from typing import Deque, Dict, Tuple

from app.core.responses import ApiError
from app.core.woocommerce_dev_flags import woocommerce_bridge_rate_limit_enabled

_lock = threading.Lock()
_windows: Dict[Tuple[int, str], Deque[float]] = defaultdict(deque)

_WINDOW_SEC = 60.0


def _max_requests_per_window() -> int:
	try:
		return max(10, int(os.getenv("WOOCOMMERCE_BRIDGE_MAX_RPM", "120")))
	except ValueError:
		return 120


def enforce_woocommerce_bridge_rate_limit(business_id: int, bucket: str = "default") -> None:
	"""حداکثر N درخواست در هر ۶۰ ثانیه برای هر (business_id, bucket)."""
	if not woocommerce_bridge_rate_limit_enabled():
		return
	bid = int(business_id)
	key = (bid, (bucket or "default")[:64])
	now = time.monotonic()
	cutoff = now - _WINDOW_SEC
	max_n = _max_requests_per_window()
	with _lock:
		q = _windows[key]
		while q and q[0] < cutoff:
			q.popleft()
		if len(q) >= max_n:
			raise ApiError(
				"WOOCOMMERCE_BRIDGE_RATE_LIMIT",
				"تعداد درخواست‌های پل ووکامرس بیش از حد مجاز است؛ لطفاً کمی بعد دوباره تلاش کنید.",
				http_status=429,
			)
		q.append(now)
