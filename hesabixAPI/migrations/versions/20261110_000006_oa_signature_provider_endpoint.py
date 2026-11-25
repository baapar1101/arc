"""نشانی زنده ارائه‌دهنده امضا. توکن در پاسخ API برنمی‌گردد.

Revision ID: 20261110_000006_oa_signature_provider_endpoint
Revises: 20261110_000005_oa_enterprise
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000006_oa_signature_provider_endpoint"
down_revision = "20261110_000005_oa_enterprise"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column("oa_signature_providers", sa.Column("endpoint_url", sa.String(length=500), nullable=True))
	op.add_column("oa_signature_providers", sa.Column("access_token", sa.String(length=500), nullable=True))


def downgrade() -> None:
	op.drop_column("oa_signature_providers", "access_token")
	op.drop_column("oa_signature_providers", "endpoint_url")
