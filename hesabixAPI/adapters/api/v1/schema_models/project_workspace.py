from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field, validator


class ProjectMemberUpsertRequest(BaseModel):
    user_id: int = Field(..., gt=0)
    role: str = Field(default="member")

    @validator("role")
    def validate_role(cls, value: str) -> str:
        allowed = {"viewer", "member", "manager", "owner"}
        if value not in allowed:
            raise ValueError(f"role must be one of {sorted(allowed)}")
        return value



class ProjectMilestoneCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    description: str | None = None
    start_at: datetime | None = None
    target_at: datetime | None = None
    status: str = Field(default="open")
    sort_order: float = 0


class ProjectMilestoneUpdateRequest(BaseModel):
    title: str | None = Field(None, min_length=1, max_length=255)
    description: str | None = None
    start_at: datetime | None = None
    target_at: datetime | None = None
    status: str | None = None
    sort_order: float | None = None



class ProjectCycleCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    goal: str | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    status: str = Field(default="planned")


class ProjectCycleUpdateRequest(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=255)
    goal: str | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    status: str | None = None
