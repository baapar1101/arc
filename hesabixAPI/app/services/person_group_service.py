from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, func
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.person import PersonCreateRequest, PersonType
from adapters.api.v1.schema_models.person_group import (
    ALLOWED_PROFILE_DEFAULT_KEYS,
    PersonGroupCreateRequest,
    PersonGroupUpdateRequest,
    sanitize_profile_defaults,
)
from adapters.db.models.person_group import PersonGroup
from app.core.responses import ApiError

logger = logging.getLogger(__name__)


def serialize_person_group(g: PersonGroup) -> Dict[str, Any]:
    try:
        pd = json.loads(g.profile_defaults or "{}")
        if not isinstance(pd, dict):
            pd = {}
    except Exception:
        pd = {}
    pd = sanitize_profile_defaults(pd)
    return {
        "id": g.id,
        "business_id": g.business_id,
        "parent_id": g.parent_id,
        "name": g.name,
        "code": g.code,
        "description": g.description,
        "profile_defaults": pd,
        "sort_order": g.sort_order,
        "is_active": bool(g.is_active),
        "created_at": g.created_at.isoformat(),
        "updated_at": g.updated_at.isoformat(),
    }


def get_person_group(db: Session, business_id: int, group_id: int) -> Optional[PersonGroup]:
    return (
        db.query(PersonGroup)
        .filter(and_(PersonGroup.id == group_id, PersonGroup.business_id == business_id))
        .first()
    )


def list_person_groups(
    db: Session,
    business_id: int,
    skip: int = 0,
    take: int = 100,
    active_only: bool = False,
    root_only: bool = True,
) -> Dict[str, Any]:
    q = db.query(PersonGroup).filter(PersonGroup.business_id == business_id)
    if active_only:
        q = q.filter(PersonGroup.is_active == True)  # noqa: E712
    if root_only:
        q = q.filter(PersonGroup.parent_id.is_(None))
    total = q.count()
    rows = (
        q.order_by(PersonGroup.sort_order.asc(), PersonGroup.name.asc())
        .offset(skip)
        .limit(take)
        .all()
    )
    items = [serialize_person_group(x) for x in rows]
    return {
        "items": items,
        "pagination": {
            "total": total,
            "skip": skip,
            "take": take,
        },
    }


def create_person_group(db: Session, business_id: int, body: PersonGroupCreateRequest) -> Dict[str, Any]:
    if body.parent_id is not None:
        raise ApiError(
            "PERSON_GROUP_PARENT_NOT_SUPPORTED",
            "در این نسخه فقط گروه بدون والد مجاز است",
            http_status=400,
        )
    if body.code is not None:
        exists = (
            db.query(PersonGroup)
            .filter(and_(PersonGroup.business_id == business_id, PersonGroup.code == body.code))
            .first()
        )
        if exists:
            raise ApiError("DUPLICATE_PERSON_GROUP_CODE", "کد گروه تکراری است", http_status=400)

    pd = sanitize_profile_defaults(body.profile_defaults)
    g = PersonGroup(
        business_id=business_id,
        parent_id=None,
        name=body.name.strip(),
        code=body.code,
        description=body.description,
        profile_defaults=json.dumps(pd, ensure_ascii=False),
        sort_order=body.sort_order,
        is_active=body.is_active,
    )
    db.add(g)
    db.commit()
    db.refresh(g)
    return serialize_person_group(g)


def update_person_group(
    db: Session, business_id: int, group_id: int, body: PersonGroupUpdateRequest
) -> Optional[Dict[str, Any]]:
    g = get_person_group(db, business_id, group_id)
    if not g:
        return None
    if body.parent_id is not None:
        raise ApiError(
            "PERSON_GROUP_PARENT_NOT_SUPPORTED",
            "در این نسخه فقط گروه بدون والد مجاز است",
            http_status=400,
        )
    data = body.model_dump(exclude_unset=True)
    if "code" in data and data["code"] is not None:
        exists = (
            db.query(PersonGroup)
            .filter(
                and_(
                    PersonGroup.business_id == business_id,
                    PersonGroup.code == data["code"],
                    PersonGroup.id != group_id,
                )
            )
            .first()
        )
        if exists:
            raise ApiError("DUPLICATE_PERSON_GROUP_CODE", "کد گروه تکراری است", http_status=400)
    if "name" in data and data["name"] is not None:
        g.name = str(data["name"]).strip()
    if "code" in data:
        g.code = data["code"]
    if "description" in data:
        g.description = data["description"]
    if "profile_defaults" in data and data["profile_defaults"] is not None:
        g.profile_defaults = json.dumps(
            sanitize_profile_defaults(data["profile_defaults"]),
            ensure_ascii=False,
        )
    if "sort_order" in data and data["sort_order"] is not None:
        g.sort_order = int(data["sort_order"])
    if "is_active" in data and data["is_active"] is not None:
        g.is_active = bool(data["is_active"])

    db.commit()
    db.refresh(g)
    return serialize_person_group(g)


