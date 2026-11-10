"""Basalam marketplace plugin APIs."""

from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Header, Path, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.basalam_plugin_dependency import check_basalam_plugin_active
from app.core.i18n import locale_dependency
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import ApiError, success_response
from app.services import basalam_integration_service as basalam_svc
from app.services import basalam_reports_service as basalam_reports
from app.services.basalam_observability import get_basalam_metrics_summary

router = APIRouter(prefix="/basalam", tags=["یکپارچه‌سازی"])


def _ensure_plugin(db: Session, business_id: int) -> None:
    if not check_basalam_plugin_active(db, business_id):
        raise ApiError(
            "BASALAM_PLUGIN_NOT_ACTIVE",
            "Basalam plugin is not active.",
            http_status=403,
            details={"plugin_code": "basalam_connector"},
        )


@router.get(
    "/observability/metrics-summary",
    summary="متریک مشاهده‌پذیری باسلام",
    description="ابزار MCP: `get_basalam_overview`.",
)
def basalam_observability_metrics_summary(
    request: Request,
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
) -> Dict[str, Any]:
    """شمارندهٔ تجمیعی عملیات باسلام (Redis). نیازمند دسترسی مدیر سیستم یا سوپرادمین."""
    if not _ctx.has_app_permission("system_settings"):
        raise ApiError(
            "FORBIDDEN",
            "برای مشاهدهٔ متریک‌های باسلام نیاز به دسترسی مدیر سیستم است.",
            http_status=403,
        )
    return success_response(get_basalam_metrics_summary(), request)


@router.get(
    "/business/{business_id}/currency-readiness",
    summary="آمادگی ارز باسلام",
    description="واحد پولی باسلام را با ارز پایه کسب‌وکار مقایسه می‌کند. ابزار MCP: get_basalam_currency_readiness.",
)
def get_basalam_currency_readiness(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "view")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.get_basalam_currency_readiness(db, business_id)
    return success_response(data, request)


