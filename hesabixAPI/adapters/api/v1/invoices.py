from typing import Dict, Any
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import success_response
from adapters.api.v1.schemas import QueryInfo


router = APIRouter(prefix="/invoices", tags=["invoices"])  # Stubs only


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_invoice_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any],
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    # Stub only: no implementation yet
    return success_response(data={}, request=request, message="INVOICE_CREATE_STUB")


@router.put("/business/{business_id}/{invoice_id}")
@require_business_access("business_id")
def update_invoice_endpoint(
    request: Request,
    business_id: int,
    invoice_id: int,
    payload: Dict[str, Any],
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    # Stub only: no implementation yet
    return success_response(data={}, request=request, message="INVOICE_UPDATE_STUB")


@router.get("/business/{business_id}/{invoice_id}")
@require_business_access("business_id")
def get_invoice_endpoint(
    request: Request,
    business_id: int,
    invoice_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    # Stub only: no implementation yet
    return success_response(data={"item": None}, request=request, message="INVOICE_GET_STUB")


@router.post("/business/{business_id}/search")
@require_business_access("business_id")
def search_invoices_endpoint(
    request: Request,
    business_id: int,
    query_info: QueryInfo,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    # Stub only: no implementation yet
    return success_response(data={"items": [], "total": 0, "take": query_info.take, "skip": query_info.skip}, request=request, message="INVOICE_SEARCH_STUB")


