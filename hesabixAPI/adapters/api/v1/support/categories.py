from __future__ import annotations

from typing import List
from fastapi import APIRouter, Depends, Request
from adapters.api.v1.support.dependencies import require_end_user_support_open
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.repositories.support.category_repository import CategoryRepository
from adapters.api.v1.support.schemas import CategoryResponse
from adapters.api.v1.schemas import SuccessResponse
from app.core.responses import success_response, format_datetime_fields

router = APIRouter()


@router.get("", response_model=SuccessResponse)
async def get_categories(
    request: Request,
    _require_support: None = Depends(require_end_user_support_open),
    db: Session = Depends(get_db)
):
    """دریافت لیست دسته‌بندی‌های فعال"""
    category_repo = CategoryRepository(db)
    categories = category_repo.get_active_categories()
    
    # Convert to dict and format datetime fields
    categories_data = [CategoryResponse.from_orm(category).dict() for category in categories]
    formatted_data = format_datetime_fields(categories_data, request)
    
    return success_response(formatted_data, request)
