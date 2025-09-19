from __future__ import annotations

from typing import Any
from pydantic import BaseModel, EmailStr, Field


class FilterItem(BaseModel):
	property: str = Field(..., description="نام فیلد مورد نظر برای اعمال فیلتر")
	operator: str = Field(..., description="نوع عملگر: =, >, >=, <, <=, !=, *, ?*, *?, in")
	value: Any = Field(..., description="مقدار مورد نظر")


class QueryInfo(BaseModel):
	sort_by: str | None = Field(default=None, description="نام فیلد مورد نظر برای مرتب سازی")
	sort_desc: bool = Field(default=False, description="false = مرتب سازی صعودی، true = مرتب سازی نزولی")
	take: int = Field(default=10, ge=1, le=1000, description="حداکثر تعداد رکورد بازگشتی")
	skip: int = Field(default=0, ge=0, description="تعداد رکوردی که از ابتدای لیست صرف نظر می شود")
	search: str | None = Field(default=None, description="عبارت جستجو")
	search_fields: list[str] | None = Field(default=None, description="آرایه ای از فیلدهایی که جستجو در آن انجام می گیرد")
	filters: list[FilterItem] | None = Field(default=None, description="آرایه ای از اشیا برای اعمال فیلتر بر روی لیست")


class CaptchaSolve(BaseModel):
	captcha_id: str = Field(..., min_length=8)
	captcha_code: str = Field(..., min_length=3, max_length=8)


class RegisterRequest(CaptchaSolve):
	first_name: str | None = Field(default=None, max_length=100)
	last_name: str | None = Field(default=None, max_length=100)
	email: EmailStr | None = None
	mobile: str | None = Field(default=None, max_length=32)
	password: str = Field(..., min_length=8, max_length=128)
	device_id: str | None = Field(default=None, max_length=100)
	referrer_code: str | None = Field(default=None, min_length=4, max_length=32)


class LoginRequest(CaptchaSolve):
	identifier: str = Field(..., min_length=3, max_length=255)
	password: str = Field(..., min_length=8, max_length=128)
	device_id: str | None = Field(default=None, max_length=100)


class ForgotPasswordRequest(CaptchaSolve):
	identifier: str = Field(..., min_length=3, max_length=255)


class ResetPasswordRequest(CaptchaSolve):
	token: str = Field(..., min_length=16)
	new_password: str = Field(..., min_length=8, max_length=128)


class ChangePasswordRequest(BaseModel):
	current_password: str = Field(..., min_length=8, max_length=128)
	new_password: str = Field(..., min_length=8, max_length=128)
	confirm_password: str = Field(..., min_length=8, max_length=128)


class CreateApiKeyRequest(BaseModel):
	name: str | None = Field(default=None, max_length=100)
	scopes: str | None = Field(default=None, max_length=500)
	expires_at: str | None = None  # ISO string; parse server-side if provided