@router.get(
    "/business/{business_id}/reports/overview",
    summary="گزارش کلی باسلام",
    description="ابزار MCP: `get_basalam_overview`.",
)
def basalam_reports_overview(
    request: Request,
    business_id: int = Path(..., gt=0),
    chart_days: int = Query(90, ge=7, le=366),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("reports", "view")),
    ____: None = Depends(require_business_permission_dep("basalam", "view")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_reports.get_overview(db, business_id, chart_days=chart_days)
    return success_response(data, request)


@router.get(
    "/business/{business_id}/reports/synced-invoices",
    summary="فاکتورهای همگام باسلام",
    description="ابزار MCP: `list_basalam_synced_invoices`.",
)
def basalam_reports_synced_invoices(
    request: Request,
    business_id: int = Path(..., gt=0),
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    skip: int = Query(0, ge=0),
    take: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("reports", "view")),
    ____: None = Depends(require_business_permission_dep("basalam", "view")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    df = basalam_reports.parse_report_date(date_from)
    dt = basalam_reports.parse_report_date(date_to)
    data = basalam_reports.list_synced_invoices(db, business_id, date_from=df, date_to=dt, skip=skip, take=take)
    return success_response(data, request)


@router.get(
    "/business/{business_id}/reports/dead-letter",
    summary="صف مرده باسلام",
    description="ابزار MCP: `list_basalam_dead_letter`.",
)
def basalam_reports_dead_letter(
    request: Request,
    business_id: int = Path(..., gt=0),
    item_type: Optional[str] = Query(None),
    limit: int = Query(100, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("reports", "view")),
    ____: None = Depends(require_business_permission_dep("basalam", "view")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_reports.list_dead_letter_for_report(
        db, business_id, item_type=item_type, limit=limit, offset=offset
    )
    return success_response(data, request)


@router.get(
    "/business/{business_id}/reports/product-conflicts",
    summary="تعارض کالای باسلام",
    description="ابزار MCP: `list_basalam_product_conflicts`.",
)
def basalam_reports_product_conflicts(
    request: Request,
    business_id: int = Path(..., gt=0),
    conflict_type: Optional[str] = Query(None),
    direction: Optional[str] = Query(None),
    search: Optional[str] = Query(None),
    sort_by: str = Query("created_at"),
    sort_dir: str = Query("desc"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("reports", "view")),
    ____: None = Depends(require_business_permission_dep("basalam", "view")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_reports.list_product_conflicts_for_report(
        db,
        business_id,
        conflict_type=conflict_type,
        direction=direction,
        search=search,
        sort_by=sort_by,
        sort_dir=sort_dir,
        limit=limit,
        offset=offset,
    )
    return success_response(data, request)


@router.get(
    "/business/{business_id}/settings",
    summary="تنظیمات باسلام",
    description="پرچم همگام، استراتژی تعارض و وضعیت کلید API (در MCP ماسک می‌شود). ابزار MCP: get_basalam_settings.",
)
def get_basalam_settings(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "view")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.get_settings(db, business_id)
    return success_response(data, request)


@router.put(
    "/business/{business_id}/settings",
    summary="ذخیره تنظیمات باسلام",
    description="فعال‌سازی همگام سفارش/کالا و استراتژی تعارض. توکن از MCP پذیرفته نمی‌شود. ابزار MCP: update_basalam_settings.",
)
def put_basalam_settings(
    request: Request,
    business_id: int = Path(..., gt=0),
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "manage")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.update_settings(db, business_id, payload or {})
    return success_response(data, request)


@router.post(
    "/business/{business_id}/sync/orders",
    summary="همگام‌سازی دستی سفارش باسلام",
    description="بدنه باید آرایه orders داشته باشد. فاکتور فروش طبق تنظیم ساخته می‌شود. ابزار MCP: sync_basalam_orders.",
)
def manual_sync_basalam_orders(
    request: Request,
    business_id: int = Path(..., gt=0),
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "sync")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.manual_sync_orders(db, business_id, payload or {}, user_id=_ctx.get_user_id())
    return success_response(data, request)


@router.post(
    "/business/{business_id}/sync/products",
    summary="همگام کالاهای باسلام",
    description="ابزار MCP: `sync_basalam_products` (نیازمند تأیید).",
)
def manual_sync_basalam_products(
    request: Request,
    business_id: int = Path(..., gt=0),
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "sync")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.manual_sync_products(db, business_id, payload or {}, user_id=_ctx.get_user_id())
    return success_response(data, request)


@router.post(
    "/business/{business_id}/sync/products/publish",
    summary="انتشار کالاهای باسلام",
    description="ابزار MCP: `publish_basalam_products` (نیازمند تأیید).",
)
def publish_basalam_products(
    request: Request,
    business_id: int = Path(..., gt=0),
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "sync")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.publish_products_to_basalam(db, business_id, payload or {}, user_id=_ctx.get_user_id())
    return success_response(data, request)


@router.post(
    "/business/{business_id}/sync/products/pull",
    summary="کشیدن کالا از باسلام",
    description="ابزار MCP: `pull_basalam_products` (نیازمند تأیید).",
)
def pull_basalam_products(
    request: Request,
    business_id: int = Path(..., gt=0),
    payload: Dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "sync")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.pull_products_from_basalam(db, business_id, payload or {}, user_id=_ctx.get_user_id())
    return success_response(data, request)


@router.post(
    "/business/{business_id}/sync/products/push/incremental",
    summary="ارسال تدریجی کالا به باسلام",
    description="ابزار MCP: `push_basalam_products_incremental` (نیازمند تأیید).",
)
def push_basalam_products_incremental(
    request: Request,
    business_id: int = Path(..., gt=0),
    payload: Dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "sync")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.push_products_incremental(db, business_id, payload or {}, user_id=_ctx.get_user_id())
    return success_response(data, request)


@router.post(
    "/business/{business_id}/sync/products/publish/retry",
    summary="تلاش مجدد انتشار کالای باسلام",
    description="انتشار مجدد کالاهای ناموفق صف. ابزار MCP: retry_basalam_product_publish.",
)
def retry_basalam_products_publish(
    request: Request,
    business_id: int = Path(..., gt=0),
    payload: Dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "sync")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.retry_failed_product_publishes(db, business_id, payload or {}, user_id=_ctx.get_user_id())
    return success_response(data, request)


@router.get(
    "/business/{business_id}/sync/products/conflicts",
    summary="لیست تعارض کالای باسلام",
    description="ابزار MCP: `list_basalam_product_conflicts`.",
)
def list_basalam_product_conflicts(
    request: Request,
    business_id: int = Path(..., gt=0),
    conflict_type: Optional[str] = Query(None),
    direction: Optional[str] = Query(None),
    search: Optional[str] = Query(None),
    sort_by: Optional[str] = Query("created_at"),
    sort_dir: Optional[str] = Query("desc"),
    limit: int = Query(25, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "sync")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.list_product_conflicts(
        db,
        business_id,
        conflict_type=conflict_type,
        direction=direction,
        search=search,
        sort_by=sort_by,
        sort_dir=sort_dir,
        limit=limit,
        offset=offset,
    )
    return success_response(data, request)


@router.delete(
    "/business/{business_id}/sync/products/conflicts",
    summary="پاک کردن تعارض کالای باسلام",
    description="همه تعارض‌های کالای باسلام همین کسب‌وکار را حذف می‌کند. ابزار MCP: clear_basalam_product_conflicts.",
)
def clear_basalam_product_conflicts(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "sync")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.clear_product_conflicts(db, business_id)
    return success_response(data, request)


@router.post(
    "/business/{business_id}/sync/products/conflicts/resolve",
    summary="رفع تعارض کالای باسلام",
    description="ابزار MCP: `resolve_basalam_product_conflicts` (نیازمند تأیید).",
)
def resolve_basalam_product_conflicts(
    request: Request,
    business_id: int = Path(..., gt=0),
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "sync")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.resolve_product_conflicts(db, business_id, payload or {}, user_id=_ctx.get_user_id())
    return success_response(data, request)


@router.post(
    "/business/{business_id}/sync/payments/unverified",
    summary="همگام پرداخت تأییدنشده باسلام",
    description="پرداخت‌های تأییدنشده را همگام می‌کند. ابزار MCP: sync_basalam_unverified_payments.",
)
def sync_basalam_unverified_payments(
    request: Request,
    business_id: int = Path(..., gt=0),
    payload: Dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "sync")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    verify_remote = payload.get("verify_remote")
    data = basalam_svc.sync_unverified_payments(
        db=db,
        business_id=business_id,
        user_id=_ctx.get_user_id(),
        verify_remote=bool(verify_remote) if verify_remote is not None else None,
    )
    return success_response(data, request)


@router.get(
    "/business/{business_id}/sync/dead-letter",
    summary="لیست صف مرده همگام باسلام",
    description="ابزار MCP: `list_basalam_dead_letter`.",
)
def list_basalam_sync_dead_letter(
    request: Request,
    business_id: int = Path(..., gt=0),
    item_type: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "sync")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.list_sync_dead_letter(
        db,
        business_id,
        limit=limit,
        offset=offset,
        item_type=item_type,
    )
    return success_response(data, request)


@router.post(
    "/business/{business_id}/sync/dead-letter/clear",
    summary="پاک کردن صف مرده باسلام",
    description="بدنه باید all=true یا dlq_ids داشته باشد. ابزار MCP: clear_basalam_dead_letter.",
)
def clear_basalam_sync_dead_letter(
    request: Request,
    business_id: int = Path(..., gt=0),
    payload: Dict[str, Any] = Body(default_factory=dict),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "manage")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    body = payload or {}
    if body.get("all") is True:
        data = basalam_svc.clear_sync_dead_letter(db, business_id, mode="all")
    elif isinstance(body.get("dlq_ids"), list):
        data = basalam_svc.clear_sync_dead_letter(db, business_id, mode="ids", dlq_ids=body.get("dlq_ids"))
    else:
        raise ApiError(
            "BASALAM_DLQ_CLEAR_PAYLOAD",
            'Body must include "all": true or "dlq_ids": [...].',
            http_status=400,
        )
    return success_response(data, request)


@router.post(
    "/business/{business_id}/sync/chats/inbound",
    summary="همگام پیام ورودی چت باسلام",
    description="پیام‌های ورودی باسلام را به کسب‌وکار می‌آورد. ابزار MCP: sync_basalam_inbound_chats.",
)
async def sync_basalam_inbound_chats(
    request: Request,
    business_id: int = Path(..., gt=0),
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "sync")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = basalam_svc.sync_inbound_chat_messages(
        db=db,
        business_id=business_id,
        payload=payload or {},
        user_id=_ctx.get_user_id(),
    )
    return success_response(data, request)


@router.post(
    "/business/{business_id}/chats/{conversation_id}/reply",
    summary="پاسخ به گفتگوی باسلام",
    description="ارسال متن پاسخ به گفتگوی متعلق به همین کسب‌وکار. ابزار MCP: reply_basalam_chat.",
)
async def send_basalam_chat_reply(
    request: Request,
    business_id: int = Path(..., gt=0),
    conversation_id: int = Path(..., gt=0),
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    _ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(locale_dependency),
    __: None = Depends(require_business_access_dep),
    ___: None = Depends(require_business_permission_dep("basalam", "manage")),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    data = await basalam_svc.send_chat_reply_to_basalam(
        db=db,
        business_id=business_id,
        conversation_id=conversation_id,
        body=str(payload.get("body") or payload.get("text") or ""),
        user_id=_ctx.get_user_id(),
        basalam_chat_id=payload.get("chat_id"),
    )
    return success_response(data, request)


@router.post(
    "/webhook/{business_id}",
    summary="وب‌هوک باسلام",
    description="وب‌هوک عمومی است و در MCP ثبت نشده.",
)
async def basalam_webhook(
    request: Request,
    business_id: int = Path(..., gt=0),
    x_basalam_signature: Optional[str] = Header(None),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    _ensure_plugin(db, business_id)
    payload = await request.json()
    raw_body = await request.body()
    data = basalam_svc.process_webhook(
        db=db,
        business_id=business_id,
        payload=payload if isinstance(payload, dict) else {},
        raw_body=raw_body,
        signature=x_basalam_signature,
        user_id=None,
    )
    return success_response(data, request)
