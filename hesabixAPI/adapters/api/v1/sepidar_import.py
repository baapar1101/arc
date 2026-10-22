from typing import Any

from fastapi import APIRouter, Body, Depends, Path, Request
from sqlalchemy.orm import Session

from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin
from adapters.db.models.sepidar_live_import import SepidarImportSetting
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access_dep
from app.core.responses import ApiError, success_response
from app.services import sepidar_import_service as service

router = APIRouter(prefix="/sepidar-import", tags=["یکپارچه‌سازی"])


def _ensure_plugin(db: Session, business_id: int) -> None:
    active = db.query(BusinessPlugin.id).join(MarketplacePlugin).filter(
        BusinessPlugin.business_id == business_id, BusinessPlugin.status == "active",
        MarketplacePlugin.code == "sepidar_live_import", MarketplacePlugin.is_active == True).first()
    if not active:
        raise ApiError("SEPIDAR_PLUGIN_NOT_ACTIVE", "افزونه ورود لایو سپیدار فعال نیست.", http_status=403)


@router.get("/business/{business_id}/settings")
def get_settings(request: Request, business_id: int = Path(..., gt=0), db: Session = Depends(get_db),
                 _: AuthContext = Depends(get_current_user), __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db, business_id)
    return success_response(service.public_setting(db.query(SepidarImportSetting).filter_by(business_id=business_id).first()), request)


@router.put("/business/{business_id}/settings")
def put_settings(request: Request, business_id: int = Path(..., gt=0), payload: dict[str, Any] = Body(...),
                 db: Session = Depends(get_db), _: AuthContext = Depends(get_current_user),
                 __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db, business_id)
    try: row = service.save_setting(db, business_id, payload)
    except ValueError as exc: raise ApiError("INVALID_SEPIDAR_SETTINGS", str(exc), http_status=400)
    return success_response(service.public_setting(row), request)


@router.post("/business/{business_id}/test")
def test(request: Request, business_id: int = Path(..., gt=0), db: Session = Depends(get_db),
         _: AuthContext = Depends(get_current_user), __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db, business_id); row = db.query(SepidarImportSetting).filter_by(business_id=business_id).first()
    if not row: raise ApiError("SEPIDAR_NOT_CONFIGURED", "تنظیمات سپیدار ثبت نشده است.", http_status=400)
    try: data = service.test_connection(row)
    except Exception as exc: raise ApiError("SEPIDAR_CONNECTION_FAILED", str(exc)[:500], http_status=502)
    return success_response(data, request)


@router.get("/business/{business_id}/tables")
def tables(request: Request, business_id: int = Path(..., gt=0), db: Session = Depends(get_db),
           _: AuthContext = Depends(get_current_user), __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db, business_id); row = db.query(SepidarImportSetting).filter_by(business_id=business_id).first()
    if not row: raise ApiError("SEPIDAR_NOT_CONFIGURED", "تنظیمات سپیدار ثبت نشده است.", http_status=400)
    return success_response({"items": service.discover(row)}, request)


@router.post("/business/{business_id}/sync")
def sync(request: Request, business_id: int = Path(..., gt=0), db: Session = Depends(get_db),
         _: AuthContext = Depends(get_current_user), __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db, business_id)
    try: data = service.run_sync(db, business_id)
    except Exception as exc: raise ApiError("SEPIDAR_SYNC_FAILED", str(exc)[:500], http_status=502)
    return success_response(data, request)


@router.get("/business/{business_id}/runs")
def runs(request: Request, business_id: int = Path(..., gt=0), db: Session = Depends(get_db),
         _: AuthContext = Depends(get_current_user), __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db, business_id)
    return success_response({"items": service.recent_runs(db, business_id)}, request)
