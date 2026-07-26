"""API گزارش‌های سفارشی HScript."""

from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.hscript_report import (
	HScriptAssistContextRequest,
	HScriptParamSchemaRequest,
	HScriptPdfExportRequest,
	HScriptReportCreateRequest,
	HScriptReportUpdateRequest,
	HScriptRestoreVersionRequest,
	HScriptScheduleUpsertRequest,
	HScriptRunRequest,
	HScriptValidateRequest,
)
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access
from app.core.hscript_permissions import require_hscript_permission_dep
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services import hscript_report_service as svc
from app.services.hscript.docs_catalog import list_doc_manifest
from fastapi.responses import Response


router = APIRouter(tags=["hscript-reports"])


def _guard_concurrency(db: Session, business_id: int) -> None:
	from app.services.hscript.plan_limits import resolve_hscript_entitlement

	ent = resolve_hscript_entitlement(db, business_id)
	if svc.count_recent_runs(db, business_id, seconds=60) >= ent.runs_per_minute:
		raise ApiError(
			"HSCRIPT_RATE_LIMIT",
			"تعداد اجرای گزارش در این دقیقه بیش از حد مجاز است. کمی بعد تلاش کنید.",
			http_status=429,
			details=ent.to_public_dict(),
		)


def _run_or_enqueue(
	*,
	db: Session,
	business_id: int,
	ctx: AuthContext,
	body: HScriptRunRequest,
	report_id: int | None = None,
	force_preview: bool | None = None,
	request: Request | None = None,
) -> dict:
	_guard_concurrency(db, business_id)
	fiscal_year_id = getattr(ctx, "fiscal_year_id", None)
	preview = bool(force_preview) if force_preview is not None else bool(body.preview)
	calendar_type = None
	if request is not None:
		calendar_type = getattr(getattr(request, "state", None), "calendar_type", None)
		if not calendar_type:
			from app.core.calendar import get_calendar_type_from_header

			calendar_type = get_calendar_type_from_header(request.headers.get("X-Calendar-Type"))

	if body.async_mode:
		from app.services.hscript.plan_limits import resolve_hscript_entitlement

		ent = resolve_hscript_entitlement(db, business_id)
		if not ent.async_allowed:
			raise ApiError(
				"HSCRIPT_ASYNC_NOT_ALLOWED",
				"اجرای پس‌زمینه در پلن فعلی مجاز نیست.",
				http_status=403,
				details=ent.to_public_dict(),
			)
		queued = svc.enqueue_run_report(
			business_id=business_id,
			user_id=ctx.user.id,
			report_id=report_id,
			source_code=body.source_code if report_id is None else None,
			params=body.params,
			fiscal_year_id=fiscal_year_id,
			preview=preview,
			persist=body.persist,
			calendar_type=calendar_type,
		)
		if queued is not None:
			return queued

	return svc.run_report(
		db,
		business_id,
		user_id=ctx.user.id,
		report_id=report_id,
		source_code=body.source_code if report_id is None else None,
		params=body.params,
		fiscal_year_id=fiscal_year_id,
		preview=preview,
		persist=body.persist,
		calendar_type=calendar_type,
	)


@router.get(
	"/businesses/{business_id}/hscript/docs/manifest",
	summary="مانیفست مستندات HScript برای RAG/AI",
)
@require_business_access("business_id")
async def docs_manifest_endpoint(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("view")),
):
	return success_response(data=list_doc_manifest(), request=request, message="HSCRIPT_DOCS_MANIFEST")


@router.get(
	"/businesses/{business_id}/hscript/plan",
	summary="وضعیت پلن و سقف‌های HScript",
)
@require_business_access("business_id")
async def plan_status_endpoint(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("view")),
):
	return success_response(data=svc.get_plan_status(db, business_id), request=request, message="HSCRIPT_PLAN")


@router.get(
	"/businesses/{business_id}/hscript/catalog",
	summary="کاتالوگ ماژول‌ها، متدهای جدول و دستورپخت‌ها",
)
@require_business_access("business_id")
async def catalog_endpoint(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("view")),
):
	return success_response(data=svc.get_catalog(), request=request, message="HSCRIPT_CATALOG")


@router.get(
	"/businesses/{business_id}/hscript/recipes",
	summary="فهرست دستورپخت‌های آماده",
)
@require_business_access("business_id")
async def recipes_endpoint(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("view")),
):
	return success_response(data=svc.list_recipes(), request=request, message="HSCRIPT_RECIPES")


