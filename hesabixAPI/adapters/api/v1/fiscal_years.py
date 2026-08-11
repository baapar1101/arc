from typing import Dict, Any, Optional, List
from fastapi import APIRouter, Depends, Request, Body, Query
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field, validator
from datetime import date

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response, ApiError, format_datetime_fields
from app.core.i18n import apply_format, get_request_translator
from app.core.cache import get_cache
from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository
from app.services.year_end_closing_service import preview_year_end_closing, close_fiscal_year
from app.services.fiscal_year_rollback_service import (
    preview_current_fiscal_year_rollback,
    execute_current_fiscal_year_rollback,
)


router = APIRouter(prefix="/business", tags=["سال مالی", "حسابداری"])


def _date_ranges_overlap(a_start: date, a_end: date, b_start: date, b_end: date) -> bool:
	"""بازه‌های شامل [start, end]؛ همپوشانی واقعی یا تماس مرزی یک‌روزه."""
	return a_start <= b_end and a_end >= b_start


class ShareholderDistributionItem(BaseModel):
    """آیتم توزیع سود بین سهامدار"""
    person_id: int = Field(..., description="شناسه سهامدار")
    profit_amount: float = Field(..., description="مبلغ سود تخصیص یافته به این سهامدار")


class YearEndClosingRequest(BaseModel):
    new_fiscal_year_title: str = Field(..., min_length=1, max_length=255, description="عنوان سال مالی جدید")
    auto_create_opening_balance: bool = Field(default=True, description="ایجاد خودکار تراز افتتاحیه سال جدید")
    
    # مالیات
    tax_percentage: Optional[float] = Field(None, ge=0, le=100, description="درصد مالیات بر درآمد")
    tax_amount: Optional[float] = Field(None, ge=0, description="مبلغ مالیات بر درآمد")
    
    # تقسیم سود
    profit_distribution_percentage: Optional[float] = Field(None, ge=0, le=100, description="درصد سود تقسیم شده")
    profit_distribution_amount: Optional[float] = Field(None, ge=0, description="مبلغ سود تقسیم شده")
    shareholder_profit_account_id: Optional[int] = Field(None, description="شناسه حساب برای ثبت سود سهامداران")
    
    # سود انباشته سنواتی
    retained_earnings_from_previous_years: Optional[float] = Field(None, ge=0, description="سود یا زیان انباشته سنواتی")
    
    # تنظیمات
    auto_issue_person_balance_document: bool = Field(default=False, description="صدور خودکار سند توازن اشخاص")
    
    # تنظیمات سال مالی جدید
    new_fiscal_year_start_date: Optional[date] = Field(None, description="تاریخ شروع سال مالی جدید (در صورت عدم ارسال، به صورت خودکار محاسبه می‌شود)")
    new_fiscal_year_end_date: Optional[date] = Field(None, description="تاریخ پایان سال مالی جدید (در صورت عدم ارسال، به صورت خودکار محاسبه می‌شود)")
    inventory_valuation_method: str = Field(default="FIFO", description="روش ارزیابی انبار: FIFO, LIFO, WeightedAverage")
    
    # تقسیم سود بین سهامداران (اختیاری - اگر نباشد بر اساس درصد سهام محاسبه می‌شود)
    shareholder_distributions: Optional[List[ShareholderDistributionItem]] = Field(None, description="لیست توزیع سود بین سهامداران")

    # تقطیع سال مالی: پایان دورهٔ بستن و انتقال اسناد به سال جدید
    closing_fiscal_end_date: Optional[date] = Field(
        None,
        description="تاریخ پایان دورهٔ بستن (شامل). در صورت ارسال و زودتر بودن از پایان تقویمی سال، دوره تقطیع می‌شود.",
    )
    document_relocation_basis: str = Field(
        default="document_date",
        description="معیار «بعد از پایان دوره» برای انتقال سند به سال جدید: document_date یا registered_at",
    )
    move_post_cutoff_documents_to_new_fiscal_year: bool = Field(
        default=True,
        description="اگر true باشد، اسناد بعد از پایان دورهٔ بستن به سال مالی جدید منتقل می‌شوند",
    )
    
    @validator('tax_percentage', 'tax_amount')
    def validate_tax(cls, v, values):
        """بررسی اینکه فقط یکی از درصد یا مبلغ مالیات وارد شود"""
        if 'tax_percentage' in values and 'tax_amount' in values:
            if values.get('tax_percentage') is not None and values.get('tax_amount') is not None:
                raise ValueError('فقط یکی از درصد یا مبلغ مالیات باید وارد شود')
        return v
    
    @validator('profit_distribution_percentage', 'profit_distribution_amount')
    def validate_profit_distribution(cls, v, values):
        """بررسی اینکه فقط یکی از درصد یا مبلغ تقسیم سود وارد شود"""
        if 'profit_distribution_percentage' in values and 'profit_distribution_amount' in values:
            if values.get('profit_distribution_percentage') is not None and values.get('profit_distribution_amount') is not None:
                raise ValueError('فقط یکی از درصد یا مبلغ تقسیم سود باید وارد شود')
        return v
    
    @validator('inventory_valuation_method')
    def validate_inventory_method(cls, v):
        """بررسی اعتبار روش ارزیابی انبار"""
        valid_methods = ['FIFO', 'LIFO', 'WeightedAverage']
        if v not in valid_methods:
            raise ValueError(f'روش ارزیابی انبار باید یکی از {valid_methods} باشد')
        return v

    @validator('document_relocation_basis')
    def validate_document_relocation_basis(cls, v):
        allowed = {'document_date', 'registered_at'}
        vv = (v or 'document_date').strip().lower()
        if vv not in allowed:
            raise ValueError(f'document_relocation_basis باید یکی از {allowed} باشد')
        return vv


