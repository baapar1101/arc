"""Task/project authorization policy over existing business permissions and project roles."""

from __future__ import annotations

from typing import Optional

from sqlalchemy.orm import Session

from adapters.db.models.project import Project
from adapters.db.models.task_management import ProjectMember, Task, TaskAssignee
from app.core.auth_dependency import AuthContext
from app.core.permissions import get_business_permissions_for_user
from app.core.responses import ApiError

_SECTION = "projects"

_ACTION_ALIASES: dict[str, tuple[str, ...]] = {
    "view": ("view", "read"),
    "project_create": ("project_create", "add"),
    "project_edit": ("project_edit", "edit", "write"),
    "project_delete": ("project_delete", "delete"),
    "manage_members": ("manage_members",),
    "task_create": ("task_create", "add"),
    "task_edit": ("task_edit", "edit", "write"),
    "task_delete": ("task_delete", "delete"),
    "task_assign": ("task_assign", "edit", "write"),
    "time_log": ("time_log", "edit", "write"),
    "time_view_team": ("time_view_team",),
}

_ROLE_LEVEL = {
    "viewer": 0,
    "member": 1,
    "manager": 2,
    "owner": 3,
}

_CAP_ROLE_LEVEL = {
    "view": 0,
    "task_create": 1,
    "task_edit": 1,
    "time_log": 1,
    "task_delete": 2,
    "task_assign": 2,
    "project_edit": 2,
    "manage_members": 2,
    "time_view_team": 2,
    "project_delete": 3,
}


def _section_permissions(
    ctx: AuthContext,
    db: Session,
    business_id: int,
) -> tuple[bool, dict]:
    """Return (explicitly_configured, section_permissions).

    Absence of the projects section intentionally means legacy mode so existing
    business members are not locked out when Phase 17 is deployed.
    """
    if ctx.is_superadmin() or ctx.is_business_owner(business_id):
        return True, {"__all__": True}
    permissions = get_business_permissions_for_user(ctx, db, business_id) or {}
    if _SECTION not in permissions:
        return False, {}
    section = permissions.get(_SECTION)
    return True, section if isinstance(section, dict) else {}


def project_permission_configured(
    ctx: AuthContext,
    db: Session,
    business_id: int,
) -> bool:
    configured, _ = _section_permissions(ctx, db, business_id)
    return configured


def business_project_action(
    ctx: AuthContext,
    db: Session,
    business_id: int,
    action: str,
) -> bool:
    if ctx.is_superadmin() or ctx.is_business_owner(business_id):
        return True
    configured, section = _section_permissions(ctx, db, business_id)
    if not configured:
        return True
    if section.get("__all__") is True:
        return True
    aliases = _ACTION_ALIASES.get(action, (action,))
    return any(section.get(key) is True for key in aliases)


def _project_role(
    db: Session,
    business_id: int,
    project_id: int,
    user_id: int,
) -> Optional[str]:
    project = db.query(Project).filter(
        Project.id == project_id,
        Project.business_id == business_id,
    ).first()
    if project is None:
        return None
    if project.manager_user_id and int(project.manager_user_id) == int(user_id):
        return "manager"
    member = db.query(ProjectMember).filter(
        ProjectMember.business_id == business_id,
        ProjectMember.project_id == project_id,
        ProjectMember.user_id == user_id,
    ).first()
    return member.role if member else None


def accessible_project_ids(
    ctx: AuthContext,
    db: Session,
    business_id: int,
) -> Optional[set[int]]:
    """None means the user can see every project in the business."""
    if business_project_action(ctx, db, business_id, "view"):
        return None
    user_id = ctx.get_user_id()
    rows = db.query(ProjectMember.project_id).filter(
        ProjectMember.business_id == business_id,
        ProjectMember.user_id == user_id,
    ).all()
    ids = {int(row[0]) for row in rows}
    manager_rows = db.query(Project.id).filter(
        Project.business_id == business_id,
        Project.manager_user_id == user_id,
    ).all()
    ids.update(int(row[0]) for row in manager_rows)
    return ids


def require_project_capability(
    ctx: AuthContext,
    db: Session,
    business_id: int,
    project_id: int,
    capability: str,
) -> Project:
    project = db.query(Project).filter(
        Project.id == project_id,
        Project.business_id == business_id,
    ).first()
    if project is None:
        raise ApiError("PROJECT_NOT_FOUND", "Project not found", http_status=404)

    if business_project_action(ctx, db, business_id, capability):
        return project

    role = _project_role(db, business_id, project_id, ctx.get_user_id())
    required = _CAP_ROLE_LEVEL.get(capability, 99)
    if role is not None and _ROLE_LEVEL.get(role, -1) >= required:
        return project

    raise ApiError(
        "PROJECT_PERMISSION_DENIED",
        f"Missing project capability: {capability}",
        http_status=403,
    )


def _is_task_assignee(
    db: Session,
    business_id: int,
    task_id: int,
    user_id: int,
) -> bool:
    return db.query(TaskAssignee.id).filter(
        TaskAssignee.business_id == business_id,
        TaskAssignee.task_id == task_id,
        TaskAssignee.user_id == user_id,
    ).first() is not None


def require_task_capability(
    ctx: AuthContext,
    db: Session,
    business_id: int,
    task_id: int,
    capability: str,
) -> Task:
    task = db.query(Task).filter(
        Task.id == task_id,
        Task.business_id == business_id,
        Task.deleted_at.is_(None),
    ).first()
    if task is None:
        raise ApiError("TASK_NOT_FOUND", "Task not found", http_status=404)

    if business_project_action(ctx, db, business_id, capability):
        return task

    user_id = ctx.get_user_id()
    if task.project_id is not None:
        role = _project_role(db, business_id, task.project_id, user_id)
        required = _CAP_ROLE_LEVEL.get(capability, 99)
        if role is not None and _ROLE_LEVEL.get(role, -1) >= required:
            return task

    own = task.created_by_user_id == user_id
    assigned = _is_task_assignee(db, business_id, task.id, user_id)
    if capability == "view" and (own or assigned):
        return task
    if capability in {"task_edit", "time_log"} and (own or assigned):
        return task
    if capability in {"task_delete", "task_assign"} and own:
        return task

    raise ApiError(
        "TASK_PERMISSION_DENIED",
        f"Missing task capability: {capability}",
        http_status=403,
    )


def task_visibility_scope(
    ctx: AuthContext,
    db: Session,
    business_id: int,
) -> tuple[Optional[set[int]], Optional[int]]:
    """Return (visible_project_ids, personal_user_id).

    (None, None) means unrestricted business-wide task visibility.
    Otherwise project tasks are limited to membership/management and personal
    unprojected tasks are limited to creator/assignee visibility.
    """
    project_ids = accessible_project_ids(ctx, db, business_id)
    if project_ids is None:
        return None, None
    return project_ids, ctx.get_user_id()
