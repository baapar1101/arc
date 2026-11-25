from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, JSON, String
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class McpOAuthClient(Base):
    __tablename__ = "mcp_oauth_clients"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    client_id: Mapped[str] = mapped_column(String(512), unique=True, index=True, nullable=False)
    client_name: Mapped[str] = mapped_column(String(200), nullable=False)
    redirect_uris: Mapped[list] = mapped_column(JSON, nullable=False)
    grant_types: Mapped[list] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class McpOAuthAuthorizationRequest(Base):
    __tablename__ = "mcp_oauth_authorization_requests"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    request_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True, nullable=False)
    client_id: Mapped[str] = mapped_column(String(512), index=True, nullable=False)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    consent_token_hash: Mapped[str | None] = mapped_column(String(128), nullable=True, unique=True, index=True)
    consent_expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    redirect_uri: Mapped[str] = mapped_column(String(2048), nullable=False)
    resource: Mapped[str] = mapped_column(String(2048), nullable=False)
    state: Mapped[str] = mapped_column(String(512), nullable=False)
    code_challenge: Mapped[str] = mapped_column(String(128), nullable=False)
    scopes: Mapped[list] = mapped_column(JSON, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class McpOAuthAuthorizationCode(Base):
    __tablename__ = "mcp_oauth_authorization_codes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    code_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True, nullable=False)
    client_id: Mapped[str] = mapped_column(String(512), index=True, nullable=False)
    redirect_uri: Mapped[str] = mapped_column(String(2048), nullable=False)
    resource: Mapped[str] = mapped_column(String(2048), nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    business_id: Mapped[int] = mapped_column(ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
    scopes: Mapped[list] = mapped_column(JSON, nullable=False)
    tool_permissions: Mapped[list | None] = mapped_column(JSON, nullable=True)
    code_challenge: Mapped[str] = mapped_column(String(128), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class McpOAuthRefreshToken(Base):
    __tablename__ = "mcp_oauth_refresh_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    token_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True, nullable=False)
    grant_id: Mapped[str] = mapped_column(String(64), index=True, nullable=False)
    client_id: Mapped[str] = mapped_column(String(512), index=True, nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    business_id: Mapped[int] = mapped_column(ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
    resource: Mapped[str] = mapped_column(String(2048), nullable=False)
    scopes: Mapped[list] = mapped_column(JSON, nullable=False)
    tool_permissions: Mapped[list | None] = mapped_column(JSON, nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    replaced_by_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