@router.post(
	"/businesses/{business_id}/hscript/param-schema",
	summary="استنتاج schema فرم پارامتر از اسکریپت و مقادیر",
)
@require_business_access("business_id")
async def param_schema_endpoint(
	request: Request,
	business_id: int,
	body: HScriptParamSchemaRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("view")),
):
	data = svc.infer_report_param_schema(
		source_code=body.source_code,
		default_params=body.default_params,
		params=body.params,
	)
	return success_response(data=data, request=request, message="HSCRIPT_PARAM_SCHEMA")


@router.post(
	"/businesses/{business_id}/hscript/assist/context",
	summary="بازیابی context مستندات برای دستیار AI",
)
@require_business_access("business_id")
async def assist_context_endpoint(
	request: Request,
	business_id: int,
	body: HScriptAssistContextRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("view")),
):
	data = svc.build_assist_context(body.query, source_code=body.source_code, limit=body.limit)
	return success_response(data=data, request=request, message="HSCRIPT_ASSIST_CONTEXT")


@router.post(
	"/businesses/{business_id}/hscript/validate",
	summary="اعتبارسنجی نحوی اسکریپت بدون اجرا",
)
@require_business_access("business_id")
async def validate_endpoint(
	request: Request,
	business_id: int,
	body: HScriptValidateRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("write")),
):
	return success_response(data=svc.validate_only(body.source_code), request=request, message="HSCRIPT_VALIDATED")


@router.post(
	"/businesses/{business_id}/hscript/run",
	summary="اجرای اسکریپت موقت (پیش‌نمایش Studio)",
)
@require_business_access("business_id")
async def run_adhoc_endpoint(
	request: Request,
	business_id: int,
	body: HScriptRunRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("write")),
):
	result = _run_or_enqueue(
		db=db,
		business_id=business_id,
		ctx=ctx,
		body=body,
		report_id=None,
		force_preview=True,
		request=request,
	)
	return success_response(data=result, request=request, message="HSCRIPT_RUN_DONE")


@router.get(
	"/businesses/{business_id}/hscript/reports",
	summary="لیست گزارش‌های HScript",
)
@require_business_access("business_id")
async def list_endpoint(
	request: Request,
	business_id: int,
	status: Optional[str] = Query(default=None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("view")),
):
	data = svc.list_reports(db, business_id, status=status)
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_LIST")


@router.post(
	"/businesses/{business_id}/hscript/reports",
	summary="ایجاد گزارش HScript",
)
@require_business_access("business_id")
async def create_endpoint(
	request: Request,
	business_id: int,
	body: HScriptReportCreateRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("write")),
):
	# نوشتن گزارش: همان سطح view فعلاً؛ فاز بعد می‌توان بخش custom_reports.write جدا کرد
	data = svc.create_report(
		db,
		business_id,
		user_id=ctx.user.id,
		title=body.title,
		source_code=body.source_code,
		slug=body.slug,
		description=body.description,
		default_params=body.default_params,
	)
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_CREATED")


@router.get(
	"/businesses/{business_id}/hscript/reports/{report_id}",
	summary="جزئیات گزارش",
)
@require_business_access("business_id")
async def get_endpoint(
	request: Request,
	business_id: int,
	report_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("view")),
):
	from app.core.hscript_permissions import has_hscript_permission

	data = svc.get_report(db, business_id, report_id)
	if not has_hscript_permission(ctx, "write"):
		data.pop("source_code", None)
		data["source_hidden"] = True
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_FETCHED")


@router.put(
	"/businesses/{business_id}/hscript/reports/{report_id}",
	summary="ویرایش گزارش",
)
@require_business_access("business_id")
async def update_endpoint(
	request: Request,
	business_id: int,
	report_id: int,
	body: HScriptReportUpdateRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("write")),
):
	data = svc.update_report(
		db,
		business_id,
		report_id,
		user_id=ctx.user.id,
		title=body.title,
		description=body.description,
		source_code=body.source_code,
		default_params=body.default_params,
		changelog=body.changelog,
	)
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_UPDATED")


@router.post(
	"/businesses/{business_id}/hscript/reports/{report_id}/publish",
	summary="انتشار گزارش",
)
@require_business_access("business_id")
async def publish_endpoint(
	request: Request,
	business_id: int,
	report_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("publish")),
):
	data = svc.publish_report(db, business_id, report_id, user_id=ctx.user.id)
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_PUBLISHED")


@router.post(
	"/businesses/{business_id}/hscript/reports/{report_id}/archive",
	summary="بایگانی گزارش",
)
@require_business_access("business_id")
async def archive_endpoint(
	request: Request,
	business_id: int,
	report_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("publish")),
):
	data = svc.archive_report(db, business_id, report_id, user_id=ctx.user.id)
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_ARCHIVED")


