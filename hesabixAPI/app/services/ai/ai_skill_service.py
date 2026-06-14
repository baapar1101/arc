"""
مدیریت مهارت‌های AI: import، نصب، انتشار، فعال/غیرفعال.
"""
from __future__ import annotations

import logging
from datetime import datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, joinedload

from adapters.db.models.ai_skill import (
    AISkillInstall,
    AISkillPackage,
    AISkillSourceType,
    AISkillVisibility,
)
from adapters.db.models.business import Business
from adapters.db.models.user import User
from app.services.ai.ai_skill_parser import (
    CompatibilityReport,
    build_compatibility_report,
    compose_skill_md,
    extract_skill_from_zip,
    merge_compat_into_report,
    parse_compat_yaml,
    parse_skill_md,
    validate_description,
    validate_skill_slug,
)

_logger = logging.getLogger(__name__)

# مهارت‌های prebuilt Anthropic — فاز ۲ runtime native
ANTHROPIC_PREBUILT_CATALOG: List[Dict[str, str]] = [
    {
        "anthropic_skill_id": "pdf",
        "skill_slug": "pdf",
        "title": "PDF Processing",
        "description": "Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDFs.",
        "source_type": AISkillSourceType.ANTHROPIC_PREBUILT.value,
    },
    {
        "anthropic_skill_id": "xlsx",
        "skill_slug": "xlsx",
        "title": "Excel (xlsx)",
        "description": "Create and analyze Excel spreadsheets. Use when building spreadsheets or analyzing tabular data.",
        "source_type": AISkillSourceType.ANTHROPIC_PREBUILT.value,
    },
    {
        "anthropic_skill_id": "docx",
        "skill_slug": "docx",
        "title": "Word (docx)",
        "description": "Create and edit Word documents. Use for document generation and formatting.",
        "source_type": AISkillSourceType.ANTHROPIC_PREBUILT.value,
    },
    {
        "anthropic_skill_id": "pptx",
        "skill_slug": "pptx",
        "title": "PowerPoint (pptx)",
        "description": "Create and edit presentations. Use when building slide decks.",
        "source_type": AISkillSourceType.ANTHROPIC_PREBUILT.value,
    },
]


def _compatibility_for_parsed(parsed: Any) -> CompatibilityReport:
    report = build_compatibility_report(parsed)
    compat_raw = (parsed.bundle_files or {}).get("hesabix.compat.yaml", {}).get("content")
    if compat_raw:
        report = merge_compat_into_report(parsed, parse_compat_yaml(str(compat_raw)))
    return report


    if not isinstance(raw, list):
        return []
    out: List[str] = []
    for t in raw[:30]:
        if isinstance(t, str):
            s = t.strip()
            if s and len(s) <= 64:
                out.append(s)
    return out[:20]


def _parsed_to_package_fields(
    parsed: Any,
    *,
    title: Optional[str],
    source_type: str,
    compatibility: CompatibilityReport,
) -> Dict[str, Any]:
    return {
        "skill_slug": parsed.skill_slug,
        "title": (title or parsed.skill_slug).strip()[:255],
        "description": parsed.description,
        "skill_body": parsed.skill_body,
        "source_type": source_type,
        "bundle_files": parsed.bundle_files or None,
        "allowed_tool_names": parsed.allowed_tool_names or None,
        "compatibility_report": compatibility.to_dict(),
        "has_scripts": parsed.has_scripts,
    }


def import_skill_zip(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    data: bytes,
    title: Optional[str] = None,
    source_repo_url: Optional[str] = None,
) -> AISkillPackage:
    parsed = extract_skill_from_zip(data)
    compatibility = _compatibility_for_parsed(parsed)
    fields = _parsed_to_package_fields(
        parsed,
        title=title,
        source_type=AISkillSourceType.PORTABLE.value,
        compatibility=compatibility,
    )
    pkg = AISkillPackage(
        **fields,
        owner_business_id=business_id,
        publisher_user_id=user_id,
        publisher_business_id=business_id,
        visibility=AISkillVisibility.DRAFT.value,
        version_label="1.0.0",
        source_repo_url=source_repo_url,
    )
    db.add(pkg)
    db.commit()
    db.refresh(pkg)
    return pkg


