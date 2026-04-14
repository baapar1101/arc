from __future__ import annotations

from typing import Dict, Any, List

from fastapi import APIRouter, Depends, Request, Body, Path, Query
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access_dep
from app.core.responses import success_response
from app.services.credit_service import (
	get_business_credit_settings,
	update_business_credit_settings,
	list_installment_plans,
	create_installment_plan,
	update_installment_plan,
	delete_installment_plan,
	get_installment_plan,
	get_person_credit,
	update_person_credit,
)


router = APIRouter(prefix="/businesses/{business_id}/credit", tags=["اعتبار"])


@router.get(
	"/settings",
	summary="دریافت تنظیمات اعتبار کسب‌وکار",
)
def get_credit_settings_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = get_business_credit_settings(db, business_id)
	return success_response(data, request)


@router.put(
	"/settings",
	summary="ویرایش تنظیمات اعتبار کسب‌وکار",
)
def update_credit_settings_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = update_business_credit_settings(db, business_id, payload)
	return success_response(data, request, message="CREDIT_SETTINGS_UPDATED")


@router.get(
	"/installment-plans",
	summary="لیست پلن‌های اقساط",
)
def list_installment_plans_endpoint(
	request: Request,
	business_id: int,
	only_active: bool | None = Query(default=None),
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	items = list_installment_plans(db, business_id, only_active=only_active)
	return success_response({"items": items}, request)


@router.post(
	"/installment-plans",
	summary="ایجاد پلن اقساطی جدید",
)
def create_installment_plan_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = create_installment_plan(db, business_id, payload)
	return success_response(data, request, message="INSTALLMENT_PLAN_CREATED")


@router.get(
	"/installment-plans/{plan_id}",
	summary="دریافت جزئیات پلن اقساطی",
)
def get_installment_plan_endpoint(
	request: Request,
	business_id: int,
	plan_id: int = Path(..., ge=1),
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = get_installment_plan(db, business_id, plan_id)
	return success_response(data, request)


@router.put(
	"/installment-plans/{plan_id}",
	summary="ویرایش پلن اقساطی",
)
def update_installment_plan_endpoint(
	request: Request,
	business_id: int,
	plan_id: int = Path(..., ge=1),
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = update_installment_plan(db, business_id, plan_id, payload)
	return success_response(data, request, message="INSTALLMENT_PLAN_UPDATED")


@router.delete(
	"/installment-plans/{plan_id}",
	summary="حذف پلن اقساطی",
)
def delete_installment_plan_endpoint(
	request: Request,
	business_id: int,
	plan_id: int = Path(..., ge=1),
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = delete_installment_plan(db, business_id, plan_id)
	return success_response(data, request, message="INSTALLMENT_PLAN_DELETED")


@router.get(
	"/persons/{person_id}",
	summary="دریافت تنظیمات اعتبار شخص",
)
def get_person_credit_endpoint(
	request: Request,
	business_id: int,
	person_id: int,
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = get_person_credit(db, business_id, person_id)
	return success_response(data, request)


@router.put(
	"/persons/{person_id}",
	summary="ویرایش تنظیمات اعتبار شخص",
)
def update_person_credit_endpoint(
	request: Request,
	business_id: int,
	person_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = update_person_credit(db, business_id, person_id, payload)
	return success_response(data, request, message="PERSON_CREDIT_UPDATED")


