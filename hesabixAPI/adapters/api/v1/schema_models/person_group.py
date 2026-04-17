from __future__ import annotations

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field, field_validator, ConfigDict


ALLOWED_PROFILE_DEFAULT_KEYS = frozenset({
    "legal_entity_type",
    "person_types",
    "name_prefix",
    "company_name",
    "payment_id",
    "national_id",
    "registration_number",
    "economic_id",
    "country",
    "province",
    "city",
    "address",
    "postal_code",
    "phone",
    "mobile",
    "fax",
    "email",
    "website",
    "share_count",
    "commission_sale_percent",
    "commission_sales_return_percent",
    "commission_sales_amount",
    "commission_sales_return_amount",
    "commission_exclude_discounts",
    "commission_exclude_additions_deductions",
    "commission_post_in_invoice_document",
    "credit_limit",
    "credit_check_enabled",
})


def sanitize_profile_defaults(data: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    if not data:
        return {}
    out: Dict[str, Any] = {}
    for k, v in data.items():
        if k not in ALLOWED_PROFILE_DEFAULT_KEYS:
            continue
        out[k] = v
    return out


class PersonGroupSummary(BaseModel):
    id: int
    name: str
    code: Optional[int] = None

    model_config = ConfigDict(from_attributes=True)


class PersonGroupCreateRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    name: str = Field(..., min_length=1, max_length=255)
    code: Optional[int] = Field(default=None, ge=1)
    description: Optional[str] = None
    parent_id: Optional[int] = Field(default=None, description="برای آینده؛ فعلاً باید خالی باشد")
    profile_defaults: Dict[str, Any] = Field(default_factory=dict)
    sort_order: int = Field(default=0)
    is_active: bool = Field(default=True)

    @field_validator("profile_defaults", mode="before")
    @classmethod
    def _sanitize_pd(cls, v: Any) -> Dict[str, Any]:
        if v is None:
            return {}
        if not isinstance(v, dict):
            return {}
        return sanitize_profile_defaults(v)


class PersonGroupUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    name: Optional[str] = Field(default=None, min_length=1, max_length=255)
    code: Optional[int] = Field(default=None, ge=1)
    description: Optional[str] = None
    parent_id: Optional[int] = None
    profile_defaults: Optional[Dict[str, Any]] = None
    sort_order: Optional[int] = None
    is_active: Optional[bool] = None

    @field_validator("profile_defaults", mode="before")
    @classmethod
    def _sanitize_pd(cls, v: Any) -> Optional[Dict[str, Any]]:
        if v is None:
            return None
        if not isinstance(v, dict):
            return {}
        return sanitize_profile_defaults(v)


class PersonGroupResponse(BaseModel):
    id: int
    business_id: int
    parent_id: Optional[int] = None
    name: str
    code: Optional[int] = None
    description: Optional[str] = None
    profile_defaults: Dict[str, Any] = Field(default_factory=dict)
    sort_order: int = 0
    is_active: bool = True
    created_at: str
    updated_at: str

    model_config = ConfigDict(from_attributes=True)


class PersonGroupListResponse(BaseModel):
    items: List[PersonGroupResponse]
    pagination: dict