def create_native_skill(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    skill_slug: str,
    title: str,
    description: str,
    skill_body: str,
    allowed_tool_names: Optional[List[str]] = None,
    tags: Any = None,
) -> AISkillPackage:
    err = validate_skill_slug(skill_slug)
    if err:
        raise ValueError(err)
    err = validate_description(description)
    if err:
        raise ValueError(err)
    body = (skill_body or "").strip()
    if not body:
        raise ValueError("SKILL_BODY_REQUIRED")

    md = compose_skill_md(
        skill_slug=skill_slug.strip().lower(),
        description=description.strip(),
        skill_body=body,
        allowed_tool_names=allowed_tool_names,
    )
    parsed = parse_skill_md(md)
    parsed.allowed_tool_names = list(allowed_tool_names or [])
    compatibility = _compatibility_for_parsed(parsed)

    pkg = AISkillPackage(
        **_parsed_to_package_fields(
            parsed,
            title=title,
            source_type=AISkillSourceType.HESABIX_NATIVE.value,
            compatibility=compatibility,
        ),
        owner_business_id=business_id,
        publisher_user_id=user_id,
        publisher_business_id=business_id,
        visibility=AISkillVisibility.DRAFT.value,
        version_label="1.0.0",
        tags=_normalize_tags(tags),
        short_description=description[:512],
    )
    db.add(pkg)
    db.commit()
    db.refresh(pkg)
    return pkg


def import_skill_from_git(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    git_url: str,
    title: Optional[str] = None,
) -> AISkillPackage:
    from app.services.ai.ai_skill_git_import import import_skill_from_git_url

    skill_zip, ref = import_skill_from_git_url(git_url)
    return import_skill_zip(
        db,
        business_id=business_id,
        user_id=user_id,
        data=skill_zip,
        title=title,
        source_repo_url=ref.source_url,
    )


def _business_has_purchased(db: Session, business_id: int, package_id: int) -> bool:
    from adapters.db.models.ai_skill import AISkillPurchase

    return (
        db.query(AISkillPurchase)
        .filter(
            AISkillPurchase.business_id == business_id,
            AISkillPurchase.package_id == package_id,
        )
        .first()
        is not None
    )


def purchase_skill_package(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    package_id: int,
) -> Dict[str, Any]:
    from adapters.db.models.ai_skill import AISkillPurchase
    from app.services.system_settings_service import get_marketplace_publisher_share_percent
    from app.services.wallet_service import charge_wallet_for_service, credit_wallet_for_service

    pkg = db.get(AISkillPackage, package_id)
    if not pkg:
        raise ValueError("SKILL_PACKAGE_NOT_FOUND")
    price = Decimal(str(pkg.price_amount or 0))
    if price <= 0:
        return {"purchased": True, "free": True}
    if _business_has_purchased(db, business_id, package_id):
        return {"purchased": True, "already_owned": True}

    charge = charge_wallet_for_service(
        db,
        business_id,
        price,
        description=f"خرید مهارت AI: {pkg.title}",
        tx_type="ai_skill_purchase",
        extra_info={"skill_package_id": package_id, "skill_slug": pkg.skill_slug},
    )
    row = AISkillPurchase(
        package_id=package_id,
        business_id=business_id,
        user_id=user_id,
        amount=float(price),
        currency_id=pkg.currency_id,
        wallet_transaction_id=charge.get("transaction_id"),
    )
    db.add(row)
    db.flush()

    publisher_biz = pkg.publisher_business_id
    if publisher_biz and int(publisher_biz) != int(business_id) and not pkg.is_official:
        share_pct = Decimal(str(get_marketplace_publisher_share_percent(db)))
        publisher_amount = (price * share_pct / Decimal("100")).quantize(Decimal("0.01"))
        platform_fee = (price - publisher_amount).quantize(Decimal("0.01"))
        row.publisher_amount = float(publisher_amount)
        row.platform_fee = float(platform_fee)
        if publisher_amount > 0:
            pub_credit = credit_wallet_for_service(
                db,
                int(publisher_biz),
                publisher_amount,
                description=f"فروش مهارت AI: {pkg.title}",
                tx_type="ai_skill_sale_credit",
                extra_info={
                    "skill_package_id": package_id,
                    "skill_slug": pkg.skill_slug,
                    "purchase_id": row.id,
                    "buyer_business_id": business_id,
                },
            )
            row.publisher_wallet_transaction_id = pub_credit.get("transaction_id")

    db.commit()
    return {
        "purchased": True,
        "wallet": charge,
        "publisher_amount": row.publisher_amount,
        "platform_fee": row.platform_fee,
    }


