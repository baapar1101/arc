from __future__ import annotations

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
