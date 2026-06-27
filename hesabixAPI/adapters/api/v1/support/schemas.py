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
    attachments: Optional[List["AttachmentResponse"]] = None

    class Config:
        from_attributes = True


class AttachmentResponse(BaseModel):
    id: int
    ticket_id: int
    message_id: Optional[int] = None
    file_storage_id: str
    original_name: str
    mime_type: Optional[str] = None
    size_bytes: int
    uploaded_by: int
    created_at: datetime

    class Config:
        from_attributes = True


class ResponseTemplateResponse(BaseModel):
    id: int
    name: str
    content: str
    category_id: Optional[int] = None
    is_global: bool = True
    created_by: int
    is_active: bool = True
    usage_count: int = 0
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ResponseTemplateCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    content: str = Field(..., min_length=1)
    category_id: Optional[int] = None
    is_global: bool = True


class ResponseTemplateUpdateRequest(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    content: Optional[str] = Field(None, min_length=1)
    category_id: Optional[int] = None
    is_global: Optional[bool] = None
    is_active: Optional[bool] = None


class TicketResponse(TicketBase):
    id: int
    user_id: int
    status_id: int
    assigned_operator_id: Optional[int] = None
    is_internal: bool = False
    closed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime
    first_response_due_at: Optional[datetime] = None
    resolution_due_at: Optional[datetime] = None
    first_responded_at: Optional[datetime] = None
    sla_breached: bool = False
    
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


class CreateMessageRequest(BaseModel):
    content: str = ""
    is_internal: bool = False
    attachment_ids: List[int] = Field(default_factory=list)


class UpdateStatusRequest(BaseModel):
    status_id: int
    assigned_operator_id: Optional[int] = None


class AssignTicketRequest(BaseModel):
    operator_id: int


class UpdatePriorityRequest(BaseModel):
    priority_id: int


class BulkAssignRequest(BaseModel):
    ticket_ids: List[int] = Field(..., min_items=1, description="لیست شناسه تیکت‌ها")
    operator_id: int = Field(..., description="شناسه اپراتور")


class BulkUpdateStatusRequest(BaseModel):
    ticket_ids: List[int] = Field(..., min_items=1, description="لیست شناسه تیکت‌ها")
    status_id: int = Field(..., description="شناسه وضعیت جدید")
    assigned_operator_id: Optional[int] = Field(None, description="شناسه اپراتور (اختیاری)")


class SubmitCsatRequest(BaseModel):
    rating: int = Field(..., ge=1, le=5, description="امتیاز ۱ تا ۵")
    comment: Optional[str] = Field(None, max_length=2000)


# PaginatedResponse is now imported from adapters.api.v1.schemas
