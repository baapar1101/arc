from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.person_group import (
    PersonGroupCreateRequest,
    PersonGroupUpdateRequest,
)
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_permission_dep
from app.core.responses import ApiError, success_response
from app.services.person_group_service import (
    create_person_group,
    delete_person_group,
    get_person_group,
    list_person_groups,
    serialize_person_group,
    update_person_group,
)

router = APIRouter(prefix="/persons", tags=["گروه اشخاص"])


@router.get(
    "/businesses/{business_id}/person-groups",
    summary="لیست گروه‌های اشخاص",
)
def list_groups(
    request: Request,
    business_id: int,
    db: Session = Depends(get_db),
    _: AuthContext = Depends(get_current_user),
    __: None = Depends(require_business_permission_dep("people", "read")),
    skip: int = Query(0, ge=0),
    take: int = Query(100, ge=1, le=500),
    active_only: bool = Query(False),
    root_only: bool = Query(True),
):
    data = list_person_groups(
        db,
        business_id,
        skip=skip,
        take=take,
        active_only=active_only,
        root_only=root_only,
    )
    return success_response(data=data, request=request)


@router.get(
    "/businesses/{business_id}/person-groups/{group_id}",
    summary="جزئیات یک گروه",
)
def get_group(
    request: Request,
    business_id: int,
    group_id: int,
    db: Session = Depends(get_db),
    _: AuthContext = Depends(get_current_user),
    __: None = Depends(require_business_permission_dep("people", "read")),
):
    g = get_person_group(db, business_id, group_id)
    if not g:
        raise ApiError("PERSON_GROUP_NOT_FOUND", "گروه یافت نشد", http_status=404)

    return success_response(data=serialize_person_group(g), request=request)


@router.post(
    "/businesses/{business_id}/person-groups",
    summary="ایجاد گروه اشخاص",
)
def create_group(
    request: Request,
    business_id: int,
    body: PersonGroupCreateRequest,
    db: Session = Depends(get_db),
    _: AuthContext = Depends(get_current_user),
    __: None = Depends(require_business_permission_dep("people", "add")),
):
    data = create_person_group(db, business_id, body)
    return success_response(data=data, request=request, message="گروه با موفقیت ایجاد شد")


@router.patch(
    "/businesses/{business_id}/person-groups/{group_id}",
    summary="ویرایش گروه اشخاص",
)
def patch_group(
    request: Request,
    business_id: int,
    group_id: int,
    body: PersonGroupUpdateRequest,
    db: Session = Depends(get_db),
    _: AuthContext = Depends(get_current_user),
    __: None = Depends(require_business_permission_dep("people", "edit")),
):
    data = update_person_group(db, business_id, group_id, body)
    if not data:
        raise ApiError("PERSON_GROUP_NOT_FOUND", "گروه یافت نشد", http_status=404)
    return success_response(data=data, request=request, message="گروه با موفقیت به‌روزرسانی شد")


@router.delete(
    "/businesses/{business_id}/person-groups/{group_id}",
    summary="حذف گروه اشخاص",
)
def remove_group(
    request: Request,
    business_id: int,
    group_id: int,
    db: Session = Depends(get_db),
    _: AuthContext = Depends(get_current_user),
    __: None = Depends(require_business_permission_dep("people", "delete")),
):
    try:
        delete_person_group(db, business_id, group_id)
    except ApiError:
        raise
    return success_response(request=request, message="گروه حذف شد")
