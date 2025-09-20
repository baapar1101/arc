from __future__ import annotations

from typing import List
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.repositories.support.priority_repository import PriorityRepository
from adapters.api.v1.support.schemas import PriorityResponse
from adapters.api.v1.schemas import SuccessResponse
from app.core.responses import success_response, format_datetime_fields

router = APIRouter()


@router.get("", response_model=SuccessResponse)
async def get_priorities(
    request: Request,
    db: Session = Depends(get_db)
):
    """دریافت لیست اولویت‌ها"""
    priority_repo = PriorityRepository(db)
    priorities = priority_repo.get_priorities_ordered()
    
    # Convert to dict and format datetime fields
    priorities_data = [PriorityResponse.from_orm(priority).dict() for priority in priorities]
    formatted_data = format_datetime_fields(priorities_data, request)
    
    return success_response(formatted_data, request)
