from __future__ import annotations

from typing import List, Optional
from pydantic import BaseModel, Field


class AccountTreeNode(BaseModel):
	id: int = Field(..., description="ID حساب")
	code: str = Field(..., description="کد حساب")
	name: str = Field(..., description="نام حساب")
	account_type: Optional[str] = Field(default=None, description="نوع حساب")
	parent_id: Optional[int] = Field(default=None, description="شناسه والد")
	level: Optional[int] = Field(default=None, description="سطح حساب در درخت")
	children: List["AccountTreeNode"] = Field(default_factory=list, description="فرزندان")

	class Config:
		from_attributes = True


class AccountCreateRequest(BaseModel):
	name: str = Field(..., min_length=1, max_length=255)
	code: str = Field(..., min_length=1, max_length=50)
	account_type: str = Field(..., min_length=1, max_length=50)
	parent_id: Optional[int] = Field(default=None)


class AccountUpdateRequest(BaseModel):
	name: Optional[str] = Field(default=None, min_length=1, max_length=255)
	code: Optional[str] = Field(default=None, min_length=1, max_length=50)
	account_type: Optional[str] = Field(default=None, min_length=1, max_length=50)
	parent_id: Optional[int] = Field(default=None)


