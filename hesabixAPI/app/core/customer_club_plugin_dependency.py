"""وابستگی FastAPI برای بررسی فعال بودن افزونه باشگاه مشتریان."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy.orm import Session

from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin


def check_customer_club_plugin_active(db: Session, business_id: int) -> bool:
	plugin = (
		db.query(MarketplacePlugin)
		.filter(
			MarketplacePlugin.code == "customer_club",
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


def require_customer_club_plugin_active(business_id_param: str = "business_id"):
	"""مانند سایر پلاگین‌ها؛ برای استفاده مستقیم در Depends بهتر است از dependency ترکیبی در ماژول API استفاده شود."""

	from fastapi import Depends, Request

	from adapters.db.session import get_db
	from app.core.auth_dependency import AuthContext, get_current_user
	from app.core.responses import ApiError

	def dependency(
		request: Request,
		ctx: AuthContext = Depends(get_current_user),
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
		if not check_customer_club_plugin_active(db, business_id):
			raise ApiError(
				"CUSTOMER_CLUB_PLUGIN_NOT_ACTIVE",
				"Customer club add-on is not active for this business.",
				http_status=403,
				details={
					"plugin_code": "customer_club",
					"required_action": "activate_plugin",
					"marketplace_url": "/marketplace",
				},
			)
		return None

	return dependency
