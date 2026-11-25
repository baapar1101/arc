"""برند محصول برای کلاینت‌های متصل (ArcWOC و مشابه). منبع: ‎.deploy_env."""
from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Depends, Header, Request
from fastapi.responses import FileResponse, Response

from app.core.auth_dependency import AuthContext, get_current_user
from app.core.branding import (
	branding_public_payload,
	etags_match,
	logo_content_type,
	logo_etag,
	resolve_branding_state,
)
from app.core.responses import ApiError, success_response

router = APIRouter(prefix="/system", tags=["system-branding"])


@router.get(
	"/branding",
	summary="برند نمونه نرم‌افزار",
	description="نام فارسی/انگلیسی و وضعیت لوگو بدون بایت تصویر. ابزار MCP: get_system_branding.",
)
def get_system_branding(
	request: Request,
	_ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	return success_response(branding_public_payload(), request)


@router.get(
	"/branding/logo",
	summary="لوگوی برند نمونه",
	description="خروجی باینری تصویر است و در MCP ثبت نشده. JSON: `get_system_branding`.",
)
def get_system_branding_logo(
	if_none_match: str | None = Header(default=None, alias="If-None-Match"),
	_ctx: AuthContext = Depends(get_current_user),
):
	state = resolve_branding_state()
	if not state.enabled or not state.has_logo or state.logo_path is None:
		raise ApiError(
			"BRANDING_LOGO_NOT_FOUND",
			"لوگوی سفارشی برای این نمونه تنظیم نشده است.",
			http_status=404,
		)
	etag = logo_etag(state.logo_path)
	if etags_match(if_none_match, etag):
		return Response(status_code=304, headers={"ETag": etag})
	return FileResponse(
		state.logo_path,
		media_type=logo_content_type(state.logo_path),
		headers={
			"ETag": etag,
			"Cache-Control": "private, max-age=3600",
		},
	)
