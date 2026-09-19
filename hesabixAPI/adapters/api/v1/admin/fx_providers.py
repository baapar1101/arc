from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Path, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services.fx_rate_provider_service import (
	fetch_and_store_provider,
	get_provider_by_code,
	list_global_rates,
	list_providers,
	test_provider_connection,
	upsert_provider,
)

router = APIRouter(prefix="/admin/fx-providers", tags=["admin-fx-providers", "مدیریت"])


def _require_admin(ctx: AuthContext) -> None:
	if not ctx.has_app_permission("system_settings"):
		raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند ارائه‌دهندگان نرخ را مدیریت کند", http_status=403)


@router.get("", summary="لیست ارائه‌دهندگان نرخ ارز")
def admin_list_fx_providers(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	items = list_providers(db)
	return success_response(
		data=format_datetime_fields({"items": items}, request),
		request=request,
		message="FX_PROVIDERS_LIST",
	)


@router.get("/global-rates", summary="اسنپ‌شات مرکزی نرخ‌ها")
def admin_list_fx_global_rates(
	request: Request,
	provider_code: Optional[str] = Query(None),
	currency_code: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	items = list_global_rates(db, provider_code=provider_code, currency_code=currency_code)
	return success_response(
		data=format_datetime_fields({"items": items, "total": len(items)}, request),
		request=request,
		message="FX_GLOBAL_RATES_LIST",
	)


@router.put("/{code}", summary="ایجاد/ویرایش ارائه‌دهنده نرخ")
def admin_upsert_fx_provider(
	request: Request,
	code: str = Path(..., description="کد ارائه‌دهنده مثل brsapi"),
	body: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	row = upsert_provider(db, code, body)
	db.commit()
	return success_response(
		data=format_datetime_fields(row, request),
		request=request,
		message="FX_PROVIDER_SAVED",
	)


@router.post("/{code}/test", summary="تست اتصال و ذخیره اسنپ‌شات")
def admin_test_fx_provider(
	request: Request,
	code: str = Path(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	provider = get_provider_by_code(db, code)
	try:
		result = test_provider_connection(db, provider)
		db.commit()
	except ApiError:
		# وضعیت last_fetch_* قبل از raise flush شده؛ commit تا در UI دیده شود
		db.commit()
		raise
	return success_response(
		data=format_datetime_fields(result, request),
		request=request,
		message="FX_PROVIDER_TEST_OK",
	)


@router.post("/{code}/fetch-now", summary="واکشی فوری نرخ‌ها")
def admin_fetch_fx_provider_now(
	request: Request,
	code: str = Path(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	provider = get_provider_by_code(db, code)
	try:
		result = fetch_and_store_provider(db, provider)
		db.commit()
	except ApiError:
		db.commit()
		raise
	return success_response(
		data=format_datetime_fields(result, request),
		request=request,
		message="FX_PROVIDER_FETCHED",
	)


@router.get("/data-health/{business_id}", summary="سلامت داده چندارزی یک کسب‌وکار")
def admin_fx_data_health(
	request: Request,
	business_id: int = Path(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	from app.services.fx_data_health_service import get_fx_data_health

	data = get_fx_data_health(db, business_id)
	return success_response(data=data, request=request, message="FX_DATA_HEALTH")


@router.post("/data-health/{business_id}/backfill-base", summary="Backfill خطوط *_base (dry-run پیش‌فرض)")
def admin_fx_backfill_base(
	request: Request,
	business_id: int = Path(...),
	body: Dict[str, Any] = Body(default={}),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	from app.services.fx_data_health_service import run_fx_base_backfill

	dry_run = bool((body or {}).get("dry_run", True))
	allow_infer = bool((body or {}).get("allow_infer", False))
	only_with_fx = bool((body or {}).get("only_with_fx_snapshot", True))
	max_docs = (body or {}).get("max_documents", 200)
	try:
		max_docs_i = int(max_docs) if max_docs is not None else None
	except Exception:
		max_docs_i = 200
	data = run_fx_base_backfill(
		db,
		business_id,
		dry_run=dry_run,
		only_with_fx_snapshot=only_with_fx,
		allow_infer=allow_infer,
		max_documents=max_docs_i,
	)
	return success_response(data=data, request=request, message="FX_BACKFILL_BASE")
