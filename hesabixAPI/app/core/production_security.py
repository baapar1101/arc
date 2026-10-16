"""اعتبارسنجی تنظیمات امنیتی هنگام راه‌اندازی در محیط production."""

from __future__ import annotations

from urllib.parse import urlsplit

from app.core.settings import Settings

_INSECURE_SECRET_VALUES = frozenset(
	{
		"",
		"change_me",
		"change_me_captcha",
		"change_me_share_link",
		"default-secret-key-change-me",
	}
)


def _is_production(settings: Settings) -> bool:
	return (settings.environment or "").strip().lower() in {"production", "prod"}


def validate_production_security(settings: Settings) -> None:
	"""در production با تنظیمات ناامن، راه‌اندازی را متوقف می‌کند."""
	if not _is_production(settings):
		return

	errors: list[str] = []

	if settings.debug:
		errors.append("DEBUG must be false in production")

	# API عمومی: CORS_ALLOWED_ORIGINS=["*"] در production مجاز است (allow_credentials=False در main.py).

	for name, value in (
		("CAPTCHA_SECRET", settings.captcha_secret),
		("SHARE_LINK_SECRET", settings.share_link_secret),
		("DB_PASSWORD", settings.db_password),
	):
		if (value or "").strip() in _INSECURE_SECRET_VALUES:
			errors.append(f"{name} must be set to a strong unique value")

	if not (settings.encryption_key or "").strip():
		errors.append("ENCRYPTION_KEY must be set in production")

	if not (settings.wallet_webhook_secret or "").strip():
		errors.append("WALLET_WEBHOOK_SECRET must be set in production")

	if not (settings.mcp_public_base_url or "").strip():
		errors.append("MCP_PUBLIC_BASE_URL must be set in production")
	else:
		try:
			public_mcp = urlsplit(settings.mcp_public_base_url.strip().rstrip("/"))
			valid_public_mcp = (
				public_mcp.scheme == "https"
				and bool(public_mcp.hostname)
				and public_mcp.port != 0
				and not public_mcp.username
				and not public_mcp.password
				and not public_mcp.path
				and not public_mcp.query
				and not public_mcp.fragment
			)
		except ValueError:
			valid_public_mcp = False
		if not valid_public_mcp:
			errors.append("MCP_PUBLIC_BASE_URL must be a valid HTTPS origin without a path")

	if errors:
		raise RuntimeError(
			"Production security validation failed:\n- " + "\n- ".join(errors)
		)
