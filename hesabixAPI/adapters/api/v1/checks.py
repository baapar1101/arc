from typing import Any, Dict
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.core.permissions import require_business_management_dep, require_business_access
from adapters.api.v1.schemas import QueryInfo
from adapters.api.v1.schema_models.check import (
    CheckCreateRequest,
    CheckUpdateRequest,
)
from app.services.check_service import (
    create_check,
    update_check,
    delete_check,
    get_check_by_id,
    list_checks,
)


router = APIRouter(prefix="/checks", tags=["checks"])


@router.post(
    "/businesses/{business_id}/checks",
    summary="لیست چک‌های کسب‌وکار",
    description="دریافت لیست چک‌ها با جستجو/فیلتر",
)
@require_business_access("business_id")
async def list_checks_endpoint(
    request: Request,
    business_id: int,
    query_info: QueryInfo,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    query_dict: Dict[str, Any] = {
        "take": query_info.take,
        "skip": query_info.skip,
        "sort_by": query_info.sort_by,
        "sort_desc": query_info.sort_desc,
        "search": query_info.search,
        "search_fields": query_info.search_fields,
        "filters": query_info.filters,
    }
    # additional params: person_id (accept from query params or body)
    # from query params
    if request.query_params.get("person_id"):
        try:
            query_dict["person_id"] = int(request.query_params.get("person_id"))
        except Exception:
            pass
    # from request body (DataTable additionalParams)
    try:
        body_json = await request.json()
        if isinstance(body_json, dict) and body_json.get("person_id") is not None:
            try:
                query_dict["person_id"] = int(body_json.get("person_id"))
            except Exception:
                pass
    except Exception:
        pass
    result = list_checks(db, business_id, query_dict)
    result["items"] = [format_datetime_fields(item, request) for item in result.get("items", [])]
    return success_response(data=result, request=request, message="CHECKS_LIST_FETCHED")


@router.post(
    "/businesses/{business_id}/checks/create",
    summary="ایجاد چک",
    description="ایجاد چک جدید برای کسب‌وکار",
)
@require_business_access("business_id")
async def create_check_endpoint(
    request: Request,
    business_id: int,
    body: CheckCreateRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    payload: Dict[str, Any] = body.model_dump(exclude_unset=True)
    created = create_check(db, business_id, payload)
    return success_response(data=format_datetime_fields(created, request), request=request, message="CHECK_CREATED")


@router.get(
    "/checks/{check_id}",
    summary="جزئیات چک",
    description="دریافت جزئیات چک",
)
async def get_check_endpoint(
    request: Request,
    check_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    result = get_check_by_id(db, check_id)
    if not result:
        raise ApiError("CHECK_NOT_FOUND", "Check not found", http_status=404)
    try:
        biz_id = int(result.get("business_id"))
    except Exception:
        biz_id = None
    if biz_id is not None and not ctx.can_access_business(biz_id):
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    return success_response(data=format_datetime_fields(result, request), request=request, message="CHECK_DETAILS")


@router.put(
    "/checks/{check_id}",
    summary="ویرایش چک",
    description="ویرایش اطلاعات چک",
)
async def update_check_endpoint(
    request: Request,
    check_id: int,
    body: CheckUpdateRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    payload: Dict[str, Any] = body.model_dump(exclude_unset=True)
    result = update_check(db, check_id, payload)
    if result is None:
        raise ApiError("CHECK_NOT_FOUND", "Check not found", http_status=404)
    try:
        biz_id = int(result.get("business_id"))
    except Exception:
        biz_id = None
    if biz_id is not None and not ctx.can_access_business(biz_id):
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    return success_response(data=format_datetime_fields(result, request), request=request, message="CHECK_UPDATED")


@router.delete(
    "/checks/{check_id}",
    summary="حذف چک",
    description="حذف یک چک",
)
async def delete_check_endpoint(
    request: Request,
    check_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    result = get_check_by_id(db, check_id)
    if result:
        try:
            biz_id = int(result.get("business_id"))
        except Exception:
            biz_id = None
        if biz_id is not None and not ctx.can_access_business(biz_id):
            raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    ok = delete_check(db, check_id)
    if not ok:
        raise ApiError("CHECK_NOT_FOUND", "Check not found", http_status=404)
    return success_response(data=None, request=request, message="CHECK_DELETED")


