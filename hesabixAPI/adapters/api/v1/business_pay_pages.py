from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import format_datetime_fields, success_response
from app.services.business_pay_page_service import (
	check_username_availability,
	get_pay_page_settings,
	list_pay_page_payments,
	update_pay_page_settings,
)

router = APIRouter(prefix="/businesses/{business_id}/pay-page", tags=["business-pay-page"])


@router.get(
	"",
	summary="تنظیمات لینک واریز عمومی کسب‌وکار",
)
def get_pay_page(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	_: None = Depends(require_business_access_dep),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = get_pay_page_settings(db, business_id)
	return success_response(format_datetime_fields(data, request, business_id=business_id), request)


@router.put(
	"",
	summary="ذخیره تنظیمات لینک واریز عمومی",
)
def put_pay_page(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(default_factory=dict),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("settings", "business")),
) -> dict:
	data = update_pay_page_settings(db, business_id, payload or {})
	return success_response(
		format_datetime_fields(data, request, business_id=business_id),
		request,
		message="PAY_PAGE_SETTINGS_UPDATED",
	)


@router.get(
	"/username-availability",
	summary="بررسی آزاد بودن نام کاربری لینک واریز",
)
def username_availability(
	request: Request,
	business_id: int,
	username: str = Query(..., min_length=1, max_length=30),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_access_dep),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = check_username_availability(db, business_id=business_id, username=username)
	return success_response(data, request)


@router.post(
	"/payments/table",
	summary="جدول واریزهای لینک پرداخت",
)
def pay_page_payments_table(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(default_factory=dict),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_access_dep),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	take = int(payload.get("take") or 20)
	skip = int(payload.get("skip") or 0)
	search = payload.get("search") or payload.get("query")
	from_dt = None
	to_dt = None
	try:
		for f in payload.get("filters") or []:
			prop = str(f.get("property") or "").lower()
			op = str(f.get("operator") or "")
			val = f.get("value")
			if prop in ("created_at", "date", "paid_at"):
				if op == ">=" and val:
					from_dt = datetime.fromisoformat(str(val).replace("Z", "+00:00").split("+")[0])
				elif op == "<=" and val:
					to_dt = datetime.fromisoformat(str(val).replace("Z", "+00:00").split("+")[0])
	except Exception:
		from_dt = None
		to_dt = None
	data = list_pay_page_payments(
		db,
		business_id,
		take=take,
		skip=skip,
		from_date=from_dt,
		to_date=to_dt,
		search=str(search) if search else None,
	)
	return success_response(format_datetime_fields(data, request, business_id=business_id), request)


@router.get(
	"/payments/export",
	summary="خروجی CSV واریزهای لینک پرداخت",
)
def pay_page_payments_export(
	request: Request,
	business_id: int,
	from_date: Optional[str] = None,
	to_date: Optional[str] = None,
	db: Session = Depends(get_db),
	_: None = Depends(require_business_access_dep),
	ctx: AuthContext = Depends(get_current_user),
):
	from_dt = datetime.fromisoformat(from_date) if from_date else None
	to_dt = datetime.fromisoformat(to_date) if to_date else None
	data = list_pay_page_payments(
		db, business_id, take=5000, skip=0, from_date=from_dt, to_date=to_dt
	)
	import csv
	import io

	from fastapi.responses import StreamingResponse

	buf = io.StringIO()
	writer = csv.writer(buf)
	writer.writerow(
		["id", "created_at", "status", "amount", "payer_name", "payer_mobile", "payer_note", "document_id", "person_id"]
	)
	for it in data.get("items") or []:
		writer.writerow(
			[
				it.get("id"),
				it.get("created_at"),
				it.get("status"),
				it.get("amount"),
				it.get("payer_name") or "",
				it.get("payer_mobile") or "",
				it.get("payer_note") or "",
				it.get("document_id") or "",
				it.get("person_id") or "",
			]
		)
	buf.seek(0)
	return StreamingResponse(
		iter([buf.getvalue()]),
		media_type="text/csv; charset=utf-8",
		headers={"Content-Disposition": "attachment; filename=pay-page-payments.csv"},
	)
