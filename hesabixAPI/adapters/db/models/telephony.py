# noqa: D100
"""مدل‌های افزونه اتصال به آستریکس و ایزابل."""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
	Boolean,
	DateTime,
	ForeignKey,
	Index,
	Integer,
	JSON,
	String,
	Text,
	UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class TelephonySettings(Base):
	"""تنظیمات تلفن per کسب‌وکار."""

	__tablename__ = "telephony_settings"
	__table_args__ = (UniqueConstraint("business_id", name="uq_telephony_settings_business"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	primary_phone_fields: Mapped[dict | None] = mapped_column(
		JSON, nullable=True, comment='["mobile","mobile_2","mobile_3","phone"]'
	)
	number_normalization_rules: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	screen_pop_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	auto_create_activity: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	post_call_form_required: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
	default_category: Mapped[str | None] = mapped_column(String(50), nullable=True)
	missed_call_create_task: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
	missed_call_task_due_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=60, server_default="60")
	recording_access_mode: Mapped[str] = mapped_column(
		String(40), nullable=False, default="permission_based", server_default="permission_based"
	)
	multi_pbx_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
	ui_preferences: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	extra_settings: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class TelephonyPbxConnection(Base):
	"""اتصال یک مرکز تلفن Issabel/Asterisk به کسب‌وکار."""

	__tablename__ = "telephony_pbx_connections"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	name: Mapped[str] = mapped_column(String(120), nullable=False)
	pbx_type: Mapped[str] = mapped_column(
		String(40), nullable=False, default="issabel", server_default="issabel",
		comment="issabel | asterisk | freepbx_compat",
	)
	host_hint: Mapped[str | None] = mapped_column(String(255), nullable=True)
	connector_token_hash: Mapped[str] = mapped_column(String(128), nullable=False)
	connector_token_prefix: Mapped[str | None] = mapped_column(String(24), nullable=True)
	connector_version: Mapped[str | None] = mapped_column(String(40), nullable=True)
	last_seen_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	status: Mapped[str] = mapped_column(
		String(20), nullable=False, default="pending", server_default="pending",
		comment="pending | online | offline | error",
	)
	last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
	settings: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	extensions: Mapped[list["TelephonyExtension"]] = relationship(
		back_populates="pbx", cascade="all, delete-orphan"
	)
	calls: Mapped[list["TelephonyCall"]] = relationship(back_populates="pbx")


class TelephonyExtension(Base):
	"""کاتالوگ داخلی‌های یک PBX."""

	__tablename__ = "telephony_extensions"
	__table_args__ = (
		UniqueConstraint("pbx_id", "extension", name="uq_telephony_extensions_pbx_ext"),
		Index("idx_telephony_extensions_business", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	pbx_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("telephony_pbx_connections.id", ondelete="CASCADE"), nullable=False, index=True
	)
	extension: Mapped[str] = mapped_column(String(32), nullable=False)
	display_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
	queue_codes: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	presence_status: Mapped[str] = mapped_column(
		String(20), nullable=False, default="unknown", server_default="unknown",
		comment="unknown | idle | ringing | busy | unavailable",
	)
	presence_updated_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	pbx: Mapped["TelephonyPbxConnection"] = relationship(back_populates="extensions")
	user_links: Mapped[list["TelephonyUserExtension"]] = relationship(
		back_populates="extension_row", cascade="all, delete-orphan"
	)


class TelephonyUserExtension(Base):
	"""نگاشت کاربر حسابیکس ↔ داخلی در یک کسب‌وکار."""

	__tablename__ = "telephony_user_extensions"
	__table_args__ = (
		UniqueConstraint(
			"business_id", "user_id", "extension_id", name="uq_telephony_user_ext_biz_user_ext"
		),
		Index("idx_telephony_user_ext_lookup", "business_id", "user_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
	pbx_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("telephony_pbx_connections.id", ondelete="CASCADE"), nullable=False, index=True
	)
	extension_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("telephony_extensions.id", ondelete="CASCADE"), nullable=False, index=True
	)
	is_primary: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	receive_screen_pop: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	can_click_to_call: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	caller_id_override: Mapped[str | None] = mapped_column(String(40), nullable=True)
	endpoint_mode: Mapped[str] = mapped_column(
		String(20),
		nullable=False,
		default="desk",
		server_default="desk",
		comment="relay | direct | desk",
	)
	allow_mode_fallback: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	direct_sip_user: Mapped[str | None] = mapped_column(String(80), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	extension_row: Mapped["TelephonyExtension"] = relationship(back_populates="user_links")


class TelephonySoftphoneSession(Base):
	"""سشن Softphone (رجیستر رسانه / آماده‌باش اپراتور)."""

	__tablename__ = "telephony_softphone_sessions"
	__table_args__ = (
		UniqueConstraint("session_id", name="uq_telephony_softphone_sessions_sid"),
		Index("idx_telephony_softphone_sessions_biz_user", "business_id", "user_id"),
		Index("idx_telephony_softphone_sessions_pbx_state", "pbx_id", "state"),
		Index("idx_telephony_softphone_sessions_expires", "expires_at"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	session_id: Mapped[str] = mapped_column(String(36), nullable=False)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	pbx_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("telephony_pbx_connections.id", ondelete="CASCADE"), nullable=False, index=True
	)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
	extension: Mapped[str] = mapped_column(String(32), nullable=False)
	mode: Mapped[str] = mapped_column(
		String(20), nullable=False, default="relay", server_default="relay", comment="relay | direct"
	)
	state: Mapped[str] = mapped_column(
		String(30),
		nullable=False,
		default="creating",
		server_default="creating",
		comment="creating | registered | ringing | in_call | ended | failed",
	)
	media_ticket_hash: Mapped[str] = mapped_column(String(128), nullable=False)
	media_ticket_prefix: Mapped[str | None] = mapped_column(String(16), nullable=True)
	media_edge_node: Mapped[str | None] = mapped_column(String(80), nullable=True)
	connector_tunnel_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
	call_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("telephony_calls.id", ondelete="SET NULL"), nullable=True
	)
	ice_policy: Mapped[str | None] = mapped_column(String(40), nullable=True)
	turn_used: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
	last_quality_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	client_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	last_heartbeat_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
	ended_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	end_reason: Mapped[str | None] = mapped_column(String(120), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class TelephonyQueue(Base):
	"""تعریف صف تماس."""

	__tablename__ = "telephony_queues"
	__table_args__ = (
		UniqueConstraint("pbx_id", "queue_code", name="uq_telephony_queues_pbx_code"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	pbx_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("telephony_pbx_connections.id", ondelete="CASCADE"), nullable=False, index=True
	)
	queue_code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(120), nullable=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	live_waiting_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
	live_talking_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class TelephonyCall(Base):
	"""تاریخچه و وضعیت تماس — منبع حقیقت تلفنی."""

	__tablename__ = "telephony_calls"
	__table_args__ = (
		UniqueConstraint("pbx_id", "asterisk_uniqueid", name="uq_telephony_calls_pbx_uniqueid"),
		Index("idx_telephony_calls_business_started", "business_id", "started_at"),
		Index("idx_telephony_calls_from_norm", "business_id", "from_number_normalized"),
		Index("idx_telephony_calls_to_norm", "business_id", "to_number_normalized"),
		Index("idx_telephony_calls_assigned", "business_id", "assigned_user_id", "started_at"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	pbx_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("telephony_pbx_connections.id", ondelete="CASCADE"), nullable=False, index=True
	)
	asterisk_uniqueid: Mapped[str] = mapped_column(String(64), nullable=False)
	asterisk_linkedid: Mapped[str | None] = mapped_column(String(64), nullable=True)
	direction: Mapped[str] = mapped_column(
		String(20), nullable=False, comment="inbound | outbound | internal"
	)
	status: Mapped[str] = mapped_column(
		String(20), nullable=False, default="ringing", server_default="ringing",
		comment="ringing | answered | missed | busy | failed | completed | cancelled",
	)
	from_number_raw: Mapped[str | None] = mapped_column(String(40), nullable=True)
	from_number_normalized: Mapped[str | None] = mapped_column(String(40), nullable=True)
	to_number_raw: Mapped[str | None] = mapped_column(String(40), nullable=True)
	to_number_normalized: Mapped[str | None] = mapped_column(String(40), nullable=True)
	extension: Mapped[str | None] = mapped_column(String(32), nullable=True)
	queue_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
	transferred_from: Mapped[str | None] = mapped_column(String(40), nullable=True)
	transferred_to: Mapped[str | None] = mapped_column(String(40), nullable=True)
	started_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
	answered_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	ended_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	duration_sec: Mapped[int | None] = mapped_column(Integer, nullable=True)
	talk_sec: Mapped[int | None] = mapped_column(Integer, nullable=True)
	hangup_cause: Mapped[str | None] = mapped_column(String(80), nullable=True)
	recording_status: Mapped[str] = mapped_column(
		String(20), nullable=False, default="none", server_default="none",
		comment="none | pending | available | failed",
	)
	recording_file_storage_id: Mapped[str | None] = mapped_column(
		String(36), ForeignKey("file_storage.id", ondelete="SET NULL"), nullable=True
	)
	recording_remote_path: Mapped[str | None] = mapped_column(String(512), nullable=True)
	recording_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
	person_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True, index=True
	)
	lead_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("crm_leads.id", ondelete="SET NULL"), nullable=True, index=True
	)
	deal_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("crm_deals.id", ondelete="SET NULL"), nullable=True, index=True
	)
	document_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True
	)
	crm_activity_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("crm_activities.id", ondelete="SET NULL"), nullable=True
	)
	assigned_user_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
	)
	category: Mapped[str | None] = mapped_column(String(50), nullable=True)
	outcome: Mapped[str | None] = mapped_column(String(100), nullable=True)
	note: Mapped[str | None] = mapped_column(Text, nullable=True)
	match_method: Mapped[str | None] = mapped_column(
		String(30), nullable=True, comment="auto | manual | created_person | created_lead"
	)
	is_anonymous: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	pbx: Mapped["TelephonyPbxConnection"] = relationship(back_populates="calls")
	events: Mapped[list["TelephonyCallEvent"]] = relationship(
		back_populates="call", cascade="all, delete-orphan", order_by="TelephonyCallEvent.occurred_at"
	)


