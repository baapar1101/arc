"""
API مخزن ورک‌فلو: انتشار، لیست، جزئیات، نصب در کسب‌وکار.
"""

from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Query, Request
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from adapters.db.models.workflow import Workflow
from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import ApiError, format_datetime_fields, success_response
from adapters.api.v1.workflows import _attach_workflow_webhook_url
from app.services.workflow.workflow_marketplace_service import (
    get_package_for_owner,
    get_published_package,
    install_package_to_business,
    list_my_packages,
    list_published_packages,
    package_detail_dict,
    package_to_public_dict,
    publish_package,
)

router = APIRouter(tags=["workflow-marketplace"])


def _workflow_to_api_dict(workflow: Workflow, request: Request) -> Dict[str, Any]:
    """فقط ستون‌های مدل — بدون _sa_instance_state و بدون مقادیر غیر JSON."""
    st = workflow.status
    status_val = st.value if hasattr(st, "value") else st
    raw: Dict[str, Any] = {
        "id": workflow.id,
        "business_id": workflow.business_id,
        "name": workflow.name,
        "description": workflow.description,
        "status": status_val,
        "workflow_data": workflow.workflow_data,
        "settings": workflow.settings,
        "created_by_user_id": workflow.created_by_user_id,
        "created_at": workflow.created_at,
        "updated_at": workflow.updated_at,
    }
    return format_datetime_fields(raw, request)


@router.get("/workflows/marketplace/packages", summary="لیست ورک‌فلوهای منتشرشده در مخزن")
async def marketplace_list_packages(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    skip: int = Query(0, ge=0),
    take: int = Query(20, ge=1, le=100),
    search: Optional[str] = Query(None),
    tag: Optional[str] = Query(None),
) -> dict:
    rows, total = list_published_packages(db, skip=skip, take=take, search=search, tag=tag)
    items = [package_to_public_dict(db, p, request) for p in rows]
    return success_response(
        data={"items": items, "total": total, "skip": skip, "take": take},
        request=request,
        message="WORKFLOW_MARKETPLACE_LISTED",
    )


@router.get("/workflows/marketplace/packages/{package_id}", summary="جزئیات یک بسته (شامل گراف ورک‌فلو)")
async def marketplace_get_package(
    request: Request,
    package_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    p = get_published_package(db, package_id)
    if not p:
        raise ApiError("WORKFLOW_MARKETPLACE_PACKAGE_NOT_FOUND", "بسته یافت نشد یا منتشر نیست", http_status=404)
    data = package_detail_dict(db, p, request, include_graph=True)
    return success_response(data=data, request=request, message="WORKFLOW_MARKETPLACE_RETRIEVED")


@router.get(
    "/businesses/{business_id}/workflows/marketplace/my-packages",
    summary="بسته‌های منتشرشده توسط من در این کسب‌وکار",
)
@require_business_access("business_id")
async def marketplace_my_packages(
    request: Request,
    business_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    skip: int = Query(0, ge=0),
    take: int = Query(20, ge=1, le=100),
) -> dict:
    rows, total = list_my_packages(
        db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        skip=skip,
        take=take,
    )
    items = [package_to_public_dict(db, p, request) for p in rows]
    return success_response(
        data={"items": items, "total": total, "skip": skip, "take": take},
        request=request,
        message="WORKFLOW_MARKETPLACE_MY_LISTED",
    )


@router.get(
    "/businesses/{business_id}/workflows/marketplace/my-packages/{package_id}",
    summary="جزئیات بستهٔ منتشرشده توسط من (شامل گراف)",
)
@require_business_access("business_id")
async def marketplace_my_package_detail(
    request: Request,
    business_id: int,
    package_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    p = get_package_for_owner(db, package_id, business_id, ctx.get_user_id())
    if not p:
        raise ApiError("WORKFLOW_MARKETPLACE_PACKAGE_NOT_FOUND", "بسته یافت نشد", http_status=404)
    data = package_detail_dict(db, p, request, include_graph=True)
    return success_response(data=data, request=request, message="WORKFLOW_MARKETPLACE_RETRIEVED")


@router.post(
    "/businesses/{business_id}/workflows/marketplace/publish",
    summary="انتشار ورک‌فلو در مخزن",
)
@require_business_access("business_id")
async def marketplace_publish(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("workflows", "edit")),
) -> dict:
    workflow_id = body.get("workflow_id")
    if not workflow_id:
        raise ApiError("WORKFLOW_ID_REQUIRED", "شناسه ورک‌فلو الزامی است", http_status=400)

    try:
        pkg = publish_package(
            db,
            business_id=business_id,
            user_id=ctx.get_user_id(),
            workflow_id=int(workflow_id),
            title=str(body.get("title") or ""),
            short_description=body.get("short_description"),
            long_description=body.get("long_description"),
            tags=body.get("tags"),
            version_label=str(body.get("version_label") or "1.0.0"),
            changelog=body.get("changelog"),
        )
    except ValueError as e:
        code = str(e.args[0]) if e.args else "WORKFLOW_MARKETPLACE_PUBLISH_FAILED"
        if code == "WORKFLOW_NOT_FOUND":
            raise ApiError(code, "ورک‌فلو یافت نشد", http_status=404)
        if code == "WORKFLOW_MARKETPLACE_TITLE_INVALID":
            raise ApiError(code, "عنوان نامعتبر است", http_status=400)
        if code == "WORKFLOW_DATA_INVALID_AFTER_SANITIZE":
            raise ApiError(
                "WORKFLOW_DATA_INVALID",
                "پس از پاک‌سازی، ساختار ورک‌فلو نامعتبر است",
                http_status=400,
            )
        raise ApiError(code, "انتشار ناموفق بود", http_status=400)
    return success_response(
        data=package_to_public_dict(db, pkg, request),
        request=request,
        message="WORKFLOW_MARKETPLACE_PUBLISHED",
    )


@router.post(
    "/businesses/{business_id}/workflows/marketplace/install",
    summary="افزودن ورک‌فلو از مخزن به این کسب‌وکار",
)
@require_business_access("business_id")
async def marketplace_install(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("workflows", "add")),
) -> dict:
    package_id = body.get("package_id")
    if not package_id:
        raise ApiError("PACKAGE_ID_REQUIRED", "شناسه بسته الزامی است", http_status=400)
    try:
        wf, _inst = install_package_to_business(
            db,
            package_id=int(package_id),
            target_business_id=business_id,
            user_id=ctx.get_user_id(),
            new_name=body.get("name"),
        )
    except ValueError as e:
        code = str(e.args[0]) if e.args else "INSTALL_FAILED"
        if code == "WORKFLOW_MARKETPLACE_PACKAGE_NOT_FOUND":
            raise ApiError(code, "بسته یافت نشد", http_status=404)
        if code == "WORKFLOW_DATA_INVALID_IMPORT":
            raise ApiError("WORKFLOW_DATA_INVALID", "ساختار ورک‌فلو پس از نصب نامعتبر است", http_status=400)
        raise ApiError(code, "نصب ناموفق بود", http_status=400)
    except SQLAlchemyError:
        db.rollback()
        raise ApiError(
            "WORKFLOW_MARKETPLACE_INSTALL_DB",
            "ذخیره نصب ناموفق بود. در صورت تازه‌بودن قابلیت مخزن، migration پایگاه داده را اجرا کنید.",
            http_status=500,
        )

    data = _workflow_to_api_dict(wf, request)
    _attach_workflow_webhook_url(data, request)
    return success_response(data={"workflow": data}, request=request, message="WORKFLOW_MARKETPLACE_INSTALLED")
