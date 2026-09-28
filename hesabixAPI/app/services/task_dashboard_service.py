"""Permission-aware aggregate dashboard for native task/project management."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import and_, case, false, func, or_, select
from sqlalchemy.orm import Session

from adapters.db.models.project import Project
from adapters.db.models.task_management import (
    Milestone,
    ProjectCycle,
    ProjectCycleTask,
    Task,
    TaskAssignee,
    TaskStatus,
    TaskTimeEntry,
)
from adapters.db.models.user import User
from app.core.auth_dependency import AuthContext
from app.core.datetime_utils import resolve_display_timezone_name
from app.core.task_project_permissions import (
    accessible_project_ids,
    business_project_action,
    task_visibility_scope,
)


def _user_name(user: User | None, user_id: int) -> str:
    if user is None:
        return f"User {user_id}"
    name = f"{user.first_name or ''} {user.last_name or ''}".strip()
    return name or user.email or user.mobile or f"User {user_id}"


def _visible_task_query(
    db: Session,
    business_id: int,
    ctx: AuthContext,
):
    query = db.query(Task).filter(
        Task.business_id == business_id,
        Task.deleted_at.is_(None),
    )
    project_ids, user_id = task_visibility_scope(ctx, db, business_id)
    if project_ids is not None:
        assigned_ids = select(TaskAssignee.task_id).where(
            TaskAssignee.business_id == business_id,
            TaskAssignee.user_id == user_id,
        )
        project_clause = (
            Task.project_id.in_(project_ids)
            if project_ids
            else false()
        )
        query = query.filter(
            or_(
                project_clause,
                and_(
                    Task.project_id.is_(None),
                    or_(
                        Task.created_by_user_id == user_id,
                        Task.id.in_(assigned_ids),
                    ),
                ),
            )
        )
    return query, project_ids, user_id


def _open_query(query):
    return query.outerjoin(TaskStatus, Task.status_id == TaskStatus.id).filter(
        Task.completed_at.is_(None),
        or_(
            TaskStatus.category.is_(None),
            TaskStatus.category != "cancelled",
        ),
    )


def _task_brief(task: Task) -> dict:
    return {
        "id": task.id,
        "title": task.title,
        "project_id": task.project_id,
        "project_name": task.project.name if task.project else None,
        "status_id": task.status_id,
        "status_name": task.status.name if task.status else None,
        "priority": task.priority,
        "due_at": task.due_at,
        "completed_at": task.completed_at,
    }


def get_task_dashboard(
    db: Session,
    business_id: int,
    ctx: AuthContext,
) -> dict:
    now = datetime.now(timezone.utc)
    seven_days_ago = now - timedelta(days=7)

    tz_name = resolve_display_timezone_name(business_id) or "UTC"
    try:
        tz = ZoneInfo(tz_name)
    except ZoneInfoNotFoundError:
        tz = ZoneInfo("UTC")
        tz_name = "UTC"

    local_now = now.astimezone(tz)
    local_today = local_now.replace(hour=0, minute=0, second=0, microsecond=0)
    today_start = local_today.astimezone(timezone.utc)
    today_end = (local_today + timedelta(days=1)).astimezone(timezone.utc)

    visible_query, scoped_project_ids, user_id = _visible_task_query(
        db,
        business_id,
        ctx,
    )
    open_query = _open_query(visible_query)
    visible_ids = visible_query.with_entities(Task.id).subquery()

    assigned_any = select(TaskAssignee.task_id).where(
        TaskAssignee.business_id == business_id,
    )

    summary = {
        "open": open_query.count(),
        "due_today": open_query.filter(
            Task.due_at >= today_start,
            Task.due_at < today_end,
        ).count(),
        "overdue": open_query.filter(
            Task.due_at.is_not(None),
            Task.due_at < now,
        ).count(),
        "completed_7d": visible_query.filter(
            Task.completed_at.is_not(None),
            Task.completed_at >= seven_days_ago,
        ).count(),
        "unassigned": open_query.filter(
            ~Task.id.in_(assigned_any)
        ).count(),
    }

    my_assigned_ids = select(TaskAssignee.task_id).where(
        TaskAssignee.business_id == business_id,
        TaskAssignee.user_id == user_id,
    )
    my_tasks = (
        _open_query(visible_query)
        .filter(
            or_(
                Task.created_by_user_id == user_id,
                Task.id.in_(my_assigned_ids),
            )
        )
        .order_by(
            Task.due_at.asc().nullslast(),
            Task.priority.desc(),
            Task.created_at.desc(),
        )
        .limit(8)
        .all()
    )

    completed_recent = (
        visible_query.filter(
            Task.completed_at.is_not(None),
            Task.completed_at >= seven_days_ago,
        )
        .order_by(Task.completed_at.desc())
        .limit(6)
        .all()
    )

    project_ids = accessible_project_ids(ctx, db, business_id)
    project_query = db.query(Project).filter(
        Project.business_id == business_id,
        Project.is_active.is_(True),
    )
    if project_ids is not None:
        if project_ids:
            project_query = project_query.filter(Project.id.in_(project_ids))
        else:
            project_query = project_query.filter(false())

    projects = project_query.order_by(Project.updated_at.desc()).limit(12).all()
    project_stats_rows = (
        db.query(
            Task.project_id,
            func.count(Task.id),
            func.sum(case((Task.completed_at.is_not(None), 1), else_=0)),
            func.sum(
                case(
                    (
                        and_(
                            Task.completed_at.is_(None),
                            Task.due_at.is_not(None),
                            Task.due_at < now,
                        ),
                        1,
                    ),
                    else_=0,
                )
            ),
        )
        .filter(
            Task.id.in_(select(visible_ids.c.id)),
            Task.project_id.is_not(None),
        )
        .group_by(Task.project_id)
        .all()
    )
    project_stats = {
        int(row[0]): {
            "total": int(row[1] or 0),
            "completed": int(row[2] or 0),
            "overdue": int(row[3] or 0),
        }
        for row in project_stats_rows
    }
    project_progress = []
    for project in projects:
        stats = project_stats.get(
            project.id,
            {"total": 0, "completed": 0, "overdue": 0},
        )
        total = stats["total"]
        completed = stats["completed"]
        project_progress.append(
            {
                "project_id": project.id,
                "code": project.code,
                "name": project.name,
                "status": project.status,
                **stats,
                "progress_percent": round(
                    (completed / total) * 100,
                    1,
                )
                if total
                else 0.0,
            }
        )

    workload_rows = (
        db.query(
            TaskAssignee.user_id,
            func.count(func.distinct(Task.id)),
            func.sum(
                case(
                    (
                        and_(
                            Task.due_at.is_not(None),
                            Task.due_at < now,
                        ),
                        1,
                    ),
                    else_=0,
                )
            ),
        )
        .join(Task, TaskAssignee.task_id == Task.id)
        .outerjoin(TaskStatus, Task.status_id == TaskStatus.id)
        .filter(
            TaskAssignee.business_id == business_id,
            Task.id.in_(select(visible_ids.c.id)),
            Task.completed_at.is_(None),
            or_(
                TaskStatus.category.is_(None),
                TaskStatus.category != "cancelled",
            ),
        )
        .group_by(TaskAssignee.user_id)
        .order_by(func.count(func.distinct(Task.id)).desc())
        .limit(10)
        .all()
    )
    workload_user_ids = [int(row[0]) for row in workload_rows]
    workload_users = (
        db.query(User).filter(User.id.in_(workload_user_ids)).all()
        if workload_user_ids
        else []
    )
    users_by_id = {user.id: user for user in workload_users}
    workload = [
        {
            "user_id": int(row[0]),
            "name": _user_name(users_by_id.get(int(row[0])), int(row[0])),
            "open": int(row[1] or 0),
            "overdue": int(row[2] or 0),
        }
        for row in workload_rows
    ]

    milestone_query = db.query(Milestone).filter(
        Milestone.business_id == business_id,
        Milestone.status.notin_(["completed", "cancelled"]),
    )
    cycle_query = db.query(ProjectCycle).filter(
        ProjectCycle.business_id == business_id,
        ProjectCycle.status.notin_(["completed", "cancelled"]),
    )
    if project_ids is not None:
        if project_ids:
            milestone_query = milestone_query.filter(
                Milestone.project_id.in_(project_ids)
            )
            cycle_query = cycle_query.filter(
                ProjectCycle.project_id.in_(project_ids)
            )
        else:
            milestone_query = milestone_query.filter(false())
            cycle_query = cycle_query.filter(false())

    milestones = milestone_query.order_by(
        Milestone.target_at.asc().nullslast(),
        Milestone.sort_order.asc(),
    ).limit(6).all()

    milestone_counts = {
        int(row[0]): (int(row[1] or 0), int(row[2] or 0))
        for row in db.query(
            Task.milestone_id,
            func.count(Task.id),
            func.sum(case((Task.completed_at.is_not(None), 1), else_=0)),
        )
        .filter(
            Task.id.in_(select(visible_ids.c.id)),
            Task.milestone_id.is_not(None),
        )
        .group_by(Task.milestone_id)
        .all()
    }

    cycles = cycle_query.order_by(
        ProjectCycle.start_at.asc().nullslast(),
        ProjectCycle.id.asc(),
    ).limit(6).all()
    cycle_counts = {
        int(row[0]): (int(row[1] or 0), int(row[2] or 0))
        for row in db.query(
            ProjectCycleTask.cycle_id,
            func.count(Task.id),
            func.sum(case((Task.completed_at.is_not(None), 1), else_=0)),
        )
        .join(Task, ProjectCycleTask.task_id == Task.id)
        .filter(Task.id.in_(select(visible_ids.c.id)))
        .group_by(ProjectCycleTask.cycle_id)
        .all()
    }

    can_view_team_time = business_project_action(
        ctx,
        db,
        business_id,
        "time_view_team",
    )
    time_query = db.query(TaskTimeEntry).filter(
        TaskTimeEntry.business_id == business_id,
        TaskTimeEntry.task_id.in_(select(visible_ids.c.id)),
        TaskTimeEntry.ended_at.is_not(None),
        TaskTimeEntry.started_at >= seven_days_ago,
    )
    if not can_view_team_time:
        time_query = time_query.filter(TaskTimeEntry.user_id == user_id)
    time_rows = time_query.all()
    time_total = sum(int(row.duration_seconds or 0) for row in time_rows)
    time_billable = sum(
        int(row.duration_seconds or 0)
        for row in time_rows
        if row.billable
    )
    summary["time_seconds_7d"] = time_total

    status_rows = (
        db.query(
            TaskStatus.id,
            TaskStatus.name,
            TaskStatus.color,
            TaskStatus.category,
            func.count(Task.id),
        )
        .join(Task, Task.status_id == TaskStatus.id)
        .filter(Task.id.in_(select(visible_ids.c.id)))
        .group_by(
            TaskStatus.id,
            TaskStatus.name,
            TaskStatus.color,
            TaskStatus.category,
        )
        .order_by(TaskStatus.sort_order.asc(), TaskStatus.id.asc())
        .all()
    )

    return {
        "scope": {
            "project_visibility": (
                "all" if scoped_project_ids is None else "scoped"
            ),
            "time_visibility": "team" if can_view_team_time else "self",
            "timezone": tz_name,
        },
        "summary": summary,
        "my_tasks": [_task_brief(task) for task in my_tasks],
        "recent_completed": [
            _task_brief(task) for task in completed_recent
        ],
        "project_progress": project_progress,
        "workload": workload,
        "milestones": [
            {
                "id": item.id,
                "project_id": item.project_id,
                "title": item.title,
                "status": item.status,
                "target_at": item.target_at,
                "total": milestone_counts.get(item.id, (0, 0))[0],
                "completed": milestone_counts.get(item.id, (0, 0))[1],
                "progress_percent": (
                    round(
                        milestone_counts.get(item.id, (0, 0))[1]
                        / milestone_counts.get(item.id, (0, 0))[0]
                        * 100,
                        1,
                    )
                    if milestone_counts.get(item.id, (0, 0))[0]
                    else 0.0
                ),
            }
            for item in milestones
        ],
        "cycles": [
            {
                "id": item.id,
                "project_id": item.project_id,
                "name": item.name,
                "goal": item.goal,
                "status": item.status,
                "start_at": item.start_at,
                "end_at": item.end_at,
                "total": cycle_counts.get(item.id, (0, 0))[0],
                "completed": cycle_counts.get(item.id, (0, 0))[1],
                "progress_percent": (
                    round(
                        cycle_counts.get(item.id, (0, 0))[1]
                        / cycle_counts.get(item.id, (0, 0))[0]
                        * 100,
                        1,
                    )
                    if cycle_counts.get(item.id, (0, 0))[0]
                    else 0.0
                ),
            }
            for item in cycles
        ],
        "time_7d": {
            "total_seconds": time_total,
            "billable_seconds": time_billable,
        },
        "status_breakdown": [
            {
                "status_id": int(row[0]),
                "name": row[1],
                "color": row[2],
                "category": row[3],
                "count": int(row[4] or 0),
            }
            for row in status_rows
        ],
    }
