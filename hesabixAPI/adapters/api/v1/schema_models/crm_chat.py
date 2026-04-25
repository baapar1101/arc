# noqa: D100
from __future__ import annotations

from typing import Any, List, Optional

from pydantic import BaseModel, Field, field_validator, model_validator


class CrmChatWidgetCreate(BaseModel):
	name: str = Field(..., min_length=1, max_length=255)
	allowed_origins: Optional[List[str]] = None
	settings: Optional[dict[str, Any]] = None
	is_active: bool = True


class CrmChatWidgetUpdate(BaseModel):
	name: Optional[str] = Field(None, min_length=1, max_length=255)
	allowed_origins: Optional[List[str]] = None
	settings: Optional[dict[str, Any]] = None
	is_active: Optional[bool] = None


class CrmChatConversationStartPublic(BaseModel):
	public_key: str = Field(..., min_length=8, max_length=64)
	first_name: str = Field(..., min_length=1, max_length=120)
	last_name: str = Field(..., min_length=1, max_length=120)
	email: str = Field(..., min_length=3, max_length=255)
	phone: str = Field(..., min_length=5, max_length=64)
	page_url: Optional[str] = Field(None, max_length=2048)

	@field_validator("email")
	@classmethod
	def email_strip(cls, v: str) -> str:
		return (v or "").strip().lower()


class CrmChatVisitorMessageCreate(BaseModel):
	visitor_token: str = Field(..., min_length=16)
	conversation_id: int = Field(..., gt=0)
	body: str = Field(..., min_length=1, max_length=8000)


class CrmChatAgentMessageCreate(BaseModel):
	body: Optional[str] = Field(None, max_length=8000)
	file_storage_id: Optional[str] = Field(
		None,
		max_length=36,
		description="پس از آپلود در فضای کسب‌وکار با module crm_web_chat",
	)

	@model_validator(mode="after")
	def body_or_file(self) -> "CrmChatAgentMessageCreate":
		b = (self.body or "").strip()
		f = (self.file_storage_id or "").strip() or None
		if not b and not f:
			raise ValueError("متن پیام یا فایل (file_storage_id) الزامی است")
		return self


class CrmChatConversationPatch(BaseModel):
	status: Optional[str] = Field(None, description="open | pending | resolved")
	assigned_to_user_id: Optional[int] = Field(None, ge=1)
	lead_id: Optional[int] = Field(None, ge=1)
	person_id: Optional[int] = Field(None, ge=1)


class BusinessCrmSettingsUpdate(BaseModel):
	allow_web_chat_file_upload: bool = Field(..., description="ارسال فایل توسط بازدیدکننده در چت وب")
