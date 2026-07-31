# noqa: D100
"""Schema models برای CRM (فرایندها، مراحل، سرنخ، فرصت، فعالیت)"""
from __future__ import annotations

from typing import Optional, List, Dict
from datetime import datetime, date
from decimal import Decimal
from pydantic import BaseModel, Field, model_validator


# --- فرایند و مراحل ---


class CrmProcessStageCreate(BaseModel):
    """ایجاد مرحله"""
    stage_code: str = Field(..., min_length=1, max_length=50)
    name: str = Field(..., min_length=1, max_length=255)
    order_index: int = Field(default=0, ge=0)
    color: Optional[str] = Field(None, max_length=20)
    is_win: bool = False
    is_lost: bool = False
    allow_transition_to: Optional[List[str]] = Field(None, description="لیست stage_codeهای مجاز برای انتقال")


class CrmProcessStageUpdate(BaseModel):
    """به‌روزرسانی مرحله"""
    stage_code: Optional[str] = Field(None, min_length=1, max_length=50)
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    order_index: Optional[int] = Field(None, ge=0)
    color: Optional[str] = None
    is_win: Optional[bool] = None
    is_lost: Optional[bool] = None
    allow_transition_to: Optional[List[str]] = None


class CrmProcessStageResponse(BaseModel):
    """پاسخ مرحله"""
    id: int
    process_definition_id: int
    stage_code: str
    name: str
    order_index: int
    color: Optional[str] = None
    is_win: bool
    is_lost: bool
    allow_transition_to: Optional[dict] = None
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


class CrmProcessDefinitionCreate(BaseModel):
    """ایجاد فرایند"""
    process_type: str = Field(
        ...,
        description="lead_funnel | sales_pipeline | activity_type | lead_source",
        min_length=1,
        max_length=50,
    )
    code: str = Field(..., min_length=1, max_length=50)
    name: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    is_default: bool = False
    is_active: bool = True
    stages: Optional[List[CrmProcessStageCreate]] = Field(default_factory=list)


class CrmProcessDefinitionUpdate(BaseModel):
    """به‌روزرسانی فرایند"""
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    is_default: Optional[bool] = None
    is_active: Optional[bool] = None


class CrmProcessDefinitionResponse(BaseModel):
    """پاسخ فرایند"""
    id: int
    business_id: int
    process_type: str
    code: str
    name: str
    description: Optional[str] = None
    is_default: bool
    is_active: bool
    created_at: str
    updated_at: str
    created_by_user_id: Optional[int] = None
    stages: Optional[List[CrmProcessStageResponse]] = None

    class Config:
        from_attributes = True


# --- سرنخ (Lead) ---


class LeadCreate(BaseModel):
    """ایجاد سرنخ"""
    process_definition_id: int = Field(..., gt=0)
    stage_id: int = Field(..., gt=0)
    code: Optional[str] = Field(None, max_length=50, description="کد دستی؛ در صورت خالی بودن، کد خودکار تولید می‌شود")
    source_code: Optional[str] = Field(None, max_length=50)
    name: str = Field(..., min_length=1, max_length=255)
    company_name: Optional[str] = Field(None, max_length=255)
    mobile: Optional[str] = Field(None, max_length=20)
    email: Optional[str] = Field(None, max_length=255)
    description: Optional[str] = None
    assigned_to_user_id: Optional[int] = None
    next_follow_up_at: Optional[datetime] = None
    extra_info: Optional[dict] = None
    custom_fields: Optional[Dict[str, object]] = Field(None, description="مقادیر فیلدهای سفارشی")
    tag_ids: Optional[List[int]] = Field(None, description="شناسه برچسب‌ها")


class LeadUpdate(BaseModel):
    """به‌روزرسانی سرنخ"""
    stage_id: Optional[int] = Field(None, gt=0)
    code: Optional[str] = Field(None, max_length=50)
    source_code: Optional[str] = None
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    company_name: Optional[str] = None
    mobile: Optional[str] = None
    email: Optional[str] = None
    description: Optional[str] = None
    assigned_to_user_id: Optional[int] = None
    next_follow_up_at: Optional[datetime] = None
    extra_info: Optional[dict] = None
    custom_fields: Optional[Dict[str, object]] = None
    tag_ids: Optional[List[int]] = None


class LeadConvertDealOption(BaseModel):
    """اختیاری: ایجاد فرصت فروش همزمان با تبدیل سرنخ"""
    process_definition_id: int = Field(..., gt=0)
    stage_id: int = Field(..., gt=0)
    title: str = Field(..., min_length=1, max_length=255)
    amount: Decimal = Field(..., ge=0)
    currency_id: Optional[int] = None
    probability_percent: Optional[int] = Field(None, ge=0, le=100)
    expected_close_date: Optional[date] = None
    assigned_to_user_id: Optional[int] = None
    description: Optional[str] = None


