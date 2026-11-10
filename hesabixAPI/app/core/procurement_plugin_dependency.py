"""گیت لایسنس افزونه تدارکات."""
from __future__ import annotations

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user
from app.core.plugin_license import is_plugin_active
from app.core.responses import ApiError

PLUGIN_CODE = "procurement"


def check_procurement_plugin_active(db: Session, business_id: int) -> bool:
	return is_plugin_active(db, business_id, PLUGIN_CODE)


def require_procurement_plugin_active(business_id_param: str = "business_id"):
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
		if not business_id:
			raise ApiError("INVALID_BUSINESS_ID", "شناسه کسب‌وکار نامعتبر است.", http_status=400)
		if not check_procurement_plugin_active(db, business_id):
			raise ApiError(
				"PROCUREMENT_PLUGIN_NOT_ACTIVE",
				"افزونه تدارکات برای این کسب‌وکار فعال نیست.",
				http_status=403,
				details={
					"plugin_code": PLUGIN_CODE,
					"required_action": "activate_plugin",
					"marketplace_url": "/marketplace",
				},
			)
		return None

	return dependency
