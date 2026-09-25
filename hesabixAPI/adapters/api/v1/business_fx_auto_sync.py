from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Body, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_permission_dep
from app.core.responses import format_datetime_fields, success_response
from app.services.business_fx_auto_sync_service import (
	get_settings_payload,
	preview_auto_sync,
	run_auto_sync_for_business,
	upsert_settings,
)

router = APIRouter(tags=["currency_revaluation", "حسابداری"], prefix="")


@router.get(
	"/businesses/{business_id}/fx-auto-sync",
	summary="تنظیمات زمان‌بندی خودکار نرخ تسعیر",
)
def get_fx_auto_sync(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "view")),
) -> dict:
	data = get_settings_payload(db, business_id)
	return success_response(
		data=format_datetime_fields(data, request),
		request=request,
		message="FX_AUTO_SYNC_SETTINGS",
	)


@router.put(
	"/businesses/{business_id}/fx-auto-sync",
	summary="ذخیره تنظیمات زمان‌بندی خودکار نرخ تسعیر",
)
def put_fx_auto_sync(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "add")),
) -> dict:
	data = upsert_settings(db, business_id, int(ctx.get_user_id()), body)
	db.commit()
	return success_response(
		data=format_datetime_fields(data, request),
		request=request,
		message="FX_AUTO_SYNC_SAVED",
	)


@router.get(
	"/businesses/{business_id}/fx-auto-sync/preview",
	summary="پیش‌نمایش نرخ مرجع و نرخ نهایی پس از آفست",
)
def preview_fx_auto_sync(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "view")),
) -> dict:
	data = preview_auto_sync(db, business_id)
	return success_response(
		data=format_datetime_fields(data, request),
		request=request,
		message="FX_AUTO_SYNC_PREVIEW",
	)


@router.post(
	"/businesses/{business_id}/fx-auto-sync/preview",
	summary="پیش‌نمایش با پیش‌نویس تنظیمات (بدون ذخیره)",
)
def preview_fx_auto_sync_draft(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(default_factory=dict),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "view")),
) -> dict:
	data = preview_auto_sync(db, business_id, draft=body or None)
	return success_response(
		data=format_datetime_fields(data, request),
		request=request,
		message="FX_AUTO_SYNC_PREVIEW_DRAFT",
	)


@router.post(
	"/businesses/{business_id}/fx-auto-sync/run-now",
	summary="اجرای فوری ثبت نرخ از اسنپ‌شات مرکزی با آفست‌ها",
)
def run_fx_auto_sync_now(
	request: Request,
	business_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "add")),
) -> dict:
	out = run_auto_sync_for_business(
		db,
		business_id,
		triggered_by="manual",
		actor_user_id=int(ctx.get_user_id()),
	)
	db.commit()
	return success_response(
		data=format_datetime_fields(out, request),
		request=request,
		message="FX_AUTO_SYNC_RUN",
	)
