from __future__ import annotations

from typing import Dict, Any, List

from fastapi import APIRouter, Depends, Request, Body, Path, Query
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from adapters.db.models.wallet import WalletAccount
from app.services.wallet_service import refund_transaction, settle_payout


router = APIRouter(prefix="/admin/wallets", tags=["admin-wallet"])


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


@router.put(
	"/payouts/{payout_id}/settle",
	summary="تسویه درخواست Payout (مدیریتی)",
)
def settle_payout_admin(
	request: Request,
	payout_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = settle_payout(db, payout_id, ctx.get_user_id())
	return success_response(data, request, message="PAYOUT_SETTLED")

