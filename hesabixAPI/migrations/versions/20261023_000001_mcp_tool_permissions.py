"""Persist per-tool MCP grants across OAuth code, refresh, and access tokens."""
from alembic import op
import sqlalchemy as sa

revision = "20261023_000001_mcp_tool_permissions"
down_revision = "20261021_000002_production_order_costing"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("api_keys", sa.Column("mcp_tool_permissions", sa.JSON(), nullable=True))
    op.add_column("mcp_oauth_authorization_codes", sa.Column("tool_permissions", sa.JSON(), nullable=True))
    op.add_column("mcp_oauth_refresh_tokens", sa.Column("tool_permissions", sa.JSON(), nullable=True))


def downgrade():
    op.drop_column("mcp_oauth_refresh_tokens", "tool_permissions")
    op.drop_column("mcp_oauth_authorization_codes", "tool_permissions")
    op.drop_column("api_keys", "mcp_tool_permissions")
