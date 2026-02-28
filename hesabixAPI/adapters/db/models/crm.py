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


# --- فعالیت (Activity) ---


class CrmActivity(Base):
    """فعالیت CRM: تماس، ایمیل، جلسه، یادداشت"""
    __tablename__ = "crm_activities"
    __table_args__ = (
        Index("idx_crm_activities_person", "business_id", "person_id"),
        UniqueConstraint("business_id", "code", name="uq_crm_activities_business_code"),
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
        ForeignKey("persons.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
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
    deal = relationship("Deal", back_populates="activities")
    created_by = relationship("User", foreign_keys=[created_by_user_id])


