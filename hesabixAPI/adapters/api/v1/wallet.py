from __future__ import annotations

from typing import Dict, Any
from datetime import datetime

from fastapi import APIRouter, Depends, Request, Body, Path
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import success_response, ApiError
from app.services.wallet_service import (
	get_wallet_overview,
	list_wallet_transactions,
	create_payout_request,
	approve_payout_request,
	cancel_payout_request,
	create_top_up_request,
	get_wallet_metrics,
	get_business_wallet_settings,
	update_business_wallet_settings,
	run_auto_settlement,
)


router = APIRouter(prefix="/businesses/{business_id}/wallet", tags=["wallet"])


@router.get(
	"",
	summary="خلاصه کیف‌پول کسب‌وکار",
	description="نمایش مانده‌ها و ارز پایه",
)
def get_wallet_overview_endpoint(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = get_wallet_overview(db, business_id)
	return success_response(data, request)

@router.post(
	"/top-up",
	summary="ایجاد درخواست افزایش اعتبار",
	description="ایجاد top-up و بازگشت شناسه تراکنش برای هدایت به درگاه",
)
def create_top_up_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = create_top_up_request(db, business_id, ctx.get_user_id(), payload)
	return success_response(data, request, message="TOPUP_REQUESTED")


@router.get(
	"/transactions",
	summary="لیست تراکنش‌های کیف‌پول",
	description="نمایش تراکنش‌ها به ترتیب نزولی",
)
def list_wallet_transactions_endpoint(
	request: Request,
	business_id: int,
	skip: int = 0,
	limit: int = 50,
	from_date: str | None = None,
	to_date: str | None = None,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from_dt = None
	to_dt = None
	try:
		if from_date:
			from_dt = datetime.fromisoformat(from_date)
		if to_date:
			to_dt = datetime.fromisoformat(to_date)
	except Exception:
		from_dt = None
		to_dt = None
	data = list_wallet_transactions(db, business_id, limit=limit, skip=skip, from_date=from_dt, to_date=to_dt)
	return success_response(data, request)


@router.get(
	"/transactions/export",
	summary="خروجی CSV تراکنش‌های کیف‌پول",
)
def export_wallet_transactions_csv_endpoint(
	request: Request,
	business_id: int,
	from_date: str | None = None,
	to_date: str | None = None,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	from_dt = None
	to_dt = None
	try:
		if from_date:
			from_dt = datetime.fromisoformat(from_date)
		if to_date:
			to_dt = datetime.fromisoformat(to_date)
	except Exception:
		from_dt = None
		to_dt = None
	items = list_wallet_transactions(db, business_id, limit=10000, skip=0, from_date=from_dt, to_date=to_dt)
	# CSV ساده
	import csv
	from io import StringIO
	buf = StringIO()
	writer = csv.writer(buf)
	writer.writerow(["id", "type", "status", "amount", "fee_amount", "description", "document_id", "created_at"])
	for it in items:
		writer.writerow([it.get("id"), it.get("type"), it.get("status"), it.get("amount"), it.get("fee_amount"), (it.get("description") or "").replace("\n", " "), it.get("document_id"), it.get("created_at")])
	csv_data = buf.getvalue().encode("utf-8")
	from fastapi.responses import Response
	return Response(content=csv_data, media_type="text/csv; charset=utf-8", headers={"Content-Disposition": f'attachment; filename="wallet_transactions_{business_id}.csv"'})


@router.get(
	"/metrics/export",
	summary="خروجی CSV خلاصه کیف‌پول",
)
def export_wallet_metrics_csv_endpoint(
	request: Request,
	business_id: int,
	from_date: str | None = None,
	to_date: str | None = None,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	from_dt = None
	to_dt = None
	try:
		if from_date:
			from_dt = datetime.fromisoformat(from_date)
		if to_date:
			to_dt = datetime.fromisoformat(to_date)
	except Exception:
		from_dt = None
		to_dt = None
	m = get_wallet_metrics(db, business_id, from_date=from_dt, to_date=to_dt)
	import csv
	from io import StringIO
	buf = StringIO()
	writer = csv.writer(buf)
	writer.writerow(["metric", "value"])
	t = m.get("totals") or {}
	writer.writerow(["gross_in", t.get("gross_in", 0)])
	writer.writerow(["fees_in", t.get("fees_in", 0)])
	writer.writerow(["net_in", t.get("net_in", 0)])
	writer.writerow(["gross_out", t.get("gross_out", 0)])
	writer.writerow(["fees_out", t.get("fees_out", 0)])
	writer.writerow(["net_out", t.get("net_out", 0)])
	b = m.get("balances") or {}
	writer.writerow(["available", b.get("available", 0)])
	writer.writerow(["pending", b.get("pending", 0)])
	csv_data = buf.getvalue().encode("utf-8")
	from fastapi.responses import Response
	return Response(content=csv_data, media_type="text/csv; charset=utf-8", headers={"Content-Disposition": f'attachment; filename="wallet_metrics_{business_id}.csv"'})


@router.post(
	"/payouts",
	summary="ایجاد درخواست تسویه",
	description="ایجاد درخواست تسویه به حساب بانکی مشخص",
)
def create_payout_request_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = create_payout_request(db, business_id, ctx.get_user_id(), payload)
	return success_response(data, request, message="PAYOUT_REQUESTED")


@router.get(
	"/metrics",
	summary="گزارش خلاصه کیف‌پول (metrics)",
	description="مبالغ ورودی/خروجی/کارمزد و مانده‌ها در بازه زمانی",
)
def get_wallet_metrics_endpoint(
	request: Request,
	business_id: int,
	from_date: str | None = None,
	to_date: str | None = None,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from_dt = None
	to_dt = None
	try:
		if from_date:
			from_dt = datetime.fromisoformat(from_date)
		if to_date:
			to_dt = datetime.fromisoformat(to_date)
	except Exception:
		from_dt = None
		to_dt = None
	data = get_wallet_metrics(db, business_id, from_date=from_dt, to_date=to_dt)
	return success_response(data, request)


@router.get(
	"/settings",
	summary="تنظیمات کیف‌پول کسب‌وکار",
)
def get_wallet_settings_business_endpoint(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = get_business_wallet_settings(db, business_id)
	return success_response(data, request)


@router.put(
	"/settings",
	summary="ویرایش تنظیمات کیف‌پول کسب‌وکار",
)
def update_wallet_settings_business_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = update_business_wallet_settings(db, business_id, payload)
	return success_response(data, request, message="WALLET_SETTINGS_UPDATED")


@router.post(
	"/auto-settle/run",
	summary="اجرای تسویه خودکار (برای cron/job)",
)
def run_auto_settle_endpoint(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = run_auto_settlement(db, business_id, ctx.get_user_id())
	return success_response(data, request, message="AUTO_SETTLE_EXECUTED" if data.get("executed") else "AUTO_SETTLE_SKIPPED")

@router.put(
	"/payouts/{payout_id}/approve",
	summary="تایید درخواست تسویه",
	description="تایید توسط کاربر مجاز",
)
def approve_payout_request_endpoint(
	request: Request,
	business_id: int,
	payout_id: int = Path(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	# Permission check could be refined (e.g., wallet.approve)
	data = approve_payout_request(db, payout_id, ctx.get_user_id())
	return success_response(data, request, message="PAYOUT_APPROVED")


@router.put(
	"/payouts/{payout_id}/cancel",
	summary="لغو درخواست تسویه",
	description="لغو و بازگردانی مبلغ به مانده قابل برداشت",
)
def cancel_payout_request_endpoint(
	request: Request,
	business_id: int,
	payout_id: int = Path(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = cancel_payout_request(db, payout_id, ctx.get_user_id())
	return success_response(data, request, message="PAYOUT_CANCELED")


