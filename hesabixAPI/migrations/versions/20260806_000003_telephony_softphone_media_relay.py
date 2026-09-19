"""Softphone media relay: sessions + endpoint_mode

Revision ID: 20260806_000003_telephony_softphone_media_relay
Revises: 20260806_000002_barcode_label_printer_settings
Create Date: 2026-08-06
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260806_000003_telephony_softphone_media_relay"
down_revision = "20260806_000002_barcode_label_printer_settings"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"telephony_user_extensions",
		sa.Column(
			"endpoint_mode",
			sa.String(length=20),
			nullable=False,
			server_default="desk",
			comment="relay | direct | desk",
		),
	)
	op.add_column(
		"telephony_user_extensions",
		sa.Column(
			"allow_mode_fallback",
			sa.Boolean(),
			nullable=False,
			server_default="1",
		),
	)
	op.add_column(
		"telephony_user_extensions",
		sa.Column("direct_sip_user", sa.String(length=80), nullable=True),
	)

	op.create_table(
		"telephony_softphone_sessions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("session_id", sa.String(length=36), nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("pbx_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("extension", sa.String(length=32), nullable=False),
		sa.Column(
			"mode",
			sa.String(length=20),
			nullable=False,
			server_default="relay",
			comment="relay | direct",
		),
		sa.Column(
			"state",
			sa.String(length=30),
			nullable=False,
			server_default="creating",
			comment="creating | registered | ringing | in_call | ended | failed",
		),
		sa.Column("media_ticket_hash", sa.String(length=128), nullable=False),
		sa.Column("media_ticket_prefix", sa.String(length=16), nullable=True),
		sa.Column("media_edge_node", sa.String(length=80), nullable=True),
		sa.Column("connector_tunnel_id", sa.String(length=64), nullable=True),
		sa.Column("call_id", sa.Integer(), nullable=True),
		sa.Column("ice_policy", sa.String(length=40), nullable=True),
		sa.Column("turn_used", sa.Boolean(), nullable=False, server_default="0"),
		sa.Column("last_quality_json", sa.JSON(), nullable=True),
		sa.Column("client_info", sa.JSON(), nullable=True),
		sa.Column("last_heartbeat_at", sa.DateTime(), nullable=True),
		sa.Column("expires_at", sa.DateTime(), nullable=False),
		sa.Column("ended_at", sa.DateTime(), nullable=True),
		sa.Column("end_reason", sa.String(length=120), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["pbx_id"], ["telephony_pbx_connections.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["call_id"], ["telephony_calls.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("session_id", name="uq_telephony_softphone_sessions_sid"),
	)
	op.create_index(
		"idx_telephony_softphone_sessions_biz_user",
		"telephony_softphone_sessions",
		["business_id", "user_id"],
	)
	op.create_index(
		"idx_telephony_softphone_sessions_pbx_state",
		"telephony_softphone_sessions",
		["pbx_id", "state"],
	)
	op.create_index(
		"idx_telephony_softphone_sessions_expires",
		"telephony_softphone_sessions",
		["expires_at"],
	)


def downgrade() -> None:
	op.drop_index("idx_telephony_softphone_sessions_expires", table_name="telephony_softphone_sessions")
	op.drop_index("idx_telephony_softphone_sessions_pbx_state", table_name="telephony_softphone_sessions")
	op.drop_index("idx_telephony_softphone_sessions_biz_user", table_name="telephony_softphone_sessions")
	op.drop_table("telephony_softphone_sessions")
	op.drop_column("telephony_user_extensions", "direct_sip_user")
	op.drop_column("telephony_user_extensions", "allow_mode_fallback")
	op.drop_column("telephony_user_extensions", "endpoint_mode")