@router.get("/{business_id}/fiscal-years")
@require_business_access("business_id")
def list_fiscal_years(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "view")),
) -> Dict[str, Any]:
    cache = get_cache()
    cache_key = f"fiscal_years:{business_id}"

    if cache.enabled:
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(data=cached, request=request, message="FISCAL_YEARS_LIST_FETCHED")

    repo = FiscalYearRepository(db)

    items = repo.list_by_business(business_id)

    data = [
        {
            "id": fy.id,
            "title": fy.title,
            "start_date": fy.start_date,
            "end_date": fy.end_date,
            "is_current": fy.is_last,
        }
        for fy in items
    ]

    formatted = format_datetime_fields({"items": data}, request)

    if cache.enabled:
        cache.set(cache_key, formatted, ttl=120)

    return success_response(data=formatted, request=request, message="FISCAL_YEARS_LIST_FETCHED")


@router.get("/{business_id}/fiscal-years/current")
@require_business_access("business_id")
def get_current_fiscal_year(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "view")),
) -> Dict[str, Any]:
    repo = FiscalYearRepository(db)

    fy = repo.get_current_for_business(business_id)
    if not fy:
        return success_response(data=None, request=request, message="NO_CURRENT_FISCAL_YEAR")

    data = {
        "id": fy.id,
        "title": fy.title,
        "start_date": fy.start_date,
        "end_date": fy.end_date,
        "is_current": fy.is_last,
    }
    return success_response(data=format_datetime_fields(data, request), request=request, message="FISCAL_YEAR_CURRENT_FETCHED")


@router.get("/{business_id}/fiscal-years/{fiscal_year_id}/closing/preview")
@require_business_access("business_id")
def preview_year_end_closing_endpoint(
    request: Request,
    business_id: int,
    fiscal_year_id: int,
    closing_fiscal_end_date: Optional[date] = Query(
        None,
        description="تاریخ پایان دورهٔ بستن (شامل) برای پیش‌نمایش تقطیع؛ خالی = پایان تقویمی سال",
    ),
    document_relocation_basis: str = Query(
        "document_date",
        description="document_date یا registered_at",
    ),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "view")),
) -> Dict[str, Any]:
    """پیش‌نمایش بستن سال مالی"""
    try:
        preview_data = preview_year_end_closing(
            db,
            business_id,
            fiscal_year_id,
            closing_fiscal_end_date=closing_fiscal_end_date,
            document_relocation_basis=document_relocation_basis,
        )
        return success_response(
            data=format_datetime_fields(preview_data, request),
            request=request,
            message="YEAR_END_CLOSING_PREVIEW_FETCHED"
        )
    except ApiError as e:
        raise e
    except Exception as e:
        raise ApiError("PREVIEW_FAILED", f"خطا در پیش‌نمایش بستن سال مالی: {str(e)}", http_status=500)


