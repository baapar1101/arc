from __future__ import annotations

from typing import Optional, Literal
from pydantic import BaseModel, Field, field_validator


class CheckCreateRequest(BaseModel):
    type: Literal['received', 'transferred']
    person_id: Optional[int] = Field(default=None, ge=1)
    issue_date: str
    due_date: str
    check_number: str = Field(..., min_length=1, max_length=50)
    sayad_code: Optional[str] = Field(default=None, min_length=16, max_length=16)
    bank_name: Optional[str] = Field(default=None, max_length=255)
    branch_name: Optional[str] = Field(default=None, max_length=255)
    amount: float = Field(..., gt=0)
    currency_id: int = Field(..., ge=1)
    # گزینه‌های حسابداری
    auto_post: Optional[bool] = Field(default=False)
    document_date: Optional[str] = None
    document_description: Optional[str] = Field(default=None, max_length=500)

    @field_validator('sayad_code')
    @classmethod
    def validate_sayad(cls, v: Optional[str]):
        if v is None:
            return v
        if not v.isdigit():
            raise ValueError('شناسه صیاد باید فقط عددی باشد')
        return v


class CheckUpdateRequest(BaseModel):
    type: Optional[Literal['received', 'transferred']] = None
    person_id: Optional[int] = Field(default=None, ge=1)
    issue_date: Optional[str] = None
    due_date: Optional[str] = None
    check_number: Optional[str] = Field(default=None, min_length=1, max_length=50)
    sayad_code: Optional[str] = Field(default=None, min_length=16, max_length=16)
    bank_name: Optional[str] = Field(default=None, max_length=255)
    branch_name: Optional[str] = Field(default=None, max_length=255)
    amount: Optional[float] = Field(default=None, gt=0)
    currency_id: Optional[int] = Field(default=None, ge=1)

    @field_validator('sayad_code')
    @classmethod
    def validate_sayad(cls, v: Optional[str]):
        if v is None:
            return v
        if not v.isdigit():
            raise ValueError('شناسه صیاد باید فقط عددی باشد')
        return v


class CheckResponse(BaseModel):
    id: int
    business_id: int
    type: str
    person_id: Optional[int]
    person_name: Optional[str]
    issue_date: str
    due_date: str
    check_number: str
    sayad_code: Optional[str]
    bank_name: Optional[str]
    branch_name: Optional[str]
    amount: float
    currency_id: int
    currency: Optional[str]
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True



# =====================
# Action Schemas
# =====================

class CheckEndorseRequest(BaseModel):
    target_person_id: int = Field(..., ge=1)
    document_date: Optional[str] = None
    description: Optional[str] = Field(default=None, max_length=500)
    auto_post: bool = Field(default=True)


class CheckClearRequest(BaseModel):
    bank_account_id: int = Field(..., ge=1)
    document_date: Optional[str] = None
    description: Optional[str] = Field(default=None, max_length=500)
    auto_post: bool = Field(default=True)


class CheckReturnRequest(BaseModel):
    target_person_id: Optional[int] = Field(default=None, ge=1)
    document_date: Optional[str] = None
    description: Optional[str] = Field(default=None, max_length=500)
    auto_post: bool = Field(default=True)


class CheckBounceRequest(BaseModel):
    bank_account_id: Optional[int] = Field(default=None, ge=1)
    expense_account_id: Optional[int] = Field(default=None, ge=1)
    expense_amount: Optional[float] = Field(default=None, gt=0)
    document_date: Optional[str] = None
    description: Optional[str] = Field(default=None, max_length=500)
    auto_post: bool = Field(default=True)


class CheckPayRequest(BaseModel):
    bank_account_id: int = Field(..., ge=1)
    document_date: Optional[str] = None
    description: Optional[str] = Field(default=None, max_length=500)
    auto_post: bool = Field(default=True)


class CheckDepositRequest(BaseModel):
    bank_account_id: int = Field(..., ge=1)
    document_date: Optional[str] = None
    description: Optional[str] = Field(default=None, max_length=500)
    auto_post: bool = Field(default=True)

