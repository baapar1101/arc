from pydantic import BaseModel, EmailStr, Field
from typing import Optional
from datetime import datetime


class EmailConfigBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=100, description="Configuration name")
    smtp_host: str = Field(..., min_length=1, max_length=255, description="SMTP host")
    smtp_port: int = Field(..., ge=1, le=65535, description="SMTP port")
    smtp_username: str = Field(..., min_length=1, max_length=255, description="SMTP username")
    smtp_password: str = Field(..., min_length=1, max_length=255, description="SMTP password")
    use_tls: bool = Field(default=True, description="Use TLS encryption")
    use_ssl: bool = Field(default=False, description="Use SSL encryption")
    from_email: EmailStr = Field(..., description="From email address")
    from_name: str = Field(..., min_length=1, max_length=100, description="From name")
    is_active: bool = Field(default=True, description="Is this configuration active")
    is_default: bool = Field(default=False, description="Is this the default configuration")


class EmailConfigCreate(EmailConfigBase):
    pass


class EmailConfigUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    smtp_host: Optional[str] = Field(None, min_length=1, max_length=255)
    smtp_port: Optional[int] = Field(None, ge=1, le=65535)
    smtp_username: Optional[str] = Field(None, min_length=1, max_length=255)
    smtp_password: Optional[str] = Field(None, min_length=1, max_length=255)
    use_tls: Optional[bool] = None
    use_ssl: Optional[bool] = None
    from_email: Optional[EmailStr] = None
    from_name: Optional[str] = Field(None, min_length=1, max_length=100)
    is_active: Optional[bool] = None
    is_default: Optional[bool] = None


class EmailConfigResponse(EmailConfigBase):
    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class SendEmailRequest(BaseModel):
    to: EmailStr = Field(..., description="Recipient email address")
    subject: str = Field(..., min_length=1, max_length=255, description="Email subject")
    body: str = Field(..., min_length=1, description="Email body (plain text)")
    html_body: Optional[str] = Field(None, description="Email body (HTML)")
    config_id: Optional[int] = Field(None, description="Specific config ID to use")


class TestConnectionRequest(BaseModel):
    config_id: int = Field(..., description="Configuration ID to test")


# These response models are no longer needed as we use SuccessResponse from schemas.py
