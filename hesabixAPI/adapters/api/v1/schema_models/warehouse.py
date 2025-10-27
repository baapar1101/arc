from __future__ import annotations

from typing import Optional
from pydantic import BaseModel, Field


class WarehouseCreateRequest(BaseModel):
    code: str = Field(..., max_length=64)
    name: str = Field(..., max_length=255)
    description: Optional[str] = Field(default=None, max_length=2000)
    is_default: bool = Field(default=False)


class WarehouseUpdateRequest(BaseModel):
    code: Optional[str] = Field(default=None, max_length=64)
    name: Optional[str] = Field(default=None, max_length=255)
    description: Optional[str] = Field(default=None, max_length=2000)
    is_default: Optional[bool] = Field(default=None)


class WarehouseResponse(BaseModel):
    id: int
    business_id: int
    code: str
    name: str
    description: Optional[str] = None
    is_default: bool
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


