from __future__ import annotations

from typing import Optional, List
from pydantic import BaseModel, Field, field_validator


class ProductAttributeCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=255, description="عنوان ویژگی")
    description: Optional[str] = Field(default=None, description="توضیحات ویژگی")
    data_type: Optional[str] = Field(default='text', description="نوع داده: text, number, date, select, boolean")
    options: Optional[List[str]] = Field(default=None, description="گزینه‌های select (فقط برای نوع select)")
    
    @field_validator('data_type')
    @classmethod
    def validate_data_type(cls, v: Optional[str]) -> str:
        if v is None:
            return 'text'
        valid_types = ['text', 'number', 'date', 'select', 'boolean']
        if v not in valid_types:
            raise ValueError(f"data_type باید یکی از {valid_types} باشد")
        return v
    
    @field_validator('options')
    @classmethod
    def validate_options(cls, v: Optional[List[str]], info) -> Optional[List[str]]:
        if v is not None and len(v) == 0:
            return None
        # اگر data_type='select' باشد، options باید وجود داشته باشد
        if info.data and info.data.get('data_type') == 'select':
            if not v or len(v) == 0:
                raise ValueError("برای نوع select باید حداقل یک گزینه مشخص شود")
        return v


class ProductAttributeUpdateRequest(BaseModel):
    title: Optional[str] = Field(default=None, min_length=1, max_length=255, description="عنوان ویژگی")
    description: Optional[str] = Field(default=None, description="توضیحات ویژگی")
    data_type: Optional[str] = Field(default=None, description="نوع داده: text, number, date, select, boolean")
    options: Optional[List[str]] = Field(default=None, description="گزینه‌های select (فقط برای نوع select)")
    
    @field_validator('data_type')
    @classmethod
    def validate_data_type(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        valid_types = ['text', 'number', 'date', 'select', 'boolean']
        if v not in valid_types:
            raise ValueError(f"data_type باید یکی از {valid_types} باشد")
        return v


class ProductAttributeResponse(BaseModel):
    id: int
    business_id: int
    title: str
    description: Optional[str] = None
    data_type: str = Field(default='text', description="نوع داده: text, number, date, select, boolean")
    options: Optional[List[str]] = Field(default=None, description="گزینه‌های select")
    created_at: str
    updated_at: str


class ProductAttributeListResponse(BaseModel):
    items: list[ProductAttributeResponse]
    pagination: dict


