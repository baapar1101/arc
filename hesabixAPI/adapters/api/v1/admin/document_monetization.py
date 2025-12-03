"""API مدیریت سناریوی درآمدزایی اسناد حسابداری (Admin)"""

from typing import Dict, Any, Optional

from fastapi import APIRouter, Depends, Body, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.document_monetization_service import (
	list_document_subscription_plans,
	create_document_subscription_plan,
	update_document_subscription_plan,
	delete_document_subscription_plan,
	assign_subscription_to_business,
	list_business_policies,
	upsert_business_policy,
	delete_business_policy,
	list_document_usage_charges,
	process_document_usage_queue,
	finalize_volume_periods,
)
from app.services.system_settings_service import (
	get_default_document_policies,
	set_default_document_policies,
)


router = APIRouter(prefix="/admin/document-monetization", tags=["admin-document-monetization"])


def _require_admin(ctx: AuthContext) -> None:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "دسترسی به این بخش ندارید", http_status=403)


@router.get(
	"/subscription-plans",
	summary="لیست پلن‌های اشتراک اسناد",
)
def list_subscription_plans_endpoint(
	request: Request,
	only_active: Optional[bool] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	data = list_document_subscription_plans(db, only_active=only_active)
	return success_response(data, request)


@router.post(
	"/subscription-plans",
	summary="ایجاد پلن اشتراک",
)
def create_subscription_plan_endpoint(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	data = create_document_subscription_plan(db, payload)
	return success_response(data, request, "پلن ایجاد شد")


@router.put(
	"/subscription-plans/{plan_id}",
	summary="ویرایش پلن اشتراک",
)
def update_subscription_plan_endpoint(
	plan_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	data = update_document_subscription_plan(db, plan_id, payload)
	return success_response(data, request, "پلن به‌روزرسانی شد")


@router.delete(
	"/subscription-plans/{plan_id}",
	summary="حذف/غیرفعال کردن پلن",
)
def delete_subscription_plan_endpoint(
	plan_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	data = delete_document_subscription_plan(db, plan_id)
	message = "پلن حذف شد" if data.get("deleted") else "به دلیل وجود اشتراک فعال، پلن غیرفعال شد"
	return success_response(data, request, message)


@router.get(
	"/business/{business_id}/policies",
	summary="لیست سیاست‌های کسب‌وکار",
)
def list_business_policies_endpoint(
	business_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	data = list_business_policies(db, business_id)
	return success_response({"items": data}, request)


@router.post(
	"/business/{business_id}/policies",
	summary="ایجاد سیاست جدید برای کسب‌وکار",
)
def create_business_policy_endpoint(
	business_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	data = upsert_business_policy(db, business_id, payload, ctx.get_user_id())
	return success_response(data, request, "سیاست ذخیره شد")


@router.put(
	"/business/{business_id}/policies/{policy_id}",
	summary="ویرایش سیاست کسب‌وکار",
)
def update_business_policy_endpoint(
	business_id: int,
	policy_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	payload = {**payload, "id": policy_id}
	data = upsert_business_policy(db, business_id, payload, ctx.get_user_id())
	return success_response(data, request, "سیاست به‌روزرسانی شد")


@router.delete(
	"/business/{business_id}/policies/{policy_id}",
	summary="حذف سیاست کسب‌وکار",
)
def delete_business_policy_endpoint(
	business_id: int,
	policy_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	data = delete_business_policy(db, business_id, policy_id)
	return success_response(data, request, "سیاست حذف شد")


@router.post(
	"/business/{business_id}/subscriptions",
	summary="اختصاص پلن اشتراک به کسب‌وکار",
)
def assign_subscription_endpoint(
	business_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	plan_id = payload.get("plan_id")
	if not plan_id:
		raise ApiError("VALIDATION_ERROR", "plan_id الزامی است", http_status=422)
	data = assign_subscription_to_business(
		db,
		business_id,
		int(plan_id),
		ctx.get_user_id(),
		auto_renew=bool(payload.get("auto_renew", False)),
	)
	return success_response(data, request, "پلن برای کسب‌وکار فعال شد")


@router.get(
	"/business/{business_id}/charges",
	summary="لیست صورتحساب‌های سناریوی اسناد",
)
def list_business_charges_endpoint(
	business_id: int,
	request: Request,
	status: Optional[str] = Query(None),
	charge_type: Optional[str] = Query(None),
	limit: int = Query(50, ge=1, le=200),
	skip: int = Query(0, ge=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
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
	"/process-pending",
	summary="اجرای پردازش اسناد معوق",
)
def process_pending_endpoint(
	request: Request,
	batch_size: int = Query(100, ge=1, le=500),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	queue_result = process_document_usage_queue(db, batch_size=batch_size)
	finalize_result = finalize_volume_periods(db)
	return success_response(
		{
			"queue": queue_result,
			"finalize": finalize_result,
		},
		request,
		"پردازش تکمیل شد",
	)


@router.get(
	"/default-policies",
	summary="دریافت سیاست‌های پیش‌فرض کسب‌وکارهای جدید",
)
def get_default_policies_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	policies = get_default_document_policies(db)
	return success_response({"policies": policies}, request)


@router.put(
	"/default-policies",
	summary="تنظیم سیاست‌های پیش‌فرض کسب‌وکارهای جدید",
)
def set_default_policies_endpoint(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	policies = payload.get("policies", [])
	if not isinstance(policies, list):
		raise ApiError("INVALID_PAYLOAD", "فیلد 'policies' باید یک آرایه باشد", http_status=400)
	updated = set_default_document_policies(db, policies)
	return success_response({"policies": updated}, request, "سیاست‌های پیش‌فرض به‌روزرسانی شد")

