from __future__ import annotations

from typing import Dict, Any, List
import json

from fastapi import APIRouter, Depends, Request, Path
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response
from adapters.db.models.payment_gateway import PaymentGateway, BusinessPaymentGateway


router = APIRouter(prefix="/businesses/{business_id}/wallet", tags=["wallet"])


@router.get(
	"/gateways",
	summary="لیست درگاه‌های فعال برای کسب‌وکار",
	description="اگر برای کسب‌وکار خاص درگاه‌هایی تنظیم شده باشد، همان‌ها را برمی‌گرداند؛ در غیر این صورت همه درگاه‌های فعال سیستم.",
)
def list_business_gateways(
	request: Request,
	business_id: int = Path(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	# اجازه دسترسی: کاربر عضو همان کسب‌وکار
	# (فرض: AuthContext قبلاً بررسی اتصال کاربر به کسب‌وکار را انجام می‌دهد)
	links = db.query(BusinessPaymentGateway).filter(
		BusinessPaymentGateway.business_id == int(business_id),
		BusinessPaymentGateway.is_active == True,  # noqa: E712
	).all()
	items: List[PaymentGateway]
	if links:
		gateway_ids = [it.gateway_id for it in links]
		items = db.query(PaymentGateway).filter(
			PaymentGateway.id.in_(gateway_ids),
			PaymentGateway.is_active == True,  # noqa: E712
		).all()
	else:
		items = db.query(PaymentGateway).filter(PaymentGateway.is_active == True).all()  # noqa: E712
	data = [
		{
			"id": it.id,
			"provider": it.provider,
			"display_name": it.display_name,
			"is_sandbox": it.is_sandbox,
		}
		for it in items
	]
	return success_response(data, request)



