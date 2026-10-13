from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Body, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.services.tax_provider_service import (
    get_provider_credential,
    save_provider_credential,
    serialize_provider_credential,
    test_provider_connection,
)

router = APIRouter(prefix="/admin/tax-providers", tags=["مدیریت ارائه‌دهندگان مالیاتی"])


def _require_admin(ctx: AuthContext) -> None:
    if not (ctx.is_superadmin() or ctx.has_app_permission("system_settings")):
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند ارائه‌دهندگان مالیاتی را مدیریت کند.", http_status=403)


@router.get("/fanava")
def get_fanava_settings(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    return success_response(serialize_provider_credential(get_provider_credential(db)), request)


@router.put("/fanava")
def put_fanava_settings(
    request: Request,
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    credential = save_provider_credential(db, payload)
    db.commit()
    db.refresh(credential)
    return success_response(serialize_provider_credential(credential), request, "تنظیم فن‌آوا ذخیره شد.")


@router.post("/fanava/test-connection")
def test_fanava_settings(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    data = test_provider_connection(db)
    return success_response(data, request, "اتصال خواندنی فن‌آوا موفق بود.")
