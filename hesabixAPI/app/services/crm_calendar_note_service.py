# noqa: D100
"""منطق یادداشت و تقویم CRM: دسترسی، انواع پیش‌فرض، audit"""
from __future__ import annotations

import json
from datetime import date, datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, exists, or_
from sqlalchemy.orm import Session, joinedload, selectinload

from adapters.db.models.business import Business
from adapters.db.models.business_permission import BusinessPermission
from adapters.db.models.crm import (
    CrmNote,
    CrmNoteAclUser,
    CrmNoteAuditEvent,
    CrmNoteComment,
    CrmNoteType,
    Lead,
)
from adapters.db.models.user import User
from app.core.auth_dependency import AuthContext
from app.core.responses import ApiError


DEFAULT_NOTE_TYPES: List[Dict[str, Any]] = [
    {
        "code": "announcement",
        "title_i18n": {"fa": "اطلاعیه", "en": "Announcement"},
        "scheduling_mode": "day_only",
        "allow_comments": True,
        "sort_order": 10,
    },
    {
        "code": "personal_note",
        "title_i18n": {"fa": "یادداشت شخصی", "en": "Personal note"},
        "scheduling_mode": "day_only",
        "allow_comments": False,
        "sort_order": 20,
    },
    {
        "code": "meeting",
        "title_i18n": {"fa": "جلسه", "en": "Meeting"},
        "scheduling_mode": "meeting",
        "allow_comments": True,
        "sort_order": 30,
    },
    {
        "code": "task",
        "title_i18n": {"fa": "وظیفه", "en": "Task"},
        "scheduling_mode": "day_only",
        "allow_comments": False,
        "sort_order": 40,
    },
]


def resolve_i18n_map(title_i18n: dict | None, lang: str) -> str:
    if not title_i18n or not isinstance(title_i18n, dict):
        return ""
    base = (lang or "en").split("-")[0].lower()
    if base not in ("fa", "en"):
        base = "en"
    v = title_i18n.get(base) or title_i18n.get("fa") or title_i18n.get("en")
    if isinstance(v, str) and v.strip():
        return v.strip()
    for _k, val in title_i18n.items():
        if isinstance(val, str) and val.strip():
            return val.strip()
    return ""


def _user_display_name(user: User | None) -> str:
    if not user:
        return ""
    parts = [user.first_name or "", user.last_name or ""]
    name = " ".join(p for p in parts if p).strip()
    return name or (user.email or user.mobile or str(user.id))


def user_has_business_join(db: Session, user_id: int, business_id: int) -> bool:
    biz = db.get(Business, business_id)
    if not biz or getattr(biz, "deleted_at", None) is not None:
        return False
    if getattr(biz, "owner_id", None) == user_id:
        return True
    perm = (
        db.query(BusinessPermission)
        .filter(
            BusinessPermission.user_id == int(user_id),
            BusinessPermission.business_id == int(business_id),
        )
        .first()
    )
    if not perm:
        return False
    raw = perm.business_permissions
    normalized: dict = {}
    if isinstance(raw, dict):
        normalized = raw
    elif isinstance(raw, list):
        try:
            if all(isinstance(item, list) and len(item) == 2 for item in raw):
                normalized = {k: v for k, v in raw if isinstance(k, str)}
            elif all(isinstance(item, dict) for item in raw):
                merged: dict = {}
                for item in raw:
                    merged.update({k: v for k, v in item.items()})
                normalized = merged
        except Exception:
            normalized = {}
    return normalized.get("join") is True


def ensure_default_note_types(db: Session, business_id: int) -> None:
    existing = db.query(CrmNoteType.id).filter(CrmNoteType.business_id == business_id).first()
    if existing:
        return
    now = datetime.utcnow()
    for row in DEFAULT_NOTE_TYPES:
        db.add(
            CrmNoteType(
                business_id=business_id,
                code=row["code"],
                title_i18n=dict(row["title_i18n"]),
                scheduling_mode=row["scheduling_mode"],
                allow_comments=bool(row["allow_comments"]),
                is_system=True,
                is_active=True,
                sort_order=int(row["sort_order"]),
                created_at=now,
                updated_at=now,
            )
        )
    db.flush()


