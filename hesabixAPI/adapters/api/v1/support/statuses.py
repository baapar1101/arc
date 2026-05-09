from __future__ import annotations

from typing import List
from fastapi import APIRouter, Depends, Request
from adapters.api.v1.support.dependencies import require_end_user_support_open
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.repositories.support.status_repository import StatusRepository
from adapters.api.v1.support.schemas import StatusResponse
from adapters.api.v1.schemas import SuccessResponse
from app.core.responses import success_response, format_datetime_fields
from app.core.cache import CacheService

router = APIRouter()
cache_service = CacheService()


@router.get("", response_model=SuccessResponse)
async def get_statuses(
    request: Request,
    _require_support: None = Depends(require_end_user_support_open),
    db: Session = Depends(get_db)
):
    """دریافت لیست وضعیت‌ها - با caching"""
    # بررسی cache
    cache_key = "support:statuses"
    cached_data = cache_service.get(cache_key)
    if cached_data:
        return success_response(cached_data, request)
    
    # اگر در cache نبود، از دیتابیس بخوان
    status_repo = StatusRepository(db)
    statuses = status_repo.get_all_statuses()
    
    # Convert to dict and format datetime fields
    statuses_data = [StatusResponse.from_orm(status).dict() for status in statuses]
    formatted_data = format_datetime_fields(statuses_data, request)
    
    # ذخیره در cache
    cache_service.set(cache_key, formatted_data, ttl=3600)
    
    return success_response(formatted_data, request)
