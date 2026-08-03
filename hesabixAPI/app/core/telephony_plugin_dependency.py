"""وابستگی FastAPI برای بررسی فعال بودن افزونه اتصال آستریکس/ایزابل."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy.orm import Session

from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin

PLUGIN_CODE = "asterisk_issabel_connector"


def check_telephony_plugin_active(db: Session, business_id: int) -> bool:
	plugin = (
		db.query(MarketplacePlugin)
		.filter(
			MarketplacePlugin.code == PLUGIN_CODE,
			MarketplacePlugin.is_active == True,  # noqa: E712
		)
		.first()
	)
	if not plugin:
		return False
	license_row = (
		db.query(BusinessPlugin)
		.filter(
			BusinessPlugin.business_id == business_id,
			BusinessPlugin.plugin_id == plugin.id,
			BusinessPlugin.status == "active",
		)
		.first()
	)
	if not license_row:
		return False
	if license_row.ends_at:
		ea = license_row.ends_at
		ends_at_val = ea.date() if isinstance(ea, datetime) else ea
		now_val = datetime.utcnow().date()
		if ends_at_val < now_val:
			return False
	return True


def require_telephony_plugin_active(business_id_param: str = "business_id"):
	from fastapi import Depends, Request

	from adapters.db.session import get_db
	from app.core.auth_dependency import get_current_user
	from app.core.responses import ApiError

	def dependency(
		request: Request,
		_ctx=Depends(get_current_user),
		db: Session = Depends(get_db),
	) -> None:
		business_id = None
		if hasattr(request, "path_params") and business_id_param in request.path_params:
			try:
				business_id = int(request.path_params[business_id_param])
			except (TypeError, ValueError):
				pass
		if business_id is None and hasattr(request, "query_params"):
			try:
				business_id = int(request.query_params.get(business_id_param) or 0)
			except (TypeError, ValueError):
				pass
		if not business_id:
			raise ApiError(
				"INVALID_BUSINESS_ID",
				f"Invalid business identifier ({business_id_param}).",
				http_status=400,
			)
		if not check_telephony_plugin_active(db, business_id):
			raise ApiError(
				"TELEPHONY_PLUGIN_NOT_ACTIVE",
				"Asterisk/Issabel telephony add-on is not active for this business.",
				http_status=403,
				details={
					"plugin_code": PLUGIN_CODE,
					"required_action": "activate_plugin",
					"marketplace_url": "/marketplace",
				},
			)
		return None

	return dependency


def require_telephony_click_or_view(business_id_param: str = "business_id"):
	"""اجازه Click-to-Call با مجوز click_to_call یا view (برای اپراتورهای عادی)."""
	from fastapi import Depends, Request

	from adapters.db.session import get_db
	from app.core.auth_dependency import AuthContext, get_current_user
	from app.core.permissions import has_business_permission_for_business
	from app.core.responses import ApiError

	def dependency(
		request: Request,
		ctx: AuthContext = Depends(get_current_user),
		db: Session = Depends(get_db),
	) -> None:
		business_id = None
		try:
			business_id = int(request.path_params.get(business_id_param))
		except Exception:
			business_id = None
		if not business_id:
			raise ApiError("INVALID_BUSINESS_ID", "Invalid business id.", http_status=400)
		ok = has_business_permission_for_business(
			ctx, db, business_id, "telephony", "click_to_call"
		) or has_business_permission_for_business(ctx, db, business_id, "telephony", "view")
		if not ok:
			raise ApiError(
				"FORBIDDEN",
				"Missing business permission: telephony.click_to_call",
				http_status=403,
			)
		return None

	return dependency
