from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Body, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.models.received_loan_facility import ReceivedLoanFacility
from adapters.db.session import get_db
from adapters.api.v1.schemas import QueryInfo
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import (
	require_business_access,
	require_business_permission_dep,
	require_business_permission_by_entity_dep,
)
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services.received_loan_facility_service import (
	create_facility,
	delete_facility,
	delete_loan_payment,
	get_facility_by_id,
	list_facilities,
	record_payment,
	regenerate_schedule,
	update_facility,
)

router = APIRouter(prefix="/loan-facilities", tags=["تسهیلات دریافتی"])


@router.post(
	"/businesses/{business_id}/query",
	summary="فهرست تسهیلات دریافتی",
)
@require_business_access("business_id")
def list_facilities_endpoint(
	request: Request,
	business_id: int,
	query_info: QueryInfo,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("loan_facilities", "view")),
):
	qd = {
		"take": query_info.take,
		"skip": query_info.skip,
		"search": query_info.search or "",
		"sort_desc": getattr(query_info, "sort_desc", True),
	}
	res = list_facilities(db, business_id, qd)
	return success_response(data=res, request=request, message="LOAN_FACILITIES_LISTED")


@router.post(
	"/businesses/{business_id}/create",
	summary="ایجاد قرارداد تسهیلات (پیش‌نویس)",
)
@require_business_access("business_id")
def create_facility_endpoint(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("loan_facilities", "add")),
):
	payload = dict(body or {})
	user_id = ctx.get_user_id()
	if not user_id:
		raise ApiError("UNAUTHORIZED", "User required", http_status=401)
	created = create_facility(db, business_id, user_id, payload)
	return success_response(data=format_datetime_fields(created, request), request=request, message="LOAN_FACILITY_CREATED")


@router.get(
	"/{facility_id}",
	summary="جزئیات تسهیلات با اقساط",
)
def get_facility_endpoint(
	request: Request,
	facility_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_by_entity_dep("loan_facilities", "view", ReceivedLoanFacility, "facility_id")),
):
	row = get_facility_by_id(db, facility_id, with_installments=True)
	if not row:
		raise ApiError("NOT_FOUND", "Facility not found", http_status=404)
	return success_response(data=format_datetime_fields(row, request), request=request, message="LOAN_FACILITY_FETCHED")


@router.patch(
	"/{facility_id}",
	summary="به‌روزرسانی قرارداد",
)
def update_facility_endpoint(
	request: Request,
	facility_id: int,
	body: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_by_entity_dep("loan_facilities", "edit", ReceivedLoanFacility, "facility_id")),
):
	updated = update_facility(db, facility_id, dict(body or {}))
	if updated is None:
		raise ApiError("NOT_FOUND", "Facility not found", http_status=404)
	return success_response(data=format_datetime_fields(updated, request), request=request, message="LOAN_FACILITY_UPDATED")


@router.delete(
	"/{facility_id}",
	summary="حذف قرارداد پیش‌نویس",
)
def delete_facility_endpoint(
	request: Request,
	facility_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_by_entity_dep("loan_facilities", "delete", ReceivedLoanFacility, "facility_id")),
):
	obj = db.get(ReceivedLoanFacility, facility_id)
	if obj is None:
		raise ApiError("NOT_FOUND", "Facility not found", http_status=404)
	business_id = obj.business_id
	ok = delete_facility(db, facility_id, business_id)
	if not ok:
		raise ApiError("NOT_FOUND", "Facility not found", http_status=404)
	return success_response(data={"deleted": True}, request=request, message="LOAN_FACILITY_DELETED")


@router.post(
	"/{facility_id}/schedule",
	summary="تولید یا بازسازی جدول اقساط",
)
def schedule_facility_endpoint(
	request: Request,
	facility_id: int,
	body: Dict[str, Any] = Body(default={}),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_by_entity_dep("loan_facilities", "edit", ReceivedLoanFacility, "facility_id")),
):
	payload = dict(body or {})
	uid = ctx.get_user_id()
	if not uid:
		raise ApiError("UNAUTHORIZED", "User required", http_status=401)
	row = regenerate_schedule(db, facility_id, payload, int(uid))
	return success_response(data=format_datetime_fields(row, request), request=request, message="LOAN_FACILITY_SCHEDULED")


@router.post(
	"/businesses/{business_id}/facilities/{facility_id}/installments/{installment_id}/payments",
	summary="ثبت پرداخت قسط",
)
@require_business_access("business_id")
def pay_installment_endpoint(
	request: Request,
	business_id: int,
	facility_id: int,
	installment_id: int,
	body: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("loan_facilities", "edit")),
):
	f = db.get(ReceivedLoanFacility, facility_id)
	if not f or f.business_id != business_id:
		raise ApiError("NOT_FOUND", "Facility not found", http_status=404)
	user_id = ctx.get_user_id()
	if not user_id:
		raise ApiError("UNAUTHORIZED", "User required", http_status=401)
	res = record_payment(db, business_id, user_id, facility_id, installment_id, dict(body or {}))
	return success_response(data=format_datetime_fields(res, request), request=request, message="LOAN_PAYMENT_RECORDED")


@router.delete(
	"/businesses/{business_id}/facilities/{facility_id}/installments/{installment_id}/payments/{payment_id}",
	summary="حذف پرداخت قسط و سند حسابداری مرتبط",
)
@require_business_access("business_id")
def delete_installment_payment_endpoint(
	request: Request,
	business_id: int,
	facility_id: int,
	installment_id: int,
	payment_id: int,
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("loan_facilities", "edit")),
):
	f = db.get(ReceivedLoanFacility, facility_id)
	if not f or f.business_id != business_id:
		raise ApiError("NOT_FOUND", "Facility not found", http_status=404)
	res = delete_loan_payment(db, business_id, facility_id, installment_id, payment_id)
	return success_response(data=format_datetime_fields(res, request), request=request, message="LOAN_PAYMENT_DELETED")

