from typing import List, Optional
from pydantic import BaseModel, Field, field_validator, model_validator, ConfigDict
from enum import Enum
from datetime import datetime


# پیشوندهای مجاز برای اشخاص (همسان با UI)
ALLOWED_PERSON_NAME_PREFIXES = frozenset({
    "آقای",
    "خانم",
    "شرکت",
    "دکتر",
    "مهندس",
    "موسسه",
    "اداره",
    "سازمان",
    "بنیاد",
    "انجمن",
})


class PersonType(str, Enum):
    """نوع شخص"""
    CUSTOMER = "مشتری"
    MARKETER = "بازاریاب"
    EMPLOYEE = "کارمند"
    SUPPLIER = "تامین‌کننده"
    PARTNER = "همکار"
    SELLER = "فروشنده"
    SHAREHOLDER = "سهامدار"


class PersonBankAccountCreateRequest(BaseModel):
    """درخواست ایجاد حساب بانکی شخص"""
    bank_name: str = Field(..., min_length=1, max_length=255, description="نام بانک")
    account_number: Optional[str] = Field(default=None, max_length=50, description="شماره حساب")
    card_number: Optional[str] = Field(default=None, max_length=20, description="شماره کارت")
    sheba_number: Optional[str] = Field(default=None, max_length=30, description="شماره شبا")


class PersonBankAccountUpdateRequest(BaseModel):
    """درخواست ویرایش حساب بانکی شخص"""
    bank_name: Optional[str] = Field(default=None, min_length=1, max_length=255, description="نام بانک")
    account_number: Optional[str] = Field(default=None, max_length=50, description="شماره حساب")
    card_number: Optional[str] = Field(default=None, max_length=20, description="شماره کارت")
    sheba_number: Optional[str] = Field(default=None, max_length=30, description="شماره شبا")


class PersonBankAccountResponse(BaseModel):
    """پاسخ اطلاعات حساب بانکی شخص"""
    id: int = Field(..., description="شناسه حساب بانکی")
    person_id: int = Field(..., description="شناسه شخص")
    bank_name: str = Field(..., description="نام بانک")
    account_number: Optional[str] = Field(default=None, description="شماره حساب")
    card_number: Optional[str] = Field(default=None, description="شماره کارت")
    sheba_number: Optional[str] = Field(default=None, description="شماره شبا")
    created_at: str = Field(..., description="تاریخ ایجاد")
    updated_at: str = Field(..., description="تاریخ آخرین بروزرسانی")

    class Config:
        from_attributes = True


class PersonSocialContactInput(BaseModel):
    """سطر ارتباط پیام‌رسان / شبکه اجتماعی (ورودی ایجاد/ویرایش)"""
    model_config = ConfigDict(extra="ignore")

    platform_key: str = Field(..., min_length=1, max_length=64, description="کلید پلتفرم (مثل telegram) یا other")
    custom_label: Optional[str] = Field(default=None, max_length=128, description="نام نمایش برای سایر/سفارشی")
    value: str = Field(..., min_length=1, max_length=2000, description="آیدی، لینک، شماره و …")

    @field_validator("platform_key", mode="before")
    @classmethod
    def _norm_platform_key(cls, v) -> str:
        if v is None:
            return ""
        s = str(v).strip().lower()
        return s

    @field_validator("custom_label", mode="before")
    @classmethod
    def _empty_custom_to_none(cls, v):
        if v is None:
            return None
        t = str(v).strip()
        return t if t else None

    @field_validator("value", mode="before")
    @classmethod
    def _norm_value(cls, v) -> str:
        s = ("" if v is None else str(v)).strip()
        return s

    @model_validator(mode="after")
    def _other_needs_label(self):
        if self.platform_key == "other" and not self.custom_label:
            raise ValueError("برای پلتفرم «سایر» باید نام/برچسب وارد شود")
        return self