def _audit(
    db: Session,
    *,
    business_id: int,
    note_id: int,
    actor_user_id: int,
    action: str,
    payload: dict | None = None,
) -> None:
    db.add(
        CrmNoteAuditEvent(
            business_id=business_id,
            note_id=note_id,
            actor_user_id=actor_user_id,
            action=action,
            payload=payload,
            occurred_at=datetime.utcnow(),
        )
    )


def _note_visible_filter(user_id: int):
    acl_exists = exists().where(
        CrmNoteAclUser.note_id == CrmNote.id,
        CrmNoteAclUser.user_id == user_id,
    )
    return or_(
        CrmNote.visibility == "business_public",
        and_(CrmNote.visibility == "private", CrmNote.created_by_user_id == user_id),
        and_(
            CrmNote.visibility == "shared",
            or_(CrmNote.created_by_user_id == user_id, acl_exists),
        ),
    )


def can_view_note(db: Session, ctx: AuthContext, note: CrmNote) -> bool:
    uid = ctx.get_user_id()
    if uid is None:
        return False
    if ctx.is_superadmin():
        return True
    if ctx.is_business_owner(note.business_id):
        return True
    if not user_has_business_join(db, int(uid), note.business_id):
        return False
    q = (
        db.query(CrmNote.id)
        .filter(
            CrmNote.id == note.id,
            CrmNote.deleted_at.is_(None),
            _note_visible_filter(int(uid)),
        )
        .first()
    )
    return q is not None


def can_edit_note(db: Session, ctx: AuthContext, note: CrmNote) -> bool:
    uid = ctx.get_user_id()
    if uid is None:
        return False
    if ctx.is_superadmin() or ctx.is_business_owner(note.business_id):
        return True
    if note.created_by_user_id == int(uid):
        return True
    return False


def comments_enabled_for(note: CrmNote, ntype: CrmNoteType) -> bool:
    if note.visibility != "business_public":
        return False
    return bool(ntype.allow_comments)


def list_note_types(db: Session, business_id: int, lang: str) -> List[dict]:
    ensure_default_note_types(db, business_id)
    db.flush()
    rows = (
        db.query(CrmNoteType)
        .filter(CrmNoteType.business_id == business_id, CrmNoteType.is_active.is_(True))
        .order_by(CrmNoteType.sort_order, CrmNoteType.id)
        .all()
    )
    out: List[dict] = []
    for r in rows:
        out.append(
            {
                "id": r.id,
                "business_id": r.business_id,
                "code": r.code,
                "title_i18n": r.title_i18n,
                "title": resolve_i18n_map(r.title_i18n, lang),
                "scheduling_mode": r.scheduling_mode,
                "allow_comments": r.allow_comments,
                "is_system": r.is_system,
                "sort_order": r.sort_order,
            }
        )
    return out


def create_note_type(
    db: Session,
    business_id: int,
    *,
    code: str,
    title_i18n: dict,
    scheduling_mode: str,
    allow_comments: bool,
    sort_order: int,
    lang: str,
    translator,
) -> dict:
    ensure_default_note_types(db, business_id)
    code_n = (code or "").strip().lower()
    if scheduling_mode not in ("day_only", "meeting"):
        raise ApiError(
            "CRM_NOTE_TYPE_INVALID_MODE",
            "Invalid scheduling_mode",
            translator=translator,
        )
    dup = db.query(CrmNoteType.id).filter(CrmNoteType.business_id == business_id, CrmNoteType.code == code_n).first()
    if dup:
        raise ApiError("CRM_NOTE_TYPE_CODE_EXISTS", "Code exists", translator=translator)
    now = datetime.utcnow()
    row = CrmNoteType(
        business_id=business_id,
        code=code_n,
        title_i18n=dict(title_i18n),
        scheduling_mode=scheduling_mode,
        allow_comments=allow_comments,
        is_system=False,
        is_active=True,
        sort_order=sort_order,
        created_at=now,
        updated_at=now,
    )
    db.add(row)
    db.flush()
    return {
        "id": row.id,
        "business_id": row.business_id,
        "code": row.code,
        "title_i18n": row.title_i18n,
        "title": resolve_i18n_map(row.title_i18n, lang),
        "scheduling_mode": row.scheduling_mode,
        "allow_comments": row.allow_comments,
        "is_system": row.is_system,
        "sort_order": row.sort_order,
    }


