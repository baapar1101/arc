from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.production_order import (
	ProductionOrderActionRequest,
	ProductionOrderCreateRequest,
	ProductionOrderLotsUpdateRequest,
	ProductionOrderUpdateRequest,
)
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services.production_order_service import (
	cancel_production_order,
	complete_production_order,
	create_production_order,
	get_production_order,
	get_production_order_costing,
	get_production_material_plan,
	list_production_orders,
	list_production_orders_by_lot,
	refresh_production_order_actual_costs,
	release_production_order,
	start_production_order,
	update_production_order,
	update_production_order_lots,
)

router = APIRouter(prefix="/production/orders", tags=["production-orders"])


def _write_permission(ctx: AuthContext) -> None:
	if not ctx.has_business_permission("inventory", "write"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)


@router.get("/business/{business_id}")
@require_business_access("business_id")
def list_production_orders_endpoint(
	request: Request,
	business_id: int,
	status: str | None = Query(default=None),
	product_id: int | None = Query(default=None, gt=0),
	due_from: str | None = Query(default=None),
	due_to: str | None = Query(default=None),
	skip: int = Query(default=0, ge=0),
	take: int = Query(default=50, ge=1, le=200),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	if not ctx.can_read_section("inventory"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
	from datetime import date
	try:
		start = date.fromisoformat(due_from) if due_from else None
		end = date.fromisoformat(due_to) if due_to else None
	except ValueError as exc:
		raise ApiError("INVALID_DATE", "فرمت تاریخ باید YYYY-MM-DD باشد", http_status=400) from exc
	if start and end and start > end:
		raise ApiError("INVALID_DATE_RANGE", "تاریخ شروع فیلتر نمی‌تواند بعد از تاریخ پایان باشد", http_status=400)
	data = list_production_orders(db, business_id, status=status, product_id=product_id, due_from=start, due_to=end, skip=skip, take=take)
	return success_response(data=format_datetime_fields(data, request), request=request)


@router.get("/business/{business_id}/material-plan")
@require_business_access("business_id")
def get_production_material_plan_endpoint(
	request: Request,
	business_id: int,
	due_from: str | None = Query(default=None),
	due_to: str | None = Query(default=None),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	if not ctx.can_read_section("inventory"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
	from datetime import date
	try:
		start = date.fromisoformat(due_from) if due_from else None
		end = date.fromisoformat(due_to) if due_to else None
	except ValueError as exc:
		raise ApiError("INVALID_DATE", "فرمت تاریخ باید YYYY-MM-DD باشد", http_status=400) from exc
	if start and end and start > end:
		raise ApiError("INVALID_DATE_RANGE", "تاریخ شروع فیلتر نمی‌تواند بعد از تاریخ پایان باشد", http_status=400)
	data = get_production_material_plan(db, business_id, due_from=start, due_to=end)
	return success_response(data=format_datetime_fields(data, request), request=request)


@router.get("/business/{business_id}/trace")
@require_business_access("business_id")
def trace_production_orders_by_lot_endpoint(
	request: Request,
	business_id: int,
	lot_code: str = Query(..., min_length=1, max_length=64),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	if not ctx.can_read_section("inventory"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
	data = list_production_orders_by_lot(db, business_id, lot_code)
	return success_response(data=format_datetime_fields(data, request), request=request)


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_production_order_endpoint(
	request: Request,
	business_id: int,
	payload: ProductionOrderCreateRequest,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	_write_permission(ctx)
	data = create_production_order(db, business_id, ctx.get_user_id(), payload)
	db.commit()
	return success_response(data=format_datetime_fields(data, request), request=request, message="PRODUCTION_ORDER_CREATED")


@router.get("/business/{business_id}/{order_id}")
@require_business_access("business_id")
def get_production_order_endpoint(
	request: Request,
	business_id: int,
	order_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	if not ctx.can_read_section("inventory"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
	data = get_production_order(db, business_id, order_id)
	return success_response(data=format_datetime_fields(data, request), request=request)


@router.patch("/business/{business_id}/{order_id}")
@require_business_access("business_id")
def update_production_order_endpoint(
	request: Request,
	business_id: int,
	order_id: int,
	payload: ProductionOrderUpdateRequest,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	_write_permission(ctx)
	data = update_production_order(db, business_id, order_id, payload)
	db.commit()
	return success_response(data=format_datetime_fields(data, request), request=request, message="PRODUCTION_ORDER_UPDATED")


def _action(
	request: Request,
	business_id: int,
	order_id: int,
	payload: ProductionOrderActionRequest,
	ctx: AuthContext,
	db: Session,
	operation: Any,
	message: str,
) -> Dict[str, Any]:
	_write_permission(ctx)
	data = operation(db, business_id, order_id, payload.version)
	db.commit()
	return success_response(data=format_datetime_fields(data, request), request=request, message=message)


@router.post("/business/{business_id}/{order_id}/release")
@require_business_access("business_id")
def release_production_order_endpoint(request: Request, business_id: int, order_id: int, payload: ProductionOrderActionRequest, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db)) -> Dict[str, Any]:
	return _action(request, business_id, order_id, payload, ctx, db, release_production_order, "PRODUCTION_ORDER_RELEASED")


@router.post("/business/{business_id}/{order_id}/start")
@require_business_access("business_id")
def start_production_order_endpoint(request: Request, business_id: int, order_id: int, payload: ProductionOrderActionRequest, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db)) -> Dict[str, Any]:
	return _action(request, business_id, order_id, payload, ctx, db, start_production_order, "PRODUCTION_ORDER_STARTED")


@router.post("/business/{business_id}/{order_id}/complete")
@require_business_access("business_id")
def complete_production_order_endpoint(request: Request, business_id: int, order_id: int, payload: ProductionOrderActionRequest, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db)) -> Dict[str, Any]:
	_write_permission(ctx)
	data = complete_production_order(db, business_id, order_id, payload.version, payload.close_reason)
	db.commit()
	return success_response(data=format_datetime_fields(data, request), request=request, message="PRODUCTION_ORDER_COMPLETED")


@router.post("/business/{business_id}/{order_id}/cancel")
@require_business_access("business_id")
def cancel_production_order_endpoint(request: Request, business_id: int, order_id: int, payload: ProductionOrderActionRequest, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db)) -> Dict[str, Any]:
	return _action(request, business_id, order_id, payload, ctx, db, cancel_production_order, "PRODUCTION_ORDER_CANCELLED")


@router.get("/business/{business_id}/{order_id}/costing")
@require_business_access("business_id")
def get_production_order_costing_endpoint(
	request: Request,
	business_id: int,
	order_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	if not ctx.can_read_section("inventory"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
	data = get_production_order_costing(db, business_id, order_id)
	return success_response(data=format_datetime_fields(data, request), request=request)


@router.post("/business/{business_id}/{order_id}/costing/refresh")
@require_business_access("business_id")
def refresh_production_order_costing_endpoint(
	request: Request,
	business_id: int,
	order_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	_write_permission(ctx)
	data = refresh_production_order_actual_costs(db, business_id, order_id)
	db.commit()
	return success_response(data=format_datetime_fields(data, request), request=request, message="PRODUCTION_ORDER_COSTING_REFRESHED")


@router.patch("/business/{business_id}/{order_id}/lots")
@require_business_access("business_id")
def update_production_order_lots_endpoint(
	request: Request,
	business_id: int,
	order_id: int,
	payload: ProductionOrderLotsUpdateRequest,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	_write_permission(ctx)
	data = update_production_order_lots(
		db,
		business_id,
		order_id,
		expected_version=payload.version,
		material_lots=[row.model_dump() for row in (payload.materials or [])],
		output_lots=[row.model_dump() for row in (payload.outputs or [])],
	)
	db.commit()
	return success_response(data=format_datetime_fields(data, request), request=request, message="PRODUCTION_ORDER_LOTS_UPDATED")
