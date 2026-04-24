from __future__ import annotations

import time
from typing import Literal

from fastapi import Request
from sqlalchemy.orm import Session

from app.core.rate_limiter import get_client_ip, get_rate_limiter
from app.core.responses import ApiError
from app.services.auth_security_event_service import log_auth_security_event
from app.services.system_settings_service import get_captcha_auth_security_effective

AuthRateKind = Literal[
	"captcha",
	"login_short",
	"login_long",
	"register",
	"forgot",
	"reset",
	"pr_otp",
]


def enforce_auth_rate_limit(
	request: Request,
	db: Session,
	*,
	kind: AuthRateKind,
	error_message: str,
) -> None:
	cfg = get_captcha_auth_security_effective(db)
	if kind == "captcha":
		max_r, win = cfg["captcha_rate_max"], cfg["captcha_rate_window_sec"]
		key_pfx = "auth_rl_captcha"
	elif kind == "login_short":
		max_r, win = cfg["login_rate_max_short"], cfg["login_rate_window_short_sec"]
		key_pfx = "auth_rl_login_s"
	elif kind == "login_long":
		max_r, win = cfg["login_rate_max_long"], cfg["login_rate_window_long_sec"]
		key_pfx = "auth_rl_login_l"
	elif kind == "register":
		max_r, win = cfg["register_rate_max"], cfg["register_rate_window_sec"]
		key_pfx = "auth_rl_reg"
	elif kind == "forgot":
		max_r, win = cfg["forgot_rate_max"], cfg["forgot_rate_window_sec"]
		key_pfx = "auth_rl_forgot"
	elif kind == "reset":
		max_r, win = cfg["reset_rate_max"], cfg["reset_rate_window_sec"]
		key_pfx = "auth_rl_reset"
	else:
		max_r, win = cfg["pr_otp_rate_max"], cfg["pr_otp_rate_window_sec"]
		key_pfx = "auth_rl_pr_otp"

	ip = get_client_ip(request)
	key = f"{key_pfx}:{ip}"
	limiter = get_rate_limiter()
	allowed, _rem, reset_after = limiter.check_rate_limit(key, max_r, win)
	if not allowed:
		log_auth_security_event(
			event_type="auth_rate_limited",
			client_ip=ip,
			detail={"kind": kind},
		)
		raise ApiError(
			"RATE_LIMIT_EXCEEDED",
			error_message,
			http_status=429,
			details={"retry_after_seconds": reset_after, "scope": kind},
		)
