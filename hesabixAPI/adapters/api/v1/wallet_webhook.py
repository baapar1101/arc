from __future__ import annotations

from typing import Dict, Any

from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.responses import success_response
from app.services.wallet_service import confirm_top_up


router = APIRouter(prefix="/wallet", tags=["wallet-webhook"])


@router.post(
	"/webhook",
	summary="وبهوک تایید افزایش اعتبار",
	description="تایید/لغو top-up از طرف درگاه پرداخت",
)
def wallet_webhook_endpoint(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
) -> dict:
	# توجه: در محیط واقعی باید امضای وبهوک و ضد تکرار بودن بررسی شود
	tx_id = int(payload.get("transaction_id") or 0)
	status = str(payload.get("status") or "").lower()
	success = status in ("success", "succeeded", "ok")
	external_ref = str(payload.get("external_ref") or "")
	# اختیاری: دریافت کارمزد از وبهوک و نگهداری در تراکنش (fee_amount)
	try:
		fee_value = payload.get("fee_amount")
		if fee_value is not None:
			from decimal import Decimal
			from adapters.db.models.wallet import WalletTransaction
			tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
			if tx:
				tx.fee_amount = Decimal(str(fee_value))
				db.flush()
	except Exception:
		pass
	data = confirm_top_up(db, tx_id, success=success, external_ref=external_ref or None)
	return success_response(data, request, message="TOPUP_CONFIRMED" if success else "TOPUP_FAILED")


