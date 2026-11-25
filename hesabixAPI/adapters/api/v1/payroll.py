from __future__ import annotations

import datetime
from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, File, Query, Request, UploadFile
from fastapi.responses import Response
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.i18n import locale_dependency, negotiate_locale
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services import payroll_service as svc
from app.services import payroll_excel as excel_svc
from app.services import payroll_reports as reports_svc

router = APIRouter(prefix="/payroll", tags=["payroll"])


def _handle_value_error(e: ValueError) -> None:
	raise ApiError("VALIDATION_ERROR", str(e), http_status=400)


def _payroll_response(data: Any, request: Request, **kwargs) -> dict:
	return success_response(format_datetime_fields(data, request), request, **kwargs)


# ─── تنظیمات ───────────────────────────────────────────────────────────────


@router.get(
	"/business/{business_id}/settings",
	summary="تنظیمات حقوق و دستمزد",
	description="ابزار MCP: `get_payroll_settings`.",
)
def get_settings_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.get_settings(db, business_id)
	return _payroll_response(data, request)


@router.put(
	"/business/{business_id}/settings",
	summary="ویرایش تنظیمات حقوق",
	description="ابزار MCP: `update_payroll_settings` (نیازمند تأیید).",
)
def update_settings_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	try:
		data = svc.update_settings(db, business_id, payload, user_id=ctx.get_user_id())
	except ApiError:
		raise
	except ValueError as e:
		_handle_value_error(e)
	return _payroll_response(data, request)


# ─── داشبورد ───────────────────────────────────────────────────────────────


@router.get(
	"/business/{business_id}/dashboard",
	summary="داشبورد حقوق و دستمزد",
	description="ابزار MCP: `get_payroll_dashboard`.",
)
def dashboard_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.get_dashboard_summary(db, business_id)
	return _payroll_response(data, request)


# ─── دسته‌بندی آیتم‌ها ─────────────────────────────────────────────────────


