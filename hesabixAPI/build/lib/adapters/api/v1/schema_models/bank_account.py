from __future__ import annotations

from typing import Optional
from pydantic import BaseModel, Field


class BankAccountCreateRequest(BaseModel):
	code: Optional[str] = Field(default=None, max_length=50)
	name: str = Field(..., min_length=1, max_length=255)
	branch: Optional[str] = Field(default=None, max_length=255)
	account_number: Optional[str] = Field(default=None, max_length=50)
	sheba_number: Optional[str] = Field(default=None, max_length=30)
	card_number: Optional[str] = Field(default=None, max_length=20)
	owner_name: Optional[str] = Field(default=None, max_length=255)
	pos_number: Optional[str] = Field(default=None, max_length=50)
	payment_id: Optional[str] = Field(default=None, max_length=100)
	description: Optional[str] = Field(default=None, max_length=500)
	currency_id: int = Field(..., ge=1)
	is_active: bool = Field(default=True)
	is_default: bool = Field(default=False)

	@classmethod
	def __get_validators__(cls):
		yield from super().__get_validators__()

	@classmethod
	def validate(cls, value):  # type: ignore[override]
		obj = super().validate(value)
		if getattr(obj, 'code', None) is not None:
			code_val = str(getattr(obj, 'code'))
		if code_val.strip() != '':
			if not code_val.isdigit():
				raise ValueError("کد حساب باید فقط عددی باشد")
			if len(code_val) < 3:
				raise ValueError("کد حساب باید حداقل ۳ رقم باشد")
		return obj


class BankAccountUpdateRequest(BaseModel):
	code: Optional[str] = Field(default=None, max_length=50)
	name: Optional[str] = Field(default=None, min_length=1, max_length=255)
	branch: Optional[str] = Field(default=None, max_length=255)
	account_number: Optional[str] = Field(default=None, max_length=50)
	sheba_number: Optional[str] = Field(default=None, max_length=30)
	card_number: Optional[str] = Field(default=None, max_length=20)
	owner_name: Optional[str] = Field(default=None, max_length=255)
	pos_number: Optional[str] = Field(default=None, max_length=50)
	payment_id: Optional[str] = Field(default=None, max_length=100)
	description: Optional[str] = Field(default=None, max_length=500)
	currency_id: Optional[int] = Field(default=None, ge=1)
	is_active: Optional[bool] = Field(default=None)
	is_default: Optional[bool] = Field(default=None)

	@classmethod
	def __get_validators__(cls):
		yield from super().__get_validators__()

	@classmethod
	def validate(cls, value):  # type: ignore[override]
		obj = super().validate(value)
		if getattr(obj, 'code', None) is not None:
			code_val = str(getattr(obj, 'code'))
		if code_val.strip() != '':
			if not code_val.isdigit():
				raise ValueError("کد حساب باید فقط عددی باشد")
			if len(code_val) < 3:
				raise ValueError("کد حساب باید حداقل ۳ رقم باشد")
		return obj


class BankAccountResponse(BaseModel):
	id: int
	business_id: int
	code: Optional[str]
	name: str
	branch: Optional[str]
	account_number: Optional[str]
	sheba_number: Optional[str]
	card_number: Optional[str]
	owner_name: Optional[str]
	pos_number: Optional[str]
	payment_id: Optional[str]
	description: Optional[str]
	currency_id: int
	is_active: bool
	is_default: bool
	created_at: str
	updated_at: str

	class Config:
		from_attributes = True


