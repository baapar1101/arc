from __future__ import annotations

import asyncio
import logging
from typing import Awaitable, Callable

from fastapi import Request
from fastapi.responses import JSONResponse

from app.core.rate_limiter import get_client_ip
from app.services import firewall_service as fw

logger = logging.getLogger(__name__)


async def internal_firewall_middleware(request: Request, call_next: Callable[[Request], Awaitable]):
	if fw.is_firewall_globally_disabled():
		return await call_next(request)
	path = request.url.path
	if fw.should_skip_firewall_path(path):
		return await call_next(request)

	if fw.should_refresh_rules_cache():
		try:
			await asyncio.to_thread(fw.refresh_rules_cache_sync)
		except Exception as e:
			logger.warning("firewall: cache refresh failed: %s", e)

	client_ip = get_client_ip(request)
	method = request.method
	decision, rule_id = fw.evaluate_request(client_ip, path, method)

	if decision == "deny":
		ua = request.headers.get("user-agent")
		try:
			await asyncio.to_thread(fw.log_blocked_request_sync, client_ip, path, method, ua, rule_id)
		except Exception as e:
			logger.warning("firewall: async log failed: %s", e)
		return JSONResponse(
			status_code=403,
			content={
				"success": False,
				"error_code": "IP_BLOCKED_BY_FIREWALL",
				"message": "دسترسی شما توسط فایروال سیستم محدود شده است.",
			},
		)

	return await call_next(request)
