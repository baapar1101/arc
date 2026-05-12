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

router = APIRouter(prefix="/basalam", tags=["یکپارچه‌سازی"])


def _ensure_plugin(db: Session, business_id: int) -> None:
    if not check_basalam_plugin_active(db, business_id):
        raise ApiError(
            "BASALAM_PLUGIN_NOT_ACTIVE",
            "Basalam plugin is not active.",
            http_status=403,
            details={"plugin_code": "basalam_connector"},
        )


@router.get("/business/{business_id}/settings")
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


@router.put("/business/{business_id}/settings")
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


@router.post("/business/{business_id}/sync/orders")
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


@router.post("/business/{business_id}/sync/products")
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


@router.post("/business/{business_id}/sync/products/publish")
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


@router.post("/business/{business_id}/sync/products/pull")
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


@router.post("/business/{business_id}/sync/products/push/incremental")
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


@router.post("/business/{business_id}/sync/products/publish/retry")
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


@router.get("/business/{business_id}/sync/products/conflicts")
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


@router.delete("/business/{business_id}/sync/products/conflicts")
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


@router.post("/business/{business_id}/sync/products/conflicts/resolve")
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


@router.post("/business/{business_id}/sync/payments/unverified")
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


@router.post("/business/{business_id}/sync/chats/inbound")
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


@router.post("/business/{business_id}/chats/{conversation_id}/reply")
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


@router.post("/webhook/{business_id}")
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
