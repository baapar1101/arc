"""
Schema Models برای API نوتیفیکیشن کسب‌وکارها
"""
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, validator


class TemplateCreate(BaseModel):
    """ایجاد قالب جدید"""
    code: str = Field(..., max_length=100, description="کد یکتا قالب")
    name: str = Field(..., max_length=200, description="نام قالب")
    description: Optional[str] = None
    event_type: str = Field(..., description="نوع رویداد")
    channel: str = Field(..., description="کانال: sms یا email")
    recipient_type: str = Field(default="customer", description="نوع گیرنده")
    subject: Optional[str] = Field(None, max_length=200, description="موضوع (برای email)")
    body: str = Field(..., description="محتوای قالب")
    daily_limit: int = Field(default=100, ge=1, le=10000, description="حداکثر ارسال روزانه")
    is_automated: bool = Field(default=False, description="ارسال خودکار")
    
    @validator('channel')
    def validate_channel(cls, v):
        if v not in ['sms', 'email']:
            raise ValueError('کانال باید sms یا email باشد')
        return v
    
    @validator('recipient_type')
    def validate_recipient_type(cls, v):
        if v not in ['customer', 'supplier', 'employee']:
            raise ValueError('نوع گیرنده نامعتبر است')
        return v


class TemplateUpdate(BaseModel):
    """به‌روزرسانی قالب"""
    name: Optional[str] = Field(None, max_length=200)
    description: Optional[str] = None
    subject: Optional[str] = Field(None, max_length=200)
    body: Optional[str] = None
    daily_limit: Optional[int] = Field(None, ge=1, le=10000)
    is_automated: Optional[bool] = None
    is_active: Optional[bool] = None


class SendNotificationRequest(BaseModel):
    """درخواست ارسال نوتیفیکیشن"""
    person_id: int = Field(..., description="شناسه Person")
    event_type: str = Field(..., description="نوع رویداد")
    context: Dict[str, Any] = Field(..., description="داده‌های متغیرها")
    channel: Optional[str] = Field(None, description="کانال (None = همه)")
    
    @validator('channel')
    def validate_channel(cls, v):
        if v is not None and v not in ['sms', 'email']:
            raise ValueError('کانال باید sms یا email باشد')
        return v


class PreviewTemplateRequest(BaseModel):
    """درخواست پیش‌نمایش قالب"""
    sample_context: Dict[str, Any] = Field(..., description="Context نمونه")


class ApproveTemplateRequest(BaseModel):
    """درخواست تایید قالب (Admin)"""
    notes: Optional[str] = Field(None, description="یادداشت مدیر")


class RejectTemplateRequest(BaseModel):
    """درخواست رد قالب (Admin)"""
    reason: str = Field(..., description="دلیل رد")
    notes: Optional[str] = Field(None, description="یادداشت اضافی")


class TemplateResponse(BaseModel):
    """پاسخ قالب"""
    id: int
    code: str
    name: str
    description: Optional[str]
    event_type: str
    channel: str
    recipient_type: str
    subject: Optional[str]
    body: str
    available_variables: List[Dict[str, Any]]
    status: str
    is_active: bool
    approval_status: str
    approved_by_ai: bool
    ai_confidence_score: Optional[float]
    daily_limit: int
    is_automated: bool
    created_at: str
    updated_at: str


class EventTypeResponse(BaseModel):
    """پاسخ نوع رویداد"""
    id: int
    code: str
    name: str
    description: Optional[str]
    category: Optional[str]
    available_variables: List[Dict[str, Any]]
    default_sms_template: Optional[str]
    default_email_template: Optional[str]
    requires_approval: bool


