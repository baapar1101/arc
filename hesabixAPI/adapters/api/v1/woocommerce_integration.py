"""APIهای یکپارچه‌سازی ووکامرس (پل ArcWOC REST)."""

from __future__ import annotations

from typing import Any, Dict, Optional

import structlog
from fastapi import APIRouter, Body, Depends, Path, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.i18n import locale_dependency
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import ApiError, success_response
from app.core.woocommerce_dev_flags import (
	woocommerce_bridge_tls_verify_enabled,
	woocommerce_dev_mode,
)
from app.core.woocommerce_plugin_dependency import PLUGIN_CODE, check_woocommerce_plugin_active
from app.services import woocommerce_integration_service as wc_svc

router = APIRouter(prefix="/woocommerce", tags=["یکپارچه‌سازی"])
_router_log = structlog.get_logger(__name__)
if woocommerce_dev_mode():
	_router_log.warning(
		"woocommerce_api_dev_mode",
		hint="SSRF/rate_limit/token_encrypt relaxed; set WOOCOMMERCE_DEV_ENABLE_* to re-enable.",
	)
if not woocommerce_bridge_tls_verify_enabled():
	_router_log.warning(
		"woocommerce_api_tls_verify_disabled",
		hint="httpx verify=False for WooCommerce bridge; use only in trusted networks.",
	)


def _ensure_plugin(db: Session, business_id: int) -> None:
	if not check_woocommerce_plugin_active(db, business_id):
		raise ApiError(
			"WOOCOMMERCE_PLUGIN_NOT_ACTIVE",
			"افزونهٔ ووکامرس برای این کسب‌وکار فعال نیست.",
			http_status=403,
			details={"plugin_code": PLUGIN_CODE},
		)


