from __future__ import annotations

from typing import Optional, List
from pydantic import BaseModel, Field


class ProductAttributeCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=255, description="عنوان ویژگی")
    description: Optional[str] = Field(default=None, description="توضیحات ویژگی")


class ProductAttributeUpdateRequest(BaseModel):
    title: Optional[str] = Field(default=None, min_length=1, max_length=255, description="عنوان ویژگی")
    description: Optional[str] = Field(default=None, description="توضیحات ویژگی")


class ProductAttributeResponse(BaseModel):
    id: int
    business_id: int
    title: str
    description: Optional[str] = None
    created_at: str
    updated_at: str


class ProductAttributeListResponse(BaseModel):
    items: list[ProductAttributeResponse]
    pagination: dict