@router.post("/{business_id}/fiscal-years/{fiscal_year_id}/close")
@require_business_access("business_id")
async def close_fiscal_year_endpoint(
    request: Request,
    business_id: int,
    fiscal_year_id: int,
    payload: YearEndClosingRequest = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "close")),
) -> Dict[str, Any]:
    """بستن سال مالی"""
    try:
        result = await close_fiscal_year(
            db=db,
            business_id=business_id,
            fiscal_year_id=fiscal_year_id,
            user_id=ctx.get_user_id(),
            new_fiscal_year_title=payload.new_fiscal_year_title,
            auto_create_opening_balance=payload.auto_create_opening_balance,
            # مالیات
            tax_percentage=payload.tax_percentage,
            tax_amount=payload.tax_amount,
            # تقسیم سود
            profit_distribution_percentage=payload.profit_distribution_percentage,
            profit_distribution_amount=payload.profit_distribution_amount,
            shareholder_profit_account_id=payload.shareholder_profit_account_id,
            # سود انباشته سنواتی
            retained_earnings_from_previous_years=payload.retained_earnings_from_previous_years,
            # تنظیمات
            auto_issue_person_balance_document=payload.auto_issue_person_balance_document,
            # تنظیمات سال مالی جدید
            new_fiscal_year_start_date=payload.new_fiscal_year_start_date,
            new_fiscal_year_end_date=payload.new_fiscal_year_end_date,
            inventory_valuation_method=payload.inventory_valuation_method,
            # تقسیم سود بین سهامداران (تبدیل از Pydantic model به dict)
            shareholder_distributions=[
                {"person_id": item.person_id, "profit_amount": item.profit_amount}
                for item in payload.shareholder_distributions
            ] if payload.shareholder_distributions else None,
            closing_fiscal_end_date=payload.closing_fiscal_end_date,
            document_relocation_basis=payload.document_relocation_basis,
            move_post_cutoff_documents_to_new_fiscal_year=payload.move_post_cutoff_documents_to_new_fiscal_year,
        )
        cache = get_cache()
        if cache.enabled:
            cache.delete(f"fiscal_years:{business_id}")
        return success_response(
            data=format_datetime_fields(result, request),
            request=request,
            message="FISCAL_YEAR_CLOSED_SUCCESSFULLY"
        )
    except ApiError as e:
        raise e
    except Exception as e:
        raise ApiError("CLOSING_FAILED", f"خطا در بستن سال مالی: {str(e)}", http_status=500)


class FiscalYearRollbackExecuteRequest(BaseModel):
    confirmation_token: str = Field(..., min_length=10, description="توکن بازگشتی از پیش‌نمایش")


@router.get("/{business_id}/fiscal-years/current/rollback/preview")
@require_business_access("business_id")
def preview_fiscal_year_rollback(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "rollback")),
) -> Dict[str, Any]:
    """پیش‌نمایش حذف سال مالی جاری و بازگشت به سال قبل"""
    translator = get_request_translator(request)
    try:
        data = preview_current_fiscal_year_rollback(db, business_id, ctx.get_user_id(), translator)
        return success_response(
            data=format_datetime_fields(data, request),
            request=request,
            message="FISCAL_YEAR_ROLLBACK_PREVIEW",
        )
    except ApiError:
        raise
    except Exception as e:
        template = translator.t(
            "ROLLBACK_PREVIEW_FAILED",
            default="Fiscal rollback preview failed. Check connectivity and try again. ({error})",
        )
        msg = apply_format(template, error=str(e))
        raise ApiError("ROLLBACK_PREVIEW_FAILED", msg, http_status=500)