def get_package_for_business(db: Session, package_id: int, business_id: int) -> Optional[AISkillPackage]:
    return (
        db.query(AISkillPackage)
        .filter(
            AISkillPackage.id == package_id,
            or_(
                AISkillPackage.owner_business_id == business_id,
                AISkillPackage.visibility == AISkillVisibility.PUBLISHED.value,
            ),
        )
        .first()
    )


def install_package(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    package_id: int,
) -> AISkillInstall:
    pkg = db.get(AISkillPackage, package_id)
    if not pkg:
        raise ValueError("SKILL_PACKAGE_NOT_FOUND")
    if pkg.visibility not in (
        AISkillVisibility.PUBLISHED.value,
        AISkillVisibility.BUSINESS_ONLY.value,
        AISkillVisibility.DRAFT.value,
    ):
        if pkg.owner_business_id != business_id:
            raise ValueError("SKILL_PACKAGE_NOT_AVAILABLE")

    price = Decimal(str(pkg.price_amount or 0))
    if price > 0 and pkg.owner_business_id != business_id:
        if not _business_has_purchased(db, business_id, package_id):
            purchase_skill_package(
                db,
                business_id=business_id,
                user_id=user_id,
                package_id=package_id,
            )

    existing = (
        db.query(AISkillInstall)
        .filter(
            AISkillInstall.business_id == business_id,
            AISkillInstall.package_id == package_id,
        )
        .first()
    )
    if existing:
        return existing

    inst = AISkillInstall(
        package_id=package_id,
        business_id=business_id,
        installed_by_user_id=user_id,
        is_enabled=True,
    )
    pkg.install_count = int(pkg.install_count or 0) + 1
    db.add(inst)
    db.commit()
    db.refresh(inst)
    return inst


def set_installs_enabled(
    db: Session,
    *,
    business_id: int,
    enable_ids: Optional[List[int]] = None,
    disable_ids: Optional[List[int]] = None,
) -> List[AISkillInstall]:
    changed: List[AISkillInstall] = []
    for iid, enabled in [(enable_ids or [], True), (disable_ids or [], False)]:
        for install_id in iid:
            row = (
                db.query(AISkillInstall)
                .filter(
                    AISkillInstall.id == int(install_id),
                    AISkillInstall.business_id == business_id,
                )
                .first()
            )
            if row and row.is_enabled != enabled:
                row.is_enabled = enabled
                changed.append(row)
    if changed:
        db.commit()
        for row in changed:
            db.refresh(row)
    return changed


def list_installed(
    db: Session,
    business_id: int,
    *,
    enabled_only: bool = False,
) -> List[AISkillInstall]:
    q = (
        db.query(AISkillInstall)
        .options(joinedload(AISkillInstall.package))
        .filter(AISkillInstall.business_id == business_id)
    )
    if enabled_only:
        q = q.filter(AISkillInstall.is_enabled == True)  # noqa: E712
    return q.order_by(AISkillInstall.id.asc()).all()


