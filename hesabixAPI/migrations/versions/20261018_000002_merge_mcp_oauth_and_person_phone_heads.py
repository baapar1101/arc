"""Merge the MCP OAuth and person phone identity migration heads."""

revision = "20261018_000002_merge_mcp_oauth_and_person_phone_heads"
down_revision = (
    "20261016_000002_mcp_oauth",
    "20261018_000001_person_phone_identity",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