@router.post("/{business_id}/fiscal-years/current/rollback/execute")
@require_business_access("business_id")
def execute_fiscal_year_rollback(
    request: Request,
    business_id: int,
    body: FiscalYearRollbackExecuteRequest = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "rollback")),
) -> Dict[str, Any]:
    """اجرای حذف سال مالی جاری و بازگشت به سال قبل"""
    translator = get_request_translator(request)
    try:
        data = execute_current_fiscal_year_rollback(
            db,
            business_id,
            ctx.get_user_id(),
            body.confirmation_token,
            translator,
            request=request,
        )
        return success_response(
            data=format_datetime_fields(data, request),
            request=request,
            message="FISCAL_YEAR_ROLLBACK_DONE",
        )
    except ApiError:
        raise
    except Exception as e:
        template = translator.t(
            "ROLLBACK_EXECUTE_FAILED",
            default="Fiscal rollback failed unexpectedly. If it persists, contact support. ({error})",
        )
        msg = apply_format(template, error=str(e))
        raise ApiError("ROLLBACK_EXECUTE_FAILED", msg, http_status=500)


class FiscalYearUpdateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=255, description="عنوان سال مالی")
    start_date: date = Field(..., description="تاریخ شروع سال مالی")
    end_date: date = Field(..., description="تاریخ پایان سال مالی")


class FiscalYearCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=255, description="عنوان سال مالی")
    start_date: date = Field(..., description="تاریخ شروع سال مالی")
    end_date: date = Field(..., description="تاریخ پایان سال مالی")
    set_as_current: bool = Field(
        default=False,
        description="اگر true باشد این سال جاری می‌شود؛ در غیر این صورت بدون تغییر is_last سال‌های موجود ایجاد می‌شود",
    )


@router.post("/{business_id}/fiscal-years")
@require_business_access("business_id")
def create_fiscal_year_endpoint(
    request: Request,
    business_id: int,
    payload: FiscalYearCreateRequest = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "edit")),
) -> Dict[str, Any]:
    """ایجاد سال مالی جدید (برای مهاجرت چندساله بدون بستن حسابداری)."""
    if payload.start_date >= payload.end_date:
        raise ApiError("INVALID_DATE_RANGE", "تاریخ شروع باید قبل از تاریخ پایان باشد", http_status=400)

    repo = FiscalYearRepository(db)
    all_fiscal = repo.list_by_business(business_id)
    for fy in all_fiscal:
        if _date_ranges_overlap(payload.start_date, payload.end_date, fy.start_date, fy.end_date):
            raise ApiError(
                "FISCAL_YEAR_RANGE_OVERLAP",
                f"بازهٔ انتخاب‌شده با سال مالی «{fy.title}» همپوشانی دارد.",
                http_status=400,
                details={
                    "conflicting_fiscal_year_id": fy.id,
                    "conflicting_start_date": fy.start_date.isoformat(),
                    "conflicting_end_date": fy.end_date.isoformat(),
                },
            )

    is_last = bool(payload.set_as_current) or len(all_fiscal) == 0
    if is_last and all_fiscal:
        for fy in all_fiscal:
            if fy.is_last:
                fy.is_last = False
                db.add(fy)
        db.flush()

    fiscal_year = repo.create_fiscal_year(
        business_id=business_id,
        title=payload.title,
        start_date=payload.start_date,
        end_date=payload.end_date,
        is_last=is_last,
    )

    cache = get_cache()
    if cache.enabled:
        cache.delete(f"fiscal_years:{business_id}")

    data = {
        "id": fiscal_year.id,
        "title": fiscal_year.title,
        "start_date": fiscal_year.start_date,
        "end_date": fiscal_year.end_date,
        "is_current": fiscal_year.is_last,
    }
    return success_response(
        data=format_datetime_fields(data, request),
        request=request,
        message="FISCAL_YEAR_CREATED_SUCCESSFULLY",
    )


class MigrationEnsureYearsRequest(BaseModel):
    years: List[FiscalYearCreateRequest] = Field(..., min_items=1)
    current_start_date: Optional[date] = Field(
        None,
        description="اگر مشخص شود، سالی که start_date برابر این مقدار است جاری می‌شود",
    )