class LeadConvertRequest(BaseModel):
    """درخواست تبدیل سرنخ به مشتری (با امکان ایجاد فرصت فروش)"""
    create_deal: Optional[LeadConvertDealOption] = Field(None, description="در صورت ارسال، همزمان یک فرصت فروش برای مشتری جدید ایجاد می‌شود")


class LeadResponse(BaseModel):
    """پاسخ سرنخ"""
    id: int
    business_id: int
    code: Optional[str] = None
    process_definition_id: int
    stage_id: int
    stage_name: Optional[str] = None
    source_code: Optional[str] = None
    name: str
    company_name: Optional[str] = None
    mobile: Optional[str] = None
    email: Optional[str] = None
    description: Optional[str] = None
    assigned_to_user_id: Optional[int] = None
    assigned_to_name: Optional[str] = None
    next_follow_up_at: Optional[str] = None
    person_id: Optional[int] = None
    person_name: Optional[str] = None
    converted_at: Optional[str] = None
    score: Optional[int] = None
    sla_due_at: Optional[str] = None
    first_touched_at: Optional[str] = None
    last_activity_at: Optional[str] = None
    tags: Optional[List[dict]] = None
    created_at: str
    updated_at: str
    created_by_user_id: int
    created_by_name: Optional[str] = None

    class Config:
        from_attributes = True


# --- فرصت فروش (Deal) ---


class DealCreate(BaseModel):
    """ایجاد فرصت فروش"""
    person_id: int = Field(..., gt=0)
    code: Optional[str] = Field(None, max_length=50, description="کد دستی؛ در صورت خالی بودن، کد خودکار تولید می‌شود")
    process_definition_id: int = Field(..., gt=0)
    stage_id: int = Field(..., gt=0)
    title: str = Field(..., min_length=1, max_length=255)
    amount: Decimal = Field(..., ge=0)
    currency_id: Optional[int] = None
    probability_percent: Optional[int] = Field(None, ge=0, le=100)
    expected_close_date: Optional[date] = None
    next_follow_up_at: Optional[datetime] = None
    assigned_to_user_id: Optional[int] = None
    description: Optional[str] = None
    extra_info: Optional[dict] = None
    custom_fields: Optional[Dict[str, object]] = None
    tag_ids: Optional[List[int]] = None


class DealUpdate(BaseModel):
    """به‌روزرسانی فرصت فروش"""
    stage_id: Optional[int] = Field(None, gt=0)
    code: Optional[str] = Field(None, max_length=50)
    title: Optional[str] = Field(None, min_length=1, max_length=255)
    amount: Optional[Decimal] = Field(None, ge=0)
    currency_id: Optional[int] = None
    probability_percent: Optional[int] = Field(None, ge=0, le=100)
    expected_close_date: Optional[date] = None
    next_follow_up_at: Optional[datetime] = None
    document_id: Optional[int] = None
    assigned_to_user_id: Optional[int] = None
    description: Optional[str] = None
    extra_info: Optional[dict] = None
    closed_at: Optional[datetime] = None
    won_reason_code: Optional[str] = Field(None, max_length=50)
    lost_reason_code: Optional[str] = Field(None, max_length=50)
    competitor_name: Optional[str] = Field(None, max_length=255)
    custom_fields: Optional[Dict[str, object]] = None
    tag_ids: Optional[List[int]] = None


class DealResponse(BaseModel):
    """پاسخ فرصت فروش"""
    id: int
    business_id: int
    code: Optional[str] = None
    person_id: int
    person_name: Optional[str] = None
    process_definition_id: int
    stage_id: int
    stage_name: Optional[str] = None
    title: str
    amount: Decimal
    currency_id: Optional[int] = None
    probability_percent: Optional[int] = None
    expected_close_date: Optional[str] = None
    next_follow_up_at: Optional[str] = None
    closed_at: Optional[str] = None
    document_id: Optional[int] = None
    assigned_to_user_id: Optional[int] = None
    assigned_to_name: Optional[str] = None
    won_reason_code: Optional[str] = None
    lost_reason_code: Optional[str] = None
    competitor_name: Optional[str] = None
    stage_entered_at: Optional[str] = None
    tags: Optional[List[dict]] = None
    created_at: str
    updated_at: str
    created_by_user_id: int
    created_by_name: Optional[str] = None

    class Config:
        from_attributes = True


# --- فعالیت (Activity) ---