def update_note_type(
    db: Session,
    business_id: int,
    type_id: int,
    *,
    title_i18n: dict | None,
    scheduling_mode: str | None,
    allow_comments: bool | None,
    is_active: bool | None,
    sort_order: int | None,
    lang: str,
    translator,
) -> dict:
    row = db.get(CrmNoteType, type_id)
    if not row or row.business_id != business_id:
        raise ApiError("CRM_NOTE_TYPE_NOT_FOUND", "Not found", http_status=404, translator=translator)
    if scheduling_mode is not None and scheduling_mode not in ("day_only", "meeting"):
        raise ApiError("CRM_NOTE_TYPE_INVALID_MODE", "Invalid mode", translator=translator)
    if title_i18n is not None:
        row.title_i18n = dict(title_i18n)
    if scheduling_mode is not None:
        row.scheduling_mode = scheduling_mode
    if allow_comments is not None:
        row.allow_comments = allow_comments
    if is_active is not None:
        row.is_active = is_active
    if sort_order is not None:
        row.sort_order = sort_order
    row.updated_at = datetime.utcnow()
    db.flush()
    return {
        "id": row.id,
        "business_id": row.business_id,
        "code": row.code,
        "title_i18n": row.title_i18n,
        "title": resolve_i18n_map(row.title_i18n, lang),
        "scheduling_mode": row.scheduling_mode,
        "allow_comments": row.allow_comments,
        "is_system": row.is_system,
        "sort_order": row.sort_order,
    }


def delete_note_type(db: Session, business_id: int, type_id: int, translator) -> None:
    row = db.get(CrmNoteType, type_id)
    if not row or row.business_id != business_id:
        raise ApiError("CRM_NOTE_TYPE_NOT_FOUND", "Not found", http_status=404, translator=translator)
    if row.is_system:
        raise ApiError("CRM_NOTE_TYPE_SYSTEM", "Cannot delete system type", translator=translator)
    in_use = db.query(CrmNote.id).filter(CrmNote.note_type_id == type_id, CrmNote.deleted_at.is_(None)).first()
    if in_use:
        raise ApiError("CRM_NOTE_TYPE_IN_USE", "Type in use", translator=translator)
    db.delete(row)


def _validate_lead(db: Session, business_id: int, lead_id: int | None, translator) -> None:
    if lead_id is None:
        return
    lead = db.get(Lead, lead_id)
    if not lead or lead.business_id != business_id:
        raise ApiError("CRM_NOTE_LEAD_INVALID", "Invalid lead", translator=translator)


def _validate_shared_users(db: Session, business_id: int, creator_id: int, user_ids: List[int], translator) -> List[int]:
    clean = sorted({int(u) for u in user_ids if int(u) != int(creator_id)})
    if not clean:
        raise ApiError("CRM_NOTE_SHARED_EMPTY", "shared_user_ids required", translator=translator)
    for uid in clean:
        if not user_has_business_join(db, uid, business_id):
            raise ApiError("CRM_NOTE_SHARED_USER_INVALID", "Invalid user", translator=translator)
    return clean


