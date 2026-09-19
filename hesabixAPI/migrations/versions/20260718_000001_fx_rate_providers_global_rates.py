"""مهاجرت جداول ارائه‌دهنده نرخ ارز و اسنپ‌شات مرکزی.

Revision ID: 20260718_000001_fx_rate_providers_global_rates
Revises: 20260714_000003_document_code_reservations
"""

from __future__ import annotations

import json
from datetime import datetime, timezone

import sqlalchemy as sa
from alembic import op

revision = "20260718_000001_fx_rate_providers_global_rates"
down_revision = "20260714_000003_document_code_reservations"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"fx_rate_providers",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("code", sa.String(length=50), nullable=False),
		sa.Column("display_name", sa.String(length=120), nullable=False),
		sa.Column("api_base_url", sa.String(length=500), nullable=True),
		sa.Column("api_key_encrypted", sa.Text(), nullable=True),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("fetch_interval_seconds", sa.Integer(), nullable=False, server_default="900"),
		sa.Column("config_json", sa.Text(), nullable=True),
		sa.Column("last_fetch_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("last_fetch_status", sa.String(length=32), nullable=True),
		sa.Column("last_fetch_error", sa.Text(), nullable=True),
		sa.Column("last_fetch_http_status", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
		sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("code", name="uq_fx_rate_providers_code"),
	)
	op.create_index("ix_fx_rate_providers_code", "fx_rate_providers", ["code"], unique=False)

	op.create_table(
		"fx_global_rates",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("provider_id", sa.Integer(), nullable=False),
		sa.Column("symbol", sa.String(length=64), nullable=False),
		sa.Column("currency_code", sa.String(length=16), nullable=False),
		sa.Column("price_quote", sa.Numeric(24, 10), nullable=False),
		sa.Column("quote_unit", sa.String(length=16), nullable=False, server_default="IRT"),
		sa.Column("price_irr", sa.Numeric(24, 10), nullable=False),
		sa.Column("name_fa", sa.String(length=120), nullable=True),
		sa.Column("name_en", sa.String(length=120), nullable=True),
		sa.Column("source_time", sa.DateTime(timezone=True), nullable=True),
		sa.Column("fetched_at", sa.DateTime(timezone=True), nullable=False),
		sa.Column("raw_json", sa.Text(), nullable=True),
		sa.ForeignKeyConstraint(["provider_id"], ["fx_rate_providers.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("provider_id", "symbol", name="uq_fx_global_rates_provider_symbol"),
	)
	op.create_index("ix_fx_global_rates_provider_id", "fx_global_rates", ["provider_id"], unique=False)
	op.create_index("ix_fx_global_rates_symbol", "fx_global_rates", ["symbol"], unique=False)
	op.create_index("ix_fx_global_rates_currency_code", "fx_global_rates", ["currency_code"], unique=False)
	op.create_index("ix_fx_global_rates_fetched_at", "fx_global_rates", ["fetched_at"], unique=False)

	now = datetime.now(timezone.utc)
	brs_config = {
		"quote_unit": "IRT",
		"endpoint_path": "/Market/Gold_Currency.php",
		"sections": ["currency"],
		"symbol_map": {
			"USD": "USD",
			"EUR": "EUR",
			"AED": "AED",
			"GBP": "GBP",
			"AUD": "AUD",
			"CAD": "CAD",
			"CNY": "CNY",
			"TRY": "TRY",
			"CHF": "CHF",
			"INR": "INR",
			"IQD": "IQD",
			"AFN": "AFN",
			"USDT_IRT": "USDT",
			"JPY": "JPY",
		},
		"symbol_divisors": {
			"JPY": 100,
		},
		"notes": "قیمت API به تومان است؛ price_irr = (price/divisor)*10",
	}
	mesghal_config = {
		"quote_unit": "IRT",
		"endpoint_path": "",
		"notes": "جایگاه آینده — هنوز پیاده‌سازی نشده",
	}
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
	op.bulk_insert(
		providers,
		[
			{
				"code": "brsapi",
				"display_name": "BRS API (brsapi.ir)",
				"api_base_url": "https://Api.BrsApi.ir",
				"api_key_encrypted": None,
				"is_active": True,
				"fetch_interval_seconds": 900,
				"config_json": json.dumps(brs_config, ensure_ascii=False),
				"created_at": now,
				"updated_at": now,
			},
			{
				"code": "mesghal",
				"display_name": "مثقال (به‌زودی)",
				"api_base_url": None,
				"api_key_encrypted": None,
				"is_active": False,
				"fetch_interval_seconds": 900,
				"config_json": json.dumps(mesghal_config, ensure_ascii=False),
				"created_at": now,
				"updated_at": now,
			},
		],
	)


def downgrade() -> None:
	op.drop_index("ix_fx_global_rates_fetched_at", table_name="fx_global_rates")
	op.drop_index("ix_fx_global_rates_currency_code", table_name="fx_global_rates")
	op.drop_index("ix_fx_global_rates_symbol", table_name="fx_global_rates")
	op.drop_index("ix_fx_global_rates_provider_id", table_name="fx_global_rates")
	op.drop_table("fx_global_rates")
	op.drop_index("ix_fx_rate_providers_code", table_name="fx_rate_providers")
	op.drop_table("fx_rate_providers")
