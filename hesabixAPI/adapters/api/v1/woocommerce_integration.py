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


@router.get(
	"/business/{business_id}/settings",
	summary="تنظیمات اتصال ووکامرس",
	description="آدرس فروشگاه و وضعیت توکن پل (ماسک‌شده). افزونه ووکامرس باید فعال باشد. ابزار MCP: get_woocommerce_settings.",
)
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


@router.put(
	"/business/{business_id}/settings",
	summary="ذخیره تنظیمات ووکامرس",
	description="store_base_url، توکن پل و پوش موجودی. در MCP توکن پذیرفته نمی‌شود. ابزار MCP: update_woocommerce_settings.",
)
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


@router.post(
	"/business/{business_id}/bridge/test",
	summary="آزمون پل ووکامرس",
	description="اتصال آزمایشی به پل وردپرس ArcWOC. ابزار MCP: test_woocommerce_bridge.",
)
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


@router.get(
	"/business/{business_id}/bridge/orders",
	summary="سفارش‌های ووکامرس",
	description="ابزار MCP: `list_woocommerce_orders`.",
)
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


@router.get(
	"/business/{business_id}/bridge/products",
	summary="کالاهای ووکامرس",
	description="ابزار MCP: `list_woocommerce_products`.",
)
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


@router.get(
	"/business/{business_id}/bridge/reports/summary",
	summary="خلاصه فروش ووکامرس",
	description="خلاصه فروش بازه after/before. ابزار MCP: get_woocommerce_sales_summary.",
)
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


@router.get(
	"/business/{business_id}/bridge/customers",
	summary="مشتریان ووکامرس",
	description="لیست مشتریان پل وردپرس. ابزار MCP: list_woocommerce_customers.",
)
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


@router.get(
	"/business/{business_id}/bridge/control/sync-stats",
	summary="آمار همگام ووکامرس",
	description="ابزار MCP: `get_woocommerce_sync_stats`.",
)
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


@router.get(
	"/business/{business_id}/bridge/control/settings-summary",
	summary="خلاصه تنظیمات پل ووکامرس",
	description="ابزار MCP: `get_woocommerce_settings`. توکن خام برنمی‌گردد.",
)
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


@router.get(
	"/business/{business_id}/bridge/control/logs",
	summary="لاگ کنترل ووکامرس",
	description="لاگ عملیات پل. ابزار MCP: list_woocommerce_control_logs.",
)
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


@router.get(
	"/business/{business_id}/bridge/control/connection",
	summary="وضعیت اتصال پل ووکامرس",
	description="وضعیت اتصال بدون توکن. ابزار MCP: get_woocommerce_connection_status.",
)
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


@router.get(
	"/business/{business_id}/bridge/control/plugin",
	summary="اطلاعات افزونه وردپرس ووکامرس",
	description="نسخه افزونه پل. ابزار MCP: get_woocommerce_plugin_info.",
)
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


@router.post(
	"/business/{business_id}/bridge/control/sync/product",
	summary="همگام یک کالای ووکامرس",
	description="ابزار MCP: `sync_woocommerce_product` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/bridge/control/sync/orders",
	summary="همگام سفارش‌های ووکامرس",
	description="ابزار MCP: `sync_woocommerce_orders` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/bridge/control/sync/products",
	summary="همگام کالاهای ووکامرس",
	description="ابزار MCP: `sync_woocommerce_products` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/bridge/control/sync/customers",
	summary="همگام مشتریان ووکامرس",
	description="ابزار MCP: `sync_woocommerce_customers` (نیازمند تأیید).",
)
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


@router.get(
	"/business/{business_id}/bridge/control/queue/snapshot",
	summary="نمای صف همگام ووکامرس",
	description="وضعیت صف. ابزار MCP: get_woocommerce_queue_snapshot.",
)
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


@router.post(
	"/business/{business_id}/bridge/control/queue/process-once",
	summary="پردازش یک دور صف ووکامرس",
	description="یک دور صف را اجرا می‌کند. ابزار MCP: process_woocommerce_queue_once.",
)
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


@router.post(
	"/business/{business_id}/bridge/control/plugin/update-check",
	summary="بررسی به‌روزرسانی افزونه ووکامرس",
	description="force اختیاری است. ابزار MCP: check_woocommerce_plugin_update.",
)
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


@router.post(
	"/business/{business_id}/bridge/control/settings/patch",
	summary="ویرایش تنظیمات پل ووکامرس",
	description="ابزار MCP: `update_woocommerce_settings` (نیازمند تأیید). توکن از MCP پذیرفته نمی‌شود.",
)
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


