# noqa: D100
"""
مدل‌های CRM: تعریف فرایند، مراحل، سرنخ، فرصت فروش، فعالیت
"""
from __future__ import annotations

from datetime import datetime, date

from sqlalchemy import (
    String,
    Integer,
    DateTime,
    Boolean,
    ForeignKey,
    JSON,
    Date,
    Text,
    UniqueConstraint,
    Numeric,
    Index,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


# --- تعریف فرایند و مراحل (زون ارجاعات / pipeline) ---


class CrmProcessDefinition(Base):
    """تعریف فرایند CRM برای کسب‌وکار (فانل سرنخ، pipeline فروش، انواع فعالیت)"""
    __tablename__ = "crm_process_definitions"
    __table_args__ = (
        UniqueConstraint(
            "business_id",
            "process_type",
            "code",
            name="uq_crm_process_def_business_type_code",
        ),
        Index("idx_crm_process_def_business_type", "business_id", "process_type"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    process_type: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        index=True,
        comment="lead_funnel | sales_pipeline | activity_type | lead_source",
    )
    code: Mapped[str] = mapped_column(String(50), nullable=False, index=True, comment="کد یکتا")
    name: Mapped[str] = mapped_column(String(255), nullable=False, comment="نام فارسی")
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_default: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="0",
        comment="فرایند پیش‌فرض برای این نوع",
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default="1",
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )
    created_by_user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    business = relationship("Business", back_populates="crm_process_definitions")
    stages: Mapped[list["CrmProcessStage"]] = relationship(
        "CrmProcessStage",
        back_populates="process_definition",
        cascade="all, delete-orphan",
        order_by="CrmProcessStage.order_index",
    )
    created_by = relationship("User", foreign_keys=[created_by_user_id])


class CrmProcessStage(Base):
    """مرحله در یک فرایند CRM"""
    __tablename__ = "crm_process_stages"
    __table_args__ = (
        UniqueConstraint(
            "process_definition_id",
            "stage_code",
            name="uq_crm_process_stage_def_code",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    process_definition_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("crm_process_definitions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    stage_code: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    order_index: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    color: Mapped[str | None] = mapped_column(String(20), nullable=True, comment="رنگ برای UI مثلاً #hex")
    is_win: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
    is_lost: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
    allow_transition_to: Mapped[dict | None] = mapped_column(
        JSON,
        nullable=True,
        comment="لیست stage_codeهایی که می‌توان به آن‌ها رفت؛ خالی = همه",
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )

    process_definition: Mapped["CrmProcessDefinition"] = relationship(
        "CrmProcessDefinition",
        back_populates="stages",
    )


# --- سرنخ (Lead) ---


class Lead(Base):
    """سرنخ / ارجاع"""
    __tablename__ = "crm_leads"
    __table_args__ = (
        Index("idx_crm_leads_business_stage", "business_id", "stage_id"),
        UniqueConstraint("business_id", "code", name="uq_crm_leads_business_code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    process_definition_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("crm_process_definitions.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    stage_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("crm_process_stages.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    code: Mapped[str] = mapped_column(String(50), nullable=False, index=True, comment="کد یکتا")
    source_code: Mapped[str | None] = mapped_column(
        String(50),
        nullable=True,
        index=True,
        comment="منبع سرنخ از فرایند نوع lead_source",
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    company_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    mobile: Mapped[str | None] = mapped_column(String(20), nullable=True, index=True)
    email: Mapped[str | None] = mapped_column(String(255), nullable=True, index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    assigned_to_user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    person_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("persons.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
        comment="پس از تبدیل به مشتری",
    )
    converted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    next_follow_up_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True, comment="یادآور پیگیری بعدی")
    # --- ارتقای اتوماسیون فروش ---
    score: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0", comment="امتیاز سرنخ")
    sla_due_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True, comment="مهلت SLA برای اولین تماس")
    first_touched_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, comment="زمان اولین برخورد/فعالیت")
    last_activity_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, comment="زمان آخرین فعالیت")
    extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )
    created_by_user_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )

    business = relationship("Business", back_populates="crm_leads")
    process_definition = relationship("CrmProcessDefinition", foreign_keys=[process_definition_id])
    stage = relationship("CrmProcessStage", foreign_keys=[stage_id])
    assigned_to = relationship("User", foreign_keys=[assigned_to_user_id])
    person = relationship("Person", foreign_keys=[person_id])
    created_by = relationship("User", foreign_keys=[created_by_user_id])
    activities: Mapped[list["CrmActivity"]] = relationship(
        "CrmActivity",
        back_populates="lead",
        foreign_keys="[CrmActivity.lead_id]",
    )
    tag_links: Mapped[list["CrmLeadTagLink"]] = relationship(
        "CrmLeadTagLink",
        back_populates="lead",
        cascade="all, delete-orphan",
    )


# --- فرصت فروش (Deal) ---


class Deal(Base):
    """فرصت فروش"""
    __tablename__ = "crm_deals"
    __table_args__ = (
        Index("idx_crm_deals_business_stage", "business_id", "stage_id"),
        UniqueConstraint("business_id", "code", name="uq_crm_deals_business_code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    person_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("persons.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    process_definition_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("crm_process_definitions.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    stage_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("crm_process_stages.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    code: Mapped[str] = mapped_column(String(50), nullable=False, index=True, comment="کد یکتا")
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
    currency_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("currencies.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    probability_percent: Mapped[int | None] = mapped_column(Integer, nullable=True)
    expected_close_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    next_follow_up_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True, comment="یادآور پیگیری بعدی")
    closed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    document_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("documents.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
        comment="فاکتور/سند پس از بستن معامله",
    )
    assigned_to_user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    # --- ارتقای اتوماسیون فروش ---
    won_reason_code: Mapped[str | None] = mapped_column(String(50), nullable=True, comment="کد دلیل برد")
    lost_reason_code: Mapped[str | None] = mapped_column(String(50), nullable=True, comment="کد دلیل باخت")
    competitor_name: Mapped[str | None] = mapped_column(String(255), nullable=True, comment="نام رقیب در صورت باخت")
    stage_entered_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, comment="زمان ورود به مرحله فعلی")
    extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )
    created_by_user_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )

    business = relationship("Business", back_populates="crm_deals")
    person = relationship("Person", back_populates="crm_deals")
    process_definition = relationship("CrmProcessDefinition", foreign_keys=[process_definition_id])
    stage = relationship("CrmProcessStage", foreign_keys=[stage_id])
    currency = relationship("Currency", foreign_keys=[currency_id])
    document = relationship("Document", foreign_keys=[document_id])
    assigned_to = relationship("User", foreign_keys=[assigned_to_user_id])
    created_by = relationship("User", foreign_keys=[created_by_user_id])
    activities: Mapped[list["CrmActivity"]] = relationship(
        "CrmActivity",
        back_populates="deal",
        foreign_keys="[CrmActivity.deal_id]",
    )
    lines: Mapped[list["CrmDealLine"]] = relationship(
        "CrmDealLine",
        back_populates="deal",
        cascade="all, delete-orphan",
        order_by="CrmDealLine.sort_order",
    )
    tag_links: Mapped[list["CrmDealTagLink"]] = relationship(
        "CrmDealTagLink",
        back_populates="deal",
        cascade="all, delete-orphan",
    )


# --- فعالیت (Activity) ---


class CrmActivity(Base):
    """فعالیت CRM: تماس، ایمیل، جلسه، یادداشت"""
    __tablename__ = "crm_activities"
    __table_args__ = (
        Index("idx_crm_activities_person", "business_id", "person_id"),
        Index("idx_crm_activities_business_lead", "business_id", "lead_id"),
        UniqueConstraint("business_id", "code", name="uq_crm_activities_business_code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    person_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("persons.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    lead_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("crm_leads.id", ondelete="SET NULL"),
        nullable=True,
        comment="فعالیت مرتبط با سرنخ قبل از تبدیل به مشتری",
    )
    code: Mapped[str] = mapped_column(String(50), nullable=False, index=True, comment="کد یکتا")
    activity_type: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        index=True,
        comment="call | email | meeting | note",
    )
    subject: Mapped[str | None] = mapped_column(String(255), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    activity_date: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    deal_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("crm_deals.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    created_by_user_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    # --- ارتقای وظایف/پیگیری ---
    is_task: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false",
        comment="آیا این یک وظیفه است (نه صرفاً لاگ فعالیت)",
    )
    due_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True, comment="سررسید وظیفه")
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="open", server_default="open",
        comment="open | done | cancelled — برای وظایف؛ لاگ‌ها می‌توانند done بمانند",
    )
    completed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    assigned_to_user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    outcome: Mapped[str | None] = mapped_column(String(100), nullable=True, comment="نتیجه فعالیت/وظیفه")
    priority: Mapped[str] = mapped_column(
        String(20), nullable=False, default="normal", server_default="normal",
        comment="low | normal | high | urgent",
    )
    extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )

    business = relationship("Business", back_populates="crm_activities")
    person = relationship("Person", back_populates="crm_activities")
    lead = relationship("Lead", back_populates="activities", foreign_keys=[lead_id])
    deal = relationship("Deal", back_populates="activities")
    created_by = relationship("User", foreign_keys=[created_by_user_id])
    assigned_to = relationship("User", foreign_keys=[assigned_to_user_id])


# --- تاریخچه تغییرات ---


class CrmChangeHistory(Base):
    """تاریخچه تغییرات فیلدهای سرنخ و فرصت فروش"""
    __tablename__ = "crm_change_history"
    __table_args__ = (Index("idx_crm_history_entity", "business_id", "entity_type", "entity_id"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    entity_type: Mapped[str] = mapped_column(String(20), nullable=False, comment="lead | deal")
    entity_id: Mapped[int] = mapped_column(Integer, nullable=False)
    field_name: Mapped[str] = mapped_column(String(80), nullable=False)
    old_value: Mapped[str | None] = mapped_column(Text, nullable=True)
    new_value: Mapped[str | None] = mapped_column(Text, nullable=True)
    changed_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    changed_by_user_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )

    business = relationship("Business")
    changed_by = relationship("User", foreign_keys=[changed_by_user_id])


# --- یادداشت و تقویم CRM ---


class CrmNoteType(Base):
    """نوع یادداشت قابل تنظیم در سطح کسب‌وکار (عنوان چندزبانه در JSON)"""
    __tablename__ = "crm_note_types"
    __table_args__ = (
        UniqueConstraint("business_id", "code", name="uq_crm_note_types_business_code"),
        Index("ix_crm_note_types_business_id", "business_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    code: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    title_i18n: Mapped[dict] = mapped_column(JSON, nullable=False)
    scheduling_mode: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="day_only",
        server_default="day_only",
        comment="day_only | meeting",
    )
    allow_comments: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
    is_system: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )

    business = relationship("Business")


class CrmNote(Base):
    """یادداشت/رویداد تقویم CRM"""
    __tablename__ = "crm_notes"
    __table_args__ = (
        Index("ix_crm_notes_business_occurs_on", "business_id", "occurs_on"),
        Index("ix_crm_notes_business_deleted", "business_id", "deleted_at"),
        Index("ix_crm_notes_lead_id", "lead_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    note_type_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("crm_note_types.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    visibility: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        comment="private | business_public | shared",
    )
    title: Mapped[str | None] = mapped_column(String(255), nullable=True)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    occurs_on: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    starts_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    ends_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    lead_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("crm_leads.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    created_by_user_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="active",
        server_default="active",
        comment="active | archived | cancelled",
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )

    business = relationship("Business")
    note_type = relationship("CrmNoteType", foreign_keys=[note_type_id])
    lead = relationship("Lead", foreign_keys=[lead_id])
    created_by = relationship("User", foreign_keys=[created_by_user_id])
    acl_users: Mapped[list["CrmNoteAclUser"]] = relationship(
        "CrmNoteAclUser",
        back_populates="note",
        cascade="all, delete-orphan",
    )


class CrmNoteAclUser(Base):
    """دسترسی افراد انتخابی برای یادداشت‌های visibility=shared"""
    __tablename__ = "crm_note_acl_users"
    __table_args__ = (UniqueConstraint("note_id", "user_id", name="uq_crm_note_acl_note_user"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    note_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("crm_notes.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

    note = relationship("CrmNote", back_populates="acl_users")
    user = relationship("User", foreign_keys=[user_id])


class CrmNoteComment(Base):
    """کامنت روی یادداشت‌های عمومی کسب‌وکار"""
    __tablename__ = "crm_note_comments"
    __table_args__ = (Index("ix_crm_note_comments_note_id", "note_id"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    note_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("crm_notes.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_by_user_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )

    note = relationship("CrmNote", foreign_keys=[note_id])
    created_by = relationship("User", foreign_keys=[created_by_user_id])


class CrmNoteAuditEvent(Base):
    """رخدادهای audit برای یادداشت CRM"""
    __tablename__ = "crm_note_audit_events"
    __table_args__ = (Index("ix_crm_note_audit_note_id", "note_id"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    note_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("crm_notes.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    actor_user_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    action: Mapped[str] = mapped_column(String(50), nullable=False)
    payload: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    occurred_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

    note = relationship("CrmNote", foreign_keys=[note_id])
    actor = relationship("User", foreign_keys=[actor_user_id])


# --- دلایل بستن معامله (برد/باخت) ---


class CrmCloseReason(Base):
    """دلایل قابل تنظیم برای بردن یا باختن فرصت فروش"""
    __tablename__ = "crm_close_reasons"
    __table_args__ = (
        UniqueConstraint("business_id", "reason_type", "code", name="uq_crm_close_reasons_business_type_code"),
        Index("idx_crm_close_reasons_business_type", "business_id", "reason_type"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    reason_type: Mapped[str] = mapped_column(String(20), nullable=False, comment="won | lost")
    code: Mapped[str] = mapped_column(String(50), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


# --- خطوط فرصت فروش ---


class CrmDealLine(Base):
    """ردیف‌های فرصت فروش (پیش‌فاکتور)"""
    __tablename__ = "crm_deal_lines"
    __table_args__ = (
        Index("idx_crm_deal_lines_deal", "deal_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    deal_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("crm_deals.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("products.id", ondelete="SET NULL"), nullable=True, index=True
    )
    description: Mapped[str | None] = mapped_column(String(500), nullable=True)
    quantity: Mapped[float] = mapped_column(Numeric(18, 4), nullable=False, default=1)
    unit_price: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
    discount_percent: Mapped[float] = mapped_column(Numeric(8, 2), nullable=False, default=0, server_default="0")
    line_total: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    deal = relationship("Deal", back_populates="lines")
    product = relationship("Product", foreign_keys=[product_id])


# --- برچسب‌ها (Tags) ---


class CrmTag(Base):
    """برچسب برای سرنخ و فرصت فروش"""
    __tablename__ = "crm_tags"
    __table_args__ = (
        UniqueConstraint("business_id", "name", name="uq_crm_tags_business_name"),
        Index("idx_crm_tags_business", "business_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    color: Mapped[str | None] = mapped_column(String(20), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class CrmLeadTagLink(Base):
    """اتصال برچسب به سرنخ"""
    __tablename__ = "crm_lead_tag_links"

    lead_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("crm_leads.id", ondelete="CASCADE"), primary_key=True
    )
    tag_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("crm_tags.id", ondelete="CASCADE"), primary_key=True
    )

    lead = relationship("Lead", back_populates="tag_links")
    tag = relationship("CrmTag", foreign_keys=[tag_id])


class CrmDealTagLink(Base):
    """اتصال برچسب به فرصت فروش"""
    __tablename__ = "crm_deal_tag_links"

    deal_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("crm_deals.id", ondelete="CASCADE"), primary_key=True
    )
    tag_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("crm_tags.id", ondelete="CASCADE"), primary_key=True
    )

    deal = relationship("Deal", back_populates="tag_links")
    tag = relationship("CrmTag", foreign_keys=[tag_id])


# --- فیلدهای سفارشی ---


class CrmCustomFieldDefinition(Base):
    """تعریف فیلد سفارشی برای سرنخ/فرصت/فعالیت"""
    __tablename__ = "crm_custom_field_definitions"
    __table_args__ = (
        UniqueConstraint(
            "business_id", "entity_type", "field_key",
            name="uq_crm_custom_field_business_entity_key",
        ),
        Index("idx_crm_custom_field_business_entity", "business_id", "entity_type"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    entity_type: Mapped[str] = mapped_column(String(20), nullable=False, comment="lead | deal | activity")
    field_key: Mapped[str] = mapped_column(String(80), nullable=False)
    label: Mapped[str] = mapped_column(String(255), nullable=False)
    field_type: Mapped[str] = mapped_column(String(20), nullable=False, comment="text | number | date | select | boolean")
    options: Mapped[dict | None] = mapped_column(JSON, nullable=True, comment="گزینه‌ها برای نوع select")
    is_required: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


# --- توالی‌های خودکار (Sequences) ---


class CrmSequence(Base):
    """توالی خودکار پیگیری برای سرنخ/فرصت"""
    __tablename__ = "crm_sequences"
    __table_args__ = (
        Index("idx_crm_sequences_business", "business_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )
    created_by_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )

    steps: Mapped[list["CrmSequenceStep"]] = relationship(
        "CrmSequenceStep",
        back_populates="sequence",
        cascade="all, delete-orphan",
        order_by="CrmSequenceStep.step_order",
    )


class CrmSequenceStep(Base):
    """گام یک توالی"""
    __tablename__ = "crm_sequence_steps"
    __table_args__ = (
        Index("idx_crm_sequence_steps_seq", "sequence_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    sequence_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("crm_sequences.id", ondelete="CASCADE"), nullable=False, index=True
    )
    step_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    delay_hours: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    action_type: Mapped[str] = mapped_column(
        String(50), nullable=False,
        comment="create_task | send_sms | notify_assignee | update_lead_stage | update_deal_stage",
    )
    action_config: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

    sequence = relationship("CrmSequence", back_populates="steps")


class CrmSequenceEnrollment(Base):
    """ثبت‌نام یک سرنخ/فرصت در یک توالی"""
    __tablename__ = "crm_sequence_enrollments"
    __table_args__ = (
        Index("idx_crm_seq_enroll_business", "business_id"),
        Index("idx_crm_seq_enroll_entity", "business_id", "entity_type", "entity_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    sequence_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("crm_sequences.id", ondelete="CASCADE"), nullable=False, index=True
    )
    entity_type: Mapped[str] = mapped_column(String(20), nullable=False, comment="lead | deal")
    entity_id: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="active", server_default="active",
        comment="active | completed | cancelled",
    )
    current_step_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    next_run_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True)
    enrolled_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)

    sequence = relationship("CrmSequence", foreign_keys=[sequence_id])


# --- جلوگیری از ارسال تکراری یادآور ---


class CrmReminderDedup(Base):
    """ثبت یادآورهای ارسال‌شده برای جلوگیری از تکرار"""
    __tablename__ = "crm_reminder_dedup"
    __table_args__ = (
        UniqueConstraint(
            "business_id", "entity_type", "entity_id", "reminder_key",
            name="uq_crm_reminder_dedup_key",
        ),
        Index("idx_crm_reminder_dedup_business", "business_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    entity_type: Mapped[str] = mapped_column(String(20), nullable=False, comment="lead | deal | activity")
    entity_id: Mapped[int] = mapped_column(Integer, nullable=False)
    reminder_key: Mapped[str] = mapped_column(String(80), nullable=False)
    sent_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


