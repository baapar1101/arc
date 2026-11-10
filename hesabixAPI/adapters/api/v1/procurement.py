"""API افزونه تدارکات."""
from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, Body, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import (
	has_business_permission_for_business,
	has_invoice_type_permission_for_business,
	require_business_access_dep,
)
from app.core.plugin_license import is_plugin_active
from app.core.procurement_plugin_dependency import PLUGIN_CODE, require_procurement_plugin_active
from app.core.responses import ApiError, success_response
from app.services import procurement_service as svc

router = APIRouter(prefix="/procurement", tags=["procurement"])
public_router = APIRouter(prefix="/public/procurement", tags=["procurement-public"])

_PLUGIN = Depends(require_procurement_plugin_active())
_ACCESS = Depends(require_business_access_dep)


def _allow(ctx: AuthContext, db: Session, business_id: int, action: str) -> None:
	if ctx.is_superadmin() or ctx.is_business_owner(business_id):
		return
	if has_business_permission_for_business(ctx, db, business_id, "procurement", "admin"):
		return
	if has_business_permission_for_business(ctx, db, business_id, "procurement", action):
		return
	if action == "view" and any(
		has_business_permission_for_business(ctx, db, business_id, "procurement", item)
		for item in ("operate", "approve", "manage")
	):
		return
	raise ApiError("FORBIDDEN", "مجوز تدارکات کافی نیست.", http_status=403)


def _require_purchase_invoice(ctx: AuthContext, db: Session, business_id: int) -> None:
	if has_invoice_type_permission_for_business(ctx, db, business_id, "invoice_purchase", "add"):
		return
	raise ApiError("FORBIDDEN", "مجوز ثبت فاکتور خرید لازم است.", http_status=403)


def _ok(data: Any, request: Request) -> dict:
	return success_response(data, request)


@router.get("/business/{business_id}/dashboard")
def dashboard(request: Request, business_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.dashboard(db, business_id, ctx.get_user_id()), request)


@router.get("/business/{business_id}/settings")
def get_settings(request: Request, business_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.get_settings(db, business_id), request)


@router.put("/business/{business_id}/settings")
def update_settings(request: Request, business_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "manage")
	return _ok(svc.update_settings(db, business_id, payload, ctx.get_user_id()), request)


@router.get("/business/{business_id}/suppliers")
def list_suppliers(request: Request, business_id: int, status: Optional[str] = None, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.list_suppliers(db, business_id, status), request)


@router.post("/business/{business_id}/suppliers")
def upsert_supplier(request: Request, business_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "manage")
	return _ok(svc.upsert_supplier(db, business_id, payload, ctx.get_user_id()), request)


@router.get("/business/{business_id}/suppliers/{profile_id}/documents")
def list_supplier_documents(request: Request, business_id: int, profile_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.list_supplier_documents(db, business_id, profile_id), request)


@router.post("/business/{business_id}/suppliers/{profile_id}/documents")
def add_supplier_document(request: Request, business_id: int, profile_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "manage")
	return _ok(svc.add_supplier_document(db, business_id, profile_id, payload, ctx.get_user_id()), request)


@router.get("/business/{business_id}/cost-centers")
def list_cost_centers(request: Request, business_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.list_cost_centers(db, business_id), request)