class CrmActivityCreate(BaseModel):
    """ایجاد فعالیت"""
    person_id: Optional[int] = Field(None, gt=0, description="مشتری؛ برای سرنخ تبدیل‌نشده می‌توان خالی گذاشت")
    lead_id: Optional[int] = Field(None, gt=0, description="سرنخ؛ حداقل یکی از person_id یا lead_id لازم است")
    code: Optional[str] = Field(None, max_length=50, description="کد دستی؛ در صورت خالی بودن، کد خودکار تولید می‌شود")
    activity_type: str = Field(..., description="call | email | meeting | note", max_length=50)
    subject: Optional[str] = Field(None, max_length=255)
    description: Optional[str] = None
    activity_date: datetime
    deal_id: Optional[int] = None
    extra_info: Optional[dict] = None
    # --- وظیفه/پیگیری ---
    is_task: bool = False
    due_at: Optional[datetime] = None
    status: Optional[str] = Field(None, max_length=20, description="open | done | cancelled")
    assigned_to_user_id: Optional[int] = None
    outcome: Optional[str] = Field(None, max_length=100)
    priority: Optional[str] = Field(None, max_length=20, description="low | normal | high | urgent")
    custom_fields: Optional[Dict[str, object]] = None

    @model_validator(mode="after")
    def require_person_or_lead(self) -> "CrmActivityCreate":
        if not self.person_id and not self.lead_id:
            raise ValueError("یکی از person_id یا lead_id الزامی است")
        return self


class CrmActivityUpdate(BaseModel):
    """به‌روزرسانی فعالیت"""
    code: Optional[str] = Field(None, max_length=50)
    activity_type: Optional[str] = Field(None, max_length=50)
    subject: Optional[str] = None
    description: Optional[str] = None
    activity_date: Optional[datetime] = None
    deal_id: Optional[int] = None
    extra_info: Optional[dict] = None
    is_task: Optional[bool] = None
    due_at: Optional[datetime] = None
    status: Optional[str] = Field(None, max_length=20)
    assigned_to_user_id: Optional[int] = None
    outcome: Optional[str] = Field(None, max_length=100)
    priority: Optional[str] = Field(None, max_length=20)
    custom_fields: Optional[Dict[str, object]] = None


class CrmActivityResponse(BaseModel):
    """پاسخ فعالیت"""
    id: int
    business_id: int
    code: Optional[str] = None
    person_id: Optional[int] = None
    person_name: Optional[str] = None
    lead_id: Optional[int] = None
    lead_name: Optional[str] = None
    activity_type: str
    subject: Optional[str] = None
    description: Optional[str] = None
    activity_date: str
    deal_id: Optional[int] = None
    is_task: Optional[bool] = None
    due_at: Optional[str] = None
    status: Optional[str] = None
    completed_at: Optional[str] = None
    assigned_to_user_id: Optional[int] = None
    assigned_to_name: Optional[str] = None
    outcome: Optional[str] = None
    priority: Optional[str] = None
    created_by_user_id: int
    created_by_name: Optional[str] = None
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


# --- یادداشت و تقویم CRM ---


class CrmNoteTypeCreate(BaseModel):
    code: str = Field(..., min_length=1, max_length=50)
    title_i18n: Dict[str, str] = Field(..., description="کلید زبان (fa, en) به متن نمایش")
    scheduling_mode: str = Field(default="day_only", max_length=20, description="day_only | meeting")
    allow_comments: bool = True
    sort_order: int = Field(default=0, ge=0)


class CrmNoteTypeUpdate(BaseModel):
    title_i18n: Optional[Dict[str, str]] = None
    scheduling_mode: Optional[str] = Field(None, max_length=20)
    allow_comments: Optional[bool] = None
    is_active: Optional[bool] = None
    sort_order: Optional[int] = Field(None, ge=0)


class CrmNoteCreate(BaseModel):
    note_type_id: int = Field(..., gt=0)
    visibility: str = Field(..., max_length=20, description="private | business_public | shared")
    title: Optional[str] = Field(None, max_length=255)
    body: str = Field(..., min_length=1)
    occurs_on: Optional[date] = Field(None, description="برای day_only؛ برای meeting از starts_at پر می‌شود")
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    lead_id: Optional[int] = Field(None, gt=0)
    shared_user_ids: Optional[List[int]] = Field(
        default=None,
        description="برای visibility=shared: شناسه کاربران عضو کسب‌وکار (غیر از سازنده)",
    )