def list_marketplace_packages(
    db: Session,
    *,
    skip: int = 0,
    take: int = 20,
    search: Optional[str] = None,
    tag: Optional[str] = None,
    source_type: Optional[str] = None,
    is_official: Optional[bool] = None,
) -> Tuple[List[AISkillPackage], int]:
    q = db.query(AISkillPackage).filter(
        AISkillPackage.visibility == AISkillVisibility.PUBLISHED.value
    )
    if source_type:
        q = q.filter(AISkillPackage.source_type == source_type)
    if is_official is True:
        q = q.filter(AISkillPackage.is_official == True)  # noqa: E712
    elif is_official is False:
        q = q.filter(AISkillPackage.is_official == False)  # noqa: E712
    if search:
        like = f"%{search.strip()}%"
        q = q.filter(
            or_(
                AISkillPackage.title.ilike(like),
                AISkillPackage.skill_slug.ilike(like),
                AISkillPackage.description.ilike(like),
            )
        )
  # tag filter — JSON contains simplified
    rows = q.order_by(AISkillPackage.published_at.desc().nullslast(), AISkillPackage.id.desc())
    total = rows.count()
    return rows.offset(skip).limit(take).all(), total


def ensure_anthropic_prebuilt_package(
    db: Session,
    anthropic_skill_id: str,
) -> AISkillPackage:
    sid = (anthropic_skill_id or "").strip().lower()
    entry = next(
        (e for e in ANTHROPIC_PREBUILT_CATALOG if e["anthropic_skill_id"] == sid),
        None,
    )
    if not entry:
        raise ValueError("ANTHROPIC_SKILL_UNKNOWN")
    existing = (
        db.query(AISkillPackage)
        .filter(
            AISkillPackage.source_type == AISkillSourceType.ANTHROPIC_PREBUILT.value,
            AISkillPackage.anthropic_skill_id == sid,
            AISkillPackage.visibility == AISkillVisibility.PUBLISHED.value,
        )
        .first()
    )
    if existing:
        return existing
    report = CompatibilityReport(
        runtime_mode="anthropic_native",
        instruction_only=False,
        anthropic_prebuilt=True,
        score=95,
        warnings=["requires_anthropic_provider"],
    )
    pkg = AISkillPackage(
        skill_slug=entry["skill_slug"],
        title=entry["title"],
        description=entry["description"],
        skill_body="",
        source_type=AISkillSourceType.ANTHROPIC_PREBUILT.value,
        anthropic_skill_id=sid,
        compatibility_report=report.to_dict(),
        has_scripts=True,
        visibility=AISkillVisibility.PUBLISHED.value,
        version_label="latest",
        published_at=datetime.utcnow(),
    )
    db.add(pkg)
    db.commit()
    db.refresh(pkg)
    return pkg


def install_anthropic_prebuilt(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    anthropic_skill_id: str,
) -> AISkillInstall:
    pkg = ensure_anthropic_prebuilt_package(db, anthropic_skill_id)
    return install_package(
        db,
        business_id=business_id,
        user_id=user_id,
        package_id=pkg.id,
    )


def moderate_skill_content(
    title: str,
    description: str,
    skill_body: str,
) -> Dict[str, Any]:
    """بررسی سبک محتوا قبل از انتشار (فاز ۳)."""
    from app.services.ai_moderation_service import SpamDetector

    combined = f"{title}\n{description}\n{skill_body}"
    spam = SpamDetector().analyze(combined)
    decision = "approve"
    if spam.get("score", 0) >= 60:
        decision = "review_required"
    if spam.get("score", 0) >= 85:
        decision = "reject"
    return {
        "decision": decision,
        "spam_score": spam.get("score", 0),
        "flags": spam.get("flags", []),
    }


