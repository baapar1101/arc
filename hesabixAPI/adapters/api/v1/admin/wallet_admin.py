from __future__ import annotations

from typing import Dict, Any, List
from datetime import datetime, date
from decimal import Decimal

from fastapi import APIRouter, Depends, Request, Body, Path, Query
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from adapters.db.models.wallet import WalletAccount
from app.services.wallet_service import (
	refund_transaction,
	settle_payout,
	list_wallet_payouts_admin,
	get_wallet_payout_admin,
	get_wallet_payouts_stats_admin,
)


router = APIRouter(prefix="/admin/wallets", tags=["admin-wallet"])


def _parse_iso_datetime(value) -> datetime | None:
	if value is None:
		return None
	if isinstance(value, datetime):
		return value
	if isinstance(value, date):
		return datetime.combine(value, datetime.min.time())
	try:
		return datetime.fromisoformat(str(value))
	except Exception as exc:
		raise ApiError("INVALID_DATE", f"تاریخ نامعتبر است: {value}") from exc


@router.get(
	"",
	summary="فهرست کیف‌پول کسب‌وکارها",
)
def list_wallets_admin(
	request: Request,
	limit: int = Query(50, ge=1, le=200),
	skip: int = Query(0, ge=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	q = db.query(WalletAccount).order_by(WalletAccount.id.desc())
	items = q.offset(skip).limit(limit).all()
	data = [
		{
			"id": it.id,
			"business_id": it.business_id,
			"available_balance": float(it.available_balance or 0),
			"pending_balance": float(it.pending_balance or 0),
			"status": it.status,
		}
		for it in items
	]
	return success_response(data, request)


@router.post(
	"/{business_id}/refunds",
	summary="ایجاد استرداد (مدیریتی)",
)
def create_refund_admin(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	tx_id = int(payload.get("transaction_id") or 0)
	amount = payload.get("amount")
	reason = payload.get("reason")
	from decimal import Decimal
	data = refund_transaction(db, tx_id, amount=Decimal(str(amount)) if amount is not None else None, reason=reason)
	return success_response(data, request, message="REFUND_CREATED")


@router.get(
	"/payouts/stats",
	summary="آمار کلی درخواست‌های تسویه کیف‌پول",
)
def get_wallet_payouts_stats_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = get_wallet_payouts_stats_admin(db)
	return success_response(data, request)


@router.post(
	"/payouts/table",
	summary="لیست درخواست‌های تسویه کیف‌پول (برای جدول)",
)
def list_wallet_payouts_admin_table_endpoint(
	request: Request,
	payload: Dict[str, Any] = Body(default_factory=dict),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	# Extract pagination params
	take = int(payload.get("take") or 20)
	skip = int(payload.get("skip") or 0)
	
	# Extract filters
	statuses = None
	business_id = None
	filters = payload.get("filters") or []
	for f in filters:
		prop = str(f.get("property") or "").lower()
		op = str(f.get("operator") or "")
		val = f.get("value")
		if prop == "status" and op == "in" and val is not None:
			if isinstance(val, list):
				statuses = [str(v).strip() for v in val if v]
			elif isinstance(val, str):
				statuses = [s.strip() for s in val.split(",") if s.strip()]
		elif prop == "business_id" and val is not None:
			business_id = int(val) if isinstance(val, (int, str)) and str(val).strip() else None
	
	data = list_wallet_payouts_admin(
		db,
		statuses=statuses,
		business_id=business_id,
		limit=take,
		skip=skip,
	)
	
	# Compute total
	try:
		from adapters.db.models.wallet import WalletPayout
		q = db.query(WalletPayout)
		if statuses:
			q = q.filter(WalletPayout.status.in_(statuses))
		if business_id:
			q = q.filter(WalletPayout.business_id == int(business_id))
		total = q.count()
	except Exception:
		total = len(data.get("items", []))
	
	page = (skip // take) + 1 if take > 0 else 1
	total_pages = (total + take - 1) // take if take > 0 else 1
	
	resp = {
		"items": data.get("items", []),
		"total": total,
		"page": page,
		"limit": take,
		"total_pages": total_pages,
	}
	return success_response(resp, request)


@router.get(
	"/payouts/{payout_id}",
	summary="جزئیات درخواست تسویه کیف‌پول",
)
def get_wallet_payout_admin_endpoint(
	request: Request,
	payout_id: int = Path(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = get_wallet_payout_admin(db, payout_id)
	return success_response(data, request)


@router.put(
	"/payouts/{payout_id}/settle",
	summary="تسویه درخواست Payout (مدیریتی)",
)
def settle_payout_admin(
	request: Request,
	payout_id: int,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	track_code = str(payload.get("bank_tracking_code") or "").strip()
	if not track_code:
		raise ApiError("TRACKING_REQUIRED", "کد پیگیری بانک الزامی است", http_status=400)
	fee_amount = payload.get("fee_amount")
	note = payload.get("note")
	settlement_date_value = payload.get("settlement_date")
	if not settlement_date_value:
		raise ApiError("SETTLEMENT_DATE_REQUIRED", "تاریخ واریز الزامی است", http_status=400)
	settlement_dt = _parse_iso_datetime(settlement_date_value)
	data = settle_payout(
		db,
		payout_id,
		ctx.get_user_id(),
		settlement_date=settlement_dt,
		bank_tracking_code=track_code,
		fee_amount=Decimal(str(fee_amount)) if fee_amount is not None else None,
		note=note,
	)
	return success_response(data, request, message="PAYOUT_SETTLED")