class TelephonyCallEvent(Base):
	"""رویدادهای ریز state machine تماس."""

	__tablename__ = "telephony_call_events"
	__table_args__ = (
		Index("idx_telephony_call_events_call", "call_id", "occurred_at"),
		UniqueConstraint("pbx_id", "event_id", name="uq_telephony_call_events_pbx_event"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	pbx_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("telephony_pbx_connections.id", ondelete="CASCADE"), nullable=False, index=True
	)
	call_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("telephony_calls.id", ondelete="CASCADE"), nullable=True, index=True
	)
	event_id: Mapped[str] = mapped_column(String(64), nullable=False)
	event_type: Mapped[str] = mapped_column(String(40), nullable=False)
	payload: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	occurred_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

	call: Mapped["TelephonyCall | None"] = relationship(back_populates="events")


class TelephonyCommand(Base):
	"""صف دستورات Hesabix → Connector (Originate و …)."""

	__tablename__ = "telephony_commands"
	__table_args__ = (
		Index("idx_telephony_commands_poll", "pbx_id", "status", "created_at"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	pbx_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("telephony_pbx_connections.id", ondelete="CASCADE"), nullable=False, index=True
	)
	command_id: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
	command_type: Mapped[str] = mapped_column(String(40), nullable=False, comment="originate | hangup | transfer | hold | resume")
	payload: Mapped[dict] = mapped_column(JSON, nullable=False)
	status: Mapped[str] = mapped_column(
		String(20), nullable=False, default="pending", server_default="pending",
		comment="pending | sent | acked | failed | expired",
	)
	created_by_user_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	call_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("telephony_calls.id", ondelete="SET NULL"), nullable=True
	)
	result_payload: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	acked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class TelephonyNumberAlias(Base):
	"""نگاشت دستی شماره خاص به شخص."""

	__tablename__ = "telephony_number_aliases"
	__table_args__ = (
		UniqueConstraint("business_id", "number_normalized", name="uq_telephony_alias_biz_number"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	number_normalized: Mapped[str] = mapped_column(String(40), nullable=False)
	person_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("persons.id", ondelete="CASCADE"), nullable=True
	)
	lead_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("crm_leads.id", ondelete="CASCADE"), nullable=True
	)
	note: Mapped[str | None] = mapped_column(String(255), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class TelephonyEventDeadLetter(Base):
	"""رویدادهای شکست‌خورده Connector."""

	__tablename__ = "telephony_event_dead_letters"
	__table_args__ = (Index("idx_telephony_dlq_business_created", "business_id", "created_at"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	pbx_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("telephony_pbx_connections.id", ondelete="SET NULL"), nullable=True
	)
	event_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
	payload: Mapped[dict] = mapped_column(JSON, nullable=False)
	error_message: Mapped[str] = mapped_column(Text, nullable=False)
	resolved: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	resolved_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class TelephonyMetricCounter(Base):
	"""شمارنده‌های مشاهده‌پذیری."""

	__tablename__ = "telephony_metric_counters"
	__table_args__ = (
		UniqueConstraint("business_id", "metric_key", name="uq_telephony_metric_biz_key"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	metric_key: Mapped[str] = mapped_column(String(80), nullable=False)
	value: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)