@router.get("/business/{business_id}/settings")
def get_woocommerce_settings(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.get_settings(db, business_id)
	return success_response(data, request)


@router.put("/business/{business_id}/settings")
def put_woocommerce_settings(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.update_settings(db, business_id, payload or {})
	return success_response(data, request)


@router.post("/business/{business_id}/bridge/test")
def post_woocommerce_bridge_test(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.test_bridge(db, business_id)
	return success_response(data, request)


@router.get("/business/{business_id}/bridge/orders")
def get_woocommerce_bridge_orders(
	request: Request,
	business_id: int = Path(..., gt=0),
	page: int = Query(1, ge=1),
	per_page: int = Query(20, ge=1, le=50),
	status: Optional[str] = Query(None),
	after: Optional[str] = Query(None),
	before: Optional[str] = Query(None),
	customer_id: Optional[int] = Query(None, ge=0),
	search: Optional[str] = Query(None),
	orderby: Optional[str] = Query(None, description="date|modified|id"),
	order: Optional[str] = Query(None, description="ASC|DESC"),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.list_orders(
		db,
		business_id,
		page=page,
		per_page=per_page,
		status=status,
		after=after,
		before=before,
		customer_id=customer_id,
		search=search,
		orderby=orderby,
		order=order,
	)
	return success_response(data, request)


@router.get("/business/{business_id}/bridge/products")
def get_woocommerce_bridge_products(
	request: Request,
	business_id: int = Path(..., gt=0),
	page: int = Query(1, ge=1),
	per_page: int = Query(20, ge=1, le=50),
	search: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.list_products(db, business_id, page=page, per_page=per_page, search=search)
	return success_response(data, request)


@router.get("/business/{business_id}/bridge/reports/summary")
def get_woocommerce_bridge_reports_summary(
	request: Request,
	business_id: int = Path(..., gt=0),
	after: Optional[str] = Query(None),
	before: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.reports_summary(db, business_id, after=after, before=before)
	return success_response(data, request)


@router.get("/business/{business_id}/bridge/customers")
def get_woocommerce_bridge_customers(
	request: Request,
	business_id: int = Path(..., gt=0),
	page: int = Query(1, ge=1),
	per_page: int = Query(20, ge=1, le=50),
	search: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.list_customers(db, business_id, page=page, per_page=per_page, search=search)
	return success_response(data, request)


@router.get("/business/{business_id}/bridge/control/sync-stats")
def get_woocommerce_bridge_control_sync_stats(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.control_sync_stats(db, business_id)
	return success_response(data, request)


@router.get("/business/{business_id}/bridge/control/settings-summary")
def get_woocommerce_bridge_control_settings_summary(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.control_settings_summary(db, business_id)
	return success_response(data, request)


@router.get("/business/{business_id}/bridge/control/logs")
def get_woocommerce_bridge_control_logs(
	request: Request,
	business_id: int = Path(..., gt=0),
	page: int = Query(1, ge=1),
	per_page: int = Query(20, ge=1, le=100),
	action: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.control_logs(db, business_id, page=page, per_page=per_page, action=action)
	return success_response(data, request)


@router.get("/business/{business_id}/bridge/control/connection")
def get_woocommerce_bridge_control_connection(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.control_connection(db, business_id)
	return success_response(data, request)


@router.get("/business/{business_id}/bridge/control/plugin")
def get_woocommerce_bridge_control_plugin(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.control_plugin(db, business_id)
	return success_response(data, request)


@router.post("/business/{business_id}/bridge/control/sync/product")
def post_woocommerce_bridge_control_sync_product(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	pid = int(payload.get("product_id") or 0)
	vid = payload.get("variation_id")
	vid_i = int(vid) if vid is not None and str(vid).strip() != "" else None
	if vid_i is not None and vid_i < 1:
		vid_i = None
	if pid < 1:
		raise ApiError("INVALID_PRODUCT_ID", "شناسهٔ محصول نامعتبر است.", http_status=400)
	data = wc_svc.post_control_sync_product(db, business_id, product_id=pid, variation_id=vid_i)
	return success_response(data, request)


@router.post("/business/{business_id}/bridge/control/sync/orders")
def post_woocommerce_bridge_control_sync_orders(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	raw = payload.get("order_ids")
	ids = [int(x) for x in raw] if isinstance(raw, list) else []
	data = wc_svc.post_control_sync_orders(db, business_id, ids)
	return success_response(data, request)


@router.post("/business/{business_id}/bridge/control/sync/products")
def post_woocommerce_bridge_control_sync_products(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	raw = payload.get("product_ids")
	ids = [int(x) for x in raw] if isinstance(raw, list) else []
	data = wc_svc.post_control_sync_products(db, business_id, ids)
	return success_response(data, request)


@router.post("/business/{business_id}/bridge/control/sync/customers")
def post_woocommerce_bridge_control_sync_customers(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	raw = payload.get("customer_ids")
	ids = [int(x) for x in raw] if isinstance(raw, list) else []
	data = wc_svc.post_control_sync_customers(db, business_id, ids)
	return success_response(data, request)


@router.get("/business/{business_id}/bridge/control/queue/snapshot")
def get_woocommerce_bridge_control_queue_snapshot(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.control_queue_snapshot(db, business_id)
	return success_response(data, request)


@router.post("/business/{business_id}/bridge/control/queue/process-once")
def post_woocommerce_bridge_control_queue_process_once(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.post_control_queue_process_once(db, business_id)
	return success_response(data, request)


@router.post("/business/{business_id}/bridge/control/plugin/update-check")
def post_woocommerce_bridge_control_plugin_update_check(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Optional[Dict[str, Any]] = Body(None),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	body = payload if isinstance(payload, dict) else {}
	force = bool(body.get("force"))
	data = wc_svc.post_control_plugin_update_check(db, business_id, force=force)
	return success_response(data, request)


@router.post("/business/{business_id}/bridge/control/settings/patch")
def post_woocommerce_bridge_control_settings_patch(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.post_control_settings_patch(db, business_id, payload or {})
	return success_response(data, request)
