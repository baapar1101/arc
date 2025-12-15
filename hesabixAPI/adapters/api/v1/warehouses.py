# Removed __future__ annotations to fix OpenAPI schema generation

from typing import Dict, Any
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep, require_business_permission_by_entity_dep
from app.core.responses import success_response, ApiError, format_datetime_fields
from adapters.api.v1.schemas import QueryInfo, PaginatedResponse
from adapters.api.v1.schema_models.warehouse import (
    WarehouseCreateRequest,
    WarehouseUpdateRequest,
)
from app.services.warehouse_service import (
    create_warehouse,
    list_warehouses,
    get_warehouse,
    update_warehouse,
    delete_warehouse,
    query_warehouses,
    get_warehouse_stock_report,
)
from adapters.db.models.warehouse import Warehouse
from app.core.cache import get_cache


router = APIRouter(prefix="/warehouses", tags=["انبارداری"])


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_warehouse_endpoint(
    request: Request,
    business_id: int,
    payload: WarehouseCreateRequest = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("warehouses", "add")),
) -> Dict[str, Any]:
    result = create_warehouse(db, business_id, payload)
    return success_response(data=format_datetime_fields(result["data"], request), request=request, message=result.get("message"))


@router.get("/business/{business_id}")
@require_business_access("business_id")
def list_warehouses_endpoint(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("warehouses", "view")),
) -> Dict[str, Any]:
    # کش لیست انبارها
    cache = get_cache()
    cache_key = None
    
    if cache.enabled:
        import json, hashlib
        key_payload = {
            "business_id": business_id,
            "endpoint": "list_warehouses"
        }
        key_str = json.dumps(key_payload, sort_keys=True, ensure_ascii=False)
        key_hash = hashlib.sha256(key_str.encode("utf-8")).hexdigest()[:16]
        cache_key = f"warehouses_list:{key_hash}"
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(data=format_datetime_fields(cached, request), request=request)
    
    result = list_warehouses(db, business_id)
    
    # ذخیره در cache با tag-based caching
    if cache.enabled and cache_key:
        cache.set_with_warehouses_tag(
            key=cache_key,
            value=result,
            business_id=business_id,
            ttl=60
        )
    
    return success_response(data=format_datetime_fields(result, request), request=request)


@router.get("/business/{business_id}/{warehouse_id}")
@require_business_access("business_id")
def get_warehouse_endpoint(
    request: Request,
    business_id: int,
    warehouse_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_by_entity_dep("warehouses", "view", Warehouse, "warehouse_id")),
) -> Dict[str, Any]:
    item = get_warehouse(db, business_id, warehouse_id)
    if not item:
        raise ApiError("NOT_FOUND", "Warehouse not found", http_status=404)
    return success_response(data=format_datetime_fields({"item": item}, request), request=request)


@router.put("/business/{business_id}/{warehouse_id}")
@require_business_access("business_id")
def update_warehouse_endpoint(
    request: Request,
    business_id: int,
    warehouse_id: int,
    payload: WarehouseUpdateRequest = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_by_entity_dep("warehouses", "edit", Warehouse, "warehouse_id")),
) -> Dict[str, Any]:
    result = update_warehouse(db, business_id, warehouse_id, payload)
    if not result:
        raise ApiError("NOT_FOUND", "Warehouse not found", http_status=404)
    return success_response(data=format_datetime_fields(result["data"], request), request=request, message=result.get("message"))


@router.delete("/business/{business_id}/{warehouse_id}")
@require_business_access("business_id")
def delete_warehouse_endpoint(
    request: Request,
    business_id: int,
    warehouse_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_by_entity_dep("warehouses", "delete", Warehouse, "warehouse_id")),
) -> Dict[str, Any]:
    ok = delete_warehouse(db, business_id, warehouse_id)
    return success_response({"deleted": ok}, request)



@router.post("/business/{business_id}/query")
@require_business_access("business_id")
def query_warehouses_endpoint(
    request: Request,
    business_id: int,
    payload: QueryInfo,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("warehouses", "view")),
) -> Dict[str, Any]:
    # کش لیست انبارها با query
    cache = get_cache()
    cache_key = None
    
    if cache.enabled:
        import json, hashlib
        from decimal import Decimal
        from datetime import datetime, date
        
        # Helper function to convert objects to JSON-serializable format
        def to_serializable(obj):
            """Convert Pydantic models and other non-serializable types to dict/primitive types"""
            if hasattr(obj, 'model_dump'):  # Pydantic v2
                return obj.model_dump()
            elif hasattr(obj, 'dict'):  # Pydantic v1
                return obj.dict()
            elif isinstance(obj, (datetime, date)):
                return obj.isoformat()
            elif isinstance(obj, Decimal):
                return float(obj)
            elif isinstance(obj, dict):
                return {k: to_serializable(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [to_serializable(item) for item in obj]
            else:
                return obj
        
        key_payload = {
            "business_id": business_id,
            "query": {
                "sort_by": payload.sort_by,
                "sort_desc": payload.sort_desc,
                "take": payload.take,
                "skip": payload.skip,
                "search": payload.search,
                "search_fields": payload.search_fields,
                "filters": [to_serializable(f) for f in (payload.filters or [])],
            }
        }
        key_str = json.dumps(key_payload, sort_keys=True, ensure_ascii=False)
        key_hash = hashlib.sha256(key_str.encode("utf-8")).hexdigest()[:16]
        cache_key = f"warehouses_list:{key_hash}"
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(data=format_datetime_fields(cached, request), request=request)
    
    result = query_warehouses(db, business_id, payload)
    # تطبیق خروجی با ساختار DataTableResponse (items + pagination)
    data = {
        "items": format_datetime_fields(result["items"], request),
        "pagination": {
            "total": result["total"],
            "page": result["page"],
            "per_page": result["limit"],
            "total_pages": result["total_pages"],
            "has_next": result["page"] < result["total_pages"],
            "has_prev": result["page"] > 1,
        },
        "query_info": payload.model_dump(),
    }
    
    # ذخیره در cache با tag-based caching
    if cache.enabled and cache_key:
        cache.set_with_warehouses_tag(
            key=cache_key,
            value=data,
            business_id=business_id,
            ttl=60
        )
    
    return success_response(data=data, request=request)


@router.post("/business/{business_id}/stock-report")
@require_business_access("business_id")
def stock_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("warehouses", "view")),
) -> Dict[str, Any]:
    """گزارش موجودی انبار."""
    result = get_warehouse_stock_report(db, business_id, body)
    return success_response(data=result, request=request)

