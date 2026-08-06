"""Barcode label studio API (plugin: barcode_label_studio)."""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.barcode_label import (
	FromPresetBody,
	LabelTemplateCreate,
	LabelTemplateUpdate,
	PrinterSettingsBody,
	SetDefaultBody,
)
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.barcode_label_plugin_dependency import require_barcode_label_plugin_active
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import format_datetime_fields, success_response
from app.services import barcode_label_service as svc

router = APIRouter(prefix="/barcode-labels", tags=["barcode-labels"])


def _uid(ctx: AuthContext) -> int | None:
	try:
		return ctx.get_user_id()
	except Exception:
		return None


@router.get("/business/{business_id}/templates", summary="لیست طرح‌های برچسب")
def list_templates(
	request: Request,
	business_id: int,
	status: Optional[str] = Query("all"),
	q: Optional[str] = Query(None),
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	# print-only users without design still use view
	data = svc.list_templates(db, business_id, status=status, q=q)
	return success_response(format_datetime_fields(data, request), request)


@router.post("/business/{business_id}/templates", summary="ایجاد طرح برچسب")
def create_template(
	request: Request,
	business_id: int,
	body: LabelTemplateCreate,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "design")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.create_template(
		db,
		business_id,
		name=body.name,
		description=body.description,
		design_json=body.design_json,
		sheet_json=body.sheet_json,
		user_id=_uid(ctx),
	)
	return success_response(format_datetime_fields(data, request), request)


@router.get("/business/{business_id}/templates/default", summary="طرح پیش‌فرض")
def get_default(
	request: Request,
	business_id: int,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.get_default_template(db, business_id)
	return success_response(format_datetime_fields(data, request), request)


@router.post("/business/{business_id}/templates/set-default", summary="تنظیم طرح پیش‌فرض")
def set_default(
	request: Request,
	business_id: int,
	body: SetDefaultBody,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "design")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.set_default_template(db, business_id, body.template_id)
	return success_response(format_datetime_fields(data, request), request)


@router.post("/business/{business_id}/templates/from-preset", summary="ساخت طرح از preset")
def from_preset(
	request: Request,
	business_id: int,
	body: FromPresetBody,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "design")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.create_from_preset(
		db,
		business_id,
		preset_code=body.preset_code,
		name=body.name,
		user_id=_uid(ctx),
	)
	return success_response(format_datetime_fields(data, request), request)


@router.get("/business/{business_id}/templates/{template_id}", summary="جزئیات طرح")
def get_template(
	request: Request,
	business_id: int,
	template_id: int,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.get_template(db, business_id, template_id)
	return success_response(format_datetime_fields(data, request), request)


@router.put("/business/{business_id}/templates/{template_id}", summary="ویرایش طرح")
def update_template(
	request: Request,
	business_id: int,
	template_id: int,
	body: LabelTemplateUpdate,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "design")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.update_template(
		db,
		business_id,
		template_id,
		payload=body.model_dump(exclude_unset=True),
		user_id=_uid(ctx),
	)
	return success_response(format_datetime_fields(data, request), request)


@router.post("/business/{business_id}/templates/{template_id}/publish", summary="انتشار طرح")
def publish_template(
	request: Request,
	business_id: int,
	template_id: int,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "design")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.publish_template(db, business_id, template_id, user_id=_uid(ctx))
	return success_response(format_datetime_fields(data, request), request)


@router.post("/business/{business_id}/templates/{template_id}/archive", summary="بایگانی طرح")
def archive_template(
	request: Request,
	business_id: int,
	template_id: int,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "design")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.archive_template(db, business_id, template_id, user_id=_uid(ctx))
	return success_response(format_datetime_fields(data, request), request)


@router.post("/business/{business_id}/templates/{template_id}/duplicate", summary="کپی طرح")
def duplicate_template(
	request: Request,
	business_id: int,
	template_id: int,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "design")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.duplicate_template(db, business_id, template_id, user_id=_uid(ctx))
	return success_response(format_datetime_fields(data, request), request)


@router.get(
	"/business/{business_id}/templates/{template_id}/revisions",
	summary="تاریخچه نسخه‌های طرح",
)
def list_revisions(
	request: Request,
	business_id: int,
	template_id: int,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "design")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.list_template_revisions(db, business_id, template_id)
	return success_response(format_datetime_fields(data, request), request)


@router.get("/business/{business_id}/presets", summary="گالری preset سیستمی")
def presets(
	request: Request,
	business_id: int,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return success_response(svc.presets_catalog(), request)


@router.get("/business/{business_id}/sample-context", summary="داده نمونه برای پیش‌نمایش")
def sample_context(
	request: Request,
	business_id: int,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return success_response(svc.get_sample_context(), request)


@router.get(
	"/business/{business_id}/printer-settings",
	summary="تنظیمات پروفایل چاپگر رولی/سیستم",
)
def get_printer_settings(
	request: Request,
	business_id: int,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return success_response(svc.get_printer_settings(db, business_id), request)


@router.put(
	"/business/{business_id}/printer-settings",
	summary="ذخیره پروفایل‌های چاپگر",
)
def put_printer_settings(
	request: Request,
	business_id: int,
	body: PrinterSettingsBody,
	_: None = Depends(require_business_access_dep),
	__: None = Depends(require_barcode_label_plugin_active("business_id")),
	___: None = Depends(require_business_permission_dep("barcode_labels", "print")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.upsert_printer_settings(db, business_id, body.model_dump())
	return success_response(data, request)