class PersonSocialContactResponse(BaseModel):
    """پاسخ اطلاعات ارتباط پیام‌رسان"""
    id: int = Field(..., description="شناسه رکورد")
    person_id: int = Field(..., description="شناسه شخص")
    platform_key: str = Field(..., description="کلید پلتفرم")
    custom_label: Optional[str] = Field(default=None, description="برچسب سفارشی")
    value: str = Field(..., description="مقدار")
    sort_order: int = Field(..., description="ترتیب نمایش")
    created_at: str = Field(..., description="تاریخ ایجاد")
    updated_at: str = Field(..., description="تاریخ بروزرسانی")

    class Config:
        from_attributes = True


class PersonCreateRequest(BaseModel):
    """درخواست ایجاد شخص جدید"""
    model_config = ConfigDict(extra="ignore")

    # اطلاعات پایه
    code: Optional[int] = Field(default=None, ge=1, description="کد یکتا در هر کسب و کار (در صورت عدم ارسال، خودکار تولید می‌شود)")
    alias_name: str = Field(..., min_length=1, max_length=255, description="نام مستعار (الزامی)")
    first_name: Optional[str] = Field(default=None, max_length=100, description="نام")
    last_name: Optional[str] = Field(default=None, max_length=100, description="نام خانوادگی")
    person_type: Optional[PersonType] = Field(default=None, description="نوع شخص (سازگاری قدیمی)")
    person_types: Optional[List[PersonType]] = Field(default=None, description="انواع شخص (چندانتخابی)")
    company_name: Optional[str] = Field(default=None, max_length=255, description="نام شرکت")
    name_prefix: Optional[str] = Field(default=None, max_length=64, description="پیشوند (آقای، خانم، شرکت، …)")
    legal_entity_type: str = Field(
        default="natural",
        description="نوع حقوقی: natural=حقیقی، legal=حقوقی",
    )
    payment_id: Optional[str] = Field(default=None, max_length=100, description="شناسه پرداخت")
    person_group_id: Optional[int] = Field(default=None, description="گروه اشخاص (اختیاری؛ قالب پیش‌فرض)")

    @field_validator("name_prefix", mode="before")
    @classmethod
    def _validate_name_prefix(cls, v):
        if v is None:
            return None
        s = str(v).strip()
        if not s:
            return None
        if s not in ALLOWED_PERSON_NAME_PREFIXES:
            raise ValueError(f"پیشوند نامعتبر است. مقادیر مجاز: {', '.join(sorted(ALLOWED_PERSON_NAME_PREFIXES))}")
        return s

    @field_validator("legal_entity_type", mode="before")
    @classmethod
    def _validate_legal_entity_type(cls, v):
        if v is None or str(v).strip() == "":
            return "natural"
        s = str(v).strip().lower()
        if s in ("legal", "حقوقی", "حقوقي"):
            return "legal"
        if s in ("natural", "حقیقی", "حقیقي"):
            return "natural"
        raise ValueError("legal_entity_type باید natural یا legal باشد")
    
    # اطلاعات اقتصادی
    national_id: Optional[str] = Field(default=None, max_length=20, description="شناسه ملی")
    registration_number: Optional[str] = Field(default=None, max_length=50, description="شماره ثبت")
    economic_id: Optional[str] = Field(default=None, max_length=50, description="شناسه اقتصادی")
    
    # اطلاعات تماس
    country: Optional[str] = Field(default=None, max_length=100, description="کشور")
    province: Optional[str] = Field(default=None, max_length=100, description="استان")
    city: Optional[str] = Field(default=None, max_length=100, description="شهرستان")
    address: Optional[str] = Field(default=None, description="آدرس")
    postal_code: Optional[str] = Field(default=None, max_length=20, description="کد پستی")
    phone: Optional[str] = Field(default=None, max_length=20, description="تلفن")
    mobile: Optional[str] = Field(default=None, max_length=20, description="موبایل")
    mobile_2: Optional[str] = Field(default=None, max_length=20, description="موبایل ۲")
    mobile_3: Optional[str] = Field(default=None, max_length=20, description="موبایل ۳")
    fax: Optional[str] = Field(default=None, max_length=20, description="فکس")
    email: Optional[str] = Field(default=None, max_length=255, description="پست الکترونیکی")
    website: Optional[str] = Field(default=None, max_length=255, description="وب‌سایت")
    
    # حساب‌های بانکی
    bank_accounts: Optional[List[PersonBankAccountCreateRequest]] = Field(default=[], description="حساب‌های بانکی")
    # پیام‌رسان / شبکه‌های اجتماعی
    social_contacts: Optional[List[PersonSocialContactInput]] = Field(default=[], description="راه‌های ارتباط (تلگرام، اینستاگرام و …)")
    # سهام
    share_count: Optional[int] = Field(default=None, ge=1, description="تعداد سهام (برای سهامدار، اجباری و حداقل 1)")
    # پورسانت (برای بازاریاب/فروشنده)
    commission_sale_percent: Optional[float] = Field(default=None, ge=0, le=100, description="درصد پورسانت از فروش")
    commission_sales_return_percent: Optional[float] = Field(default=None, ge=0, le=100, description="درصد پورسانت از برگشت از فروش")
    commission_sales_amount: Optional[float] = Field(default=None, ge=0, description="مبلغ فروش مبنا")
    commission_sales_return_amount: Optional[float] = Field(default=None, ge=0, description="مبلغ برگشت از فروش مبنا")
    commission_exclude_discounts: Optional[bool] = Field(default=False, description="عدم محاسبه تخفیف")
    commission_exclude_additions_deductions: Optional[bool] = Field(default=False, description="عدم محاسبه اضافات و کسورات")
    commission_post_in_invoice_document: Optional[bool] = Field(default=False, description="ثبت پورسانت در سند فاکتور")
    # اعتبار
    credit_limit: Optional[float] = Field(default=None, ge=0, description="سقف اعتبار شخص")
    credit_check_enabled: Optional[bool] = Field(default=None, description="فعال بودن بررسی اعتبار برای شخص (در صورت عدم ارسال، از تنظیمات کسب‌وکار تبعیت می‌کند)")

    @classmethod
    def __get_validators__(cls):
        yield from super().__get_validators__()

    @staticmethod
    def _has_shareholder(person_type: Optional[PersonType], person_types: Optional[List[PersonType]]) -> bool:
        if person_type == PersonType.SHAREHOLDER:
            return True
        if person_types:
            return PersonType.SHAREHOLDER in person_types
        return False

    @classmethod
    def validate(cls, value):  # type: ignore[override]
        obj = super().validate(value)
        # اعتبارسنجی شرطی سهامدار
        if cls._has_shareholder(getattr(obj, 'person_type', None), getattr(obj, 'person_types', None)):
            sc = getattr(obj, 'share_count', None)
            if sc is None or (isinstance(sc, int) and sc <= 0):
                raise ValueError("برای سهامدار، مقدار تعداد سهام الزامی و باید بزرگتر از صفر باشد")
        return obj