def create_note(
    db: Session,
    ctx: AuthContext,
    business_id: int,
    *,
    note_type_id: int,
    visibility: str,
    title: str | None,
    body: str,
    occurs_on: date | None,
    starts_at: datetime | None,
    ends_at: datetime | None,
    lead_id: int | None,
    shared_user_ids: List[int] | None,
    translator,
) -> CrmNote:
    ensure_default_note_types(db, business_id)
    uid = ctx.get_user_id()
    if uid is None:
        raise ApiError("UNAUTHORIZED", "Unauthorized", http_status=401, translator=translator)
    if visibility not in ("private", "business_public", "shared"):
        raise ApiError("CRM_NOTE_VISIBILITY_INVALID", "Invalid visibility", translator=translator)
    ntype = db.get(CrmNoteType, note_type_id)
    if not ntype or ntype.business_id != business_id or not ntype.is_active:
        raise ApiError("CRM_NOTE_TYPE_NOT_FOUND", "Note type not found", http_status=404, translator=translator)

    occ: date | None = occurs_on
    st = starts_at
    en = ends_at
    if ntype.scheduling_mode == "meeting":
        if st is None:
            raise ApiError("CRM_NOTE_MEETING_START", "starts_at required", translator=translator)
        occ = st.date()
    else:
        if occ is None:
            raise ApiError("CRM_NOTE_DATE_REQUIRED", "occurs_on required", translator=translator)
        st = None
        en = None

    acl: List[int] = []
    if visibility == "shared":
        if not shared_user_ids:
            raise ApiError("CRM_NOTE_SHARED_EMPTY", "shared_user_ids required", translator=translator)
        acl = _validate_shared_users(db, business_id, int(uid), shared_user_ids, translator)

    _validate_lead(db, business_id, lead_id, translator)

    now = datetime.utcnow()
    note = CrmNote(
        business_id=business_id,
        note_type_id=note_type_id,
        visibility=visibility,
        title=(title or "").strip() or None,
        body=body.strip(),
        occurs_on=occ,  # type: ignore[arg-type]
        starts_at=st,
        ends_at=en,
        lead_id=lead_id,
        created_by_user_id=int(uid),
        status="active",
        deleted_at=None,
        created_at=now,
        updated_at=now,
    )
    db.add(note)
    db.flush()
    for x in acl:
        db.add(
            CrmNoteAclUser(
                business_id=business_id,
                note_id=note.id,
                user_id=x,
                created_at=now,
            )
        )
    db.flush()
    _audit(
        db,
        business_id=business_id,
        note_id=note.id,
        actor_user_id=int(uid),
        action="CREATED",
        payload={
            "visibility": visibility,
            "note_type_id": note_type_id,
            "occurs_on": occ.isoformat() if occ else None,
            "lead_id": lead_id,
            "shared_user_ids": acl,
        },
    )
    return note


