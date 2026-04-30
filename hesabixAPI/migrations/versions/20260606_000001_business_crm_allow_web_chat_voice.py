# noqa: D100
"""ارسال ویس در چت وب — فلگ سطح CRM."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260606_000001_business_crm_allow_web_chat_voice"
down_revision = "20260605_000001_seed_notification_event_types_workflow_extensions"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"business_crm_settings",
		sa.Column(
			"allow_web_chat_voice",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("false"),
		),
	)
	op.alter_column("business_crm_settings", "allow_web_chat_voice", server_default=None)


def downgrade() -> None:
	op.drop_column("business_crm_settings", "allow_web_chat_voice")
