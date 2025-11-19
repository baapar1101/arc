from __future__ import annotations

from typing import Optional, Literal, List
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
    # گزینه‌های حسابداری (ثبت سند همیشه انجام می‌شود)
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


class CheckClearRequest(BaseModel):
    bank_account_id: int = Field(..., ge=1)
    document_date: Optional[str] = None
    description: Optional[str] = Field(default=None, max_length=500)


class CheckReturnRequest(BaseModel):
    target_person_id: Optional[int] = Field(default=None, ge=1)
    document_date: Optional[str] = None
    description: Optional[str] = Field(default=None, max_length=500)


class CheckBounceRequest(BaseModel):
    bank_account_id: Optional[int] = Field(default=None, ge=1)
    expense_account_id: Optional[int] = Field(default=None, ge=1)
    expense_amount: Optional[float] = Field(default=None, gt=0)
    document_date: Optional[str] = None
    description: Optional[str] = Field(default=None, max_length=500)


class CheckPayRequest(BaseModel):
    bank_account_id: int = Field(..., ge=1)
    document_date: Optional[str] = None
    description: Optional[str] = Field(default=None, max_length=500)


class CheckDepositRequest(BaseModel):
    # bank_account_id در schema اجباری است اما در منطق استفاده نمی‌شود
    # برای سازگاری با schema، آن را اختیاری می‌کنیم
    bank_account_id: Optional[int] = Field(default=None, ge=1)
    document_date: Optional[str] = None
    description: Optional[str] = Field(default=None, max_length=500)


# =====================
# Reconciliation Schemas
# =====================

class CheckReconciliationCalculateRequest(BaseModel):
    check_ids: List[int] = Field(..., min_items=2)
    base_date: str
    currency_id: Optional[int] = Field(default=None, ge=1)


class CheckReconciliationCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    check_ids: List[int] = Field(..., min_items=2)
    base_date: str
    description: Optional[str] = Field(default=None, max_length=1000)


class CheckReconciliationItemResponse(BaseModel):
    id: int
    check_id: int
    check_number: Optional[str]
    person_name: Optional[str]
    amount: float
    due_date: Optional[str]
    days_to_maturity: int
    weighted_value: float


class CheckReconciliationResponse(BaseModel):
    id: int
    business_id: int
    name: str
    base_date: str
    calculated_average_days: float
    calculated_date: str
    total_amount: float
    check_count: int
    currency_id: int
    currency: Optional[str]
    description: Optional[str]
    created_by_user_id: int
    created_at: str
    updated_at: str
    items: List[CheckReconciliationItemResponse]