def update_note(
    db: Session,
    ctx: AuthContext,
    business_id: int,
    note_id: int,
    *,
    note_type_id: int | None,
    visibility: str | None,
    title: str | None,
    body: str | None,
    occurs_on: date | None,
    starts_at: datetime | None,
    ends_at: datetime | None,
    lead_id: int | None,
    lead_field_set: bool = False,
    status: str | None,
    shared_user_ids: List[int] | None,
    translator,
) -> CrmNote:
    note = (
        db.query(CrmNote)
        .options(selectinload(CrmNote.acl_users))
        .filter(CrmNote.id == note_id, CrmNote.business_id == business_id, CrmNote.deleted_at.is_(None))
        .first()
    )
    if not note:
        raise ApiError("CRM_NOTE_NOT_FOUND", "Not found", http_status=404, translator=translator)
    if not can_edit_note(db, ctx, note):
        raise ApiError("CRM_NOTE_FORBIDDEN", "Forbidden", http_status=403, translator=translator)

    uid = int(ctx.get_user_id() or 0)
    changes: dict[str, Any] = {}

    ntype = note.note_type
    if note_type_id is not None:
        nt = db.get(CrmNoteType, note_type_id)
        if not nt or nt.business_id != business_id or not nt.is_active:
            raise ApiError("CRM_NOTE_TYPE_NOT_FOUND", "Note type not found", http_status=404, translator=translator)
        if nt.id != note.note_type_id:
            changes["note_type_id"] = {"old": note.note_type_id, "new": note_type_id}
        note.note_type_id = note_type_id
        ntype = nt

    if visibility is not None:
        if visibility not in ("private", "business_public", "shared"):
            raise ApiError("CRM_NOTE_VISIBILITY_INVALID", "Invalid visibility", translator=translator)
        if visibility != note.visibility:
            changes["visibility"] = {"old": note.visibility, "new": visibility}
        note.visibility = visibility
        if visibility == "shared" and shared_user_ids is None and not note.acl_users:
            raise ApiError("CRM_NOTE_SHARED_EMPTY", "shared_user_ids required", translator=translator)

    if title is not None:
        note.title = title.strip() or None
    if body is not None:
        note.body = body.strip()

    if lead_field_set:
        if lead_id is None:
            if note.lead_id is not None:
                changes["lead_id"] = {"old": note.lead_id, "new": None}
            note.lead_id = None
        else:
            _validate_lead(db, business_id, lead_id, translator)
            if note.lead_id != lead_id:
                changes["lead_id"] = {"old": note.lead_id, "new": lead_id}
            note.lead_id = lead_id

    if status is not None:
        if status not in ("active", "archived", "cancelled"):
            raise ApiError("CRM_NOTE_STATUS_INVALID", "Invalid status", translator=translator)
        if note.status != status:
            changes["status"] = {"old": note.status, "new": status}
        note.status = status

    if ntype.scheduling_mode == "meeting":
        if starts_at is not None:
            if note.starts_at != starts_at:
                changes["starts_at"] = {"old": _iso(note.starts_at), "new": _iso(starts_at)}
            note.starts_at = starts_at
            note.occurs_on = starts_at.date()
        if ends_at is not None:
            if note.ends_at != ends_at:
                changes["ends_at"] = {"old": _iso(note.ends_at), "new": _iso(ends_at)}
            note.ends_at = ends_at
    else:
        if occurs_on is not None:
            if note.occurs_on != occurs_on:
                changes["occurs_on"] = {"old": note.occurs_on.isoformat(), "new": occurs_on.isoformat()}
            note.occurs_on = occurs_on
            note.starts_at = None
            note.ends_at = None

    if shared_user_ids is not None:
        if note.visibility != "shared":
            raise ApiError("CRM_NOTE_ACL_NOT_SHARED", "Not shared note", translator=translator)
        acl = _validate_shared_users(db, business_id, note.created_by_user_id, shared_user_ids, translator)
        old_ids = sorted([a.user_id for a in note.acl_users])
        if old_ids != sorted(acl):
            changes["shared_user_ids"] = {"old": old_ids, "new": acl}
        note.acl_users.clear()
        db.flush()
        now = datetime.utcnow()
        for x in acl:
            note.acl_users.append(
                CrmNoteAclUser(
                    business_id=business_id,
                    note_id=note.id,
                    user_id=x,
                    created_at=now,
                )
            )

    if note.visibility != "shared" and note.acl_users:
        changes["shared_user_ids_cleared"] = True
        note.acl_users.clear()
        db.flush()

    note.updated_at = datetime.utcnow()
    db.flush()
    if changes:
        _audit(
            db,
            business_id=business_id,
            note_id=note.id,
            actor_user_id=uid,
            action="UPDATED",
            payload=changes,
        )
    return note


