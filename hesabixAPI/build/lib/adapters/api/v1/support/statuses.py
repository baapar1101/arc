from __future__ import annotations

from typing import List
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.repositories.support.status_repository import StatusRepository
from adapters.api.v1.support.schemas import StatusResponse
from adapters.api.v1.schemas import SuccessResponse
from app.core.responses import success_response, format_datetime_fields

router = APIRouter()


@router.get("", response_model=SuccessResponse)
async def get_statuses(
    request: Request,
    db: Session = Depends(get_db)
):
    """دریافت لیست وضعیت‌ها"""
    status_repo = StatusRepository(db)
    statuses = status_repo.get_all_statuses()
    
    # Convert to dict and format datetime fields
    statuses_data = [StatusResponse.from_orm(status).dict() for status in statuses]
    formatted_data = format_datetime_fields(statuses_data, request)
    
    return success_response(formatted_data, request)
