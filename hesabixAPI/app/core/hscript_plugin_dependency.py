"""وابستگی FastAPI برای وضعیت افزونه HScript (بدون قفل سخت مسیرهای پایه)."""

from __future__ import annotations

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user
from app.core.responses import ApiError
from app.services.hscript.plan_limits import PLUGIN_CODE, check_hscript_plugin_active


def require_hscript_plugin_active(business_id_param: str = "business_id"):
	"""قفل سخت — فقط برای مسیرهایی که صراحتاً نیاز به لایسنس دارند."""

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
		if not check_hscript_plugin_active(db, business_id):
			raise ApiError(
				"HSCRIPT_PLUGIN_NOT_ACTIVE",
				"افزونه گزارش‌ساز اسکریپتی برای این کسب‌وکار فعال نیست.",
				http_status=403,
				details={
					"plugin_code": PLUGIN_CODE,
					"required_action": "activate_plugin",
					"marketplace_url": "/marketplace",
				},
			)
		return None

	return dependency
