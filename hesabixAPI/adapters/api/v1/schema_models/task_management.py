from __future__ import annotations

from datetime import datetime
from typing import Optional

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
    assignee_user_ids: list[int] = Field(default_factory=list)


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
    assignee_user_ids: Optional[list[int]] = None


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
