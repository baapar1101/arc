from fastapi import APIRouter, Body, Depends, Path, Request
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from adapters.db.models.sepidar_live_import import SepidarImportSetting
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import ApiError, success_response
from app.services import sepidar_import_service as service

router = APIRouter(prefix="/sepidar-import", tags=["یکپارچه‌سازی"],
                   dependencies=[Depends(require_business_permission_dep("settings", "business"))])


class SettingsPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")
    host: str = Field(min_length=1, max_length=255)
    port: int = Field(default=1433, ge=1, le=65535)
    database_name: str = Field(min_length=1, max_length=255)
    username: str = Field(min_length=1, max_length=255)
    password: str | None = Field(default=None, max_length=2048)
    enabled: bool = False
    native_enabled: bool = False
    operations_enabled: bool = False
    plugins_enabled: bool = False
    sync_interval_minutes: int = Field(default=15, ge=1, le=1440)
    batch_size: int = Field(default=500, ge=50, le=5000)
    included_schemas: list[str] = Field(default_factory=list, max_length=1000)
    included_tables: list[str] = Field(default_factory=list, max_length=10000)


def _ensure_plugin(db: Session, business_id: int) -> None:
    if not service.plugin_active(db, business_id):
        raise ApiError("SEPIDAR_PLUGIN_NOT_ACTIVE", "افزونه ورود لایو سپیدار فعال نیست.", http_status=403)


@router.get('/business/{business_id}/plugin-coverage')
def plugin_coverage(request: Request, business_id: int = Path(..., gt=0), db: Session = Depends(get_db),
                    _: AuthContext = Depends(get_current_user), __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db,business_id)
    from app.services.sepidar_plugin_service import coverage
    return success_response(coverage(db,business_id),request)


@router.get("/business/{business_id}/settings")
def get_settings(request: Request, business_id: int = Path(..., gt=0), db: Session = Depends(get_db),
                 _: AuthContext = Depends(get_current_user), __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db, business_id)
    return success_response(service.public_setting(db.query(SepidarImportSetting).filter_by(business_id=business_id).first()), request)


@router.put("/business/{business_id}/settings")
def put_settings(request: Request, business_id: int = Path(..., gt=0), payload: SettingsPayload = Body(...),
                 db: Session = Depends(get_db), _: AuthContext = Depends(get_current_user),
                 __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db, business_id)
    try: row = service.save_setting(db, business_id, payload.model_dump(exclude_unset=True))
    except ValueError as exc: raise ApiError("INVALID_SEPIDAR_SETTINGS", str(exc), http_status=400)
    return success_response(service.public_setting(row), request)


@router.post("/business/{business_id}/test")
def test(request: Request, business_id: int = Path(..., gt=0), db: Session = Depends(get_db),
         _: AuthContext = Depends(get_current_user), __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db, business_id); row = db.query(SepidarImportSetting).filter_by(business_id=business_id).first()
    if not row: raise ApiError("SEPIDAR_NOT_CONFIGURED", "تنظیمات سپیدار ثبت نشده است.", http_status=400)
    try: data = service.test_connection(row)
    except Exception as exc: raise ApiError("SEPIDAR_CONNECTION_FAILED", service.error_message(exc), http_status=502)
    return success_response(data, request)


@router.get("/business/{business_id}/tables")
def tables(request: Request, business_id: int = Path(..., gt=0), db: Session = Depends(get_db),
           _: AuthContext = Depends(get_current_user), __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db, business_id); row = db.query(SepidarImportSetting).filter_by(business_id=business_id).first()
    if not row: raise ApiError("SEPIDAR_NOT_CONFIGURED", "تنظیمات سپیدار ثبت نشده است.", http_status=400)
    try: data = service.discover(row)
    except Exception as exc: raise ApiError("SEPIDAR_CONNECTION_FAILED", service.error_message(exc), http_status=502)
    return success_response({"items": data}, request)


@router.post("/business/{business_id}/sync")
def sync(request: Request, business_id: int = Path(..., gt=0), db: Session = Depends(get_db),
         _: AuthContext = Depends(get_current_user), __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db, business_id)
    try: data = service.run_sync(db, business_id)
    except service.SyncAlreadyRunning as exc: raise ApiError("SEPIDAR_SYNC_RUNNING", service.error_message(exc), http_status=409)
    except Exception as exc: raise ApiError("SEPIDAR_SYNC_FAILED", service.error_message(exc), http_status=502)
    return success_response(data, request)


@router.get("/business/{business_id}/runs")
def runs(request: Request, business_id: int = Path(..., gt=0), db: Session = Depends(get_db),
         _: AuthContext = Depends(get_current_user), __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db, business_id)
    return success_response({"items": service.recent_runs(db, business_id)}, request)


@router.post("/business/{business_id}/convert-native")
def convert_native(request: Request, business_id: int = Path(..., gt=0), db: Session = Depends(get_db),
                   _: AuthContext = Depends(get_current_user), __: None = Depends(require_business_access_dep)):
    _ensure_plugin(db, business_id)
    from app.services.sepidar_native_service import project_native
    try:
        with service._sync_lock(db, business_id):
            result = project_native(db, business_id)
    except service.SyncAlreadyRunning as exc:
        raise ApiError("SEPIDAR_SYNC_RUNNING", service.error_message(exc), http_status=409)
    except Exception as exc:
        raise ApiError("SEPIDAR_NATIVE_FAILED", service.error_message(exc), http_status=422)
    return success_response(result, request)
