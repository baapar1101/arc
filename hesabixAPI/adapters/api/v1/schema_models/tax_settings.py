from __future__ import annotations

from typing import Optional, Literal

from pydantic import BaseModel, Field, field_validator, FieldValidationInfo


class TaxSettingsSaveRequest(BaseModel):
    tax_memory_id: str = Field(..., min_length=3, max_length=128, description="شناسه حافظه مالیاتی")
    economic_code: str = Field(..., min_length=3, max_length=64, description="کد اقتصادی کسب‌وکار")
    private_key: str = Field(..., description="کلید خصوصی (PEM)")
    public_key: Optional[str] = Field(default=None, description="کلید عمومی (اختیاری)")
    certificate: Optional[str] = Field(default=None, description="گواهی دیجیتال (اختیاری)")
    certificate_request: Optional[str] = Field(default=None, description="درخواست CSR ذخیره شده")
    sandbox_mode: bool = Field(default=False, description="فعال بودن حالت Sandbox")

    @field_validator("tax_memory_id", "economic_code", mode="before")
    @classmethod
    def _trim(cls, value: str) -> str:
        if isinstance(value, str):
            cleaned = value.strip()
            if not cleaned:
                raise ValueError("این مقدار نمی‌تواند خالی باشد")
            return cleaned
        raise ValueError("رشته معتبر وارد کنید")


class TaxSettingsResponse(BaseModel):
    business_id: int
    tax_memory_id: Optional[str]
    economic_code: Optional[str]
    private_key: Optional[str]
    public_key: Optional[str]
    certificate: Optional[str]
    certificate_request: Optional[str]
    sandbox_mode: bool
    has_private_key: bool
    updated_at: Optional[str]


class GenerateKeysRequest(BaseModel):
    person_type: Literal["natural", "legal"] = Field(default="natural", description="نوع شخصیت")
    national_id: str = Field(..., min_length=5, max_length=20, description="شناسه ملی")
    name_fa: Optional[str] = Field(default=None, description="نام فارسی (برای اشخاص حقوقی)")
    name_en: Optional[str] = Field(default=None, description="نام انگلیسی (برای اشخاص حقوقی)")
    email: Optional[str] = Field(default=None, description="ایمیل (برای اشخاص حقوقی)")

    @field_validator("national_id", mode="before")
    @classmethod
    def _clean_national_id(cls, value: str) -> str:
        if isinstance(value, str):
            cleaned = value.strip()
            if not cleaned:
                raise ValueError("شناسه ملی الزامی است")
            return cleaned
        raise ValueError("شناسه ملی نامعتبر است")

    @field_validator("name_fa", "name_en", "email", mode="after")
    @classmethod
    def _validate_legal_fields(cls, value: Optional[str], info: FieldValidationInfo):
        person_type = info.data.get("person_type")
        if person_type == "legal" and not value:
            label = info.field_name or "field"
            raise ValueError(f"{label} برای اشخاص حقوقی الزامی است")
        return value


class GenerateKeysResponse(BaseModel):
    private_key: str
    public_key: str
    csr: Optional[str] = None


GenerateKeysRequest.model_rebuild()