@router.post("/business/{business_id}/cost-centers")
def create_cost_center(request: Request, business_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "manage")
	return _ok(svc.create_cost_center(db, business_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/delegations")
def create_delegation(request: Request, business_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "manage")
	return _ok(svc.create_delegation(db, business_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/demand/preview")
def preview_demand(request: Request, business_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.preview_demand(db, business_id, payload), request)


@router.get("/business/{business_id}/requisitions")
def list_requisitions(request: Request, business_id: int, status: Optional[str] = None, limit: int = 100, skip: int = 0, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.list_requisitions(db, business_id, status, limit, skip), request)


@router.post("/business/{business_id}/requisitions")
def create_requisition(request: Request, business_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.create_requisition(db, business_id, payload, ctx.get_user_id()), request)


@router.get("/business/{business_id}/requisitions/{requisition_id}")
def get_requisition(request: Request, business_id: int, requisition_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.get_requisition(db, business_id, requisition_id), request)


@router.put("/business/{business_id}/requisitions/{requisition_id}")
def update_requisition(request: Request, business_id: int, requisition_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.update_requisition(db, business_id, requisition_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/requisitions/{requisition_id}/submit")
def submit_requisition(request: Request, business_id: int, requisition_id: int, payload: dict = Body(default={}), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.submit_requisition(db, business_id, requisition_id, payload or {}, ctx.get_user_id()), request)


@router.post("/business/{business_id}/requisitions/{requisition_id}/order")
def order_from_requisition(request: Request, business_id: int, requisition_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.create_order_from_requisition(db, business_id, requisition_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/decisions/{entity_type}/{entity_id}")
def decide(request: Request, business_id: int, entity_type: str, entity_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "approve")
	return _ok(svc.decide(db, business_id, entity_type, entity_id, str(payload.get("action") or ""), payload.get("note"), ctx.get_user_id()), request)


@router.get("/business/{business_id}/orders")
def list_orders(request: Request, business_id: int, status: Optional[str] = None, limit: int = 100, skip: int = 0, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.list_orders(db, business_id, status, limit, skip), request)


@router.post("/business/{business_id}/orders")
def create_order(request: Request, business_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.create_order(db, business_id, payload, ctx.get_user_id()), request)


@router.get("/business/{business_id}/orders/{order_id}")
def get_order(request: Request, business_id: int, order_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.get_order(db, business_id, order_id), request)


@router.put("/business/{business_id}/orders/{order_id}")
def update_order(request: Request, business_id: int, order_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.update_order(db, business_id, order_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/orders/{order_id}/submit")
def submit_order(request: Request, business_id: int, order_id: int, payload: dict = Body(default={}), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.submit_order(db, business_id, order_id, payload or {}, ctx.get_user_id()), request)


@router.post("/business/{business_id}/orders/{order_id}/send")
def send_order(request: Request, business_id: int, order_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.mark_order_sent(db, business_id, order_id, ctx.get_user_id()), request)


@router.post("/business/{business_id}/orders/{order_id}/cancel")
def cancel_order(request: Request, business_id: int, order_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.cancel_order(db, business_id, order_id, ctx.get_user_id()), request)


@router.post("/business/{business_id}/orders/{order_id}/receipts")
def receive_order(request: Request, business_id: int, order_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.receive_order(db, business_id, order_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/orders/{order_id}/returns")
def return_order(request: Request, business_id: int, order_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.return_to_supplier(db, business_id, order_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/orders/{order_id}/invoice")
def invoice_order(request: Request, business_id: int, order_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	_require_purchase_invoice(ctx, db, business_id)
	if payload.get("accept_price_variance"):
		_allow(ctx, db, business_id, "approve")
	return _ok(svc.create_invoice_for_order(db, business_id, order_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/orders/{order_id}/close")
def close_order(request: Request, business_id: int, order_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.close_order(db, business_id, order_id, ctx.get_user_id()), request)


@router.post("/business/{business_id}/orders/{order_id}/prepayments")
def prepay(request: Request, business_id: int, order_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.link_prepayment(db, business_id, order_id, payload, ctx.get_user_id()), request)


@router.get("/business/{business_id}/sourcing")
def list_sourcing(request: Request, business_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.list_sourcing(db, business_id), request)


@router.post("/business/{business_id}/sourcing")
def create_sourcing(request: Request, business_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.create_sourcing(db, business_id, payload, ctx.get_user_id()), request)


@router.get("/business/{business_id}/sourcing/{event_id}")
def get_sourcing(request: Request, business_id: int, event_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.get_sourcing(db, business_id, event_id), request)


@router.post("/business/{business_id}/sourcing/{event_id}/invites")
def invite(request: Request, business_id: int, event_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.invite_suppliers(db, business_id, event_id, payload.get("person_ids") or [], ctx.get_user_id()), request)


@router.post("/business/{business_id}/sourcing/invites/{invite_id}/bids")
def bid(request: Request, business_id: int, invite_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.submit_bid(db, business_id, invite_id, payload, ctx.get_user_id()), request)


@router.get("/business/{business_id}/sourcing/{event_id}/comparison")
def compare(request: Request, business_id: int, event_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.compare_sourcing(db, business_id, event_id), request)


@router.post("/business/{business_id}/sourcing/{event_id}/open-technical")
def open_technical(request: Request, business_id: int, event_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "approve")
	return _ok(svc.open_technical(db, business_id, event_id, ctx.get_user_id()), request)


@router.post("/business/{business_id}/sourcing/{event_id}/technical-scores")
def technical_scores(request: Request, business_id: int, event_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "approve")
	return _ok(svc.score_technical(db, business_id, event_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/sourcing/{event_id}/open-financial")
def open_financial(request: Request, business_id: int, event_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "approve")
	return _ok(svc.open_financial(db, business_id, event_id, ctx.get_user_id()), request)


@router.post("/business/{business_id}/sourcing/{event_id}/minutes")
def minutes(request: Request, business_id: int, event_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "approve")
	return _ok(svc.record_minutes(db, business_id, event_id, str(payload.get("minutes") or ""), ctx.get_user_id()), request)


@router.post("/business/{business_id}/sourcing/{event_id}/award")
def award(request: Request, business_id: int, event_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "approve")
	return _ok(svc.award_sourcing(db, business_id, event_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/sourcing/{event_id}/lines")
def add_sourcing_lines(request: Request, business_id: int, event_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.add_sourcing_lines(db, business_id, event_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/sourcing/{event_id}/cancel")
def cancel_sourcing(request: Request, business_id: int, event_id: int, payload: dict = Body(default={}), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.cancel_sourcing(db, business_id, event_id, ctx.get_user_id(), payload.get("reason") if isinstance(payload, dict) else None), request)


@router.get("/business/{business_id}/budgets")
def list_budgets(request: Request, business_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.list_budgets(db, business_id), request)


@router.get("/business/{business_id}/budget-movements")
def list_budget_movements(request: Request, business_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.list_pending_budget_movements(db, business_id), request)


@router.post("/business/{business_id}/budgets")
def create_budget(request: Request, business_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "manage")
	return _ok(svc.create_budget(db, business_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/budgets/{budget_id}/increases")
def increase_budget(request: Request, business_id: int, budget_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.request_budget_increase(db, business_id, budget_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/budget-transfers")
def transfer_budget(request: Request, business_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.request_budget_transfer(db, business_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/budget-movements/{movement_id}/resubmit")
def resubmit_budget_movement(request: Request, business_id: int, movement_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.resubmit_budget_movement(db, business_id, movement_id, payload, ctx.get_user_id()), request)


@router.get("/business/{business_id}/contracts")
def list_contracts(request: Request, business_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.list_contracts(db, business_id), request)


@router.post("/business/{business_id}/contracts")
def create_contract(request: Request, business_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "manage")
	return _ok(svc.create_contract(db, business_id, payload, ctx.get_user_id()), request)


@router.get("/business/{business_id}/contracts/{contract_id}")
def get_contract(request: Request, business_id: int, contract_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.get_contract(db, business_id, contract_id), request)


@router.post("/business/{business_id}/contracts/{contract_id}/activate")
def activate_contract(request: Request, business_id: int, contract_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "manage")
	return _ok(svc.activate_contract(db, business_id, contract_id, ctx.get_user_id()), request)


@router.post("/business/{business_id}/contracts/{contract_id}/release")
def release_contract(request: Request, business_id: int, contract_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.release_contract_order(db, business_id, contract_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/guarantees")
def guarantee(request: Request, business_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "manage")
	return _ok(svc.add_guarantee(db, business_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/scores/{person_id}")
def score(request: Request, business_id: int, person_id: int, payload: dict = Body(default={}), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "manage")
	period = str((payload or {}).get("period_key") or "")
	if not period:
		from datetime import date
		period = date.today().strftime("%Y-%m")
	return _ok(svc.recompute_score(db, business_id, person_id, period, ctx.get_user_id()), request)


@router.post("/business/{business_id}/reorder/refresh")
def refresh_reorder(request: Request, business_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.refresh_reorder(db, business_id, ctx.get_user_id()), request)


@router.get("/business/{business_id}/reorder")
def list_reorder(request: Request, business_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.list_reorder(db, business_id), request)


@router.post("/business/{business_id}/reorder/{suggestion_id}/convert")
def convert_reorder(request: Request, business_id: int, suggestion_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.convert_reorder(db, business_id, suggestion_id, ctx.get_user_id()), request)


@router.get("/business/{business_id}/products/{product_id}/sources")
def sources(request: Request, business_id: int, product_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "view")
	return _ok(svc.product_sources(db, business_id, product_id), request)


@router.post("/business/{business_id}/share-links")
def share_link(request: Request, business_id: int, payload: dict = Body(...), ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.create_share_link(db, business_id, payload, ctx.get_user_id()), request)


@router.post("/business/{business_id}/share-links/{link_id}/revoke")
def revoke_share_link(request: Request, business_id: int, link_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), _a=_ACCESS, _p=_PLUGIN):
	_allow(ctx, db, business_id, "operate")
	return _ok(svc.revoke_share_link(db, business_id, link_id, ctx.get_user_id()), request)


def _public_plugin(db: Session, business_id: int) -> None:
	if not is_plugin_active(db, business_id, PLUGIN_CODE):
		raise ApiError("PROCUREMENT_PLUGIN_NOT_ACTIVE", "افزونه تدارکات فعال نیست.", http_status=403)


@public_router.get("/{token}")
def public_view(request: Request, token: str, db: Session = Depends(get_db)):
	link = svc._share(db, token)
	_public_plugin(db, link.business_id)
	return _ok(svc.portal_view(db, token), request)


@public_router.post("/{token}/bid")
def public_bid(request: Request, token: str, payload: dict = Body(...), db: Session = Depends(get_db)):
	link = svc._share(db, token)
	_public_plugin(db, link.business_id)
	return _ok(svc.portal_bid(db, token, payload), request)


@public_router.post("/{token}/acknowledge")
def public_ack(request: Request, token: str, db: Session = Depends(get_db)):
	link = svc._share(db, token)
	_public_plugin(db, link.business_id)
	return _ok(svc.portal_ack(db, token), request)


@public_router.post("/{token}/invoice")
def public_invoice(request: Request, token: str, payload: dict = Body(...), db: Session = Depends(get_db)):
	link = svc._share(db, token)
	_public_plugin(db, link.business_id)
	return _ok(svc.portal_invoice_notice(db, token, payload), request)
