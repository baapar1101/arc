"""اعتبارسنجی آدرس فروشگاه برای کاهش ریسک SSRF هنگام پروکسی به پل ووکامرس."""

from __future__ import annotations

import ipaddress
import os
import re
import socket
from urllib.parse import urlparse

from app.core.responses import ApiError
from app.core.woocommerce_dev_flags import woocommerce_ssrf_validation_enabled

_BLOCKED_HOSTNAMES = frozenset(
	{
		"localhost",
		"metadata.google.internal",
		"metadata",
	}
)


def _allow_http_store_url() -> bool:
	return os.getenv("WOOCOMMERCE_ALLOW_HTTP_STORE_URL", "").strip().lower() in ("1", "true", "yes")


def _is_blocked_literal_ip(ip: object) -> bool:
	if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast:
		return True
	if isinstance(ip, ipaddress.IPv4Address):
		if ip == ipaddress.IPv4Address("169.254.169.254"):
			return True
	return False


def _check_resolved_ips(hostname: str) -> None:
	"""اگر هر آدرس حل‌شده خصوصی/لوپ‌بک باشد، رد می‌کند."""
	try:
		infos = socket.getaddrinfo(hostname, None, type=socket.SOCK_STREAM, proto=socket.IPPROTO_TCP)
	except socket.gaierror as exc:
		raise ApiError(
			"WOOCOMMERCE_BRIDGE_HOST_UNRESOLVED",
			f"نام میزبان فروشگاه قابل حل نیست: {exc!s}",
			http_status=400,
		) from exc
	for info in infos:
		sockaddr = info[4]
		addr = sockaddr[0]
		try:
			ip = ipaddress.ip_address(addr)
		except ValueError:
			continue
		if _is_blocked_literal_ip(ip):
			raise ApiError(
				"WOOCOMMERCE_BRIDGE_HOST_FORBIDDEN",
				"آدرس حل‌شدهٔ فروشگاه در محدودهٔ شبکهٔ داخلی یا غیرمجاز است.",
				http_status=400,
			)


def validate_woocommerce_store_base_url(raw_url: str) -> str:
	"""
	بررسی scheme، hostname و (در صورت امکان) رکوردهای DNS برای جلوگیری از SSRF.
	"""
	u = (raw_url or "").strip().rstrip("/")
	if not u.startswith(("http://", "https://")):
		raise ApiError(
			"INVALID_STORE_URL",
			"آدرس فروشگاه باید با https:// یا http:// شروع شود.",
			http_status=400,
		)
	allow_http = _allow_http_store_url()
	if u.startswith("http://") and not allow_http:
		raise ApiError(
			"INVALID_STORE_URL",
			"فقط آدرس‌های https:// برای فروشگاه پذیرفته می‌شوند (برای محیط توسعه WOOCOMMERCE_ALLOW_HTTP_STORE_URL=1).",
			http_status=400,
		)

	parsed = urlparse(u)
	host = (parsed.hostname or "").strip().lower()
	if not host:
		raise ApiError("INVALID_STORE_URL", "نام میزبان فروشگاه نامعتبر است.", http_status=400)
	if woocommerce_ssrf_validation_enabled() and host in _BLOCKED_HOSTNAMES:
		raise ApiError("INVALID_STORE_URL", "نام میزبان فروشگاه نامعتبر است.", http_status=400)

	if re.search(r"[\s\x00-\x1f]", host):
		raise ApiError("INVALID_STORE_URL", "نام میزبان فروشگاه نامعتبر است.", http_status=400)

	if not woocommerce_ssrf_validation_enabled():
		return u

	try:
		ip = ipaddress.ip_address(host)
		if _is_blocked_literal_ip(ip):
			raise ApiError(
				"WOOCOMMERCE_BRIDGE_HOST_FORBIDDEN",
				"آدرس IP فروشگاه در محدودهٔ غیرمجاز است.",
				http_status=400,
			)
		_check_resolved_ips(host)
		return u
	except ValueError:
		pass

	_check_resolved_ips(host)
	return u
