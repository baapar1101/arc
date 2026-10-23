"""Tenant-scoped operational entities for the five specialist add-ons.

Kinds have a server-owned typed schema. Source payloads are provenance, never
executed code. Financial posting remains in the existing document subsystem.
"""
from datetime import datetime
from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, JSON, Numeric, String, Text, UniqueConstraint, Index
from sqlalchemy.orm import Mapped, mapped_column
from adapters.db.session import Base


class AdvancedPluginSetting(Base):
    __tablename__ = 'advanced_plugin_settings'
    __table_args__ = (UniqueConstraint('business_id', 'plugin_code', name='uq_advanced_plugin_setting'),)
    id: Mapped[int] = mapped_column(primary_key=True)
    business_id: Mapped[int] = mapped_column(ForeignKey('businesses.id', ondelete='CASCADE'), index=True)
    plugin_code: Mapped[str] = mapped_column(String(100))
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    sync_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    options: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)
    revision: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime)
    sync_summary: Mapped[dict | None] = mapped_column(JSON)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class AdvancedPluginRecord(Base):
    __tablename__ = 'advanced_plugin_records'
    __table_args__ = (
        UniqueConstraint('business_id', 'plugin_code', 'identity', name='uq_advanced_plugin_identity'),
        Index('ix_advanced_plugin_kind_status', 'business_id', 'plugin_code', 'kind', 'status'),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    business_id: Mapped[int] = mapped_column(ForeignKey('businesses.id', ondelete='CASCADE'), index=True)
    plugin_code: Mapped[str] = mapped_column(String(100), index=True)
    kind: Mapped[str] = mapped_column(String(80))
    identity: Mapped[str] = mapped_column(String(64))
    code: Mapped[str | None] = mapped_column(String(120))
    title: Mapped[str] = mapped_column(String(500))
    status: Mapped[str] = mapped_column(String(30), default='active')
    start_date: Mapped[datetime | None] = mapped_column(Date)
    end_date: Mapped[datetime | None] = mapped_column(Date)
    amount: Mapped[float | None] = mapped_column(Numeric(24, 4))
    quantity: Mapped[float | None] = mapped_column(Numeric(24, 6))
    currency_id: Mapped[int | None] = mapped_column(ForeignKey('currencies.id', ondelete='RESTRICT'))
    product_id: Mapped[int | None] = mapped_column(ForeignKey('products.id', ondelete='RESTRICT'), index=True)
    person_id: Mapped[int | None] = mapped_column(ForeignKey('persons.id', ondelete='RESTRICT'), index=True)
    parent_id: Mapped[int | None] = mapped_column(ForeignKey('advanced_plugin_records.id', ondelete='RESTRICT'), index=True)
    data: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)
    source_database: Mapped[str | None] = mapped_column(String(255))
    source_table: Mapped[str | None] = mapped_column(String(150))
    source_key: Mapped[str | None] = mapped_column(Text)
    source_hash: Mapped[str | None] = mapped_column(String(64))
    source_payload: Mapped[dict | None] = mapped_column(JSON)
    source_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    revision: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class AdvancedPluginAudit(Base):
    __tablename__ = 'advanced_plugin_audits'
    id: Mapped[int] = mapped_column(primary_key=True)
    business_id: Mapped[int] = mapped_column(ForeignKey('businesses.id', ondelete='CASCADE'), index=True)
    plugin_code: Mapped[str] = mapped_column(String(100))
    record_id: Mapped[int | None] = mapped_column(ForeignKey('advanced_plugin_records.id', ondelete='SET NULL'))
    actor_user_id: Mapped[int | None] = mapped_column(ForeignKey('users.id', ondelete='SET NULL'))
    action: Mapped[str] = mapped_column(String(40))
    details: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)


class AdvancedPluginPostingConfig(Base):
    __tablename__ = 'advanced_plugin_posting_configs'
    __table_args__ = (UniqueConstraint('business_id','plugin_code',name='uq_advanced_posting_config'),)
    id: Mapped[int] = mapped_column(primary_key=True)
    business_id: Mapped[int] = mapped_column(ForeignKey('businesses.id',ondelete='CASCADE'),index=True)
    plugin_code: Mapped[str] = mapped_column(String(100))
    enabled: Mapped[bool] = mapped_column(Boolean,default=False,nullable=False)
    accounts: Mapped[dict] = mapped_column(JSON,default=dict,nullable=False)
    contract_side: Mapped[str] = mapped_column(String(30),default='require_review',nullable=False)
    revision: Mapped[int] = mapped_column(Integer,default=1,nullable=False)
    updated_by_user_id: Mapped[int | None] = mapped_column(ForeignKey('users.id',ondelete='RESTRICT'))
    updated_at: Mapped[datetime] = mapped_column(DateTime,default=datetime.utcnow,onupdate=datetime.utcnow)


class AdvancedPluginPosting(Base):
    __tablename__ = 'advanced_plugin_postings'
    __table_args__ = (
        UniqueConstraint('business_id','plugin_code','event_key',name='uq_advanced_posting_event'),
        UniqueConstraint('record_id',name='uq_advanced_posting_record'),
        UniqueConstraint('document_id',name='uq_advanced_posting_document'),
        UniqueConstraint('reversal_document_id',name='uq_advanced_posting_reversal'),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    business_id: Mapped[int] = mapped_column(ForeignKey('businesses.id',ondelete='RESTRICT'),index=True)
    plugin_code: Mapped[str] = mapped_column(String(100),index=True)
    record_id: Mapped[int] = mapped_column(ForeignKey('advanced_plugin_records.id',ondelete='RESTRICT'),index=True)
    event_key: Mapped[str] = mapped_column(String(64))
    state: Mapped[str] = mapped_column(String(20),default='draft',nullable=False)
    revision: Mapped[int] = mapped_column(Integer,default=1,nullable=False)
    input_hash: Mapped[str] = mapped_column(String(64))
    proposal: Mapped[dict] = mapped_column(JSON,nullable=False)
    document_id: Mapped[int | None] = mapped_column(ForeignKey('documents.id',ondelete='RESTRICT'))
    reversal_document_id: Mapped[int | None] = mapped_column(ForeignKey('documents.id',ondelete='RESTRICT'))
    created_by_user_id: Mapped[int] = mapped_column(ForeignKey('users.id',ondelete='RESTRICT'))
    approved_by_user_id: Mapped[int | None] = mapped_column(ForeignKey('users.id',ondelete='RESTRICT'))
    reversed_by_user_id: Mapped[int | None] = mapped_column(ForeignKey('users.id',ondelete='RESTRICT'))
    decision_reason: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime,default=datetime.utcnow)
    approved_at: Mapped[datetime | None] = mapped_column(DateTime)
    reversed_at: Mapped[datetime | None] = mapped_column(DateTime)