class PersonUpdateRequest(BaseModel):
    """درخواست ویرایش شخص"""
    model_config = ConfigDict(extra="ignore")

    # اطلاعات پایه
    code: Optional[int] = Field(default=None, ge=1, description="کد یکتا در هر کسب و کار")
    alias_name: Optional[str] = Field(default=None, min_length=1, max_length=255, description="نام مستعار")
    first_name: Optional[str] = Field(default=None, max_length=100, description="نام")
    last_name: Optional[str] = Field(default=None, max_length=100, description="نام خانوادگی")
    person_type: Optional[PersonType] = Field(default=None, description="نوع شخص (سازگاری قدیمی)")
    person_types: Optional[List[PersonType]] = Field(default=None, description="انواع شخص (چندانتخابی)")
    company_name: Optional[str] = Field(default=None, max_length=255, description="نام شرکت")
    name_prefix: Optional[str] = Field(default=None, max_length=64, description="پیشوند")
    legal_entity_type: Optional[str] = Field(default=None, description="نوع حقوقی: natural یا legal")
    payment_id: Optional[str] = Field(default=None, max_length=100, description="شناسه پرداخت")
    person_group_id: Optional[int] = Field(default=None, description="گروه اشخاص (خالی برای حذف انتساب)")

    @field_validator("name_prefix", mode="before")
    @classmethod
    def _validate_name_prefix_upd(cls, v):
        if v is None:
            return None
        s = str(v).strip()
        if not s:
            return None
        if s not in ALLOWED_PERSON_NAME_PREFIXES:
            raise ValueError(f"پیشوند نامعتبر است. مقادیر مجاز: {', '.join(sorted(ALLOWED_PERSON_NAME_PREFIXES))}")
        return s

    @field_validator("legal_entity_type", mode="before")
    @classmethod
    def _validate_legal_entity_type_upd(cls, v):
        if v is None or str(v).strip() == "":
            return None
        s = str(v).strip().lower()
        if s in ("legal", "حقوقی", "حقوقي"):
            return "legal"
        if s in ("natural", "حقیقی", "حقیقي"):
            return "natural"
        raise ValueError("legal_entity_type باید natural یا legal باشد")
    
    # اطلاعات اقتصادی
    national_id: Optional[str] = Field(default=None, max_length=20, description="شناسه ملی")
    registration_number: Optional[str] = Field(default=None, max_length=50, description="شماره ثبت")
    economic_id: Optional[str] = Field(default=None, max_length=50, description="شناسه اقتصادی")
    
    # اطلاعات تماس
    country: Optional[str] = Field(default=None, max_length=100, description="کشور")
    province: Optional[str] = Field(default=None, max_length=100, description="استان")
    city: Optional[str] = Field(default=None, max_length=100, description="شهرستان")
    address: Optional[str] = Field(default=None, description="آدرس")
    postal_code: Optional[str] = Field(default=None, max_length=20, description="کد پستی")
    phone: Optional[str] = Field(default=None, max_length=20, description="تلفن")
    mobile: Optional[str] = Field(default=None, max_length=20, description="موبایل")
    mobile_2: Optional[str] = Field(default=None, max_length=20, description="موبایل ۲")
    mobile_3: Optional[str] = Field(default=None, max_length=20, description="موبایل ۳")
    fax: Optional[str] = Field(default=None, max_length=20, description="فکس")
    email: Optional[str] = Field(default=None, max_length=255, description="پست الکترونیکی")
    website: Optional[str] = Field(default=None, max_length=255, description="وب‌سایت")
    
    # سهام
    share_count: Optional[int] = Field(default=None, ge=1, description="تعداد سهام (برای سهامدار)")
    # پورسانت
    commission_sale_percent: Optional[float] = Field(default=None, ge=0, le=100, description="درصد پورسانت از فروش")
    commission_sales_return_percent: Optional[float] = Field(default=None, ge=0, le=100, description="درصد پورسانت از برگشت از فروش")
    commission_sales_amount: Optional[float] = Field(default=None, ge=0, description="مبلغ فروش مبنا")
    commission_sales_return_amount: Optional[float] = Field(default=None, ge=0, description="مبلغ برگشت از فروش مبنا")
    commission_exclude_discounts: Optional[bool] = Field(default=None, description="عدم محاسبه تخفیف")
    commission_exclude_additions_deductions: Optional[bool] = Field(default=None, description="عدم محاسبه اضافات و کسورات")
    commission_post_in_invoice_document: Optional[bool] = Field(default=None, description="ثبت پورسانت در سند فاکتور")
    # اعتبار
    credit_limit: Optional[float] = Field(default=None, ge=0, description="سقف اعتبار شخص")
    credit_check_enabled: Optional[bool] = Field(default=None, description="فعال بودن بررسی اعتبار برای شخص (خالی یعنی تبعیت از تنظیمات کسب‌وکار)")
    # پیام‌رسان / شبکه‌های اجتماعی (در صورت ارسال، کل لیست جایگزین قبلی می‌شود)
    social_contacts: Optional[List[PersonSocialContactInput]] = Field(default=None, description="راه‌های ارتباط؛ اگر ارسال شود جایگزین کامل است")

    @classmethod
    def __get_validators__(cls):
        yield from super().__get_validators__()

    @staticmethod
    def _has_shareholder(person_type: Optional[PersonType], person_types: Optional[List[PersonType]]) -> bool:
        if person_type == PersonType.SHAREHOLDER:
            return True
        if person_types:
            return PersonType.SHAREHOLDER in person_types
        return False

    @classmethod
    def validate(cls, value):  # type: ignore[override]
        obj = super().validate(value)
        # اگر ورودی‌ها مشخصاً به سهامدار اشاره دارند، share_count باید معتبر باشد
        if cls._has_shareholder(getattr(obj, 'person_type', None), getattr(obj, 'person_types', None)):
            sc = getattr(obj, 'share_count', None)
            if sc is None or (isinstance(sc, int) and sc <= 0):
                raise ValueError("برای سهامدار، مقدار تعداد سهام الزامی و باید بزرگتر از صفر باشد")
        return obj


