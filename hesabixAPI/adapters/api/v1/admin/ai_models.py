from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Path, Request
from sqlalchemy.orm import Session

from adapters.db.models.ai_model import AIModel
from adapters.db.repositories.ai_model_repository import AIModelRepository
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.services.ai.ai_model_service import serialize_model
from app.services.ai.ai_model_seed_service import seed_models_from_config

router = APIRouter(prefix="/admin/ai/models", tags=["admin-ai-models"])


def _require_admin(ctx: AuthContext) -> None:
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند مدل‌ها را مدیریت کند", http_status=403)


def _serialize(model: AIModel) -> Dict[str, Any]:
    return serialize_model(model)


@router.get("", summary="لیست مدل‌های AI")
async def list_ai_models(
    request: Request,
    only_active: Optional[bool] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    repo = AIModelRepository(db)
    if only_active:
        models = repo.get_active_models()
    else:
        models = repo.get_all()
    return success_response([_serialize(m) for m in models], request)


@router.get("/{model_id}", summary="جزئیات مدل AI")
async def get_ai_model(
    model_id: int = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    repo = AIModelRepository(db)
    model = repo.get_by_id(model_id)
    if not model:
        raise ApiError("MODEL_NOT_FOUND", "مدل یافت نشد", http_status=404)
    return success_response(_serialize(model), request)


@router.post("", summary="ایجاد مدل AI")
async def create_ai_model(
    request: Request,
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    code = str(payload.get("code") or "").strip()
    if not code:
        raise ApiError("CODE_REQUIRED", "کد مدل الزامی است", http_status=400)
    repo = AIModelRepository(db)
    if repo.get_by_code(code):
        raise ApiError("DUPLICATE_MODEL_CODE", "کد مدل تکراری است", http_status=400)

    model = AIModel(
        code=code,
        display_name=str(payload.get("display_name") or code),
        description=payload.get("description"),
        provider=str(payload.get("provider") or "openai"),
        model_id=str(payload.get("model_id") or code),
        tier=payload.get("tier"),
        supports_tools=bool(payload.get("supports_tools", True)),
        max_tokens_default=int(payload.get("max_tokens_default") or 4000),
        reference_input_cost_per_1k=payload.get("reference_input_cost_per_1k"),
        reference_output_cost_per_1k=payload.get("reference_output_cost_per_1k"),
        is_active=bool(payload.get("is_active", True)),
        sort_order=int(payload.get("sort_order") or 0),
    )
    db.add(model)
    db.commit()
    db.refresh(model)
    return success_response(_serialize(model), request, "مدل با موفقیت ایجاد شد")


@router.put("/{model_id}", summary="ویرایش مدل AI")
async def update_ai_model(
    model_id: int = Path(...),
    request: Request = None,
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    repo = AIModelRepository(db)
    model = repo.get_by_id(model_id)
    if not model:
        raise ApiError("MODEL_NOT_FOUND", "مدل یافت نشد", http_status=404)

    allowed = (
        "display_name",
        "description",
        "provider",
        "model_id",
        "tier",
        "supports_tools",
        "max_tokens_default",
        "reference_input_cost_per_1k",
        "reference_output_cost_per_1k",
        "is_active",
        "sort_order",
    )
    for key in allowed:
        if key in payload:
            setattr(model, key, payload[key])

    db.commit()
    db.refresh(model)
    return success_response(_serialize(model), request, "مدل با موفقیت به‌روزرسانی شد")


@router.delete("/{model_id}", summary="غیرفعال کردن مدل AI")
async def deactivate_ai_model(
    model_id: int = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    repo = AIModelRepository(db)
    model = repo.get_by_id(model_id)
    if not model:
        raise ApiError("MODEL_NOT_FOUND", "مدل یافت نشد", http_status=404)
    model.is_active = False
    db.commit()
    return success_response({"id": model.id}, request, "مدل با موفقیت غیرفعال شد")


@router.post("/seed-from-config", summary="ایجاد خودکار مدل‌ها از تنظیمات")
async def seed_models_endpoint(
    request: Request,
    include_presets: bool = Body(True, embed=True),
    force: bool = Body(False, embed=True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    result = seed_models_from_config(db, include_presets=include_presets, force=force)
    return success_response(result, request, "عملیات seed انجام شد")
