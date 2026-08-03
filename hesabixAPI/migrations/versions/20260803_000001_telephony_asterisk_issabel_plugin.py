"""Telephony Asterisk/Issabel plugin tables

Revision ID: 20260803_000001_telephony_asterisk_issabel_plugin
Revises: 20260731_000001_crm_sales_automation_upgrade
Create Date: 2026-08-03
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260803_000001_telephony_asterisk_issabel_plugin"
down_revision = "20260731_000001_crm_sales_automation_upgrade"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"telephony_settings",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("primary_phone_fields", sa.JSON(), nullable=True),
		sa.Column("number_normalization_rules", sa.JSON(), nullable=True),
		sa.Column("screen_pop_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("auto_create_activity", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("post_call_form_required", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("default_category", sa.String(length=50), nullable=True),
		sa.Column("missed_call_create_task", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("missed_call_task_due_minutes", sa.Integer(), nullable=False, server_default="60"),
		sa.Column("recording_access_mode", sa.String(length=40), nullable=False, server_default="permission_based"),
		sa.Column("multi_pbx_enabled", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("ui_preferences", sa.JSON(), nullable=True),
		sa.Column("extra_settings", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", name="uq_telephony_settings_business"),
	)
	op.create_index("ix_telephony_settings_business_id", "telephony_settings", ["business_id"])

	op.create_table(
		"telephony_pbx_connections",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("name", sa.String(length=120), nullable=False),
		sa.Column("pbx_type", sa.String(length=40), nullable=False, server_default="issabel"),
		sa.Column("host_hint", sa.String(length=255), nullable=True),
		sa.Column("connector_token_hash", sa.String(length=128), nullable=False),
		sa.Column("connector_token_prefix", sa.String(length=24), nullable=True),
		sa.Column("connector_version", sa.String(length=40), nullable=True),
		sa.Column("last_seen_at", sa.DateTime(), nullable=True),
		sa.Column("status", sa.String(length=20), nullable=False, server_default="pending"),
		sa.Column("last_error", sa.Text(), nullable=True),
		sa.Column("settings", sa.JSON(), nullable=True),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_telephony_pbx_connections_business_id", "telephony_pbx_connections", ["business_id"])

	op.create_table(
		"telephony_extensions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("pbx_id", sa.Integer(), nullable=False),
		sa.Column("extension", sa.String(length=32), nullable=False),
		sa.Column("display_name", sa.String(length=120), nullable=True),
		sa.Column("queue_codes", sa.JSON(), nullable=True),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("presence_status", sa.String(length=20), nullable=False, server_default="unknown"),
		sa.Column("presence_updated_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["pbx_id"], ["telephony_pbx_connections.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("pbx_id", "extension", name="uq_telephony_extensions_pbx_ext"),
	)
	op.create_index("ix_telephony_extensions_business_id", "telephony_extensions", ["business_id"])
	op.create_index("ix_telephony_extensions_pbx_id", "telephony_extensions", ["pbx_id"])
	op.create_index("idx_telephony_extensions_business", "telephony_extensions", ["business_id"])

	op.create_table(
		"telephony_user_extensions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("pbx_id", sa.Integer(), nullable=False),
		sa.Column("extension_id", sa.Integer(), nullable=False),
		sa.Column("is_primary", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("receive_screen_pop", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("can_click_to_call", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("caller_id_override", sa.String(length=40), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["pbx_id"], ["telephony_pbx_connections.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["extension_id"], ["telephony_extensions.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "user_id", "extension_id", name="uq_telephony_user_ext_biz_user_ext"),
	)
	op.create_index("ix_telephony_user_extensions_business_id", "telephony_user_extensions", ["business_id"])
	op.create_index("ix_telephony_user_extensions_user_id", "telephony_user_extensions", ["user_id"])
	op.create_index("ix_telephony_user_extensions_pbx_id", "telephony_user_extensions", ["pbx_id"])
	op.create_index("ix_telephony_user_extensions_extension_id", "telephony_user_extensions", ["extension_id"])
	op.create_index("idx_telephony_user_ext_lookup", "telephony_user_extensions", ["business_id", "user_id"])

	op.create_table(
		"telephony_queues",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("pbx_id", sa.Integer(), nullable=False),
		sa.Column("queue_code", sa.String(length=64), nullable=False),
		sa.Column("name", sa.String(length=120), nullable=False),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("live_waiting_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("live_talking_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["pbx_id"], ["telephony_pbx_connections.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("pbx_id", "queue_code", name="uq_telephony_queues_pbx_code"),
	)
	op.create_index("ix_telephony_queues_business_id", "telephony_queues", ["business_id"])
	op.create_index("ix_telephony_queues_pbx_id", "telephony_queues", ["pbx_id"])

	op.create_table(
		"telephony_calls",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("pbx_id", sa.Integer(), nullable=False),
		sa.Column("asterisk_uniqueid", sa.String(length=64), nullable=False),
		sa.Column("asterisk_linkedid", sa.String(length=64), nullable=True),
		sa.Column("direction", sa.String(length=20), nullable=False),
		sa.Column("status", sa.String(length=20), nullable=False, server_default="ringing"),
		sa.Column("from_number_raw", sa.String(length=40), nullable=True),
		sa.Column("from_number_normalized", sa.String(length=40), nullable=True),
		sa.Column("to_number_raw", sa.String(length=40), nullable=True),
		sa.Column("to_number_normalized", sa.String(length=40), nullable=True),
		sa.Column("extension", sa.String(length=32), nullable=True),
		sa.Column("queue_code", sa.String(length=64), nullable=True),
		sa.Column("transferred_from", sa.String(length=40), nullable=True),
		sa.Column("transferred_to", sa.String(length=40), nullable=True),
		sa.Column("started_at", sa.DateTime(), nullable=False),
		sa.Column("answered_at", sa.DateTime(), nullable=True),
		sa.Column("ended_at", sa.DateTime(), nullable=True),
		sa.Column("duration_sec", sa.Integer(), nullable=True),
		sa.Column("talk_sec", sa.Integer(), nullable=True),
		sa.Column("hangup_cause", sa.String(length=80), nullable=True),
		sa.Column("recording_status", sa.String(length=20), nullable=False, server_default="none"),
		sa.Column("recording_file_storage_id", sa.Integer(), nullable=True),
		sa.Column("recording_remote_path", sa.String(length=512), nullable=True),
		sa.Column("recording_url", sa.String(length=1024), nullable=True),
		sa.Column("person_id", sa.Integer(), nullable=True),
		sa.Column("lead_id", sa.Integer(), nullable=True),
		sa.Column("deal_id", sa.Integer(), nullable=True),
		sa.Column("document_id", sa.Integer(), nullable=True),
		sa.Column("crm_activity_id", sa.Integer(), nullable=True),
		sa.Column("assigned_user_id", sa.Integer(), nullable=True),
		sa.Column("category", sa.String(length=50), nullable=True),
		sa.Column("outcome", sa.String(length=100), nullable=True),
		sa.Column("note", sa.Text(), nullable=True),
		sa.Column("match_method", sa.String(length=30), nullable=True),
		sa.Column("is_anonymous", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["pbx_id"], ["telephony_pbx_connections.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["recording_file_storage_id"], ["file_storage.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["lead_id"], ["crm_leads.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["deal_id"], ["crm_deals.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["crm_activity_id"], ["crm_activities.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["assigned_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("pbx_id", "asterisk_uniqueid", name="uq_telephony_calls_pbx_uniqueid"),
	)
	op.create_index("ix_telephony_calls_business_id", "telephony_calls", ["business_id"])
	op.create_index("ix_telephony_calls_pbx_id", "telephony_calls", ["pbx_id"])
	op.create_index("ix_telephony_calls_person_id", "telephony_calls", ["person_id"])
	op.create_index("ix_telephony_calls_lead_id", "telephony_calls", ["lead_id"])
	op.create_index("ix_telephony_calls_deal_id", "telephony_calls", ["deal_id"])
	op.create_index("ix_telephony_calls_assigned_user_id", "telephony_calls", ["assigned_user_id"])
	op.create_index("idx_telephony_calls_business_started", "telephony_calls", ["business_id", "started_at"])
	op.create_index("idx_telephony_calls_from_norm", "telephony_calls", ["business_id", "from_number_normalized"])
	op.create_index("idx_telephony_calls_to_norm", "telephony_calls", ["business_id", "to_number_normalized"])
	op.create_index(
		"idx_telephony_calls_assigned", "telephony_calls", ["business_id", "assigned_user_id", "started_at"]
	)

	op.create_table(
		"telephony_call_events",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("pbx_id", sa.Integer(), nullable=False),
		sa.Column("call_id", sa.Integer(), nullable=True),
		sa.Column("event_id", sa.String(length=64), nullable=False),
		sa.Column("event_type", sa.String(length=40), nullable=False),
		sa.Column("payload", sa.JSON(), nullable=True),
		sa.Column("occurred_at", sa.DateTime(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["pbx_id"], ["telephony_pbx_connections.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["call_id"], ["telephony_calls.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("pbx_id", "event_id", name="uq_telephony_call_events_pbx_event"),
	)
	op.create_index("ix_telephony_call_events_business_id", "telephony_call_events", ["business_id"])
	op.create_index("ix_telephony_call_events_pbx_id", "telephony_call_events", ["pbx_id"])
	op.create_index("ix_telephony_call_events_call_id", "telephony_call_events", ["call_id"])
	op.create_index("idx_telephony_call_events_call", "telephony_call_events", ["call_id", "occurred_at"])

	op.create_table(
		"telephony_commands",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("pbx_id", sa.Integer(), nullable=False),
		sa.Column("command_id", sa.String(length=64), nullable=False),
		sa.Column("command_type", sa.String(length=40), nullable=False),
		sa.Column("payload", sa.JSON(), nullable=False),
		sa.Column("status", sa.String(length=20), nullable=False, server_default="pending"),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("call_id", sa.Integer(), nullable=True),
		sa.Column("result_payload", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("acked_at", sa.DateTime(), nullable=True),
		sa.Column("expires_at", sa.DateTime(), nullable=True),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["pbx_id"], ["telephony_pbx_connections.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["call_id"], ["telephony_calls.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("command_id"),
	)
	op.create_index("ix_telephony_commands_business_id", "telephony_commands", ["business_id"])
	op.create_index("ix_telephony_commands_pbx_id", "telephony_commands", ["pbx_id"])
	op.create_index("idx_telephony_commands_poll", "telephony_commands", ["pbx_id", "status", "created_at"])

	op.create_table(
		"telephony_number_aliases",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("number_normalized", sa.String(length=40), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=True),
		sa.Column("lead_id", sa.Integer(), nullable=True),
		sa.Column("note", sa.String(length=255), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["lead_id"], ["crm_leads.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "number_normalized", name="uq_telephony_alias_biz_number"),
	)
	op.create_index("ix_telephony_number_aliases_business_id", "telephony_number_aliases", ["business_id"])

	op.add_column("crm_activities", sa.Column("telephony_call_id", sa.Integer(), nullable=True))
	op.create_index("ix_crm_activities_telephony_call_id", "crm_activities", ["telephony_call_id"])
	op.create_foreign_key(
		"fk_crm_activities_telephony_call_id",
		"crm_activities",
		"telephony_calls",
		["telephony_call_id"],
		["id"],
		ondelete="SET NULL",
	)


def downgrade() -> None:
	op.drop_constraint("fk_crm_activities_telephony_call_id", "crm_activities", type_="foreignkey")
	op.drop_index("ix_crm_activities_telephony_call_id", table_name="crm_activities")
	op.drop_column("crm_activities", "telephony_call_id")

	op.drop_table("telephony_number_aliases")
	op.drop_table("telephony_commands")
	op.drop_table("telephony_call_events")
	op.drop_table("telephony_calls")
	op.drop_table("telephony_queues")
	op.drop_table("telephony_user_extensions")
	op.drop_table("telephony_extensions")
	op.drop_table("telephony_pbx_connections")
	op.drop_table("telephony_settings")