@router.get(
	"/business/{business_id}/item-categories",
	summary="دسته‌بندی آیتم‌های حقوق",
	description="ابزار MCP: `list_payroll_item_categories`.",
)
def list_item_categories_endpoint(
	request: Request,
	business_id: int,
	include_inactive: bool = Query(False),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	items = svc.list_item_categories(db, business_id, include_inactive=include_inactive)
	return _payroll_response({"items": items}, request)


@router.post(
	"/business/{business_id}/item-categories",
	summary="ایجاد دسته آیتم حقوق",
	description="ابزار MCP: `create_payroll_item_category` (نیازمند تأیید).",
)
def create_item_category_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	try:
		data = svc.create_item_category(db, business_id, payload, user_id=ctx.get_user_id())
	except ApiError:
		raise
	except ValueError as e:
		_handle_value_error(e)
	return _payroll_response(data, request)


@router.put(
	"/business/{business_id}/item-categories/{category_id}",
	summary="ویرایش دسته آیتم حقوق",
	description="ابزار MCP: `update_payroll_item_category` (نیازمند تأیید).",
)
def update_item_category_endpoint(
	request: Request,
	business_id: int,
	category_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	try:
		data = svc.update_item_category(db, business_id, category_id, payload, user_id=ctx.get_user_id())
	except ApiError:
		raise
	except ValueError as e:
		_handle_value_error(e)
	return _payroll_response(data, request)


@router.delete(
	"/business/{business_id}/item-categories/{category_id}",
	summary="حذف دسته آیتم حقوق",
	description="ابزار MCP: `delete_payroll_item_category` (نیازمند تأیید).",
)
def delete_item_category_endpoint(
	request: Request,
	business_id: int,
	category_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	svc.delete_item_category(db, business_id, category_id, user_id=ctx.get_user_id())
	return _payroll_response({"deleted": True}, request)


# ─── آیتم‌های حقوق ─────────────────────────────────────────────────────────


@router.get(
	"/business/{business_id}/items",
	summary="اجزای حقوق",
	description="ابزار MCP: `list_payroll_items`.",
)
def list_items_endpoint(
	request: Request,
	business_id: int,
	item_kind: Optional[str] = Query(None),
	include_inactive: bool = Query(False),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	items = svc.list_item_definitions(
		db, business_id, item_kind=item_kind, include_inactive=include_inactive
	)
	return _payroll_response({"items": items}, request)


@router.post(
	"/business/{business_id}/items",
	summary="تعریف جزء حقوق",
	description="ابزار MCP: `create_payroll_item` (نیازمند تأیید).",
)
def create_item_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	try:
		data = svc.create_item_definition(db, business_id, payload, user_id=ctx.get_user_id())
	except ApiError:
		raise
	except ValueError as e:
		_handle_value_error(e)
	return _payroll_response(data, request)


@router.put(
	"/business/{business_id}/items/{item_id}",
	summary="ویرایش جزء حقوق",
	description="ابزار MCP: `update_payroll_item` (نیازمند تأیید).",
)
def update_item_endpoint(
	request: Request,
	business_id: int,
	item_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	try:
		data = svc.update_item_definition(db, business_id, item_id, payload, user_id=ctx.get_user_id())
	except ApiError:
		raise
	except ValueError as e:
		_handle_value_error(e)
	return _payroll_response(data, request)


@router.delete(
	"/business/{business_id}/items/{item_id}",
	summary="حذف جزء حقوق",
	description="ابزار MCP: `delete_payroll_item` (نیازمند تأیید).",
)
def delete_item_endpoint(
	request: Request,
	business_id: int,
	item_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	svc.delete_item_definition(db, business_id, item_id, user_id=ctx.get_user_id())
	return _payroll_response({"deleted": True}, request)


# ─── بخش‌ها ────────────────────────────────────────────────────────────────


@router.get(
	"/business/{business_id}/departments",
	summary="بخش‌های سازمانی حقوق",
	description="ابزار MCP: `list_payroll_departments`.",
)
def list_departments_endpoint(
	request: Request,
	business_id: int,
	include_inactive: bool = Query(False),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	items = svc.list_departments(db, business_id, include_inactive=include_inactive)
	return _payroll_response({"items": items}, request)


@router.post(
	"/business/{business_id}/departments",
	summary="ایجاد بخش حقوق",
	description="ابزار MCP: `create_payroll_department` (نیازمند تأیید).",
)
def create_department_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	try:
		data = svc.create_department(db, business_id, payload, user_id=ctx.get_user_id())
	except ApiError:
		raise
	except ValueError as e:
		_handle_value_error(e)
	return _payroll_response(data, request)


# ─── پرسنل ──────────────────────────────────────────────────────────────────


@router.get(
	"/business/{business_id}/employees",
	summary="پرسنل حقوق",
	description="ابزار MCP: `list_payroll_employees`.",
)
def list_employees_endpoint(
	request: Request,
	business_id: int,
	include_inactive: bool = Query(False),
	department_id: Optional[int] = Query(None),
	limit: int = Query(100, ge=1, le=500),
	skip: int = Query(0, ge=0),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	items, total = svc.list_employees(
		db,
		business_id,
		include_inactive=include_inactive,
		department_id=department_id,
		limit=limit,
		skip=skip,
	)
	return _payroll_response({"items": items, "total": total}, request)


@router.post(
	"/business/{business_id}/employees",
	summary="ثبت پروفایل حقوق پرسنل",
	description="ابزار MCP: `create_payroll_employee` (نیازمند تأیید).",
)
def create_employee_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	try:
		data = svc.create_employee(db, business_id, payload, user_id=ctx.get_user_id())
	except ApiError:
		raise
	except ValueError as e:
		_handle_value_error(e)
	return _payroll_response(data, request)


# ─── دوره‌ها ─────────────────────────────────────────────────────────────────


@router.get(
	"/business/{business_id}/periods",
	summary="دوره‌های حقوق",
	description="ابزار MCP: `list_payroll_periods`.",
)
def list_periods_endpoint(
	request: Request,
	business_id: int,
	limit: int = Query(24, ge=1, le=120),
	skip: int = Query(0, ge=0),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	items, total = svc.list_periods(db, business_id, limit=limit, skip=skip)
	return _payroll_response({"items": items, "total": total}, request)


@router.post(
	"/business/{business_id}/periods",
	summary="ایجاد دوره حقوق",
	description="ابزار MCP: `create_payroll_period` (نیازمند تأیید).",
)
def create_period_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	try:
		data = svc.create_period(db, business_id, payload, user_id=ctx.get_user_id())
	except ApiError:
		raise
	except ValueError as e:
		_handle_value_error(e)
	return _payroll_response(data, request)


@router.post(
	"/business/{business_id}/periods/{period_id}/close",
	summary="بستن دوره حقوق",
	description="ابزار MCP: `close_payroll_period` (نیازمند تأیید).",
)
def close_period_endpoint(
	request: Request,
	business_id: int,
	period_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.close_period(db, business_id, period_id, user_id=ctx.get_user_id())
	return _payroll_response(data, request)


# ─── اجرای حقوق ─────────────────────────────────────────────────────────────


@router.get(
	"/business/{business_id}/runs",
	summary="اجراهای حقوق",
	description="ابزار MCP: `list_payroll_runs`.",
)
def list_runs_endpoint(
	request: Request,
	business_id: int,
	status: Optional[str] = Query(None),
	period_id: Optional[int] = Query(None),
	limit: int = Query(50, ge=1, le=200),
	skip: int = Query(0, ge=0),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	items, total = svc.list_runs(
		db, business_id, status=status, period_id=period_id, limit=limit, skip=skip
	)
	return _payroll_response({"items": items, "total": total}, request)


@router.get(
	"/business/{business_id}/runs/{run_id}",
	summary="جزئیات اجرای حقوق",
	description="ابزار MCP: `get_payroll_run`. PDF فیش جداست.",
)
def get_run_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.get_run(db, business_id, run_id)
	return _payroll_response(data, request)


@router.post(
	"/business/{business_id}/runs",
	summary="ایجاد اجرای حقوق",
	description="ابزار MCP: `create_payroll_run` (نیازمند تأیید).",
)
def create_run_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	try:
		data = svc.create_run(db, business_id, payload, user_id=ctx.get_user_id())
	except ApiError:
		raise
	except ValueError as e:
		_handle_value_error(e)
	return _payroll_response(data, request)


@router.put(
	"/business/{business_id}/runs/{run_id}",
	summary="ویرایش اجرای حقوق",
	description="ابزار MCP: `update_payroll_run` (نیازمند تأیید).",
)
def update_run_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	try:
		data = svc.update_run(db, business_id, run_id, payload, user_id=ctx.get_user_id())
	except ApiError:
		raise
	except ValueError as e:
		_handle_value_error(e)
	return _payroll_response(data, request)


@router.delete(
	"/business/{business_id}/runs/{run_id}",
	summary="حذف پیش‌نویس اجرای حقوق",
	description="ابزار MCP: `delete_payroll_run` (نیازمند تأیید).",
)
def delete_run_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	svc.delete_run(db, business_id, run_id, user_id=ctx.get_user_id())
	return _payroll_response({"deleted": True}, request)


@router.post(
	"/business/{business_id}/runs/{run_id}/finalize",
	summary="قطعی‌سازی اجرای حقوق",
	description="ابزار MCP: `finalize_payroll_run` (نیازمند تأیید).",
)
def finalize_run_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.finalize_run(db, business_id, run_id, user_id=ctx.get_user_id())
	return _payroll_response(data, request)


@router.post(
	"/business/{business_id}/runs/{run_id}/cancel",
	summary="لغو اجرای حقوق",
	description="ابزار MCP: `cancel_payroll_run` (نیازمند تأیید).",
)
def cancel_run_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.cancel_run(db, business_id, run_id, user_id=ctx.get_user_id())
	return _payroll_response(data, request)


@router.post(
	"/business/{business_id}/runs/{run_id}/copy",
	summary="کپی اجرای حقوق",
	description="ابزار MCP: `copy_payroll_run` (نیازمند تأیید).",
)
def copy_run_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	payload: Dict[str, Any] = Body(default={}),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	try:
		data = svc.copy_run(db, business_id, run_id, payload, user_id=ctx.get_user_id())
	except ApiError:
		raise
	except ValueError as e:
		_handle_value_error(e)
	return _payroll_response(data, request)


@router.get(
	"/business/{business_id}/runs/{run_id}/payslip/pdf",
	summary="PDF فیش حقوق",
	description="خروجی باینری PDF است و در MCP ثبت نشده.",
)
async def payslip_pdf_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	line_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
):
	from weasyprint import HTML
	from weasyprint.text.fonts import FontConfiguration
	from app.services.pdf.template_renderer import load_farsi_font_data_uris, render_template

	locale = negotiate_locale(request.headers.get("Accept-Language"))
	is_fa = locale == "fa"
	calendar_type = getattr(request.state, "calendar_type", "jalali") or "jalali"
	ctx_data = svc.build_payslip_render_context(
		db, business_id, run_id, line_id=line_id, calendar_type=calendar_type
	)
	fa_reg, fa_bold = load_farsi_font_data_uris()
	html_content = render_template(
		"pdf/payroll/payslip.html",
		{
			**ctx_data,
			"is_fa": is_fa,
			"title_text": "فیش حقوق" if is_fa else "Payslip",
			"fa_font_url_regular": fa_reg,
			"fa_font_url_bold": fa_bold,
			"paper_size": "A4",
			"orientation": "portrait",
			"footer_text": ctx_data.get("run", {}).get("code") or "",
		},
	)
	pdf_bytes = HTML(string=html_content).write_pdf(font_config=FontConfiguration())
	suffix = f"_line_{line_id}" if line_id else ""
	filename = f"payslip_{run_id}{suffix}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
	return Response(
		content=pdf_bytes,
		media_type="application/pdf",
		headers={
			"Content-Disposition": f"attachment; filename={filename}",
			"Content-Length": str(len(pdf_bytes)),
			"Access-Control-Expose-Headers": "Content-Disposition",
		},
	)


@router.get(
	"/business/{business_id}/reports/department-summary",
	summary="خلاصه حقوق بر اساس بخش",
	description="ابزار MCP: `get_payroll_department_summary`.",
)
def department_summary_endpoint(
	request: Request,
	business_id: int,
	period_id: Optional[int] = Query(None),
	run_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.get_run_department_summary(db, business_id, period_id=period_id, run_id=run_id)
	return _payroll_response(data, request)


@router.get(
	"/business/{business_id}/reports/item-summary",
	summary="خلاصه اجزای حقوق",
	description="ابزار MCP: `get_payroll_item_summary`.",
)
def item_summary_report_endpoint(
	request: Request,
	business_id: int,
	period_id: Optional[int] = Query(None),
	run_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = reports_svc.get_item_summary_report(db, business_id, period_id=period_id, run_id=run_id)
	return _payroll_response(data, request)


@router.get(
	"/business/{business_id}/reports/employee-summary",
	summary="خلاصه حقوق پرسنل",
	description="ابزار MCP: `get_payroll_employee_summary`.",
)
def employee_summary_report_endpoint(
	request: Request,
	business_id: int,
	period_id: Optional[int] = Query(None),
	run_id: Optional[int] = Query(None),
	limit: int = Query(500, ge=1, le=2000),
	skip: int = Query(0, ge=0),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = reports_svc.get_employee_summary_report(
		db, business_id, period_id=period_id, run_id=run_id, limit=limit, skip=skip
	)
	return _payroll_response(data, request)


@router.get(
	"/business/{business_id}/reports/statutory-summary",
	summary="خلاصه کسور قانونی حقوق",
	description="ابزار MCP: `get_payroll_statutory_summary`.",
)
def statutory_summary_report_endpoint(
	request: Request,
	business_id: int,
	period_id: Optional[int] = Query(None),
	run_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = reports_svc.get_statutory_summary_report(db, business_id, period_id=period_id, run_id=run_id)
	return _payroll_response(data, request)


@router.get(
	"/business/{business_id}/reports/period-overview",
	summary="نمای کلی دوره‌های حقوق",
	description="ابزار MCP: `get_payroll_period_overview`.",
)
def period_overview_report_endpoint(
	request: Request,
	business_id: int,
	year: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = reports_svc.get_period_overview_report(db, business_id, year=year)
	return _payroll_response(data, request)


@router.get(
	"/business/{business_id}/employees/import/template",
	summary="قالب اکسل پرسنل حقوق",
	description="خروجی باینری Excel است و در MCP ثبت نشده.",
)
def employees_import_template_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
):
	_ = db  # گیت لایسنس در سرویس import
	content, filename = excel_svc.build_employees_import_template(db, business_id)
	return Response(
		content=content,
		media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
		headers={
			"Content-Disposition": f"attachment; filename={filename}",
			"Access-Control-Expose-Headers": "Content-Disposition",
		},
	)


@router.get(
	"/business/{business_id}/employees/export/excel",
	summary="خروجی اکسل پرسنل حقوق",
	description="خروجی باینری Excel است و در MCP ثبت نشده.",
)
def export_employees_excel_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
):
	content, filename = excel_svc.export_employees_excel(
		db,
		business_id,
		calendar_type=getattr(request.state, "calendar_type", "jalali") or "jalali",
	)
	return Response(
		content=content,
		media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
		headers={
			"Content-Disposition": f"attachment; filename={filename}",
			"Access-Control-Expose-Headers": "Content-Disposition",
		},
	)


@router.post(
	"/business/{business_id}/employees/import/excel",
	summary="ورود اکسل پرسنل حقوق",
	description="آپلود باینری Excel است و در MCP ثبت نشده.",
)
async def import_employees_excel_endpoint(
	request: Request,
	business_id: int,
	file: UploadFile = File(...),
	dry_run: bool = Query(True),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not file.filename or not str(file.filename).lower().endswith(".xlsx"):
		raise ApiError("INVALID_FILE", "فقط فایل‌های .xlsx پشتیبانی می‌شوند", http_status=400)
	content = await file.read()
	data = excel_svc.import_employees_from_excel(
		db, business_id, content, dry_run=dry_run, user_id=ctx.get_user_id()
	)
	return _payroll_response(data, request)


@router.get(
	"/business/{business_id}/runs/{run_id}/import/template",
	summary="قالب اکسل اجرای حقوق",
	description="خروجی باینری Excel است و در MCP ثبت نشده.",
)
def run_lines_import_template_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "operate")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
):
	content, filename = excel_svc.build_run_lines_import_template(db, business_id, run_id)
	return Response(
		content=content,
		media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
		headers={
			"Content-Disposition": f"attachment; filename={filename}",
			"Access-Control-Expose-Headers": "Content-Disposition",
		},
	)


@router.post(
	"/business/{business_id}/runs/{run_id}/import/excel",
	summary="ورود اکسل اجرای حقوق",
	description="آپلود باینری Excel است و در MCP ثبت نشده.",
)
async def import_run_lines_excel_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	file: UploadFile = File(...),
	dry_run: bool = Query(True),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not file.filename or not str(file.filename).lower().endswith(".xlsx"):
		raise ApiError("INVALID_FILE", "فقط فایل‌های .xlsx پشتیبانی می‌شوند", http_status=400)
	content = await file.read()
	data = excel_svc.import_run_lines_from_excel(
		db, business_id, run_id, content, dry_run=dry_run, user_id=ctx.get_user_id()
	)
	return _payroll_response(data, request)


@router.post(
	"/business/{business_id}/runs/{run_id}/approve",
	summary="تأیید اجرای حقوق",
	description="ابزار MCP: `approve_payroll_run` (نیازمند تأیید).",
)
def approve_run_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "approve")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.approve_run(db, business_id, run_id, user_id=ctx.get_user_id())
	return _payroll_response(data, request)


@router.post(
	"/business/{business_id}/runs/{run_id}/reject",
	summary="رد اجرای حقوق",
	description="ابزار MCP: `reject_payroll_run` (نیازمند تأیید).",
)
def reject_run_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	payload: Dict[str, Any] = Body(default={}),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "approve")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	reason = payload.get("reason") if isinstance(payload, dict) else None
	data = svc.reject_run(db, business_id, run_id, user_id=ctx.get_user_id(), reason=reason)
	return _payroll_response(data, request)


@router.post(
	"/business/{business_id}/runs/{run_id}/post",
	summary="ثبت سند حقوق در حسابداری",
	description="ابزار MCP: `post_payroll_run_to_accounting` (نیازمند تأیید).",
)
def post_run_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "post")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.post_run_to_accounting(db, business_id, run_id, user_id=ctx.get_user_id())
	return _payroll_response(data, request)


@router.post(
	"/business/{business_id}/runs/{run_id}/post-payment",
	summary="ثبت پرداخت اجرای حقوق",
	description="ابزار MCP: `post_payroll_run_payment` (نیازمند تأیید).",
)
def post_payment_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "post")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	payment_account_id = payload.get("payment_account_id")
	if payment_account_id is None:
		raise ApiError("PAYMENT_ACCOUNT_REQUIRED", "payment_account_id الزامی است.", http_status=400)
	data = svc.post_run_payment(
		db, business_id, run_id, ctx.get_user_id(), int(payment_account_id)
	)
	return _payroll_response(data, request)


@router.put(
	"/business/{business_id}/employees/{employee_id}",
	summary="ویرایش پروفایل حقوق پرسنل",
	description="ابزار MCP: `update_payroll_employee` (نیازمند تأیید).",
)
def update_employee_endpoint(
	request: Request,
	business_id: int,
	employee_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	try:
		data = svc.update_employee(db, business_id, employee_id, payload, user_id=ctx.get_user_id())
	except ApiError:
		raise
	except ValueError as e:
		_handle_value_error(e)
	return _payroll_response(data, request)


@router.put(
	"/business/{business_id}/departments/{department_id}",
	summary="ویرایش بخش حقوق",
	description="ابزار MCP: `update_payroll_department` (نیازمند تأیید).",
)
def update_department_endpoint(
	request: Request,
	business_id: int,
	department_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("payroll", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	try:
		data = svc.update_department(db, business_id, department_id, payload, user_id=ctx.get_user_id())
	except ApiError:
		raise
	except ValueError as e:
		_handle_value_error(e)
	return _payroll_response(data, request)
