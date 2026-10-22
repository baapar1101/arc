"""Add Navasan as a centrally managed FX rates provider."""

from __future__ import annotations

import json
from datetime import datetime, timezone

import sqlalchemy as sa
from alembic import op

revision = "20261018_000003_navasan_fx_provider"
down_revision = "20261018_000002_merge_mcp_oauth_and_person_phone_heads"
branch_labels = None
depends_on = None


def upgrade() -> None:
	providers = sa.table(
		"fx_rate_providers",
		sa.column("code", sa.String),
		sa.column("display_name", sa.String),
		sa.column("api_base_url", sa.String),
		sa.column("api_key_encrypted", sa.Text),
		sa.column("is_active", sa.Boolean),
		sa.column("fetch_interval_seconds", sa.Integer),
		sa.column("config_json", sa.Text),
		sa.column("created_at", sa.DateTime(timezone=True)),
		sa.column("updated_at", sa.DateTime(timezone=True)),
	)
	conn = op.get_bind()
	exists = conn.execute(sa.select(providers.c.code).where(providers.c.code == "navasan")).first()
	if exists:
		return
	now = datetime.now(timezone.utc)
	config = {
		"quote_unit": "IRT",
		"endpoint_path": "/latest/",
		"notes": "نرخ‌های latest نوسان به‌صورت تومان تفسیر می‌شوند. symbol_map در سرویس قابل تنظیم است.",
	}
	conn.execute(
		providers.insert().values(
			code="navasan",
			display_name="نوسان (Navasan)",
			api_base_url="https://api.navasan.tech",
			api_key_encrypted=None,
			is_active=True,
			fetch_interval_seconds=900,
			config_json=json.dumps(config, ensure_ascii=False),
			created_at=now,
			updated_at=now,
		)
	)


def downgrade() -> None:
	conn = op.get_bind()
	provider_id = conn.execute(
		sa.text("SELECT id FROM fx_rate_providers WHERE code = :code"), {"code": "navasan"}
	).scalar()
	if provider_id is not None:
		conn.execute(sa.text("DELETE FROM fx_global_rates WHERE provider_id = :id"), {"id": provider_id})
		conn.execute(sa.text("DELETE FROM fx_rate_providers WHERE id = :id"), {"id": provider_id})