@router.delete(
	"/businesses/{business_id}/hscript/reports/{report_id}",
	summary="حذف نرم گزارش",
)
@require_business_access("business_id")
async def delete_endpoint(
	request: Request,
	business_id: int,
	report_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("write")),
):
	data = svc.delete_report(db, business_id, report_id, user_id=ctx.user.id)
	return success_response(data=data, request=request, message="HSCRIPT_DELETED")


@router.get(
	"/businesses/{business_id}/hscript/reports/{report_id}/versions",
	summary="نسخه‌های گزارش",
)
@require_business_access("business_id")
async def versions_endpoint(
	request: Request,
	business_id: int,
	report_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("view")),
):
	data = svc.list_versions(db, business_id, report_id)
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_VERSIONS")


@router.get(
	"/businesses/{business_id}/hscript/reports/{report_id}/versions/{version_id}",
	summary="جزئیات یک نسخه",
)
@require_business_access("business_id")
async def version_detail_endpoint(
	request: Request,
	business_id: int,
	report_id: int,
	version_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("view")),
):
	data = svc.get_version(db, business_id, report_id, version_id)
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_VERSION")


@router.post(
	"/businesses/{business_id}/hscript/reports/{report_id}/versions/{version_id}/restore",
	summary="بازگردانی نسخهٔ قبلی",
)
@require_business_access("business_id")
async def restore_version_endpoint(
	request: Request,
	business_id: int,
	report_id: int,
	version_id: int,
	body: HScriptRestoreVersionRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("write")),
):
	data = svc.restore_version(
		db,
		business_id,
		report_id,
		version_id,
		user_id=ctx.user.id,
		changelog=body.changelog,
	)
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_VERSION_RESTORED")


@router.get(
	"/businesses/{business_id}/hscript/reports/{report_id}/runs",
	summary="سابقه اجرای گزارش",
)
@require_business_access("business_id")
async def report_runs_endpoint(
	request: Request,
	business_id: int,
	report_id: int,
	limit: int = Query(30, ge=1, le=100),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("view")),
):
	data = svc.list_runs(db, business_id, report_id, limit=limit)
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_RUNS")


@router.post(
	"/businesses/{business_id}/hscript/reports/{report_id}/run",
	summary="اجرای گزارش ذخیره‌شده",
)
@require_business_access("business_id")
async def run_saved_endpoint(
	request: Request,
	business_id: int,
	report_id: int,
	body: HScriptRunRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("view")),
):
	result = _run_or_enqueue(
		db=db,
		business_id=business_id,
		ctx=ctx,
		body=body,
		report_id=report_id,
		force_preview=None,
		request=request,
	)
	return success_response(data=result, request=request, message="HSCRIPT_RUN_DONE")


@router.post(
	"/businesses/{business_id}/hscript/pdf",
	summary="خروجی PDF از اسکریپت یا Spec",
)
@require_business_access("business_id")
async def pdf_adhoc_endpoint(
	request: Request,
	business_id: int,
	body: HScriptPdfExportRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("export")),
):
	fiscal_year_id = getattr(ctx, "fiscal_year_id", None)
	pdf_bytes, filename = svc.export_pdf(
		db,
		business_id,
		user_id=ctx.user.id,
		source_code=body.source_code,
		spec=body.spec,
		params=body.params,
		fiscal_year_id=fiscal_year_id,
	)
	return Response(
		content=pdf_bytes,
		media_type="application/pdf",
		headers={
			"Content-Disposition": f'attachment; filename="{filename}"',
			"Content-Length": str(len(pdf_bytes)),
			"Access-Control-Expose-Headers": "Content-Disposition",
		},
	)


@router.post(
	"/businesses/{business_id}/hscript/reports/{report_id}/pdf",
	summary="خروجی PDF گزارش ذخیره‌شده",
)
@require_business_access("business_id")
async def pdf_saved_endpoint(
	request: Request,
	business_id: int,
	report_id: int,
	body: HScriptPdfExportRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("export")),
):
	fiscal_year_id = getattr(ctx, "fiscal_year_id", None)
	pdf_bytes, filename = svc.export_pdf(
		db,
		business_id,
		user_id=ctx.user.id,
		report_id=report_id,
		spec=body.spec,
		params=body.params,
		fiscal_year_id=fiscal_year_id,
	)
	return Response(
		content=pdf_bytes,
		media_type="application/pdf",
		headers={
			"Content-Disposition": f'attachment; filename="{filename}"',
			"Content-Length": str(len(pdf_bytes)),
			"Access-Control-Expose-Headers": "Content-Disposition",
		},
	)