def add_skill_review(
    db: Session,
    *,
    package_id: int,
    user_id: int,
    rating: int,
    comment: Optional[str] = None,
) -> Any:
    from adapters.db.models.ai_skill import AISkillReview

    if rating < 1 or rating > 5:
        raise ValueError("SKILL_REVIEW_RATING_INVALID")
    pkg = db.get(AISkillPackage, package_id)
    if not pkg or pkg.visibility != AISkillVisibility.PUBLISHED.value:
        raise ValueError("SKILL_PACKAGE_NOT_FOUND")
    existing = (
        db.query(AISkillReview)
        .filter(AISkillReview.package_id == package_id, AISkillReview.user_id == user_id)
        .first()
    )
    if existing:
        existing.rating = rating
        existing.comment = (comment or "").strip() or None
    else:
        existing = AISkillReview(
            package_id=package_id,
            user_id=user_id,
            rating=rating,
            comment=(comment or "").strip() or None,
        )
        db.add(existing)
    db.commit()
    db.refresh(existing)
    return existing


def list_skill_reviews(db: Session, package_id: int) -> Tuple[List[Any], float, int]:
    from adapters.db.models.ai_skill import AISkillReview

    rows = (
        db.query(AISkillReview)
        .filter(AISkillReview.package_id == package_id)
        .order_by(AISkillReview.created_at.desc())
        .limit(50)
        .all()
    )
    avg_row = (
        db.query(func.avg(AISkillReview.rating), func.count(AISkillReview.id))
        .filter(AISkillReview.package_id == package_id)
        .first()
    )
    avg = float(avg_row[0] or 0) if avg_row else 0.0
    count = int(avg_row[1] or 0) if avg_row else 0
    return rows, avg, count


def list_pending_packages(db: Session, skip: int = 0, take: int = 50) -> Tuple[List[AISkillPackage], int]:
    q = db.query(AISkillPackage).filter(
        AISkillPackage.visibility == AISkillVisibility.PENDING_REVIEW.value
    )
    total = q.count()
    return q.order_by(AISkillPackage.updated_at.desc()).offset(skip).limit(take).all(), total


def seed_official_skills(db: Session) -> int:
    """درج مهارت‌های رسمی ERP (idempotent)."""
    from adapters.db.models.ai_skill import AISkillSourceType, AISkillVisibility
    from adapters.db.seed_data.ai_official_skills_seed import OFFICIAL_ERP_SKILLS
    from app.services.ai.ai_skill_parser import compose_skill_md, parse_skill_md

    created = 0
    for row in OFFICIAL_ERP_SKILLS:
        exists = (
            db.query(AISkillPackage)
            .filter(
                AISkillPackage.skill_slug == row["skill_slug"],
                AISkillPackage.is_official == True,  # noqa: E712
            )
            .first()
        )
        if exists:
            continue
        md = compose_skill_md(
            skill_slug=row["skill_slug"],
            description=row["description"],
            skill_body=row["skill_body"],
            allowed_tool_names=row.get("allowed_tool_names"),
        )
        parsed = parse_skill_md(md)
        compatibility = _compatibility_for_parsed(parsed)
        pkg = AISkillPackage(
            **_parsed_to_package_fields(
                parsed,
                title=row["title"],
                source_type=AISkillSourceType.HESABIX_NATIVE.value,
                compatibility=compatibility,
            ),
            visibility=AISkillVisibility.PUBLISHED.value,
            version_label="1.0.0",
            tags=_normalize_tags(row.get("tags")),
            is_official=True,
            published_at=datetime.utcnow(),
        )
        db.add(pkg)
        created += 1
    if created:
        db.commit()
    return created


