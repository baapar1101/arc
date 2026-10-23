from decimal import Decimal
from typing import Literal
from uuid import UUID
import base64
from datetime import datetime

from fastapi import APIRouter, Depends, Request, Query, UploadFile, File, Form
from fastapi.responses import Response
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy.orm import Session
from sqlalchemy import select
from adapters.db.models.api_key import ApiKey
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.services import platform_admin_service as service

router = APIRouter(prefix='/admin/platform', tags=['مدیریت پلتفرم'])
public_router = APIRouter(prefix='/platform', tags=['برند پلتفرم'])


def platform_admin(ctx: AuthContext = Depends(get_current_user)):
    # Never authorize by a client-supplied email; use the existing server role.
    if not ctx.is_superadmin():
        raise ApiError('FORBIDDEN', 'این بخش فقط برای مدیر ارشد پلتفرم است.', http_status=403)
    if ctx.db is not None:
        key = ctx.db.scalars(select(ApiKey).where(ApiKey.id == ctx.api_key_id).execution_options(populate_existing=True)).first()
        if not key or key.key_type != 'session' or key.revoked_at or (key.expires_at and key.expires_at <= datetime.utcnow()):
            raise ApiError('FORBIDDEN', 'مدیریت پلتفرم به نشست ورود مستقیم مدیر نیاز دارد.', http_status=403)
    return ctx


class Reason(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    reason: str = Field(min_length=5, max_length=300)


class BrandingPayload(Reason):
    name_fa: str = Field(min_length=1, max_length=80)
    name_en: str = Field(min_length=1, max_length=80)
    tagline: str = Field(default='', max_length=180)


class AdjustmentPayload(Reason):
    delta: Decimal = Field(max_digits=18, decimal_places=2, allow_inf_nan=False)
    expected_balance: Decimal = Field(max_digits=18, decimal_places=2, allow_inf_nan=False)
    request_id: UUID

    @field_validator('delta')
    @classmethod
    def nonzero(cls, v):
        if v == 0:
            raise ValueError('مبلغ اصلاح نمی‌تواند صفر باشد.')
        return v


class ControlsPayload(Reason):
    status: Literal['active', 'suspended']
    mode: Literal['manual', 'auto']
    frequency: Literal['daily', 'weekly'] | None = None
    threshold_amount: Decimal = Field(default=Decimal('0'), ge=0, max_digits=18, decimal_places=2, allow_inf_nan=False)
    min_reserve: Decimal = Field(default=Decimal('0'), ge=0, max_digits=18, decimal_places=2, allow_inf_nan=False)
    default_bank_account_id: int | None = Field(default=None, gt=0)


class AdvancedPayload(Reason):
    max_file_size: int | None = Field(default=None, ge=1, le=1000)
    max_users: int | None = Field(default=None, ge=0, le=10000)
    mcp_oauth_session_days: int | None = Field(default=None, ge=1, le=365)
    default_timezone: str | None = Field(default=None, max_length=80)
    support_tickets_enabled: bool | None = None
    support_tickets_disabled_message: str | None = Field(default=None, max_length=255)
    legacy_api_import_enabled: bool | None = None
    legacy_api_import_disabled_message: str | None = Field(default=None, max_length=255)


@public_router.get('/branding')
def public_branding(request: Request, db: Session = Depends(get_db)):
    return success_response(service.branding(db), request)


@public_router.get('/logo')
def public_logo(db: Session = Depends(get_db)):
    logo = service.setting_json(db, service.LOGO_KEY)
    if not logo:
        raise ApiError('NOT_FOUND', 'لوگو تنظیم نشده است.', http_status=404)
    return Response(base64.b64decode(logo['data']), media_type='image/png',
        headers={'Cache-Control': 'no-cache, must-revalidate', 'ETag': '"'+logo['sha256']+'"', 'X-Content-Type-Options': 'nosniff'})


@router.get('/overview')
def overview(request: Request, ctx=Depends(platform_admin), db: Session = Depends(get_db)):
    return success_response(service.overview(db), request)


@router.get('/wallets')
def wallets(request: Request, q: str = Query('', max_length=100), skip: int = Query(0, ge=0),
            limit: int = Query(25, ge=1, le=100), ctx=Depends(platform_admin), db: Session = Depends(get_db)):
    return success_response(service.list_business_wallets(db, q, skip, limit), request)


@router.get('/wallets/{business_id}')
def wallet(request: Request, business_id: int, ctx=Depends(platform_admin), db: Session = Depends(get_db)):
    return success_response(service.wallet_detail(db, business_id), request)


@router.post('/wallets/{business_id}/adjustments')
def adjustment(request: Request, business_id: int, payload: AdjustmentPayload, ctx=Depends(platform_admin), db: Session = Depends(get_db)):
    return success_response(service.adjust_wallet(db, business_id, ctx.user.id, **payload.model_dump()), request)


@router.put('/wallets/{business_id}/controls')
def controls(request: Request, business_id: int, payload: ControlsPayload, ctx=Depends(platform_admin), db: Session = Depends(get_db)):
    data = payload.model_dump()
    reason = data.pop('reason')
    return success_response(service.update_wallet_controls(db, business_id, ctx.user.id, data, reason), request)


@router.put('/branding')
def put_branding(request: Request, payload: BrandingPayload, ctx=Depends(platform_admin), db: Session = Depends(get_db)):
    data = payload.model_dump()
    reason = data.pop('reason')
    return success_response(service.update_branding(db, ctx.user.id, data, reason), request)


@router.post('/logo')
async def put_logo(request: Request, file: UploadFile = File(...), reason: str = Form(..., min_length=5, max_length=300),
                   ctx=Depends(platform_admin), db: Session = Depends(get_db)):
    raw = await file.read(2 * 1024 * 1024 + 1)
    reason = reason.strip()
    if len(reason) < 5:
        raise ApiError('INVALID_REASON', 'دلیل کامل وارد کنید.', http_status=400)
    return success_response(service.update_logo(db, ctx.user.id, raw, reason), request)


@router.get('/advanced')
def advanced(request: Request, ctx=Depends(platform_admin), db: Session = Depends(get_db)):
    return success_response(service.advanced_settings(db), request)


@router.put('/advanced')
def put_advanced(request: Request, payload: AdvancedPayload, ctx=Depends(platform_admin), db: Session = Depends(get_db)):
    data = payload.model_dump(exclude_none=True, exclude_unset=True)
    reason = data.pop('reason')
    return success_response(service.update_advanced(db, ctx.user.id, data, reason), request)


@router.get('/audit')
def audit(request: Request, skip: int = Query(0, ge=0), limit: int = Query(30, ge=1, le=100),
          ctx=Depends(platform_admin), db: Session = Depends(get_db)):
    return success_response(service.audit_events(db, skip, limit), request)
