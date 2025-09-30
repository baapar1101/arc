from typing import Any, Dict
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import success_response, ApiError
from adapters.db.repositories.category_repository import CategoryRepository


router = APIRouter(prefix="/categories", tags=["categories"])


@router.post("/business/{business_id}/tree")
@require_business_access("business_id")
def get_categories_tree(
    request: Request,
    business_id: int,
    body: Dict[str, Any] | None = None,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    # اجازه مشاهده نیاز به view روی سکشن categories دارد
    if not ctx.can_read_section("categories"):
        raise ApiError("FORBIDDEN", "Missing business permission: categories.view", http_status=403)
    repo = CategoryRepository(db)
    # درخت سراسری: بدون فیلتر نوع
    tree = repo.get_tree(business_id, None)
    # تبدیل کلید title به label به صورت بازگشتی
    def _map_label(nodes: list[Dict[str, Any]]) -> list[Dict[str, Any]]:
        mapped: list[Dict[str, Any]] = []
        for n in nodes:
            children = n.get("children") or []
            mapped.append({
                "id": n.get("id"),
                "parent_id": n.get("parent_id"),
                "label": n.get("title", ""),
                "translations": n.get("translations", {}),
                "children": _map_label(children) if isinstance(children, list) else [],
            })
        return mapped
    items = _map_label(tree)
    return success_response({"items": items}, request)


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_category(
    request: Request,
    business_id: int,
    body: Dict[str, Any],
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("categories", "add"):
        raise ApiError("FORBIDDEN", "Missing business permission: categories.add", http_status=403)
    parent_id = body.get("parent_id")
    label: str = (body.get("label") or "").strip()
    # ساخت ترجمه‌ها از روی برچسب واحد
    translations: Dict[str, str] = {"fa": label, "en": label} if label else {}
    repo = CategoryRepository(db)
    obj = repo.create_category(business_id=business_id, parent_id=parent_id, translations=translations)
    item = {
        "id": obj.id,
        "parent_id": obj.parent_id,
        "label": (obj.title_translations or {}).get(ctx.language)
                 or (obj.title_translations or {}).get("fa")
                 or (obj.title_translations or {}).get("en"),
        "translations": obj.title_translations,
    }
    return success_response({"item": item}, request)


@router.post("/business/{business_id}/update")
@require_business_access("business_id")
def update_category(
    request: Request,
    business_id: int,
    body: Dict[str, Any],
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("categories", "edit"):
        raise ApiError("FORBIDDEN", "Missing business permission: categories.edit", http_status=403)
    category_id = body.get("category_id")
    label = body.get("label")
    translations = {"fa": label, "en": label} if isinstance(label, str) and label.strip() else None
    repo = CategoryRepository(db)
    obj = repo.update_category(category_id=category_id, translations=translations)
    if not obj:
        raise ApiError("NOT_FOUND", "Category not found", http_status=404)
    item = {
        "id": obj.id,
        "parent_id": obj.parent_id,
        "label": (obj.title_translations or {}).get(ctx.language)
                 or (obj.title_translations or {}).get("fa")
                 or (obj.title_translations or {}).get("en"),
        "translations": obj.title_translations,
    }
    return success_response({"item": item}, request)


@router.post("/business/{business_id}/move")
@require_business_access("business_id")
def move_category(
    request: Request,
    business_id: int,
    body: Dict[str, Any],
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("categories", "edit"):
        raise ApiError("FORBIDDEN", "Missing business permission: categories.edit", http_status=403)
    category_id = body.get("category_id")
    new_parent_id = body.get("new_parent_id")
    repo = CategoryRepository(db)
    obj = repo.move_category(category_id=category_id, new_parent_id=new_parent_id)
    if not obj:
        raise ApiError("NOT_FOUND", "Category not found", http_status=404)
    item = {
        "id": obj.id,
        "parent_id": obj.parent_id,
        "label": (obj.title_translations or {}).get(ctx.language)
                 or (obj.title_translations or {}).get("fa")
                 or (obj.title_translations or {}).get("en"),
        "translations": obj.title_translations,
    }
    return success_response({"item": item}, request)


@router.post("/business/{business_id}/delete")
@require_business_access("business_id")
def delete_category(
    request: Request,
    business_id: int,
    body: Dict[str, Any],
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("categories", "delete"):
        raise ApiError("FORBIDDEN", "Missing business permission: categories.delete", http_status=403)
    repo = CategoryRepository(db)
    category_id = body.get("category_id")
    ok = repo.delete_category(category_id=category_id)
    return success_response({"deleted": ok}, request)


