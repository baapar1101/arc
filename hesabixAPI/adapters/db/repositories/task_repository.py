"""
Repository helpers for first-class task management.
"""

from __future__ import annotations

from typing import Optional

from sqlalchemy import or_, select
from sqlalchemy.orm import Session, joinedload

from adapters.db.models.task_management import Task, TaskAssignee, TaskStatus


class TaskRepository:
    """Persistence helpers for first-class business tasks."""

    def __init__(self, db: Session):
        self.db = db

    def get_by_id(
        self,
        task_id: int,
        business_id: Optional[int] = None,
        *,
        include_deleted: bool = False,
    ) -> Optional[Task]:
        query = (
            self.db.query(Task)
            .options(
                joinedload(Task.status),
                joinedload(Task.project),
                joinedload(Task.created_by),
            )
            .filter(Task.id == task_id)
        )
        if business_id is not None:
            query = query.filter(Task.business_id == business_id)
        if not include_deleted:
            query = query.filter(Task.deleted_at.is_(None))
        return query.first()

    def list_statuses(self, business_id: int) -> list[TaskStatus]:
        return (
            self.db.query(TaskStatus)
            .filter(TaskStatus.business_id == business_id)
            .order_by(TaskStatus.sort_order.asc(), TaskStatus.id.asc())
            .all()
        )

    def list_tasks(
        self,
        business_id: int,
        *,
        search: Optional[str] = None,
        project_id: Optional[int] = None,
        status_id: Optional[int] = None,
        assignee_user_id: Optional[int] = None,
        priority: Optional[str] = None,
        completed: Optional[bool] = None,
        skip: int = 0,
        limit: int = 100,
    ) -> tuple[list[Task], int]:
        query = (
            self.db.query(Task)
            .options(
                joinedload(Task.status),
                joinedload(Task.project),
                joinedload(Task.created_by),
            )
            .filter(
                Task.business_id == business_id,
                Task.deleted_at.is_(None),
            )
        )

        if search:
            pattern = f"%{search.strip()}%"
            query = query.filter(
                or_(
                    Task.title.ilike(pattern),
                    Task.description.ilike(pattern),
                )
            )
        if project_id is not None:
            query = query.filter(Task.project_id == project_id)
        if status_id is not None:
            query = query.filter(Task.status_id == status_id)
        if priority:
            query = query.filter(Task.priority == priority)
        if completed is True:
            query = query.filter(Task.completed_at.is_not(None))
        elif completed is False:
            query = query.filter(Task.completed_at.is_(None))

        if assignee_user_id is not None:
            assigned_task_ids = select(TaskAssignee.task_id).where(
                TaskAssignee.user_id == assignee_user_id
            )
            query = query.filter(Task.id.in_(assigned_task_ids))

        total = query.count()
        items = (
            query.order_by(
                Task.due_at.asc().nullslast(),
                Task.sort_order.asc(),
                Task.created_at.desc(),
            )
            .offset(skip)
            .limit(limit)
            .all()
        )
        return items, total

    def next_sort_order(self, business_id: int, project_id: Optional[int]) -> int:
        query = self.db.query(Task.sort_order).filter(
            Task.business_id == business_id,
            Task.deleted_at.is_(None),
        )
        if project_id is None:
            query = query.filter(Task.project_id.is_(None))
        else:
            query = query.filter(Task.project_id == project_id)

        value = query.order_by(Task.sort_order.desc()).limit(1).scalar()
        if value is None:
            return 1000
        try:
            return int(value) + 1000
        except Exception:
            return 1000

    def assignee_rows(self, task_id: int) -> list[TaskAssignee]:
        return (
            self.db.query(TaskAssignee)
            .options(joinedload(TaskAssignee.user))
            .filter(TaskAssignee.task_id == task_id)
            .order_by(TaskAssignee.assigned_at.asc(), TaskAssignee.id.asc())
            .all()
        )