def _iso(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    return dt.isoformat()


def soft_delete_note(db: Session, ctx: AuthContext, business_id: int, note_id: int, translator) -> None:
    note = db.get(CrmNote, note_id)
    if not note or note.business_id != business_id or note.deleted_at is not None:
        raise ApiError("CRM_NOTE_NOT_FOUND", "Not found", http_status=404, translator=translator)
    if not can_edit_note(db, ctx, note):
        raise ApiError("CRM_NOTE_FORBIDDEN", "Forbidden", http_status=403, translator=translator)
    note.deleted_at = datetime.utcnow()
    note.updated_at = datetime.utcnow()
    db.flush()
    _audit(
        db,
        business_id=business_id,
        note_id=note.id,
        actor_user_id=int(ctx.get_user_id() or 0),
        action="SOFT_DELETED",
        payload=None,
    )


def list_notes(
    db: Session,
    ctx: AuthContext,
    business_id: int,
    from_date: date,
    to_date: date,
    lang: str,
) -> List[dict]:
    ensure_default_note_types(db, business_id)
    uid = ctx.get_user_id()
    if uid is None:
        return []
    q = (
        db.query(CrmNote)
        .options(
            joinedload(CrmNote.note_type),
            joinedload(CrmNote.created_by),
            joinedload(CrmNote.lead),
            selectinload(CrmNote.acl_users),
        )
        .filter(
            CrmNote.business_id == business_id,
            CrmNote.deleted_at.is_(None),
            CrmNote.occurs_on >= from_date,
            CrmNote.occurs_on <= to_date,
            _note_visible_filter(int(uid)),
        )
        .order_by(CrmNote.occurs_on, CrmNote.starts_at, CrmNote.id)
    )
    rows = q.all()
    return [note_to_dict(n, lang) for n in rows]


def get_note(db: Session, ctx: AuthContext, business_id: int, note_id: int, lang: str) -> dict | None:
    note = (
        db.query(CrmNote)
        .options(
            joinedload(CrmNote.note_type),
            joinedload(CrmNote.created_by),
            joinedload(CrmNote.lead),
            selectinload(CrmNote.acl_users),
        )
        .filter(CrmNote.id == note_id, CrmNote.business_id == business_id, CrmNote.deleted_at.is_(None))
        .first()
    )
    if not note or not can_view_note(db, ctx, note):
        return None
    return note_to_dict(note, lang, include_acl=True)


def note_to_dict(note: CrmNote, lang: str, *, include_acl: bool = False) -> dict:
    nt = note.note_type
    lead = note.lead
    data: dict[str, Any] = {
        "id": note.id,
        "business_id": note.business_id,
        "note_type_id": note.note_type_id,
        "note_type_code": nt.code if nt else None,
        "note_type_title": resolve_i18n_map(nt.title_i18n, lang) if nt else "",
        "scheduling_mode": nt.scheduling_mode if nt else "day_only",
        "visibility": note.visibility,
        "title": note.title,
        "body": note.body,
        "occurs_on": note.occurs_on,
        "starts_at": note.starts_at,
        "ends_at": note.ends_at,
        "lead_id": note.lead_id,
        "lead_name": lead.name if lead else None,
        "lead_code": lead.code if lead else None,
        "status": note.status,
        "created_by_user_id": note.created_by_user_id,
        "created_by_name": _user_display_name(note.created_by),
        "comments_enabled": comments_enabled_for(note, nt) if nt else False,
        "created_at": note.created_at,
        "updated_at": note.updated_at,
    }
    if include_acl and note.visibility == "shared":
        data["shared_user_ids"] = [a.user_id for a in note.acl_users]
    return data


def list_comments(db: Session, ctx: AuthContext, business_id: int, note_id: int, lang: str) -> List[dict]:
    note = db.get(CrmNote, note_id)
    if not note or note.business_id != business_id or note.deleted_at is not None:
        raise ApiError("CRM_NOTE_NOT_FOUND", "Not found", http_status=404, translator=None)
    if not can_view_note(db, ctx, note):
        raise ApiError("CRM_NOTE_FORBIDDEN", "Forbidden", http_status=403, translator=None)
    ntype = db.get(CrmNoteType, note.note_type_id)
    if not ntype or not comments_enabled_for(note, ntype):
        return []
    rows = (
        db.query(CrmNoteComment)
        .options(joinedload(CrmNoteComment.created_by))
        .filter(
            CrmNoteComment.note_id == note_id,
            CrmNoteComment.business_id == business_id,
            CrmNoteComment.deleted_at.is_(None),
        )
        .order_by(CrmNoteComment.id)
        .all()
    )
    out = []
    for c in rows:
        out.append(
            {
                "id": c.id,
                "note_id": c.note_id,
                "body": c.body,
                "created_by_user_id": c.created_by_user_id,
                "created_by_name": _user_display_name(c.created_by),
                "created_at": c.created_at,
                "updated_at": c.updated_at,
            }
        )
    return out


def add_comment(
    db: Session,
    ctx: AuthContext,
    business_id: int,
    note_id: int,
    body: str,
    translator,
) -> dict:
    note = db.get(CrmNote, note_id)
    if not note or note.business_id != business_id or note.deleted_at is not None:
        raise ApiError("CRM_NOTE_NOT_FOUND", "Not found", http_status=404, translator=translator)
    if not can_view_note(db, ctx, note):
        raise ApiError("CRM_NOTE_FORBIDDEN", "Forbidden", http_status=403, translator=translator)
    ntype = db.get(CrmNoteType, note.note_type_id)
    if not ntype or not comments_enabled_for(note, ntype):
        raise ApiError("CRM_NOTE_COMMENTS_DISABLED", "Comments disabled", http_status=400, translator=translator)
    uid = int(ctx.get_user_id() or 0)
    now = datetime.utcnow()
    c = CrmNoteComment(
        business_id=business_id,
        note_id=note_id,
        body=body.strip(),
        created_by_user_id=uid,
        created_at=now,
        updated_at=now,
    )
    db.add(c)
    db.flush()
    author = db.get(User, uid)
    _audit(
        db,
        business_id=business_id,
        note_id=note_id,
        actor_user_id=uid,
        action="COMMENT_CREATED",
        payload={"comment_id": c.id},
    )
    return {
        "id": c.id,
        "note_id": c.note_id,
        "body": c.body,
        "created_by_user_id": c.created_by_user_id,
        "created_by_name": _user_display_name(author),
        "created_at": c.created_at,
        "updated_at": c.updated_at,
    }


def delete_comment(db: Session, ctx: AuthContext, business_id: int, note_id: int, comment_id: int, translator) -> None:
    note = db.get(CrmNote, note_id)
    if not note or note.business_id != business_id:
        raise ApiError("CRM_NOTE_NOT_FOUND", "Not found", http_status=404, translator=translator)
    c = db.get(CrmNoteComment, comment_id)
    if not c or c.note_id != note_id or c.deleted_at is not None:
        raise ApiError("CRM_NOTE_COMMENT_NOT_FOUND", "Not found", http_status=404, translator=translator)
    uid = int(ctx.get_user_id() or 0)
    if c.created_by_user_id != uid and not (ctx.is_superadmin() or ctx.is_business_owner(business_id)):
        raise ApiError("CRM_NOTE_FORBIDDEN", "Forbidden", http_status=403, translator=translator)
    c.deleted_at = datetime.utcnow()
    c.updated_at = datetime.utcnow()
    db.flush()
    _audit(
        db,
        business_id=business_id,
        note_id=note_id,
        actor_user_id=uid,
        action="COMMENT_DELETED",
        payload={"comment_id": comment_id},
    )


def list_audit(db: Session, ctx: AuthContext, business_id: int, note_id: int) -> List[dict]:
    note = db.get(CrmNote, note_id)
    if not note or note.business_id != business_id:
        raise ApiError("CRM_NOTE_NOT_FOUND", "Not found", http_status=404, translator=None)
    if not can_view_note(db, ctx, note):
        raise ApiError("CRM_NOTE_FORBIDDEN", "Forbidden", http_status=403, translator=None)
    uid = int(ctx.get_user_id() or 0)
    if not (
        ctx.is_superadmin()
        or ctx.is_business_owner(business_id)
        or note.created_by_user_id == uid
    ):
        raise ApiError("CRM_NOTE_AUDIT_FORBIDDEN", "Audit forbidden", http_status=403, translator=None)
    rows = (
        db.query(CrmNoteAuditEvent)
        .options(joinedload(CrmNoteAuditEvent.actor))
        .filter(CrmNoteAuditEvent.note_id == note_id, CrmNoteAuditEvent.business_id == business_id)
        .order_by(CrmNoteAuditEvent.id.desc())
        .limit(200)
        .all()
    )
    out = []
    for e in rows:
        payload = e.payload
        if isinstance(payload, dict):
            payload_str = json.dumps(payload, ensure_ascii=False)
        else:
            payload_str = None
        out.append(
            {
                "id": e.id,
                "action": e.action,
                "payload": e.payload,
                "payload_text": payload_str,
                "actor_user_id": e.actor_user_id,
                "actor_name": _user_display_name(e.actor),
                "occurred_at": e.occurred_at,
            }
        )
    return out