# مسیرهای migration باید قبل از .../{fiscal_year_id}/set-current ثبت شوند؛
# وگرنه FastAPI مقدار "migration" را به‌عنوان fiscal_year_id می‌گیرد.
@router.post("/{business_id}/fiscal-years/migration/ensure")
@require_business_access("business_id")
def migration_ensure_fiscal_years(
    request: Request,
    business_id: int,
    payload: MigrationEnsureYearsRequest = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "edit")),
) -> Dict[str, Any]:
    """ایجاد/بازیابی دسته‌ای سال‌های مالی برای مهاجرت بدون بستن حسابداری."""
    repo = FiscalYearRepository(db)
    existing = repo.list_by_business(business_id)
    by_start = {fy.start_date: fy for fy in existing}

    created_count = 0
    reused_count = 0
    items_out: List[Dict[str, Any]] = []

    for y in sorted(payload.years, key=lambda x: x.start_date):
        if y.start_date >= y.end_date:
            raise ApiError("INVALID_DATE_RANGE", "تاریخ شروع باید قبل از تاریخ پایان باشد", http_status=400)
        found = by_start.get(y.start_date)
        if found is not None:
            reused_count += 1
            items_out.append(
                {
                    "id": found.id,
                    "title": found.title,
                    "start_date": found.start_date,
                    "end_date": found.end_date,
                    "is_current": found.is_last,
                }
            )
            continue

        for fy in existing:
            if _date_ranges_overlap(y.start_date, y.end_date, fy.start_date, fy.end_date):
                raise ApiError(
                    "FISCAL_YEAR_RANGE_OVERLAP",
                    f"بازهٔ «{y.title}» با سال مالی «{fy.title}» همپوشانی دارد.",
                    http_status=400,
                )

        is_first = len(existing) == 0 and created_count == 0
        fy_new = repo.create_fiscal_year(
            business_id=business_id,
            title=y.title,
            start_date=y.start_date,
            end_date=y.end_date,
            is_last=is_first,
            commit=False,
        )
        existing.append(fy_new)
        by_start[y.start_date] = fy_new
        created_count += 1
        items_out.append(
            {
                "id": fy_new.id,
                "title": fy_new.title,
                "start_date": fy_new.start_date,
                "end_date": fy_new.end_date,
                "is_current": fy_new.is_last,
            }
        )

    db.commit()

    current = repo.get_current_for_business(business_id)
    if payload.current_start_date is not None:
        target = by_start.get(payload.current_start_date)
        if target is None:
            raise ApiError(
                "FISCAL_YEAR_NOT_FOUND",
                "سال مالی با start_date درخواستی یافت نشد",
                http_status=404,
            )
        current = repo.set_current_for_business(business_id, int(target.id))
        for row in items_out:
            row["is_current"] = int(row["id"]) == int(current.id)

    cache = get_cache()
    if cache.enabled:
        cache.delete(f"fiscal_years:{business_id}")

    current_data = None
    if current is not None:
        current_data = {
            "id": current.id,
            "title": current.title,
            "start_date": current.start_date,
            "end_date": current.end_date,
            "is_current": current.is_last,
        }

    return success_response(
        data=format_datetime_fields(
            {
                "items": items_out,
                "created_count": created_count,
                "reused_count": reused_count,
                "current": current_data,
            },
            request,
        ),
        request=request,
        message="FISCAL_YEARS_ENSURED_FOR_MIGRATION",
    )


class MigrationSetCurrentRequest(BaseModel):
    fiscal_year_id: int = Field(..., gt=0)


@router.post("/{business_id}/fiscal-years/migration/set-current")
@require_business_access("business_id")
def migration_set_current_fiscal_year(
    request: Request,
    business_id: int,
    payload: MigrationSetCurrentRequest = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "edit")),
) -> Dict[str, Any]:
    """تعویض نرم سال جاری برای مهاجرت (سازگار با کلاینت Holoo2Hesabix)."""
    repo = FiscalYearRepository(db)
    fiscal_year = repo.set_current_for_business(business_id, int(payload.fiscal_year_id))
    cache = get_cache()
    if cache.enabled:
        cache.delete(f"fiscal_years:{business_id}")
    current_data = {
        "id": fiscal_year.id,
        "title": fiscal_year.title,
        "start_date": fiscal_year.start_date,
        "end_date": fiscal_year.end_date,
        "is_current": fiscal_year.is_last,
    }
    return success_response(
        data=format_datetime_fields({"current": current_data}, request),
        request=request,
        message="FISCAL_YEAR_SET_CURRENT_SUCCESSFULLY",
    )


