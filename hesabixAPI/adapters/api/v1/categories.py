from typing import Any, Dict
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response, ApiError
from adapters.db.repositories.category_repository import CategoryRepository


router = APIRouter(prefix="/categories", tags=["محصولات و کالاها"])


@router.post("/business/{business_id}/tree")
@require_business_access("business_id")
def get_categories_tree(
    request: Request,
    business_id: int,
    body: Dict[str, Any] | None = None,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("categories", "view")),
) -> Dict[str, Any]:
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
                "description": n.get("description"),
                "sort_order": n.get("sort_order", 0),
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
    _: None = Depends(require_business_permission_dep("categories", "add")),
) -> Dict[str, Any]:
    parent_id = body.get("parent_id")
    label: str = (body.get("label") or "").strip()
    description: str | None = body.get("description")
    if description:
        description = description.strip() if isinstance(description, str) else None
    # ساخت ترجمه‌ها از روی برچسب واحد
    translations: Dict[str, str] = {"fa": label, "en": label} if label else {}
    repo = CategoryRepository(db)
    obj = repo.create_category(business_id=business_id, parent_id=parent_id, translations=translations, description=description)
    item = {
        "id": obj.id,
        "parent_id": obj.parent_id,
        "label": (obj.title_translations or {}).get(ctx.language)
                 or (obj.title_translations or {}).get("fa")
                 or (obj.title_translations or {}).get("en"),
        "translations": obj.title_translations,
        "description": obj.description,
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
    _: None = Depends(require_business_permission_dep("categories", "edit")),
) -> Dict[str, Any]:
    category_id = body.get("category_id")
    label = body.get("label")
    description = body.get("description")
    sort_order = body.get("sort_order")
    parent_id = body.get("parent_id")
    
    if description is not None:
        description = description.strip() if isinstance(description, str) else None
    
    # تبدیل sort_order به int
    sort_order_int = None
    if sort_order is not None:
        try:
            sort_order_int = int(sort_order)
        except (ValueError, TypeError):
            sort_order_int = None
    
    # تبدیل parent_id به int یا None
    parent_id_int = None
    if parent_id is not None:
        if parent_id == "" or parent_id == "null":
            parent_id_int = None
        else:
            try:
                parent_id_int = int(parent_id)
            except (ValueError, TypeError):
                parent_id_int = None
    
    translations = {"fa": label, "en": label} if isinstance(label, str) and label.strip() else None
    repo = CategoryRepository(db)
    try:
        obj = repo.update_category(
            category_id=category_id,
            translations=translations,
            description=description,
            sort_order=sort_order_int,
            parent_id=parent_id_int if parent_id is not None else None,  # فقط اگر ارسال شده باشد
        )
    except ValueError as e:
        raise ApiError("INVALID_REQUEST", str(e), http_status=400)
    
    if not obj:
        raise ApiError("NOT_FOUND", "Category not found", http_status=404)
    item = {
        "id": obj.id,
        "parent_id": obj.parent_id,
        "label": (obj.title_translations or {}).get(ctx.language)
                 or (obj.title_translations or {}).get("fa")
                 or (obj.title_translations or {}).get("en"),
        "translations": obj.title_translations,
        "description": obj.description,
        "sort_order": obj.sort_order,
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
    _: None = Depends(require_business_permission_dep("categories", "edit")),
) -> Dict[str, Any]:
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
        "description": obj.description,
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
    _: None = Depends(require_business_permission_dep("categories", "delete")),
) -> Dict[str, Any]:
    repo = CategoryRepository(db)
    category_id = body.get("category_id")
    ok = repo.delete_category(category_id=category_id)
    return success_response({"deleted": ok}, request)


# Server-side search categories with breadcrumb path
@router.post("/business/{business_id}/search")
@require_business_access("business_id")
def search_categories(
    request: Request,
    business_id: int,
    body: Dict[str, Any] | None = None,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("categories", "view")),
) -> Dict[str, Any]:
    q = (body or {}).get("query") if isinstance(body, dict) else None
    limit = (body or {}).get("limit") if isinstance(body, dict) else None
    if not isinstance(q, str) or not q.strip():
        return success_response({"items": []}, request)
    try:
        limit_int = int(limit) if isinstance(limit, int) or (isinstance(limit, str) and str(limit).isdigit()) else 50
        limit_int = max(1, min(limit_int, 200))
    except Exception:
        limit_int = 50
    repo = CategoryRepository(db)
    items = repo.search_with_paths(business_id=business_id, query=q.strip(), limit=limit_int)
    # map label consistently
    mapped = [
        {
            "id": it.get("id"),
            "parent_id": it.get("parent_id"),
            "label": it.get("title") or "",
            "translations": it.get("translations") or {},
            "description": it.get("description"),
            "path": it.get("path") or [],
        }
        for it in items
    ]
    return success_response({"items": mapped}, request)

