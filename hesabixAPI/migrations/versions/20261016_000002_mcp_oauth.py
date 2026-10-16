"""Add OAuth 2.1 authorization state for the MCP server."""

import sqlalchemy as sa
from alembic import op

revision = "20261016_000002_mcp_oauth"
down_revision = "20261016_000001_mcp_business_bound_credentials"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("api_keys", sa.Column("mcp_resource", sa.String(length=2048), nullable=True))
    op.add_column("api_keys", sa.Column("oauth_client_id", sa.String(length=512), nullable=True))
    op.create_index("ix_api_keys_oauth_client_id", "api_keys", ["oauth_client_id"])
    op.add_column("api_keys", sa.Column("oauth_grant_id", sa.String(length=64), nullable=True))
    op.create_index("ix_api_keys_oauth_grant_id", "api_keys", ["oauth_grant_id"])
    op.create_table(
        "mcp_oauth_clients",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("client_id", sa.String(length=512), nullable=False),
        sa.Column("client_name", sa.String(length=200), nullable=False),
        sa.Column("redirect_uris", sa.JSON(), nullable=False),
        sa.Column("grant_types", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_mcp_oauth_clients_client_id", "mcp_oauth_clients", ["client_id"], unique=True)
    op.create_table(
        "mcp_oauth_authorization_requests",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("request_hash", sa.String(length=128), nullable=False),
        sa.Column("client_id", sa.String(length=512), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=True),
        sa.Column("consent_token_hash", sa.String(length=128), nullable=True),
        sa.Column("consent_expires_at", sa.DateTime(), nullable=True),
        sa.Column("redirect_uri", sa.String(length=2048), nullable=False),
        sa.Column("resource", sa.String(length=2048), nullable=False),
        sa.Column("state", sa.String(length=512), nullable=False),
        sa.Column("code_challenge", sa.String(length=128), nullable=False),
        sa.Column("scopes", sa.JSON(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_mcp_oauth_authorization_requests_request_hash", "mcp_oauth_authorization_requests", ["request_hash"], unique=True)
    op.create_index("ix_mcp_oauth_authorization_requests_client_id", "mcp_oauth_authorization_requests", ["client_id"])
    op.create_index("ix_mcp_oauth_authorization_requests_user_id", "mcp_oauth_authorization_requests", ["user_id"])
    op.create_index("ix_mcp_oauth_authorization_requests_consent_token_hash", "mcp_oauth_authorization_requests", ["consent_token_hash"], unique=True)
    op.create_index("ix_mcp_oauth_authorization_requests_expires_at", "mcp_oauth_authorization_requests", ["expires_at"])
    op.create_table(
        "mcp_oauth_authorization_codes",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("code_hash", sa.String(length=128), nullable=False),
        sa.Column("client_id", sa.String(length=512), nullable=False),
        sa.Column("redirect_uri", sa.String(length=2048), nullable=False),
        sa.Column("resource", sa.String(length=2048), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("scopes", sa.JSON(), nullable=False),
        sa.Column("code_challenge", sa.String(length=128), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("consumed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_mcp_oauth_authorization_codes_code_hash", "mcp_oauth_authorization_codes", ["code_hash"], unique=True)
    for column in ("client_id", "user_id", "business_id", "expires_at"):
        op.create_index(f"ix_mcp_oauth_authorization_codes_{column}", "mcp_oauth_authorization_codes", [column])
    op.create_table(
        "mcp_oauth_refresh_tokens",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("token_hash", sa.String(length=128), nullable=False),
        sa.Column("grant_id", sa.String(length=64), nullable=False),
        sa.Column("client_id", sa.String(length=512), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("resource", sa.String(length=2048), nullable=False),
        sa.Column("scopes", sa.JSON(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.Column("replaced_by_id", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_mcp_oauth_refresh_tokens_token_hash", "mcp_oauth_refresh_tokens", ["token_hash"], unique=True)
    op.create_index("ix_mcp_oauth_refresh_tokens_grant_id", "mcp_oauth_refresh_tokens", ["grant_id"])
    for column in ("client_id", "user_id", "business_id", "expires_at"):
        op.create_index(f"ix_mcp_oauth_refresh_tokens_{column}", "mcp_oauth_refresh_tokens", [column])


def downgrade() -> None:
    op.drop_table("mcp_oauth_refresh_tokens")
    op.drop_table("mcp_oauth_authorization_codes")
    op.drop_table("mcp_oauth_authorization_requests")
    op.drop_table("mcp_oauth_clients")
    op.drop_index("ix_api_keys_oauth_client_id", table_name="api_keys")
    op.drop_column("api_keys", "oauth_client_id")
    op.drop_index("ix_api_keys_oauth_grant_id", table_name="api_keys")
    op.drop_column("api_keys", "oauth_grant_id")
    op.drop_column("api_keys", "mcp_resource")
