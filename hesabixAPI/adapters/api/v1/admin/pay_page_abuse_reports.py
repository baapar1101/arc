from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_app_permission
from app.core.responses import success_response
from app.services.public_pay_page_abuse_service import (
	list_pay_page_abuse_reports,
	update_pay_page_abuse_report,
)

router = APIRouter(prefix="/admin/pay-page-abuse-reports", tags=["admin.pay-page-abuse"])


@router.get("", summary="گزارش‌های تخلف لینک واریز عمومی")
@require_app_permission("system_settings")
def admin_list_pay_page_abuse_reports(
	request: Request,
	status: Optional[str] = Query(default=None),
	take: int = Query(default=30, ge=1, le=100),
	skip: int = Query(default=0, ge=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	data = list_pay_page_abuse_reports(db, status=status, take=take, skip=skip)
	return success_response(data, request)


@router.patch("/{report_id}", summary="بررسی گزارش تخلف لینک واریز")
@require_app_permission("system_settings")
def admin_update_pay_page_abuse_report(
	report_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(default={}),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	data = update_pay_page_abuse_report(
		db,
		report_id,
		status=payload.get("status"),
		admin_note=payload.get("admin_note"),
		reviewed_by=ctx.get_user_id(),
	)
	return success_response(data, request)
