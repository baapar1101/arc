"""اعتبارسنجی تنظیمات امنیتی هنگام راه‌اندازی در محیط production."""

from __future__ import annotations

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

	if settings.cors_allowed_origins == ["*"]:
		errors.append("CORS_ALLOWED_ORIGINS must list explicit frontend domains in production")

	for name, value in (
		("CAPTCHA_SECRET", settings.captcha_secret),
		("SHARE_LINK_SECRET", settings.share_link_secret),
		("DB_PASSWORD", settings.db_password),
	):
		if (value or "").strip() in _INSECURE_SECRET_VALUES:
			errors.append(f"{name} must be set to a strong unique value")

	if not (settings.encryption_key or "").strip():
		errors.append("ENCRYPTION_KEY must be set in production")

	import os

	if not os.getenv("WALLET_WEBHOOK_SECRET", "").strip():
		errors.append("WALLET_WEBHOOK_SECRET must be set in production")

	if errors:
		raise RuntimeError(
			"Production security validation failed:\n- " + "\n- ".join(errors)
		)