@router.post(
	"/businesses/{business_id}/hscript/excel",
	summary="خروجی Excel از اسکریپت یا Spec",
)
@require_business_access("business_id")
async def excel_adhoc_endpoint(
	request: Request,
	business_id: int,
	body: HScriptPdfExportRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("export")),
):
	fiscal_year_id = getattr(ctx, "fiscal_year_id", None)
	xlsx_bytes, filename = svc.export_excel(
		db,
		business_id,
		user_id=ctx.user.id,
		source_code=body.source_code,
		spec=body.spec,
		params=body.params,
		fiscal_year_id=fiscal_year_id,
	)
	return Response(
		content=xlsx_bytes,
		media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
		headers={
			"Content-Disposition": f'attachment; filename="{filename}"',
			"Content-Length": str(len(xlsx_bytes)),
			"Access-Control-Expose-Headers": "Content-Disposition",
		},
	)


@router.post(
	"/businesses/{business_id}/hscript/reports/{report_id}/excel",
	summary="خروجی Excel گزارش ذخیره‌شده",
)
@require_business_access("business_id")
async def excel_saved_endpoint(
	request: Request,
	business_id: int,
	report_id: int,
	body: HScriptPdfExportRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("export")),
):
	fiscal_year_id = getattr(ctx, "fiscal_year_id", None)
	xlsx_bytes, filename = svc.export_excel(
		db,
		business_id,
		user_id=ctx.user.id,
		report_id=report_id,
		spec=body.spec,
		params=body.params,
		fiscal_year_id=fiscal_year_id,
	)
	return Response(
		content=xlsx_bytes,
		media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
		headers={
			"Content-Disposition": f'attachment; filename="{filename}"',
			"Content-Length": str(len(xlsx_bytes)),
			"Access-Control-Expose-Headers": "Content-Disposition",
		},
	)

@router.get(
	"/businesses/{business_id}/hscript/schedules",
	summary="فهرست زمان‌بندی‌های HScript",
)
@require_business_access("business_id")
async def list_schedules_endpoint(
	request: Request,
	business_id: int,
	report_id: Optional[int] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("schedule")),
):
	from app.services import hscript_schedule_service as sched_svc

	data = sched_svc.list_schedules(db, business_id, report_id=report_id)
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_SCHEDULES")


@router.post(
	"/businesses/{business_id}/hscript/reports/{report_id}/schedules",
	summary="ایجاد زمان‌بندی برای گزارش منتشرشده",
)
@require_business_access("business_id")
async def create_schedule_endpoint(
	request: Request,
	business_id: int,
	report_id: int,
	body: HScriptScheduleUpsertRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("schedule")),
):
	from app.services import hscript_schedule_service as sched_svc

	data = sched_svc.create_schedule(
		db,
		business_id,
		user_id=ctx.user.id,
		report_id=report_id,
		data=body.model_dump(),
	)
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_SCHEDULE_CREATED")


@router.put(
	"/businesses/{business_id}/hscript/schedules/{schedule_id}",
	summary="ویرایش زمان‌بندی",
)
@require_business_access("business_id")
async def update_schedule_endpoint(
	request: Request,
	business_id: int,
	schedule_id: int,
	body: HScriptScheduleUpsertRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("schedule")),
):
	from app.services import hscript_schedule_service as sched_svc

	data = sched_svc.update_schedule(
		db,
		business_id,
		schedule_id,
		user_id=ctx.user.id,
		data=body.model_dump(exclude_unset=True),
	)
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_SCHEDULE_UPDATED")


@router.delete(
	"/businesses/{business_id}/hscript/schedules/{schedule_id}",
	summary="حذف زمان‌بندی",
)
@require_business_access("business_id")
async def delete_schedule_endpoint(
	request: Request,
	business_id: int,
	schedule_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("schedule")),
):
	from app.services import hscript_schedule_service as sched_svc

	data = sched_svc.delete_schedule(db, business_id, schedule_id)
	return success_response(data=data, request=request, message="HSCRIPT_SCHEDULE_DELETED")


@router.post(
	"/businesses/{business_id}/hscript/schedules/{schedule_id}/run-now",
	summary="اجرای فوری زمان‌بندی",
)
@require_business_access("business_id")
async def run_schedule_now_endpoint(
	request: Request,
	business_id: int,
	schedule_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_hscript_permission_dep("schedule")),
):
	from app.services import hscript_schedule_service as sched_svc

	row = sched_svc._get_schedule(db, business_id, schedule_id)
	data = sched_svc.run_schedule_now(db, row, triggered_by="manual")
	return success_response(data=data, request=request, message="HSCRIPT_SCHEDULE_RUN")