class PersonResponse(BaseModel):
    """پاسخ اطلاعات شخص"""
    id: int = Field(..., description="شناسه شخص")
    business_id: int = Field(..., description="شناسه کسب و کار")
    
    # اطلاعات پایه
    code: Optional[int] = Field(default=None, description="کد یکتا")
    alias_name: str = Field(..., description="نام مستعار")
    first_name: Optional[str] = Field(default=None, description="نام")
    last_name: Optional[str] = Field(default=None, description="نام خانوادگی")
    person_type: str = Field(..., description="نوع شخص")
    person_types: List[str] = Field(default_factory=list, description="انواع شخص")
    company_name: Optional[str] = Field(default=None, description="نام شرکت")
    name_prefix: Optional[str] = Field(default=None, description="پیشوند نام")
    legal_entity_type: str = Field(default="natural", description="نوع حقوقی: natural یا legal")
    payment_id: Optional[str] = Field(default=None, description="شناسه پرداخت")
    person_group_id: Optional[int] = Field(default=None, description="شناسه گروه اشخاص")
    person_group_name: Optional[str] = Field(default=None, description="نام گروه اشخاص")
    
    # اطلاعات اقتصادی
    national_id: Optional[str] = Field(default=None, description="شناسه ملی")
    registration_number: Optional[str] = Field(default=None, description="شماره ثبت")
    economic_id: Optional[str] = Field(default=None, description="شناسه اقتصادی")
    
    # اطلاعات تماس
    country: Optional[str] = Field(default=None, description="کشور")
    province: Optional[str] = Field(default=None, description="استان")
    city: Optional[str] = Field(default=None, description="شهرستان")
    address: Optional[str] = Field(default=None, description="آدرس")
    postal_code: Optional[str] = Field(default=None, description="کد پستی")
    phone: Optional[str] = Field(default=None, description="تلفن")
    mobile: Optional[str] = Field(default=None, description="موبایل")
    mobile_2: Optional[str] = Field(default=None, description="موبایل ۲")
    mobile_3: Optional[str] = Field(default=None, description="موبایل ۳")
    fax: Optional[str] = Field(default=None, description="فکس")
    email: Optional[str] = Field(default=None, description="پست الکترونیکی")
    website: Optional[str] = Field(default=None, description="وب‌سایت")
    
    # زمان‌بندی
    created_at: str = Field(..., description="تاریخ ایجاد")
    updated_at: str = Field(..., description="تاریخ آخرین بروزرسانی")
    
    # حساب‌های بانکی
    bank_accounts: List[PersonBankAccountResponse] = Field(default=[], description="حساب‌های بانکی")
    social_contacts: List[PersonSocialContactResponse] = Field(default_factory=list, description="پیام‌رسان و شبکه‌های اجتماعی")
    # سهام
    share_count: Optional[int] = Field(default=None, description="تعداد سهام")
    # پورسانت
    commission_sale_percent: Optional[float] = Field(default=None, description="درصد پورسانت از فروش")
    commission_sales_return_percent: Optional[float] = Field(default=None, description="درصد پورسانت از برگشت از فروش")
    commission_sales_amount: Optional[float] = Field(default=None, description="مبلغ فروش مبنا")
    commission_sales_return_amount: Optional[float] = Field(default=None, description="مبلغ برگشت از فروش مبنا")
    commission_exclude_discounts: Optional[bool] = Field(default=False, description="عدم محاسبه تخفیف")
    commission_exclude_additions_deductions: Optional[bool] = Field(default=False, description="عدم محاسبه اضافات و کسورات")
    commission_post_in_invoice_document: Optional[bool] = Field(default=False, description="ثبت پورسانت در سند فاکتور")
    # اعتبار
    credit_limit: Optional[float] = Field(default=None, description="سقف اعتبار شخص")
    credit_check_enabled: Optional[bool] = Field(default=None, description="فعال بودن بررسی اعتبار برای شخص")
    
    # تراز و وضعیت مالی
    balance: Optional[float] = Field(default=None, description="تراز شخص (بستانکار - بدهکار)")
    status: Optional[str] = Field(default=None, description="وضعیت مالی (بستانکار/بدهکار/بالانس/بدون تراکنش)")

    class Config:
        from_attributes = True