class CrmNoteUpdate(BaseModel):
    note_type_id: Optional[int] = Field(None, gt=0)
    visibility: Optional[str] = Field(None, max_length=20)
    title: Optional[str] = Field(None, max_length=255)
    body: Optional[str] = Field(None, min_length=1)
    occurs_on: Optional[date] = None
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    lead_id: Optional[int] = None
    clear_lead: bool = False
    status: Optional[str] = Field(None, max_length=20)
    shared_user_ids: Optional[List[int]] = None


class CrmNoteCommentCreate(BaseModel):
    body: str = Field(..., min_length=1)


# --- برچسب‌ها (Tags) ---


class CrmTagCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    color: Optional[str] = Field(None, max_length=20)
    sort_order: int = Field(default=0, ge=0)


class CrmTagUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=120)
    color: Optional[str] = Field(None, max_length=20)
    is_active: Optional[bool] = None
    sort_order: Optional[int] = Field(None, ge=0)


class CrmSetTagsRequest(BaseModel):
    tag_ids: List[int] = Field(default_factory=list)


# --- دلایل بستن معامله ---


class CrmCloseReasonCreate(BaseModel):
    reason_type: str = Field(..., description="won | lost", max_length=20)
    code: str = Field(..., min_length=1, max_length=50)
    name: str = Field(..., min_length=1, max_length=255)
    sort_order: int = Field(default=0, ge=0)


class CrmCloseReasonUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    is_active: Optional[bool] = None
    sort_order: Optional[int] = Field(None, ge=0)


# --- فیلدهای سفارشی ---


class CrmCustomFieldCreate(BaseModel):
    entity_type: str = Field(..., description="lead | deal | activity", max_length=20)
    field_key: str = Field(..., min_length=1, max_length=80)
    label: str = Field(..., min_length=1, max_length=255)
    field_type: str = Field(..., description="text | number | date | select | boolean", max_length=20)
    options: Optional[List[str]] = Field(None, description="گزینه‌ها برای نوع select")
    is_required: bool = False
    sort_order: int = Field(default=0, ge=0)


class CrmCustomFieldUpdate(BaseModel):
    label: Optional[str] = Field(None, min_length=1, max_length=255)
    options: Optional[List[str]] = None
    is_required: Optional[bool] = None
    sort_order: Optional[int] = Field(None, ge=0)
    is_active: Optional[bool] = None


# --- خطوط فرصت فروش ---


class CrmDealLineInput(BaseModel):
    product_id: Optional[int] = Field(None, gt=0)
    description: Optional[str] = Field(None, max_length=500)
    quantity: Decimal = Field(..., gt=0)
    unit_price: Decimal = Field(default=Decimal(0), ge=0)
    discount_percent: Decimal = Field(default=Decimal(0), ge=0, le=100)
    sort_order: int = Field(default=0, ge=0)


class CrmDealLinesReplaceRequest(BaseModel):
    lines: List[CrmDealLineInput] = Field(default_factory=list)


# --- توالی‌های خودکار ---


class CrmSequenceStepInput(BaseModel):
    step_order: int = Field(..., ge=0)
    delay_hours: int = Field(default=0, ge=0)
    action_type: str = Field(
        ...,
        description="create_task | send_sms | notify_assignee | update_lead_stage | update_deal_stage",
        max_length=50,
    )
    action_config: Optional[dict] = None


class CrmSequenceCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    is_active: bool = True
    steps: Optional[List[CrmSequenceStepInput]] = Field(default_factory=list)


class CrmSequenceUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    is_active: Optional[bool] = None
    steps: Optional[List[CrmSequenceStepInput]] = None


class CrmSequenceEnrollRequest(BaseModel):
    entity_type: str = Field(..., description="lead | deal", max_length=20)
    entity_id: int = Field(..., gt=0)


# --- تبدیل فرصت فروش به فاکتور ---


class CrmDealConvertToInvoiceRequest(BaseModel):
    is_proforma: bool = Field(default=True, description="پیش‌فاکتور یا فاکتور نهایی")
    close_as_won: bool = Field(default=False, description="بستن معامله به‌عنوان برد پس از ایجاد فاکتور")
    won_reason_code: Optional[str] = Field(None, max_length=50)
    warehouse_id: Optional[int] = Field(None, description="انبار برای خطوط دارای کالا (اختیاری)")


# --- تنظیمات اتوماسیون CRM ---


class CrmAutomationSettingsUpdate(BaseModel):
    lead_sla_hours: Optional[int] = Field(None, ge=0)
    auto_assign_enabled: Optional[bool] = None
    auto_assign_user_ids: Optional[List[int]] = None
    follow_up_notify_enabled: Optional[bool] = None
    stale_deal_days: Optional[int] = Field(None, ge=0)
    score_rules: Optional[dict] = None
