# noqa: D100
"""ویجت چت وب CRM (جاسازی در سایت مشتری) و مکالمه/پیام."""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
	String,
	Integer,
	Boolean,
	ForeignKey,
	Text,
	JSON,
	DateTime,
	UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class CrmChatWidget(Base):
	"""تعریف ویجت چت برای یک کسب‌وکار (کلید عمومی برای embed)."""
	__tablename__ = "crm_chat_widgets"
	__table_args__ = (UniqueConstraint("public_key", name="uq_crm_chat_widgets_public_key"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	public_key: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
	allowed_origins: Mapped[list | None] = mapped_column(JSON, nullable=True)
	settings: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	conversations: Mapped[list["CrmChatConversation"]] = relationship(
		"CrmChatConversation",
		back_populates="widget",
		foreign_keys="CrmChatConversation.widget_id",
	)


class CrmChatConversation(Base):
	"""یک نشست گفت‌وگو پس از تکمیل فرم هویت بازدیدکننده."""
	__tablename__ = "crm_chat_conversations"
	__table_args__ = (UniqueConstraint("visitor_token_hash", name="uq_crm_chat_conversations_visitor_token_hash"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	widget_id: Mapped[int] = mapped_column(Integer, ForeignKey("crm_chat_widgets.id", ondelete="CASCADE"), nullable=False, index=True)
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="open", server_default="open", index=True)
	visitor_first_name: Mapped[str] = mapped_column(String(120), nullable=False)
	visitor_last_name: Mapped[str] = mapped_column(String(120), nullable=False)
	visitor_email: Mapped[str] = mapped_column(String(255), nullable=False)
	visitor_phone: Mapped[str] = mapped_column(String(64), nullable=False)
	visitor_token_hash: Mapped[str] = mapped_column(String(64), nullable=False)
	page_url: Mapped[str | None] = mapped_column(Text, nullable=True)
	extra_metadata: Mapped[dict | None] = mapped_column("extra_metadata", JSON, nullable=True)
	lead_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("crm_leads.id", ondelete="SET NULL"), nullable=True)
	person_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True)
	assigned_to_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	last_message_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True)
	created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	widget = relationship("CrmChatWidget", back_populates="conversations", foreign_keys=[widget_id])
	messages: Mapped[list["CrmChatMessage"]] = relationship(
		"CrmChatMessage",
		back_populates="conversation",
		order_by="CrmChatMessage.created_at",
	)


class CrmChatMessage(Base):
	__tablename__ = "crm_chat_messages"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	conversation_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("crm_chat_conversations.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	sender_role: Mapped[str] = mapped_column(String(20), nullable=False)
	body: Mapped[str] = mapped_column(Text, nullable=False)
	user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	file_storage_id: Mapped[str | None] = mapped_column(
		String(36), ForeignKey("file_storage.id", ondelete="SET NULL"), nullable=True, index=True
	)
	created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow, nullable=False, index=True)
	read_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True)
	deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True)

	conversation = relationship("CrmChatConversation", back_populates="messages")
