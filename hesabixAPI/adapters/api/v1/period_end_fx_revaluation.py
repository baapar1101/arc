"""API تسعیر پایان دوره (P8)."""
from __future__ import annotations

from datetime import date, datetime
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response
from app.services.period_end_fx_revaluation_service import (
	create_period_end_fx_revaluation_document,
	preview_period_end_fx_revaluation,
)

router = APIRouter(tags=["currency_revaluation", "حسابداری"], prefix="")


class PeriodEndFxCreateBody(BaseModel):
	fiscal_year_id: Optional[int] = None
	as_of: Optional[datetime] = None
	document_date: Optional[date] = None
	description: Optional[str] = Field(None, max_length=500)


@router.get(
	"/businesses/{business_id}/period-end-fx-revaluation/preview",
	summary="پیش‌نمایش تسعیر پایان دوره",
)
@require_business_access("business_id")
async def preview_period_end_fx(
	request: Request,
	business_id: int,
	fiscal_year_id: Optional[int] = None,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "view")),
) -> Dict[str, Any]:
	data = preview_period_end_fx_revaluation(
		db, business_id, fiscal_year_id=fiscal_year_id
	)
	return success_response(data=data, request=request)


@router.post(
	"/businesses/{business_id}/period-end-fx-revaluation",
	summary="ایجاد سند تسعیر پایان دوره",
)
@require_business_access("business_id")
async def create_period_end_fx(
	request: Request,
	business_id: int,
	body: Optional[PeriodEndFxCreateBody] = None,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "add")),
) -> Dict[str, Any]:
	payload = body or PeriodEndFxCreateBody()
	data = create_period_end_fx_revaluation_document(
		db,
		business_id,
		int(ctx.get_user_id()),
		fiscal_year_id=payload.fiscal_year_id,
		as_of=payload.as_of,
		document_date=payload.document_date,
		description=payload.description,
	)
	return success_response(data=data, request=request)