class PersonListResponse(BaseModel):
    """پاسخ لیست اشخاص"""
    items: List[PersonResponse] = Field(..., description="لیست اشخاص")
    pagination: dict = Field(..., description="اطلاعات صفحه‌بندی")
    query_info: dict = Field(..., description="اطلاعات جستجو و فیلتر")


class PersonSummaryResponse(BaseModel):
    """پاسخ خلاصه اشخاص"""
    total_persons: int = Field(..., description="تعداد کل اشخاص")
    by_type: dict = Field(..., description="تعداد بر اساس نوع")
    active_persons: int = Field(..., description="تعداد اشخاص فعال")
    inactive_persons: int = Field(..., description="تعداد اشخاص غیرفعال")


class PersonShareLinkOptions(BaseModel):
    """تنظیمات محتوای لینک اشتراک"""
    include_ledger: bool = Field(
        default=True,
        description="آیا کارت حساب (تراکنش‌ها) برای مشتری نمایش داده شود",
    )
    include_invoices: bool = Field(
        default=True, description="آیا فهرست فاکتورها نمایش داده شود"
    )
    documents_limit: int = Field(
        default=50,
        ge=10,
        le=200,
        description="حداکثر تعداد ردیف برای لیست‌ها",
    )


class PersonShareLinkCreateRequest(BaseModel):
    """درخواست ایجاد یا به‌روزرسانی لینک اشتراک"""
    expires_in_hours: Optional[int] = Field(
        default=None,
        ge=1,
        le=720,
        description="مدت اعتبار لینک (ساعت). در صورت عدم ارسال از مقدار پیش‌فرض تنظیمات استفاده می‌شود.",
    )
    max_view_count: Optional[int] = Field(
        default=None,
        ge=1,
        le=1000,
        description="حداکثر تعداد بازدید مجاز. خالی یعنی بدون محدودیت.",
    )
    replace_existing: bool = Field(
        default=True,
        description="در صورت وجود لینک فعال، ابتدا لغو و لینک جدید ایجاد شود",
    )
    options: PersonShareLinkOptions = Field(
        default_factory=PersonShareLinkOptions,
        description="تنظیمات محتوای قابل نمایش برای مشتری",
    )


class PersonShareLinkResponse(BaseModel):
    """پاسخ اطلاعات لینک اشتراک"""
    id: int
    business_id: int
    person_id: int
    code: str
    short_url: str
    created_at: str
    expires_at: Optional[str]
    revoked_at: Optional[str]
    last_view_at: Optional[str]
    view_count: int
    max_view_count: Optional[int]
    is_active: bool
    is_expired: bool
    status: str
    remaining_hours: Optional[float]
    options: PersonShareLinkOptions
