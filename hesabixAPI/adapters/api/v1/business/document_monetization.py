"""API سناریوی درآمدزایی اسناد حسابداری (Business)"""

from typing import Dict, Any, Optional
from datetime import datetime

from fastapi import APIRouter, Depends, Body, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.document_monetization_service import (
	list_business_policies,
	list_document_usage_charges,
	pay_document_usage_charge,
	process_document_usage_for_document,
	finalize_volume_periods,
	evaluate_document_policy_for_amount,
	list_document_subscription_plans,
	assign_subscription_to_business,
	get_business_subscription_status,
)


router = APIRouter(prefix="/business/{business_id}/document-monetization", tags=["business-document-monetization"])


def _ensure_business_access(ctx: AuthContext, business_id: int) -> None:
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "به این کسب‌وکار دسترسی ندارید", http_status=403)


@router.get(
	"/overview",
	summary="نمای کلی سناریو",
)
def document_monetization_overview(
	business_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_business_access(ctx, business_id)
	policies = list_business_policies(db, business_id)
	charges = list_document_usage_charges(db, business_id, limit=20)
	return success_response(
		{
			"policies": policies,
			"charges": charges,
		},
		request,
	)


@router.get(
	"/plans",
	summary="لیست پکیج‌ها و اشتراک فعال کسب‌وکار",
)
def list_business_subscription_plans(
	business_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_business_access(ctx, business_id)
	plans = list_document_subscription_plans(db, only_active=True)
	current = get_business_subscription_status(db, business_id)
	return success_response(
		{
			"plans": plans,
			"current_subscription": current,
		},
		request,
	)


@router.post(
	"/subscriptions",
	summary="فعال‌سازی پکیج توسط کسب‌وکار",
)
def activate_business_subscription(
	business_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_business_access(ctx, business_id)
	if not (ctx.is_superadmin() or ctx.is_business_owner(business_id)):
		raise ApiError("FORBIDDEN", "فقط مالک کسب‌وکار می‌تواند پکیج را مدیریت کند", http_status=403)
	plan_id = payload.get("plan_id")
	if not plan_id:
		raise ApiError("VALIDATION_ERROR", "plan_id الزامی است", http_status=422)
	result = assign_subscription_to_business(
		db,
		business_id,
		int(plan_id),
		ctx.get_user_id(),
		auto_renew=bool(payload.get("auto_renew", False)),
	)
	return success_response(result, request, "پکیج فعال شد")


@router.get(
	"/charges",
	summary="لیست صورتحساب‌ها",
)
def document_monetization_charges(
	business_id: int,
	request: Request,
	status: Optional[str] = Query(None),
	charge_type: Optional[str] = Query(None),
	limit: int = Query(50, ge=1, le=200),
	skip: int = Query(0, ge=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_business_access(ctx, business_id)
	data = list_document_usage_charges(
		db,
		business_id,
		status=status,
		charge_type=charge_type,
		limit=limit,
		skip=skip,
	)
	return success_response(data, request)


@router.post(
	"/charges/table",
	summary="لیست صورتحساب‌ها برای جدول (پگینیشن استاندارد)",
	description="سازگار با DataTableWidget: ورودی QueryInfo و خروجی items/total/page/limit",
)
def document_monetization_charges_table(
	business_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(default_factory=dict),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_business_access(ctx, business_id)
	# Extract pagination params
	take = int(payload.get("take") or 20)
	skip = int(payload.get("skip") or 0)
	# Extract filters
	status = None
	charge_type = None
	try:
		filters = payload.get("filters") or []
		for f in filters:
			prop = str(f.get("property") or "").lower()
			val = f.get("value")
			if prop == "status" and val:
				status = str(val)
			elif prop == "charge_type" and val:
				charge_type = str(val)
	except Exception:
		pass
	data = list_document_usage_charges(
		db,
		business_id,
		status=status,
		charge_type=charge_type,
		limit=take,
		skip=skip,
	)
	# Compute pagination
	page = (skip // take) + 1 if take > 0 else 1
	total_pages = (data["total"] + take - 1) // take if take > 0 else 1
	resp = {
		"items": data["items"],
		"total": data["total"],
		"page": page,
		"limit": take,
		"total_pages": total_pages,
	}
	return success_response(resp, request)


@router.post(
	"/charges/{charge_id}/pay",
	summary="پرداخت صورتحساب سناریو",
)
def pay_document_monetization_charge(
	business_id: int,
	charge_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_business_access(ctx, business_id)
	data = pay_document_usage_charge(db, business_id, charge_id, ctx.get_user_id())
	return success_response(data, request, "صورتحساب پرداخت شد")


@router.post(
	"/documents/{document_id}/process",
	summary="پردازش دستی سند برای سناریو",
)
def process_document_usage_endpoint(
	business_id: int,
	document_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_business_access(ctx, business_id)
	result = process_document_usage_for_document(db, document_id)
	return success_response(result, request, "سند پردازش شد")


@router.post(
	"/finalize-volume",
	summary="نهایی‌سازی دوره‌های حجمی",
)
def finalize_volume_endpoint(
	business_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_business_access(ctx, business_id)
	result = finalize_volume_periods(db, business_id=business_id)
	return success_response(result, request, "دوره‌ها نهایی شدند")


@router.post(
	"/validate",
	summary="بررسی مجوز ثبت سند قبل از ذخیره",
)
def validate_document_policy_endpoint(
	business_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_business_access(ctx, business_id)
	document_type = (payload.get("document_type") or "").strip()
	if not document_type:
		raise ApiError("DOCUMENT_TYPE_REQUIRED", "document_type الزامی است", http_status=422)
	if "amount" not in payload:
		raise ApiError("AMOUNT_REQUIRED", "amount الزامی است", http_status=422)
	document_date = payload.get("document_date") or datetime.utcnow().date()
	result = evaluate_document_policy_for_amount(
		db,
		business_id=business_id,
		document_type=document_type,
		document_date=document_date,
		amount=payload.get("amount", 0),
	)
	return success_response(result, request)