def delete_person_group(db: Session, business_id: int, group_id: int) -> None:
    g = get_person_group(db, business_id, group_id)
    if not g:
        raise ApiError("PERSON_GROUP_NOT_FOUND", "گروه یافت نشد", http_status=404)
    n = count_persons_in_group(db, business_id, group_id)
    if n > 0:
        raise ApiError(
            "PERSON_GROUP_NOT_EMPTY",
            f"این گروه دارای {n} شخص است؛ ابتدا انتساب را تغییر دهید",
            http_status=400,
        )
    db.delete(g)
    db.commit()


def assert_assignable_person_group(db: Session, business_id: int, group_id: int) -> PersonGroup:
    g = get_person_group(db, business_id, group_id)
    if not g:
        raise ApiError("PERSON_GROUP_NOT_FOUND", "گروه اشخاص یافت نشد", http_status=404)
    if not g.is_active:
        raise ApiError("PERSON_GROUP_INACTIVE", "گروه اشخاص غیرفعال است", http_status=400)
    if g.parent_id is not None:
        raise ApiError(
            "PERSON_GROUP_NOT_ASSIGNABLE",
            "فعلاً فقط گروه سطح اول قابل انتساب است",
            http_status=400,
        )
    return g


def _coerce_person_types_from_defaults(val: Any) -> Optional[List[PersonType]]:
    if not isinstance(val, list) or not val:
        return None
    out: List[PersonType] = []
    for x in val:
        if isinstance(x, PersonType):
            out.append(x)
            continue
        if isinstance(x, str):
            try:
                out.append(PersonType(x))
            except ValueError:
                try:
                    # مقدار فارسی enum
                    match = next((e for e in PersonType if e.value == x), None)
                    if match:
                        out.append(match)
                except Exception:
                    pass
    return out or None


def merge_person_create_with_group_defaults(
    db: Session,
    business_id: int,
    data: PersonCreateRequest,
) -> PersonCreateRequest:
    """فقط فیلدهای خالی/نامعتبر را از قالب گروه پر می‌کند (منطق یکسان برای API)."""
    gid = getattr(data, "person_group_id", None)
    if gid is None:
        return data
    g = assert_assignable_person_group(db, business_id, int(gid))
    try:
        raw = json.loads(g.profile_defaults or "{}")
    except Exception:
        raw = {}
    if not isinstance(raw, dict):
        raw = {}
    defaults = sanitize_profile_defaults(raw)
    d: Dict[str, Any] = data.model_dump()

    def is_empty_person_types() -> bool:
        pt = d.get("person_types")
        if pt is None:
            return True
        if isinstance(pt, list) and len(pt) == 0:
            return True
        return False

    for key, val in defaults.items():
        if key not in ALLOWED_PROFILE_DEFAULT_KEYS:
            continue
        if val is None:
            continue
        if key == "person_types":
            if is_empty_person_types():
                coerced = _coerce_person_types_from_defaults(val)
                if coerced:
                    d["person_types"] = coerced
            continue
        if key == "legal_entity_type":
            cur = d.get("legal_entity_type")
            if cur is None or str(cur).strip() == "":
                if val in ("natural", "legal"):
                    d["legal_entity_type"] = val
            continue
        if key in (
            "commission_exclude_discounts",
            "commission_exclude_additions_deductions",
            "commission_post_in_invoice_document",
            "credit_check_enabled",
        ):
            cur = d.get(key)
            if cur is None:
                d[key] = bool(val)
            continue
        if key == "share_count":
            cur = d.get("share_count")
            if cur is None:
                try:
                    d["share_count"] = int(val)
                except (TypeError, ValueError):
                    pass
            continue
        # رشته‌ها و اعداد
        cur = d.get(key)
        if cur is None or (isinstance(cur, str) and cur.strip() == ""):
            d[key] = val

    return PersonCreateRequest.model_validate(d)


def count_persons_in_group(db: Session, business_id: int, group_id: int) -> int:
    from adapters.db.models.person import Person

    return (
        db.query(func.count(Person.id))
        .filter(and_(Person.business_id == business_id, Person.person_group_id == group_id))
        .scalar()
        or 0
    )