@router.post("/{business_id}/fiscal-years/{fiscal_year_id}/set-current")
@require_business_access("business_id")
def set_current_fiscal_year_endpoint(
    request: Request,
    business_id: int,
    fiscal_year_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "edit")),
) -> Dict[str, Any]:
    """
    تعویض نرم سال مالی جاری (فقط is_last) بدون بستن سود و زیان.
    مناسب مهاجرت تاریخچه سال‌به‌سال (Holoo و مشابه).
    """
    repo = FiscalYearRepository(db)
    fiscal_year = repo.set_current_for_business(business_id, fiscal_year_id)

    cache = get_cache()
    if cache.enabled:
        cache.delete(f"fiscal_years:{business_id}")

    data = {
        "id": fiscal_year.id,
        "title": fiscal_year.title,
        "start_date": fiscal_year.start_date,
        "end_date": fiscal_year.end_date,
        "is_current": fiscal_year.is_last,
    }
    return success_response(
        data=format_datetime_fields(data, request),
        request=request,
        message="FISCAL_YEAR_SET_CURRENT_SUCCESSFULLY",
    )


@router.put("/{business_id}/fiscal-years/current")
@require_business_access("business_id")
def update_current_fiscal_year(
    request: Request,
    business_id: int,
    payload: FiscalYearUpdateRequest = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "edit")),
) -> Dict[str, Any]:
    """ویرایش یا ایجاد سال مالی جاری (اگر وجود نداشت، ایجاد می‌شود)"""
    repo = FiscalYearRepository(db)
    
    # بررسی اعتبار تاریخ‌ها
    if payload.start_date >= payload.end_date:
        raise ApiError("INVALID_DATE_RANGE", "تاریخ شروع باید قبل از تاریخ پایان باشد", http_status=400)

    all_fiscal = repo.list_by_business(business_id)
    exclude_id: Optional[int] = None

    # دریافت سال مالی جاری
    fiscal_year = repo.get_current_for_business(business_id)

    if fiscal_year:
        exclude_id = int(fiscal_year.id)
    for fy in all_fiscal:
        if exclude_id is not None and int(fy.id) == exclude_id:
            continue
        if _date_ranges_overlap(
            payload.start_date,
            payload.end_date,
            fy.start_date,
            fy.end_date,
        ):
            raise ApiError(
                "FISCAL_YEAR_RANGE_OVERLAP",
                f"بازهٔ انتخاب‌شده با سال مالی «{fy.title}» همپوشانی دارد.",
                http_status=400,
                details={
                    "conflicting_fiscal_year_id": fy.id,
                    "conflicting_start_date": fy.start_date.isoformat(),
                    "conflicting_end_date": fy.end_date.isoformat(),
                },
            )

    if fiscal_year:
        # اگر سال مالی جاری وجود داشت: به‌روزرسانی می‌کنیم
        # بررسی اینکه سال مالی متعلق به این کسب و کار است
        if int(fiscal_year.business_id) != int(business_id):
            raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی متعلق به این کسب‌وکار نیست", http_status=404)
        
        # به‌روزرسانی فیلدها
        fiscal_year.title = payload.title
        fiscal_year.start_date = payload.start_date
        fiscal_year.end_date = payload.end_date
        
        db.commit()
        db.refresh(fiscal_year)
        
        message = "FISCAL_YEAR_UPDATED_SUCCESSFULLY"
    else:
        # اگر سال مالی جاری وجود نداشت: ایجاد می‌کنیم
        fiscal_year = repo.create_fiscal_year(
            business_id=business_id,
            title=payload.title,
            start_date=payload.start_date,
            end_date=payload.end_date,
            is_last=True,  # سال مالی جدید به عنوان سال مالی جاری ایجاد می‌شود
        )
        message = "FISCAL_YEAR_CREATED_SUCCESSFULLY"

    cache = get_cache()
    if cache.enabled:
        cache.delete(f"fiscal_years:{business_id}")
    
    data = {
        "id": fiscal_year.id,
        "title": fiscal_year.title,
        "start_date": fiscal_year.start_date,
        "end_date": fiscal_year.end_date,
        "is_current": fiscal_year.is_last,
    }
    
    return success_response(
        data=format_datetime_fields(data, request),
        request=request,
        message=message
    )


