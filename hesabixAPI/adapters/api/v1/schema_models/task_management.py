from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, Field


class TaskCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=500)
    description: Optional[str] = None
    project_id: Optional[int] = Field(None, gt=0)
    parent_task_id: Optional[int] = Field(None, gt=0)
    status_id: Optional[int] = Field(None, gt=0)
    priority: str = Field(default="normal")
    start_at: Optional[datetime] = None
    due_at: Optional[datetime] = None
    estimated_minutes: Optional[int] = Field(None, ge=0)
    recurrence_rule: Optional[str] = Field(None, max_length=512)
    recurrence_timezone: Optional[str] = Field(None, max_length=80)
    recurrence_end_at: Optional[datetime] = None
    assignee_user_ids: list[int] = Field(default_factory=list)
    label_ids: list[int] = Field(default_factory=list)


class TaskUpdateRequest(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=500)
    description: Optional[str] = None
    project_id: Optional[int] = Field(None, gt=0)
    parent_task_id: Optional[int] = Field(None, gt=0)
    status_id: Optional[int] = Field(None, gt=0)
    priority: Optional[str] = None
    start_at: Optional[datetime] = None
    due_at: Optional[datetime] = None
    estimated_minutes: Optional[int] = Field(None, ge=0)
    recurrence_rule: Optional[str] = Field(None, max_length=512)
    recurrence_timezone: Optional[str] = Field(None, max_length=80)
    recurrence_end_at: Optional[datetime] = None
    assignee_user_ids: Optional[list[int]] = None
    label_ids: Optional[list[int]] = None


class TaskAssigneesRequest(BaseModel):
    user_ids: list[int] = Field(default_factory=list)



class TaskMoveRequest(BaseModel):
    target_status_id: int = Field(..., gt=0)
    target_index: int = Field(..., ge=0)



class TaskSubtaskCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=500)
    description: Optional[str] = None
    priority: str = Field(default="normal")
    due_at: Optional[datetime] = None
    assignee_user_ids: list[int] = Field(default_factory=list)


class TaskRelationCreateRequest(BaseModel):
    related_task_id: int = Field(..., gt=0)
    relation_type: str = Field(..., min_length=1, max_length=20)



class TaskCommentCreateRequest(BaseModel):
    body: str = Field(..., min_length=1, max_length=10000)


class TaskCommentUpdateRequest(BaseModel):
    body: str = Field(..., min_length=1, max_length=10000)



class TaskLabelCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    color: Optional[str] = Field(None, max_length=20)
    description: Optional[str] = None


class TaskLabelUpdateRequest(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    color: Optional[str] = Field(None, max_length=20)
    description: Optional[str] = None


class TaskLabelsAssignRequest(BaseModel):
    label_ids: list[int] = Field(default_factory=list)


class TaskSavedViewCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    project_id: Optional[int] = Field(None, gt=0)
    view_type: str = Field(default="list", min_length=1, max_length=30)
    filters: dict[str, Any] = Field(default_factory=dict)
    sort: dict[str, Any] = Field(default_factory=dict)
    is_shared: bool = False


class TaskSavedViewUpdateRequest(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=120)
    project_id: Optional[int] = Field(None, gt=0)
    view_type: Optional[str] = Field(None, min_length=1, max_length=30)
    filters: Optional[dict[str, Any]] = None
    sort: Optional[dict[str, Any]] = None
    is_shared: Optional[bool] = None



class TaskReminderCreateRequest(BaseModel):
    user_id: Optional[int] = Field(None, gt=0)
    remind_at: Optional[datetime] = None
    relative_to: Optional[str] = Field(None, max_length=20)
    offset_minutes: Optional[int] = Field(None, ge=0)
