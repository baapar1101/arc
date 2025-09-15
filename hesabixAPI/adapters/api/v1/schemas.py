from __future__ import annotations

from pydantic import BaseModel, EmailStr, Field


class CaptchaSolve(BaseModel):
	captcha_id: str = Field(..., min_length=8)
	captcha_code: str = Field(..., min_length=3, max_length=8)


class RegisterRequest(CaptchaSolve):
	first_name: str | None = Field(default=None, max_length=100)
	last_name: str | None = Field(default=None, max_length=100)
	email: EmailStr | None = None
	mobile: str | None = Field(default=None, max_length=32)
	password: str = Field(..., min_length=8, max_length=128)


class LoginRequest(CaptchaSolve):
	identifier: str = Field(..., min_length=3, max_length=255)
	password: str = Field(..., min_length=8, max_length=128)
	device_id: str | None = Field(default=None, max_length=100)


class ForgotPasswordRequest(CaptchaSolve):
	identifier: str = Field(..., min_length=3, max_length=255)


class ResetPasswordRequest(CaptchaSolve):
	token: str = Field(..., min_length=16)
	new_password: str = Field(..., min_length=8, max_length=128)


class CreateApiKeyRequest(BaseModel):
	name: str | None = Field(default=None, max_length=100)
	scopes: str | None = Field(default=None, max_length=500)
	expires_at: str | None = None  # ISO string; parse server-side if provided


