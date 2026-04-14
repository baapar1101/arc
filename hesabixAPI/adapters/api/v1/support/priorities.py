from __future__ import annotations

from typing import List
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.repositories.support.priority_repository import PriorityRepository
from adapters.api.v1.support.schemas import PriorityResponse
from adapters.api.v1.schemas import SuccessResponse
from app.core.responses import success_response, format_datetime_fields
from app.core.cache import CacheService

router = APIRouter()
cache_service = CacheService()


@router.get("", response_model=SuccessResponse)
async def get_priorities(
    request: Request,
    db: Session = Depends(get_db)
):
    """دریافت لیست اولویت‌ها - با caching"""
    # بررسی cache
    cache_key = "support:priorities"
    cached_data = cache_service.get(cache_key)
    if cached_data:
        return success_response(cached_data, request)
    
    # اگر در cache نبود، از دیتابیس بخوان
    priority_repo = PriorityRepository(db)
    priorities = priority_repo.get_priorities_ordered()
    
    # Convert to dict and format datetime fields
    priorities_data = [PriorityResponse.from_orm(priority).dict() for priority in priorities]
    formatted_data = format_datetime_fields(priorities_data, request)
    
    # ذخیره در cache
    cache_service.set(cache_key, formatted_data, ttl=3600)
    
    return success_response(formatted_data, request)
