"""
API مهارت‌های AI — import، نصب، مارکت‌پلیس (فاز ۱).
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Body, Depends, File, Query, Request, UploadFile
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import ApiError, success_response
from app.services.ai.ai_skill_service import (
    ANTHROPIC_PREBUILT_CATALOG,
    add_skill_review,
    create_native_skill,
    get_package_for_business,
    import_skill_from_git,
    import_skill_zip,
    install_anthropic_prebuilt,
    install_package,
    install_to_dict,
    list_installed,
    list_marketplace_packages,
    list_skill_reviews,
    package_to_dict,
    publish_to_marketplace,
    purchase_skill_package,
    seed_official_skills,
    set_installs_enabled,
    list_owned_packages,
    get_publisher_revenue,
)

_logger = logging.getLogger(__name__)

router = APIRouter(tags=["ai-skills"])


def _skill_value_error(e: ValueError) -> None:
    code = str(e.args[0]) if e.args else "SKILL_ERROR"
    messages = {
        "SKILL_MD_NOT_FOUND": ("SKILL_MD_NOT_FOUND", "فایل SKILL.md در ZIP یافت نشد", 400),
        "SKILL_ZIP_INVALID": ("SKILL_ZIP_INVALID", "فایل ZIP نامعتبر است", 400),
        "SKILL_ZIP_TOO_LARGE": ("SKILL_ZIP_TOO_LARGE", "حجم ZIP بیش از حد مجاز (۱۰MB)", 400),
        "SKILL_SLUG_FORMAT_INVALID": ("SKILL_SLUG_INVALID", "نام مهارت (slug) نامعتبر است", 400),
        "SKILL_DESCRIPTION_REQUIRED": ("SKILL_DESCRIPTION_REQUIRED", "توضیح مهارت الزامی است", 400),
        "SKILL_BODY_REQUIRED": ("SKILL_BODY_REQUIRED", "متن دستورالعمل مهارت خالی است", 400),
        "SKILL_PACKAGE_NOT_FOUND": ("SKILL_PACKAGE_NOT_FOUND", "بسته مهارت یافت نشد", 404),
        "SKILL_PACKAGE_NOT_AVAILABLE": ("SKILL_PACKAGE_NOT_AVAILABLE", "این مهارت قابل نصب نیست", 403),
        "ANTHROPIC_SKILL_UNKNOWN": ("ANTHROPIC_SKILL_UNKNOWN", "مهارت Anthropic ناشناخته است", 400),
        "SKILL_MODERATION_REJECTED": ("SKILL_MODERATION_REJECTED", "محتوای مهارت رد شد", 400),
        "SKILL_REVIEW_RATING_INVALID": ("SKILL_REVIEW_RATING_INVALID", "امتیاز باید ۱ تا ۵ باشد", 400),
        "GIT_URL_REQUIRED": ("GIT_URL_REQUIRED", "آدرس Git الزامی است", 400),
        "GIT_URL_INVALID": ("GIT_URL_INVALID", "آدرس Git نامعتبر است", 400),
        "GIT_URL_UNSUPPORTED_HOST": ("GIT_URL_UNSUPPORTED_HOST", "فقط GitHub پشتیبانی می‌شود", 400),
        "GIT_DOWNLOAD_FAILED": ("GIT_DOWNLOAD_FAILED", "دانلود مخزن ناموفق بود", 502),
    }
    if code in messages:
        c, msg, status = messages[code]
        raise ApiError(c, msg, http_status=status)
    raise ApiError(code, code, http_status=400)


@router.get("/ai/skills/marketplace/packages/{package_id}", summary="جزئیات مهارت مارکت‌پلیس")
async def marketplace_get_package(
    request: Request,
    package_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    from adapters.db.models.ai_skill import AISkillPackage, AISkillVisibility

    pkg = (
        db.query(AISkillPackage)
        .filter(
            AISkillPackage.id == package_id,
            AISkillPackage.visibility == AISkillVisibility.PUBLISHED.value,
        )
        .first()
    )
    if not pkg:
        raise ApiError("SKILL_PACKAGE_NOT_FOUND", "بسته یافت نشد", http_status=404)
    rows, avg, count = list_skill_reviews(db, package_id)
    data = package_to_dict(pkg, include_body=True)
    data["reviews"] = {
        "average_rating": round(avg, 2),
        "count": count,
        "items": [
            {
                "user_id": r.user_id,
                "rating": r.rating,
                "comment": r.comment,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in rows
        ],
    }
    return success_response(data=data, request=request, message="AI_SKILL_RETRIEVED")


@router.post(
    "/businesses/{business_id}/ai/skills/install-anthropic",
    summary="نصب مهارت prebuilt Anthropic",
)
@require_business_access("business_id")
async def install_anthropic_skill(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    sid = body.get("anthropic_skill_id")
    if not sid:
        raise ApiError("ANTHROPIC_SKILL_ID_REQUIRED", "شناسه مهارت الزامی است", http_status=400)
    try:
        inst = install_anthropic_prebuilt(
            db,
            business_id=business_id,
            user_id=ctx.get_user_id(),
            anthropic_skill_id=str(sid),
        )
    except ValueError as e:
        code = str(e.args[0]) if e.args else "SKILL_ERROR"
        if code == "ANTHROPIC_SKILL_UNKNOWN":
            raise ApiError(code, "مهارت Anthropic ناشناخته است", http_status=400)
        _skill_value_error(e)
    return success_response(
        data=install_to_dict(inst, db=db),
        request=request,
        message="AI_SKILL_ANTHROPIC_INSTALLED",
    )


@router.post(
    "/ai/skills/marketplace/packages/{package_id}/reviews",
    summary="ثبت امتیاز برای مهارت",
)
async def post_review(
    request: Request,
    package_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    rating = body.get("rating")
    if rating is None:
        raise ApiError("RATING_REQUIRED", "امتیاز الزامی است", http_status=400)
    try:
        row = add_skill_review(
            db,
            package_id=package_id,
            user_id=ctx.get_user_id(),
            rating=int(rating),
            comment=body.get("comment"),
        )
    except ValueError as e:
        _skill_value_error(e)
    return success_response(
        data={"id": row.id, "rating": row.rating, "comment": row.comment},
        request=request,
        message="AI_SKILL_REVIEW_SAVED",
    )


@router.get("/ai/skills/catalog/anthropic", summary="کاتالوگ مهارت‌های prebuilt Anthropic")
async def anthropic_skill_catalog(
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    return success_response(
        data={"items": ANTHROPIC_PREBUILT_CATALOG},
        request=request,
        message="AI_SKILLS_ANTHROPIC_CATALOG",
    )


@router.get("/ai/skills/marketplace/packages", summary="لیست مهارت‌های منتشرشده")
async def marketplace_list(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    skip: int = Query(0, ge=0),
    take: int = Query(20, ge=1, le=100),
    search: Optional[str] = Query(None),
    source_type: Optional[str] = Query(None),
    is_official: Optional[bool] = Query(None),
    business_id: Optional[int] = Query(None, description="برای نمایش وضعیت خرید"),
) -> dict:
    rows, total = list_marketplace_packages(
        db, skip=skip, take=take, search=search, source_type=source_type, is_official=is_official
    )
    items = [package_to_dict(p, business_id=business_id, db=db) for p in rows]
    return success_response(
        data={"items": items, "total": total, "skip": skip, "take": take},
        request=request,
        message="AI_SKILLS_MARKETPLACE_LISTED",
    )


@router.get(
    "/businesses/{business_id}/ai/skills/installed",
    summary="مهارت‌های نصب‌شده در کسب‌وکار",
)
@require_business_access("business_id")
async def list_business_installed(
    request: Request,
    business_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    enabled_only: bool = Query(False),
) -> dict:
    rows = list_installed(db, business_id, enabled_only=enabled_only)
    return success_response(
        data={"items": [install_to_dict(r, db=db) for r in rows]},
        request=request,
        message="AI_SKILLS_INSTALLED_LISTED",
    )


@router.get(
    "/businesses/{business_id}/ai/skills/owned",
    summary="مهارت‌های مالکیت کسب‌وکار (برای انتشار)",
)
@require_business_access("business_id")
async def list_business_owned(
    request: Request,
    business_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    skip: int = Query(0, ge=0),
    take: int = Query(50, ge=1, le=100),
) -> dict:
    rows, total = list_owned_packages(db, business_id, skip=skip, take=take)
    return success_response(
        data={
            "items": [package_to_dict(p, business_id=business_id, db=db) for p in rows],
            "total": total,
            "skip": skip,
            "take": take,
        },
        request=request,
        message="AI_SKILLS_OWNED_LISTED",
    )


@router.get(
    "/businesses/{business_id}/ai/skills/publisher/revenue",
    summary="گزارش درآمد ناشر مهارت‌های AI",
)
@require_business_access("business_id")
async def publisher_revenue(
    request: Request,
    business_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    skip: int = Query(0, ge=0),
    take: int = Query(20, ge=1, le=100),
) -> dict:
    data = get_publisher_revenue(db, business_id, skip=skip, take=take)
    return success_response(
        data=data,
        request=request,
        message="AI_SKILLS_PUBLISHER_REVENUE",
    )


@router.post(
    "/businesses/{business_id}/ai/skills/import",
    summary="import مهارت از ZIP (agentskills.io)",
)
@require_business_access("business_id")
async def import_zip(
    request: Request,
    business_id: int,
    file: UploadFile = File(...),
    title: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = await file.read()
    try:
        pkg = import_skill_zip(
            db,
            business_id=business_id,
            user_id=ctx.get_user_id(),
            data=data,
            title=title,
        )
    except ValueError as e:
        _skill_value_error(e)
    return success_response(
        data=package_to_dict(pkg, include_body=True),
        request=request,
        message="AI_SKILL_IMPORTED",
    )


@router.post(
    "/businesses/{business_id}/ai/skills/import-git",
    summary="import مهارت از URL مخزن GitHub",
)
@require_business_access("business_id")
async def import_git(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    git_url = body.get("git_url") or body.get("url")
    if not git_url:
        raise ApiError("GIT_URL_REQUIRED", "آدرس Git الزامی است", http_status=400)
    try:
        pkg = import_skill_from_git(
            db,
            business_id=business_id,
            user_id=ctx.get_user_id(),
            git_url=str(git_url),
            title=body.get("title"),
        )
    except ValueError as e:
        _skill_value_error(e)
    return success_response(
        data=package_to_dict(pkg, include_body=True),
        request=request,
        message="AI_SKILL_IMPORTED_FROM_GIT",
    )


@router.post(
    "/businesses/{business_id}/ai/skills/purchase",
    summary="خرید مهارت پولی (قبل از نصب)",
)
@require_business_access("business_id")
async def purchase_skill(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    package_id = body.get("package_id")
    if not package_id:
        raise ApiError("PACKAGE_ID_REQUIRED", "شناسه بسته الزامی است", http_status=400)
    try:
        result = purchase_skill_package(
            db,
            business_id=business_id,
            user_id=ctx.get_user_id(),
            package_id=int(package_id),
        )
    except ValueError as e:
        _skill_value_error(e)
    return success_response(data=result, request=request, message="AI_SKILL_PURCHASED")


@router.post(
    "/businesses/{business_id}/ai/skills",
    summary="ایجاد مهارت بومی (hesabix_native)",
)
@require_business_access("business_id")
async def create_skill(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    try:
        pkg = create_native_skill(
            db,
            business_id=business_id,
            user_id=ctx.get_user_id(),
            skill_slug=str(body.get("skill_slug") or ""),
            title=str(body.get("title") or ""),
            description=str(body.get("description") or ""),
            skill_body=str(body.get("skill_body") or ""),
            allowed_tool_names=body.get("allowed_tool_names"),
            tags=body.get("tags"),
        )
    except ValueError as e:
        _skill_value_error(e)
    return success_response(
        data=package_to_dict(pkg, include_body=True),
        request=request,
        message="AI_SKILL_CREATED",
    )


@router.post(
    "/businesses/{business_id}/ai/skills/install",
    summary="نصب مهارت در کسب‌وکار",
)
@require_business_access("business_id")
async def install_skill(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    package_id = body.get("package_id")
    if not package_id:
        raise ApiError("PACKAGE_ID_REQUIRED", "شناسه بسته الزامی است", http_status=400)
    try:
        inst = install_package(
            db,
            business_id=business_id,
            user_id=ctx.get_user_id(),
            package_id=int(package_id),
        )
    except ValueError as e:
        _skill_value_error(e)
    return success_response(
        data=install_to_dict(inst, db=db),
        request=request,
        message="AI_SKILL_INSTALLED",
    )


@router.put(
    "/businesses/{business_id}/ai/skills/enabled",
    summary="فعال/غیرفعال کردن داینامیک مهارت‌های نصب‌شده",
)
@require_business_access("business_id")
async def update_enabled(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    changed = set_installs_enabled(
        db,
        business_id=business_id,
        enable_ids=body.get("enable_ids"),
        disable_ids=body.get("disable_ids"),
    )
    return success_response(
        data={"updated": [install_to_dict(c, db=db) for c in changed]},
        request=request,
        message="AI_SKILLS_ENABLED_UPDATED",
    )


@router.post(
    "/businesses/{business_id}/ai/skills/{package_id}/publish",
    summary="ارسال مهارت به مارکت‌پلیس (pending_review)",
)
@require_business_access("business_id")
async def publish_skill(
    request: Request,
    business_id: int,
    package_id: int,
    body: Dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    try:
        pkg = publish_to_marketplace(
            db,
            package_id=package_id,
            business_id=business_id,
            user_id=ctx.get_user_id(),
            short_description=body.get("short_description"),
            long_description=body.get("long_description"),
            tags=body.get("tags"),
            version_label=str(body.get("version_label") or "1.0.0"),
            changelog=body.get("changelog"),
            price_amount=body.get("price_amount"),
            currency_id=body.get("currency_id"),
        )
    except ValueError as e:
        _skill_value_error(e)
    return success_response(
        data=package_to_dict(pkg),
        request=request,
        message="AI_SKILL_PUBLISH_SUBMITTED",
    )


@router.get(
    "/businesses/{business_id}/ai/skills/packages/{package_id}",
    summary="جزئیات بسته مهارت",
)
@require_business_access("business_id")
async def get_package(
    request: Request,
    business_id: int,
    package_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    pkg = get_package_for_business(db, package_id, business_id)
    if not pkg:
        raise ApiError("SKILL_PACKAGE_NOT_FOUND", "بسته یافت نشد", http_status=404)
    return success_response(
        data=package_to_dict(pkg, include_body=True, business_id=business_id, db=db),
        request=request,
        message="AI_SKILL_RETRIEVED",
    )