@router.post(
	"/business/{business_id}/bridge/control/stock-pull/run",
	summary="کشیدن موجودی از ووکامرس",
	description="موجودی فروشگاه را به حسابیکس می‌کشد. ابزار MCP: run_woocommerce_stock_pull.",
)
def post_woocommerce_bridge_control_stock_pull_run(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(default_factory=dict),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.post_control_stock_pull_run(db, business_id, payload or {})
	return success_response(data, request)


@router.get(
	"/business/{business_id}/bridge/control/stock-status",
	summary="وضعیت همگام موجودی ووکامرس",
	description="وضعیت موجودی بین دو سیستم. ابزار MCP: get_woocommerce_stock_status.",
)
def get_woocommerce_bridge_control_stock_status(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.control_stock_status(db, business_id)
	return success_response(data, request)


@router.get(
	"/business/{business_id}/bridge/control/stock-conflicts",
	summary="تعارض موجودی ووکامرس",
	description="ابزار MCP: `get_woocommerce_stock_conflicts`.",
)
def get_woocommerce_bridge_control_stock_conflicts(
	request: Request,
	business_id: int = Path(..., gt=0),
	limit: int = 25,
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.control_stock_conflicts(db, business_id, limit=limit)
	return success_response(data, request)


@router.get(
	"/business/{business_id}/bridge/control/opening-inventory/status",
	summary="وضعیت موجودی اول دوره ووکامرس",
	description="وضعیت پل موجودی اول دوره فروشگاه ووکامرس همین کسب‌وکار. ابزار MCP: get_woocommerce_opening_inventory_status.",
)
def get_woocommerce_bridge_control_opening_inventory_status(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.control_opening_inventory_status(db, business_id)
	return success_response(data, request)


@router.get(
	"/business/{business_id}/bridge/control/opening-inventory/accounts",
	summary="حساب‌های موجودی اول دوره ووکامرس",
	description="حساب‌های قابل انتخاب برای سند موجودی اول دوره. ابزار MCP: get_woocommerce_opening_inventory_accounts.",
)
def get_woocommerce_bridge_control_opening_inventory_accounts(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.control_opening_inventory_accounts(db, business_id)
	return success_response(data, request)


@router.post(
	"/business/{business_id}/bridge/control/opening-inventory/preview",
	summary="پیش‌نمایش موجودی اول دوره ووکامرس",
	description="پیش‌نمایش سند بدون ثبت نهایی. ابزار MCP: preview_woocommerce_opening_inventory.",
)
def post_woocommerce_bridge_control_opening_inventory_preview(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(default_factory=dict),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.post_control_opening_inventory_preview(db, business_id, payload or {})
	return success_response(data, request)


@router.post(
	"/business/{business_id}/bridge/control/opening-inventory/prepare",
	summary="آماده‌سازی موجودی اول دوره ووکامرس",
	description="تقسیم موجودی به دسته‌ها برای ارسال به پل. ابزار MCP: prepare_woocommerce_opening_inventory.",
)
def post_woocommerce_bridge_control_opening_inventory_prepare(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(default_factory=dict),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.post_control_opening_inventory_prepare(db, business_id, payload or {})
	return success_response(data, request)


@router.post(
	"/business/{business_id}/bridge/control/opening-inventory/batch",
	summary="ارسال دسته موجودی اول دوره ووکامرس",
	description="ارسال یک دسته از اقلام موجودی اول دوره. ابزار MCP: batch_woocommerce_opening_inventory.",
)
def post_woocommerce_bridge_control_opening_inventory_batch(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(default_factory=dict),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.post_control_opening_inventory_batch(db, business_id, payload or {})
	return success_response(data, request)


@router.post(
	"/business/{business_id}/bridge/control/opening-inventory/finalize",
	summary="نهایی‌سازی موجودی اول دوره ووکامرس",
	description="ثبت نهایی موجودی اول دوره در حسابیکس و پل. ابزار MCP: finalize_woocommerce_opening_inventory.",
)
def post_woocommerce_bridge_control_opening_inventory_finalize(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(default_factory=dict),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.post_control_opening_inventory_finalize(db, business_id, payload or {})
	return success_response(data, request)


@router.post(
	"/business/{business_id}/bridge/control/opening-inventory/cancel",
	summary="لغو موجودی اول دوره ووکامرس",
	description="لغو فرآیند باز موجودی اول دوره. ابزار MCP: cancel_woocommerce_opening_inventory.",
)
def post_woocommerce_bridge_control_opening_inventory_cancel(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(default_factory=dict),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("woocommerce", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = wc_svc.post_control_opening_inventory_cancel(db, business_id, payload or {})
	return success_response(data, request)