def publish_to_marketplace(
    db: Session,
    *,
    package_id: int,
    business_id: int,
    user_id: int,
    short_description: Optional[str] = None,
    long_description: Optional[str] = None,
    tags: Any = None,
    version_label: str = "1.0.0",
    changelog: Optional[str] = None,
    price_amount: Optional[float] = None,
    currency_id: Optional[int] = None,
) -> AISkillPackage:
    pkg = (
        db.query(AISkillPackage)
        .filter(
            AISkillPackage.id == package_id,
            AISkillPackage.owner_business_id == business_id,
        )
        .first()
    )
    if not pkg:
        raise ValueError("SKILL_PACKAGE_NOT_FOUND")
    mod = moderate_skill_content(pkg.title, pkg.description, pkg.skill_body)
    if mod.get("decision") == "reject":
        raise ValueError("SKILL_MODERATION_REJECTED")
    pkg.visibility = AISkillVisibility.PENDING_REVIEW.value
    pkg.compatibility_report = {
        **(pkg.compatibility_report or {}),
        "moderation": mod,
    }
    pkg.publisher_user_id = user_id
    pkg.publisher_business_id = business_id
    pkg.short_description = (short_description or pkg.description)[:2000] if short_description or pkg.description else None
    pkg.long_description = (long_description or "").strip() or None
    pkg.tags = _normalize_tags(tags) or pkg.tags
    pkg.version_label = (version_label or "1.0.0").strip()[:64]
    pkg.changelog = (changelog or "").strip() or None
    if price_amount is not None:
        pkg.price_amount = float(price_amount) if float(price_amount) > 0 else None
    if currency_id is not None:
        pkg.currency_id = int(currency_id) if currency_id else None
    elif pkg.price_amount and not pkg.currency_id:
        from app.services.system_settings_service import get_wallet_settings

        settings = get_wallet_settings(db)
        pkg.currency_id = settings.get("wallet_base_currency_id")
    db.commit()
    db.refresh(pkg)
    return pkg


def approve_package_publish(db: Session, package_id: int) -> AISkillPackage:
    """تأیید admin برای انتشار در مارکت‌پلیس."""
    pkg = db.get(AISkillPackage, package_id)
    if not pkg:
        raise ValueError("SKILL_PACKAGE_NOT_FOUND")
    pkg.visibility = AISkillVisibility.PUBLISHED.value
    pkg.published_at = datetime.utcnow()
    db.commit()
    db.refresh(pkg)
    return pkg


def reject_package_publish(
    db: Session,
    package_id: int,
    *,
    reason: str = "",
) -> AISkillPackage:
    pkg = db.get(AISkillPackage, package_id)
    if not pkg:
        raise ValueError("SKILL_PACKAGE_NOT_FOUND")
    pkg.visibility = AISkillVisibility.HIDDEN.value
    report = dict(pkg.compatibility_report or {})
    report["rejection_reason"] = (reason or "").strip() or None
    pkg.compatibility_report = report
    db.commit()
    db.refresh(pkg)
    return pkg


def package_to_dict(
    pkg: AISkillPackage,
    *,
    include_body: bool = False,
    business_id: Optional[int] = None,
    db: Optional[Session] = None,
) -> Dict[str, Any]:
    is_purchased: Optional[bool] = None
    if business_id is not None and db is not None:
        price = pkg.price_amount
        if price is None or price <= 0:
            is_purchased = True
        else:
            is_purchased = _business_has_purchased(db, business_id, pkg.id)
    d: Dict[str, Any] = {
        "id": pkg.id,
        "skill_slug": pkg.skill_slug,
        "title": pkg.title,
        "description": pkg.description,
        "source_type": pkg.source_type,
        "anthropic_skill_id": pkg.anthropic_skill_id,
        "allowed_tool_names": pkg.allowed_tool_names or [],
        "compatibility_report": pkg.compatibility_report,
        "has_scripts": pkg.has_scripts,
        "visibility": pkg.visibility,
        "version_label": pkg.version_label,
        "tags": pkg.tags or [],
        "short_description": pkg.short_description,
        "install_count": pkg.install_count,
        "published_at": pkg.published_at.isoformat() if pkg.published_at else None,
        "price_amount": float(pkg.price_amount) if pkg.price_amount is not None else None,
        "currency_id": pkg.currency_id,
        "is_official": bool(pkg.is_official),
        "source_repo_url": pkg.source_repo_url,
        "is_purchased": is_purchased,
    }
    if include_body:
        d["skill_body"] = pkg.skill_body
        d["bundle_files"] = pkg.bundle_files
    return d


def install_to_dict(inst: AISkillInstall, *, db: Optional[Session] = None) -> Dict[str, Any]:
    pkg = inst.package
    return {
        "id": inst.id,
        "package_id": inst.package_id,
        "business_id": inst.business_id,
        "is_enabled": inst.is_enabled,
        "custom_title": inst.custom_title,
        "package": package_to_dict(pkg, business_id=inst.business_id, db=db) if pkg else None,
    }


