"""API گزارش‌های سفارشی HScript."""

from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.hscript_report import (
	HScriptAssistContextRequest,
	HScriptPdfExportRequest,
	HScriptReportCreateRequest,
	HScriptReportUpdateRequest,
	HScriptRunRequest,
	HScriptValidateRequest,
)
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access, require_business_permission_dep
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
	_: None = Depends(require_business_permission_dep("reports", "view")),
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
	_: None = Depends(require_business_permission_dep("reports", "view")),
):
	return success_response(data=svc.get_plan_status(db, business_id), request=request, message="HSCRIPT_PLAN")


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
	_: None = Depends(require_business_permission_dep("reports", "view")),
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
	_: None = Depends(require_business_permission_dep("reports", "view")),
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
	_: None = Depends(require_business_permission_dep("reports", "view")),
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
	_: None = Depends(require_business_permission_dep("reports", "view")),
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
	_: None = Depends(require_business_permission_dep("reports", "view")),
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
	_: None = Depends(require_business_permission_dep("reports", "view")),
):
	data = svc.get_report(db, business_id, report_id)
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
	_: None = Depends(require_business_permission_dep("reports", "view")),
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
	_: None = Depends(require_business_permission_dep("reports", "view")),
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
	_: None = Depends(require_business_permission_dep("reports", "view")),
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
	_: None = Depends(require_business_permission_dep("reports", "view")),
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
	_: None = Depends(require_business_permission_dep("reports", "view")),
):
	data = svc.list_versions(db, business_id, report_id)
	return success_response(data=format_datetime_fields(data, request), request=request, message="HSCRIPT_VERSIONS")


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
	_: None = Depends(require_business_permission_dep("reports", "view")),
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
	_: None = Depends(require_business_permission_dep("reports", "export")),
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
	_: None = Depends(require_business_permission_dep("reports", "export")),
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
	_: None = Depends(require_business_permission_dep("reports", "export")),
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
	_: None = Depends(require_business_permission_dep("reports", "export")),
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
