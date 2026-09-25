from __future__ import annotations

from typing import Optional, List
from pydantic import BaseModel, Field, field_validator


class CatalogSpecFieldCreateRequest(BaseModel):
	title: str = Field(..., min_length=1, max_length=255, description="عنوان فیلد مشخصات")
	description: Optional[str] = Field(default=None, description="توضیحات راهنما")
	data_type: Optional[str] = Field(default="text", description="text, number, date, select, boolean")
	options: Optional[List[str]] = Field(default=None, description="گزینه‌های select")
	sort_order: int = Field(default=0, ge=0)
	is_required: bool = Field(default=False)
	is_active: bool = Field(default=True)

	@field_validator("data_type")
	@classmethod
	def validate_data_type(cls, v: Optional[str]) -> str:
		if v is None:
			return "text"
		valid_types = ["text", "number", "date", "select", "boolean"]
		if v not in valid_types:
			raise ValueError(f"data_type باید یکی از {valid_types} باشد")
		return v

	@field_validator("options")
	@classmethod
	def validate_options(cls, v: Optional[List[str]], info) -> Optional[List[str]]:
		if v is not None and len(v) == 0:
			return None
		if info.data and info.data.get("data_type") == "select":
			if not v or len(v) == 0:
				raise ValueError("برای نوع select باید حداقل یک گزینه مشخص شود")
		return v


class CatalogSpecFieldUpdateRequest(BaseModel):
	title: Optional[str] = Field(default=None, min_length=1, max_length=255)
	description: Optional[str] = None
	data_type: Optional[str] = None
	options: Optional[List[str]] = None
	sort_order: Optional[int] = Field(default=None, ge=0)
	is_required: Optional[bool] = None
	is_active: Optional[bool] = None

	@field_validator("data_type")
	@classmethod
	def validate_data_type(cls, v: Optional[str]) -> Optional[str]:
		if v is None:
			return None
		valid_types = ["text", "number", "date", "select", "boolean"]
		if v not in valid_types:
			raise ValueError(f"data_type باید یکی از {valid_types} باشد")
		return v
