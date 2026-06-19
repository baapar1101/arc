"""محدودیت اتصال خروجی به آدرس‌های داخلی/خصوصی (SSRF mitigation)."""

from __future__ import annotations

import ipaddress
import socket
from typing import Iterable

from app.core.responses import ApiError


def _blocked_ip_addresses() -> Iterable[ipaddress._BaseAddress]:
	yield ipaddress.ip_address("0.0.0.0")
	yield ipaddress.ip_address("::")


def _is_blocked_ip(addr: ipaddress._BaseAddress) -> bool:
	if addr in _blocked_ip_addresses():
		return True
	if addr.is_private or addr.is_loopback or addr.is_link_local:
		return True
	if addr.is_reserved or addr.is_multicast:
		return True
	# CGNAT / shared address space
	if isinstance(addr, ipaddress.IPv4Address) and addr in ipaddress.ip_network("100.64.0.0/10"):
		return True
	return False


def assert_public_egress_host(host: str, *, purpose: str = "connection") -> None:
	"""
	رد اتصال به hostnameهایی که به IPهای داخلی resolve می‌شوند.
	"""
	raw = (host or "").strip()
	if not raw:
		raise ApiError("INVALID_HOST", "آدرس میزبان نامعتبر است", http_status=400)

	# حذف براکت IPv6
	if raw.startswith("[") and raw.endswith("]"):
		candidate = raw[1:-1]
	else:
		candidate = raw.split("%", 1)[0]

	try:
		parsed = ipaddress.ip_address(candidate)
		if _is_blocked_ip(parsed):
			raise ApiError(
				"EGRESS_BLOCKED",
				f"اتصال {purpose} به آدرس‌های داخلی مجاز نیست",
				http_status=400,
			)
		return
	except ValueError:
		pass

	try:
		results = socket.getaddrinfo(raw, None, type=socket.SOCK_STREAM)
	except socket.gaierror as exc:
		raise ApiError("INVALID_HOST", "نام میزبان قابل resolve نیست", http_status=400) from exc

	if not results:
		raise ApiError("INVALID_HOST", "نام میزبان قابل resolve نیست", http_status=400)

	for item in results:
		ip_str = item[4][0]
		try:
			addr = ipaddress.ip_address(ip_str)
		except ValueError:
			continue
		if _is_blocked_ip(addr):
			raise ApiError(
				"EGRESS_BLOCKED",
				f"اتصال {purpose} به آدرس‌های داخلی مجاز نیست",
				http_status=400,
			)
