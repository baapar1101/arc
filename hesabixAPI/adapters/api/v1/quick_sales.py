from __future__ import annotations

import json
import logging
import os
import re
from datetime import date, datetime
from typing import Any, Dict

from fastapi import APIRouter, Body, Depends, Request, Response
from sqlalchemy.orm import Session

from adapters.db.models.person import PersonType
from adapters.db.models.document import Document
from adapters.db.models.quick_sales_settings import QuickSalesSetting
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import (
    has_business_permission_for_business,
    require_business_access_dep,
    require_business_permission_dep,
    require_invoice_type_permission_from_payload_dep,
    user_can_change_invoice_unit_price,
)
from app.core.responses import ApiError, success_response
from app.services.quick_sale_invoice_job_service import (
    enqueue_quick_sale_invoice,
    find_quick_sale_invoice,
    get_quick_sale_invoice_job,
    list_quick_sale_invoice_jobs,
    serialize_quick_sale_job,
)
from app.services.quick_sales_service import (
    create_quick_sales_payment_button,
    delete_quick_sales_payment_button,
    get_configured_anonymous_customer,
    get_or_create_anonymous_customer,
    get_quick_sales_customer_balance,
    get_quick_sales_settings,
    list_quick_sales_payment_default_shortcuts,
    list_quick_sales_payment_buttons,
    reorder_quick_sales_payment_buttons,
    set_quick_sales_payment_default_shortcuts,
    set_quick_sales_payment_button_shortcut,
    set_quick_sales_payment_button_shortcuts,
    update_quick_sales_payment_button,
    update_quick_sales_settings,
)

logger = logging.getLogger(__name__)


router = APIRouter(prefix="/businesses/{business_id}/quick-sales", tags=["quick-sales"])


def _anonymous_customer_data(customer) -> dict:
    person_types = []
    if customer.person_types:
        try:
            parsed_types = json.loads(customer.person_types)
            person_types = parsed_types if isinstance(parsed_types, list) else []
        except (json.JSONDecodeError, TypeError) as exc:
            logger.warning(
                "Failed to parse person_types for customer %s: %s",
                customer.id,
                exc,
            )
    return {
        "id": customer.id,
        "name": customer.alias_name,
        "is_customer": PersonType.CUSTOMER.value in person_types,
    }


def _can(ctx: AuthContext, db: Session, business_id: int, section: str, action: str) -> bool:
    return has_business_permission_for_business(ctx, db, business_id, section, action)


def _body_date(value: Any) -> date:
    try:
        return datetime.fromisoformat(str(value)).date()
    except Exception as exc:
        raise ApiError("INVALID_DATE", "تاریخ اصلاح موجودی نامعتبر است", http_status=400) from exc


