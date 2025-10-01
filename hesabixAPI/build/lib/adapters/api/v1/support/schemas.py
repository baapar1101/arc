# Removed __future__ annotations to fix OpenAPI schema generation

from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field

from adapters.db.models.support.message import SenderType
from adapters.api.v1.schemas import PaginatedResponse


# Base schemas
class CategoryBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = None
    is_active: bool = True


class PriorityBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=50)
    description: Optional[str] = None
    color: Optional[str] = Field(None, pattern=r'^#[0-9A-Fa-f]{6}$')
    order: int = 0


class StatusBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=50)
    description: Optional[str] = None
    color: Optional[str] = Field(None, pattern=r'^#[0-9A-Fa-f]{6}$')
    is_final: bool = False


class TicketBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    description: str = Field(..., min_length=1)
    category_id: int
    priority_id: int


class MessageBase(BaseModel):
    content: str = Field(..., min_length=1)
    is_internal: bool = False


# Response schemas
class CategoryResponse(CategoryBase):
    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class PriorityResponse(PriorityBase):
    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class StatusResponse(StatusBase):
    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class UserInfo(BaseModel):
    id: int
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    email: Optional[str] = None

    class Config:
        from_attributes = True


class MessageResponse(MessageBase):
    id: int
    ticket_id: int
    sender_id: int
    sender_type: SenderType
    sender: Optional[UserInfo] = None
    created_at: datetime

    class Config:
        from_attributes = True


class TicketResponse(TicketBase):
    id: int
    user_id: int
    status_id: int
    assigned_operator_id: Optional[int] = None
    is_internal: bool = False
    closed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime
    
    # Related objects
    user: Optional[UserInfo] = None
    assigned_operator: Optional[UserInfo] = None
    category: Optional[CategoryResponse] = None
    priority: Optional[PriorityResponse] = None
    status: Optional[StatusResponse] = None
    messages: Optional[List[MessageResponse]] = None

    class Config:
        from_attributes = True


# Request schemas
class CreateTicketRequest(TicketBase):
    pass


class CreateMessageRequest(MessageBase):
    pass


class UpdateStatusRequest(BaseModel):
    status_id: int
    assigned_operator_id: Optional[int] = None


class AssignTicketRequest(BaseModel):
    operator_id: int


# PaginatedResponse is now imported from adapters.api.v1.schemas
