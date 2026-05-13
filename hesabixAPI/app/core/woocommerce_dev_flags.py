"""پرچم‌های محیط برای یکپارچه‌سازی ووکامرس (توسعه در برابر پروداکشن).

| متغیر | معنی |
|--------|------|
| ``WOOCOMMERCE_DEV_MODE=1`` | حالت توسعه: SSRF سخت، rate limit پل و رمزنگاری توکن پیش‌فرض خاموش. |
| ``WOOCOMMERCE_DEV_ENABLE_SSRF=1`` | با dev mode: بررسی کامل SSRF (DNS + IP). |
| ``WOOCOMMERCE_DEV_ENABLE_RATE_LIMIT=1`` | با dev mode: rate limit پل روشن. |
| ``WOOCOMMERCE_DEV_ENABLE_TOKEN_ENCRYPT=1`` | با dev mode: ذخیرهٔ رمزشدهٔ توکن روشن. |
| ``WOOCOMMERCE_DEV_DISABLE_TLS_VERIFY=1`` | با dev mode: httpx بدون verify گواهی SSL. |
| ``WOOCOMMERCE_DISABLE_SSRF_CHECK=1`` | بدون dev mode: فقط scheme/netloc (بدون DNS). |
| ``WOOCOMMERCE_DISABLE_BRIDGE_RATE_LIMIT=1`` | بدون dev mode: بدون rate limit پل. |
| ``WOOCOMMERCE_DISABLE_TOKEN_ENCRYPT=1`` | بدون dev mode: توکن متن ساده (توصیه نمی‌شود). |
| ``WOOCOMMERCE_BRIDGE_VERIFY_SSL=0`` | غیرفعال کردن verify TLS (اضطراری؛ ریسک امنیتی). |
"""

from __future__ import annotations

import os


def _truthy(name: str) -> bool:
	return os.getenv(name, "").strip().lower() in ("1", "true", "yes", "on")


def woocommerce_dev_mode() -> bool:
	return _truthy("WOOCOMMERCE_DEV_MODE")


def woocommerce_ssrf_validation_enabled() -> bool:
	"""اگر False باشد فقط scheme/netloc پایه چک می‌شود (بدون resolve DNS و بدون بلاک IP)."""
	if woocommerce_dev_mode():
		return _truthy("WOOCOMMERCE_DEV_ENABLE_SSRF")
	return not _truthy("WOOCOMMERCE_DISABLE_SSRF_CHECK")


def woocommerce_bridge_rate_limit_enabled() -> bool:
	if woocommerce_dev_mode():
		return _truthy("WOOCOMMERCE_DEV_ENABLE_RATE_LIMIT")
	return not _truthy("WOOCOMMERCE_DISABLE_BRIDGE_RATE_LIMIT")


def woocommerce_bridge_token_encrypt_enabled() -> bool:
	if woocommerce_dev_mode():
		return _truthy("WOOCOMMERCE_DEV_ENABLE_TOKEN_ENCRYPT")
	return not _truthy("WOOCOMMERCE_DISABLE_TOKEN_ENCRYPT")


def woocommerce_bridge_tls_verify_enabled() -> bool:
	"""پیش‌فرض True؛ با dev+WOOCOMMERCE_DEV_DISABLE_TLS_VERIFY یا BRIDGE_VERIFY_SSL=0 خاموش."""
	if os.getenv("WOOCOMMERCE_BRIDGE_VERIFY_SSL", "1").strip().lower() in ("0", "false", "no"):
		return False
	if woocommerce_dev_mode() and _truthy("WOOCOMMERCE_DEV_DISABLE_TLS_VERIFY"):
		return False
	return True