@router.post(
    "/invoices",
    summary="ثبت async فاکتور فروش سریع",
    description="درخواست را در outbox پایدار ذخیره می‌کند و شناسهٔ پیگیری برمی‌گرداند.",
)
def enqueue_quick_sale_invoice_endpoint(
	request: Request,
	response: Response,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(require_business_permission_dep("invoices", "add")),
	__: None = Depends(require_invoice_type_permission_from_payload_dep("add")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if os.getenv("HESABIX_BACKGROUND_JOBS_ENABLED", "true").strip().lower() in {"0", "false", "no", "off"}:
		raise ApiError(
			"QUICK_SALE_ASYNC_WORKER_DISABLED",
			"ثبت غیرهم‌زمان فروش سریع موقتاً در دسترس نیست؛ دوباره تلاش کنید.",
			http_status=503,
		)
	job_payload = dict(payload)
	extra = dict(job_payload.get("extra_info") or {})
	extra.pop("_stock_override", None)
	if extra.get("quick_sale") is not True or job_payload.get("invoice_type") != "invoice_sales":
		raise ApiError("QUICK_SALE_ASYNC_ONLY", "این مسیر فقط برای فاکتور فروش سریع است", http_status=400)
	request_id = str(extra.get("quick_sale_request_id") or "").strip()
	if not re.fullmatch(r"[A-Za-z0-9._:-]{16,160}", request_id):
		raise ApiError("QUICK_SALE_REQUEST_ID_REQUIRED", "شناسه یکتای درخواست فروش سریع نامعتبر است", http_status=400)
	job_payload["extra_info"] = extra

	requested_override = job_payload.pop("stock_override", None)
	if requested_override is not None:
		settings_row = (
			db.query(QuickSalesSetting)
			.filter(QuickSalesSetting.business_id == int(business_id))
			.first()
		)
		if not bool(settings_row and getattr(settings_row, "enable_stock_shortage_override", False)):
			raise ApiError("STOCK_OVERRIDE_DISABLED", "ثبت فروش با موجودی منفی در تنظیمات فروش سریع فعال نیست", http_status=403)
		if not _can(ctx, db, business_id, "inventory", "negative_stock_override"):
			raise ApiError("STOCK_OVERRIDE_FORBIDDEN", "مجوز ثبت یک‌باره موجودی منفی را ندارید", http_status=403)
		override = requested_override if isinstance(requested_override, dict) else {}
		reason_code = str(override.get("reason_code") or "").strip()
		reason_note = str(override.get("reason_note") or "").strip()
		request_token = str(override.get("request_token") or "").strip()
		if reason_code not in {"physical_stock_exists", "urgent_sale", "other"}:
			raise ApiError("STOCK_OVERRIDE_REASON_REQUIRED", "علت ثبت موجودی منفی را انتخاب کنید", http_status=400)
		if reason_code == "other" and not reason_note:
			raise ApiError("STOCK_OVERRIDE_NOTE_REQUIRED", "برای علت «سایر» توضیح وارد کنید", http_status=400)
		if not request_token or len(request_token) > 80:
			raise ApiError("STOCK_OVERRIDE_TOKEN_REQUIRED", "شناسه درخواست نامعتبر است", http_status=400)
		extra["_stock_override"] = {
			"authorized": True,
			"authorized_by_user_id": ctx.get_user_id(),
			"reason_code": reason_code,
			"reason_note": reason_note or None,
			"request_token": request_token,
			"authorized_at": datetime.utcnow().isoformat(),
		}
	job_payload["extra_info"] = extra

	from adapters.api.v1.invoices import _user_can_select_fx_rate_for_business

	job = enqueue_quick_sale_invoice(
		db,
		business_id=business_id,
		user_id=ctx.get_user_id(),
		request_id=request_id,
		payload=job_payload,
		user_can_select_fx_rate=_user_can_select_fx_rate_for_business(db, ctx, business_id),
		user_can_change_invoice_unit_price=user_can_change_invoice_unit_price(ctx, db, business_id),
	)
	response.status_code = 202 if job.status in {"queued", "processing"} else 200
	return success_response(serialize_quick_sale_job(job), request, message="QUICK_SALE_INVOICE_QUEUED")


@router.get(
	"/invoices/jobs/{request_id}",
	summary="وضعیت ثبت async فروش سریع",
)
def get_quick_sale_invoice_job_endpoint(
	request: Request,
	business_id: int,
	request_id: str,
	_: None = Depends(require_business_permission_dep("invoices", "add")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	job = get_quick_sale_invoice_job(
		db,
		business_id=business_id,
		user_id=ctx.get_user_id(),
		request_id=request_id,
	)
	if job is None:
		invoice = find_quick_sale_invoice(db, business_id, request_id)
		if invoice is not None and int(invoice.created_by_user_id or 0) == ctx.get_user_id():
			return success_response({
				"request_id": request_id,
				"status": "completed",
				"invoice_id": int(invoice.id),
				"invoice_code": invoice.code,
			}, request, message="QUICK_SALE_INVOICE_STATUS")
		raise ApiError("QUICK_SALE_JOB_NOT_FOUND", "درخواست ثبت فروش سریع پیدا نشد", http_status=404)
	return success_response(serialize_quick_sale_job(job), request, message="QUICK_SALE_INVOICE_STATUS")


@router.get(
	"/invoices/jobs",
	summary="فهرست فروش‌های سریع async جاری کاربر",
)
def list_quick_sale_invoice_jobs_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(require_business_permission_dep("invoices", "add")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	jobs = list_quick_sale_invoice_jobs(
		db,
		business_id=business_id,
		user_id=ctx.get_user_id(),
		limit=20,
	)
	return success_response(
		[serialize_quick_sale_job(job) for job in jobs],
		request,
		message="QUICK_SALE_INVOICE_JOBS",
	)


@router.get("/customer-balance", summary="مانده مشتری در فروش سریع")
def get_customer_balance_endpoint(
    request: Request,
    business_id: int,
    person_id: int,
    currency_id: int,
    as_of_date: date,
    _: None = Depends(
        require_business_permission_dep("quick_sales", "view_customer_balance")
    ),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = get_quick_sales_customer_balance(
        db,
        business_id=business_id,
        person_id=person_id,
        currency_id=currency_id,
        as_of_date=as_of_date,
    )
    return success_response(data, request)


@router.get(
    "/settings",
    summary="دریافت تنظیمات فروش سریع",
    description="دریافت تنظیمات فروش سریع یک کسب‌وکار شامل مشتری ناشناس، انبار، صندوق و سایر تنظیمات",
)
def get_quick_sales_settings_endpoint(
    request: Request,
    business_id: int,
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    """دریافت تنظیمات فروش سریع"""
    data = get_quick_sales_settings(db, business_id)
    return success_response(data, request)


@router.put(
    "/settings",
    summary="ویرایش تنظیمات فروش سریع",
    description="به‌روزرسانی تنظیمات فروش سریع یک کسب‌وکار",
)
def update_quick_sales_settings_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_permission_dep("settings", "business")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    """به‌روزرسانی تنظیمات فروش سریع"""
    data = update_quick_sales_settings(db, business_id, payload, ctx.get_user_id())
    return success_response(data, request, message="QUICK_SALES_SETTINGS_UPDATED")


@router.get(
    "/anonymous-customer",
    summary="دریافت مشتری ناشناس تنظیم‌شده",
)
def read_anonymous_customer_endpoint(
    request: Request,
    business_id: int,
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    customer = get_configured_anonymous_customer(db, business_id)
    return success_response(_anonymous_customer_data(customer), request)


@router.post(
    "/anonymous-customer",
    summary="دریافت یا ایجاد مشتری ناشناس",
    description="دریافت مشتری ناشناس پیش‌فرض یا ایجاد آن در صورت عدم وجود",
)
def get_anonymous_customer_endpoint(
    request: Request,
    business_id: int,
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    """دریافت یا ایجاد مشتری ناشناس"""
    try:
        customer = get_or_create_anonymous_customer(db, business_id)
        return success_response(_anonymous_customer_data(customer), request)
    except Exception as e:
        logger.error(f"Error in get_anonymous_customer_endpoint for business {business_id}: {type(e).__name__}: {str(e)}", exc_info=True)
        raise


@router.get("/payment-buttons", summary="دکمه‌های پرداخت فروش سریع")
def list_payment_buttons_endpoint(
    request: Request,
    business_id: int,
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = list_quick_sales_payment_buttons(db, business_id, ctx.get_user_id())
    return success_response(data, request)


@router.post("/payment-buttons", summary="ایجاد دکمه پرداخت فروش سریع")
def create_payment_button_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = create_quick_sales_payment_button(
        db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        payload=payload,
        can_manage_business=_can(ctx, db, business_id, "settings", "business"),
    )
    return success_response(data, request, message="QUICK_SALES_PAYMENT_BUTTON_CREATED")


@router.put("/payment-buttons/reorder", summary="تغییر ترتیب دکمه‌های پرداخت فروش سریع")
def reorder_payment_buttons_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = reorder_quick_sales_payment_buttons(
        db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        button_ids=list(payload.get("button_ids") or []),
        can_manage_business=_can(ctx, db, business_id, "settings", "business"),
    )
    return success_response(data, request, message="QUICK_SALES_PAYMENT_BUTTONS_REORDERED")


@router.put(
    "/payment-buttons/{button_key}/shortcut",
    summary="تنظیم میانبر دکمه پرداخت برای کاربر جاری",
)
def update_payment_button_shortcut_endpoint(
    request: Request,
    business_id: int,
    button_key: str,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    if "platforms" in payload:
        data = set_quick_sales_payment_button_shortcuts(
            db,
            business_id=business_id,
            user_id=ctx.get_user_id(),
            button_key=button_key,
            platforms=payload.get("platforms"),
        )
    else:
        data = set_quick_sales_payment_button_shortcut(
            db,
            business_id=business_id,
            user_id=ctx.get_user_id(),
            button_key=button_key,
            shortcut=payload.get("shortcut"),
            mode=payload.get("mode"),
            platform=str(payload.get("platform") or "windows").strip().lower(),
        )
    return success_response(data, request, message="QUICK_SALES_PAYMENT_SHORTCUT_UPDATED")


@router.get(
    "/payment-buttons/default-shortcuts",
    summary="فهرست میانبرهای پیش‌فرض دکمه‌های مشترک فروش سریع",
)
def list_payment_button_default_shortcuts_endpoint(
    request: Request,
    business_id: int,
    _: None = Depends(
        require_business_permission_dep(
            "quick_sales", "manage_default_payment_shortcuts"
        )
    ),
    db: Session = Depends(get_db),
) -> dict:
    data = list_quick_sales_payment_default_shortcuts(db, business_id)
    return success_response(data, request)


@router.put(
    "/payment-buttons/default-shortcuts",
    summary="ذخیره یکجای میانبرهای پیش‌فرض دکمه‌های مشترک فروش سریع",
)
def update_payment_button_default_shortcuts_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(
        require_business_permission_dep(
            "quick_sales", "manage_default_payment_shortcuts"
        )
    ),
    db: Session = Depends(get_db),
) -> dict:
    data = set_quick_sales_payment_default_shortcuts(
        db,
        business_id=business_id,
        items=payload.get("shortcuts"),
    )
    return success_response(
        data,
        request,
        message="QUICK_SALES_DEFAULT_PAYMENT_SHORTCUTS_UPDATED",
    )


@router.put("/payment-buttons/{button_id}", summary="ویرایش دکمه پرداخت فروش سریع")
def update_payment_button_endpoint(
    request: Request,
    business_id: int,
    button_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = update_quick_sales_payment_button(
        db,
        business_id=business_id,
        button_id=button_id,
        user_id=ctx.get_user_id(),
        payload=payload,
        can_manage_business=_can(ctx, db, business_id, "settings", "business"),
    )
    return success_response(data, request, message="QUICK_SALES_PAYMENT_BUTTON_UPDATED")


@router.delete("/payment-buttons/{button_id}", summary="حذف دکمه پرداخت فروش سریع")
def delete_payment_button_endpoint(
    request: Request,
    business_id: int,
    button_id: int,
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    delete_quick_sales_payment_button(
        db,
        business_id=business_id,
        button_id=button_id,
        user_id=ctx.get_user_id(),
        can_manage_business=_can(ctx, db, business_id, "settings", "business"),
    )
    return success_response({"id": button_id}, request, message="QUICK_SALES_PAYMENT_BUTTON_DELETED")


@router.get("/stock-discrepancies", summary="فهرست مغایرت‌های موجودی فروش سریع")
def list_stock_discrepancies_endpoint(
    request: Request,
    business_id: int,
    status: str | None = None,
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    if not _can(ctx, db, business_id, "inventory", "view"):
        raise ApiError("FORBIDDEN", "دسترسی مشاهده موجودی را ندارید", http_status=403)
    from app.services.inventory_discrepancy_service import list_cases

    return success_response(list_cases(db, business_id, status), request)


@router.post("/stock-corrections", summary="اصلاح کسری پیش از ثبت فروش سریع")
def create_stock_correction_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    request_token = str(payload.get("request_token") or "").strip()
    if not request_token:
        raise ApiError(
            "STOCK_CORRECTION_REQUEST_TOKEN_REQUIRED",
            "شناسه درخواست اصلاح موجودی الزامی است",
            http_status=400,
        )
    if payload.get("confirm_unexplained_physical_surplus") is not True:
        raise ApiError(
            "PHYSICAL_SURPLUS_CONFIRMATION_REQUIRED",
            "باید تأیید کنید که کالا واقعاً موجود است و منشأ ثبت‌نشده دیگری ندارد",
            http_status=400,
        )
    if not _can(ctx, db, business_id, "goods_expense_income", "add"):
        raise ApiError("FORBIDDEN", "مجوز ایجاد کالای درآمدشده را ندارید", http_status=403)
    from app.services.inventory_discrepancy_service import create_goods_income_correction

    result = create_goods_income_correction(
        db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        document_date=_body_date(payload.get("document_date")),
        lines=list(payload.get("lines") or []),
        description=str(payload.get("description") or "اصلاح کسری کشف‌شده در فروش سریع"),
        user_can_allocate=_can(ctx, db, business_id, "goods_expense_income", "allocate"),
        user_can_post=_can(ctx, db, business_id, "goods_expense_income", "post"),
        user_can_change_unit_cost=_can(ctx, db, business_id, "goods_expense_income", "change_unit_cost"),
        request_token=request_token,
    )
    db.commit()
    return success_response(result, request, message="QUICK_SALES_STOCK_CORRECTED")


@router.post("/stock-discrepancies/{case_id}/resolve", summary="رفع مغایرت با کالای درآمدشده")
def resolve_stock_discrepancy_endpoint(
    request: Request,
    business_id: int,
    case_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    if not _can(ctx, db, business_id, "goods_expense_income", "add"):
        raise ApiError("FORBIDDEN", "مجوز ایجاد کالای درآمدشده را ندارید", http_status=403)
    from app.services.inventory_discrepancy_service import resolve_case_with_goods_income

    result = resolve_case_with_goods_income(
        db,
        business_id=business_id,
        case_id=case_id,
        user_id=ctx.get_user_id(),
        lines=list(payload.get("lines") or []),
        document_date=_body_date(payload.get("document_date")),
        user_can_allocate=_can(ctx, db, business_id, "goods_expense_income", "allocate"),
        user_can_post=_can(ctx, db, business_id, "goods_expense_income", "post"),
        user_can_change_unit_cost=_can(ctx, db, business_id, "goods_expense_income", "change_unit_cost"),
    )
    return success_response(result, request, message="INVENTORY_DISCREPANCY_RESOLVED")
