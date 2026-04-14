from __future__ import annotations

from typing import Dict, Any
import os
import hmac
import hashlib
import json

from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.responses import success_response, ApiError
from app.services.wallet_service import confirm_top_up
from adapters.db.models.wallet import WalletTransaction


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
	# امضای وبهوک (اختیاری بر اساس تنظیم محیط)
	secret = os.getenv("WALLET_WEBHOOK_SECRET", "").strip()
	if secret:
		signature = request.headers.get("x-signature") or request.headers.get("X-Signature")
		if not signature:
			raise ApiError("INVALID_SIGNATURE", "امضای وبهوک ارسال نشده است", http_status=403)
		try:
			body_str = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
			digest = hmac.new(secret.encode("utf-8"), body_str.encode("utf-8"), hashlib.sha256).hexdigest()
			if not hmac.compare_digest(digest, str(signature).strip()):
				raise ApiError("INVALID_SIGNATURE", "امضای وبهوک نامعتبر است", http_status=403)
		except ApiError:
			raise
		except Exception:
			raise ApiError("INVALID_SIGNATURE", "خطا در اعتبارسنجی امضا", http_status=403)

	tx_id = int(payload.get("transaction_id") or 0)
	if tx_id <= 0:
		raise ApiError("INVALID_TX_ID", "شناسه تراکنش نامعتبر است", http_status=400)
	
	status = str(payload.get("status") or "").lower()
	success = status in ("success", "succeeded", "ok")
	external_ref = str(payload.get("external_ref") or "")
	nonce = str(payload.get("nonce") or "")

	# بارگذاری تراکنش برای بررسی‌های امنیتی
	tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
	if not tx:
		raise ApiError("TX_NOT_FOUND", "تراکنش یافت نشد", http_status=404)
	
	# بررسی نوع تراکنش
	if tx.type != "top_up":
		raise ApiError("INVALID_TX_TYPE", "تراکنش از نوع top_up نیست", http_status=400)
	
	# بررسی تعلق تراکنش به کسب‌وکار (امنیتی)
	business_id_from_payload = payload.get("business_id")
	if business_id_from_payload and int(business_id_from_payload) != int(tx.business_id):
		raise ApiError("BUSINESS_MISMATCH", "تراکنش متعلق به کسب‌وکار درخواستی نیست", http_status=403)

	# ضد تکرار ساده: ذخیره آخرین nonce در extra_info تراکنش و رد تکراری
	user_id = None
	try:
		if tx and nonce:
			try:
				extra = json.loads(tx.extra_info or "{}") if tx.extra_info else {}
			except Exception:
				extra = {}
			prev_nonce = str(extra.get("last_webhook_nonce") or "")
			if prev_nonce and prev_nonce == nonce:
				# تراکنش تکراری؛ بدون تغییر وضعیت پاسخ می‌دهیم
				return success_response({"transaction_id": tx_id, "status": tx.status}, request, message="DUPLICATE_WEBHOOK_IGNORED")
			extra["last_webhook_nonce"] = nonce
			# استخراج user_id از extra_info
			user_id = extra.get("created_by_user_id")
			tx.extra_info = json.dumps(extra, ensure_ascii=False)
			db.flush()
		else:
			# اگر nonce نداریم، user_id را از extra_info استخراج می‌کنیم
			try:
				extra = json.loads(tx.extra_info or "{}") if tx.extra_info else {}
				user_id = extra.get("created_by_user_id")
			except Exception:
				pass
	except Exception:
		# عدم موفقیت در ضدتکرار نباید مانع مسیر اصلی شود؛ confirm_top_up ایدم‌پوتنت است
		pass
	
	# اختیاری: دریافت کارمزد از وبهوک و نگهداری در تراکنش (fee_amount)
	try:
		fee_value = payload.get("fee_amount")
		if fee_value is not None:
			from decimal import Decimal
			tx.fee_amount = Decimal(str(fee_value))
			db.flush()
	except Exception:
		pass
	
	data = confirm_top_up(db, tx_id, success=success, external_ref=external_ref or None, user_id=user_id)
	return success_response(data, request, message="TOPUP_CONFIRMED" if success else "TOPUP_FAILED")


