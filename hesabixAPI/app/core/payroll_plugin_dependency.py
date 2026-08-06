"""وابستگی FastAPI برای بررسی فعال بودن افزونه حقوق و دستمزد."""

from __future__ import annotations

from datetime import datetime

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin
from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user
from app.core.responses import ApiError

PLUGIN_CODE = "payroll"


def check_payroll_plugin_active(db: Session, business_id: int) -> bool:
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


def require_payroll_plugin_active(business_id_param: str = "business_id"):
	"""Request/Depends در سطح ماژول تا با future annotations به query اجباری تبدیل نشود."""

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
		if not check_payroll_plugin_active(db, business_id):
			raise ApiError(
				"PAYROLL_PLUGIN_NOT_ACTIVE",
				"Payroll add-on is not active for this business.",
				http_status=403,
				details={
					"plugin_code": PLUGIN_CODE,
					"required_action": "activate_plugin",
					"marketplace_url": "/marketplace",
				},
			)
		return None

	return dependency