def list_owned_packages(
    db: Session,
    business_id: int,
    *,
    skip: int = 0,
    take: int = 50,
) -> tuple[List[AISkillPackage], int]:
    q = db.query(AISkillPackage).filter(AISkillPackage.owner_business_id == business_id)
    total = q.count()
    rows = (
        q.order_by(AISkillPackage.updated_at.desc())
        .offset(max(0, skip))
        .limit(max(1, min(100, take)))
        .all()
    )
    return rows, total


def get_publisher_revenue(
    db: Session,
    business_id: int,
    *,
    skip: int = 0,
    take: int = 20,
) -> Dict[str, Any]:
    from adapters.db.models.ai_skill import AISkillPurchase
    from app.services.system_settings_service import get_marketplace_publisher_share_percent
    from sqlalchemy import func

    pub_filter = AISkillPackage.publisher_business_id == business_id

    agg = (
        db.query(
            func.count(AISkillPurchase.id),
            func.coalesce(func.sum(AISkillPurchase.amount), 0),
            func.coalesce(func.sum(AISkillPurchase.publisher_amount), 0),
            func.coalesce(func.sum(AISkillPurchase.platform_fee), 0),
        )
        .join(AISkillPackage, AISkillPackage.id == AISkillPurchase.package_id)
        .filter(pub_filter)
        .first()
    )
    sales_count = int(agg[0] or 0) if agg else 0
    gross_sales = float(agg[1] or 0) if agg else 0.0
    publisher_earnings = float(agg[2] or 0) if agg else 0.0
    platform_fees = float(agg[3] or 0) if agg else 0.0

    published_count = (
        db.query(func.count(AISkillPackage.id))
        .filter(
            pub_filter,
            AISkillPackage.visibility == AISkillVisibility.PUBLISHED.value,
        )
        .scalar()
        or 0
    )

    q = (
        db.query(AISkillPurchase, AISkillPackage)
        .join(AISkillPackage, AISkillPackage.id == AISkillPurchase.package_id)
        .filter(pub_filter)
        .order_by(AISkillPurchase.created_at.desc())
    )
    total_recent = q.count()
    recent_rows = q.offset(max(0, skip)).limit(max(1, min(100, take))).all()

    recent_sales = []
    for purchase, pkg in recent_rows:
        recent_sales.append(
            {
                "purchase_id": purchase.id,
                "package_id": pkg.id,
                "skill_title": pkg.title,
                "skill_slug": pkg.skill_slug,
                "buyer_business_id": purchase.business_id,
                "amount": float(purchase.amount or 0),
                "publisher_amount": float(purchase.publisher_amount or 0)
                if purchase.publisher_amount is not None
                else None,
                "platform_fee": float(purchase.platform_fee or 0)
                if purchase.platform_fee is not None
                else None,
                "created_at": purchase.created_at.isoformat() if purchase.created_at else None,
            }
        )

    published_packages = (
        db.query(AISkillPackage)
        .filter(pub_filter, AISkillPackage.visibility == AISkillVisibility.PUBLISHED.value)
        .order_by(AISkillPackage.install_count.desc())
        .limit(20)
        .all()
    )

    return {
        "publisher_share_percent": get_marketplace_publisher_share_percent(db),
        "sales_count": sales_count,
        "gross_sales": gross_sales,
        "publisher_earnings": publisher_earnings,
        "platform_fees": platform_fees,
        "published_packages_count": int(published_count),
        "recent_sales": recent_sales,
        "recent_sales_total": total_recent,
        "top_packages": [
            {
                "id": p.id,
                "title": p.title,
                "skill_slug": p.skill_slug,
                "install_count": p.install_count,
                "price_amount": float(p.price_amount) if p.price_amount is not None else None,
            }
            for p in published_packages
        ],
        "skip": skip,
        "take": take,
    }
