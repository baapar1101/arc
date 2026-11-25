"""سازمان، سهمیه، مدیر، صف سرنخ و مجوز رکورد CRM.

Revision ID: 20261110_000006_crm_enterprise
Revises: 20261110_000005_crm_person_stats
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000006_crm_enterprise"
down_revision = "20261110_000005_crm_person_stats"
branch_labels = None
depends_on = None


def _tables(inspector) -> set[str]:
    return set(inspector.get_table_names())


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = _tables(inspector)
    if "crm_organizations" not in tables:
        op.create_table(
            "crm_organizations",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
            sa.Column("name", sa.String(255), nullable=False),
            sa.Column("billing_person_id", sa.Integer(), sa.ForeignKey("persons.id", ondelete="RESTRICT"), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("business_id", "name", name="uq_crm_organizations_business_name"),
        )
    if "crm_organization_contacts" not in _tables(sa.inspect(conn)):
        op.create_table(
            "crm_organization_contacts",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("organization_id", sa.Integer(), sa.ForeignKey("crm_organizations.id", ondelete="CASCADE"), nullable=False),
            sa.Column("person_id", sa.Integer(), sa.ForeignKey("persons.id", ondelete="CASCADE"), nullable=False),
            sa.UniqueConstraint("organization_id", "person_id", name="uq_crm_org_contact"),
        )
    if "crm_quotas" not in _tables(sa.inspect(conn)):
        op.create_table(
            "crm_quotas",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("period_start", sa.Date(), nullable=False),
            sa.Column("period_end", sa.Date(), nullable=False),
            sa.Column("amount", sa.Numeric(18, 2), nullable=False),
            sa.Column("currency_id", sa.Integer(), sa.ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("business_id", "user_id", "period_start", "currency_id", name="uq_crm_quotas_period"),
        )
    if "crm_manager_links" not in _tables(sa.inspect(conn)):
        op.create_table(
            "crm_manager_links",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
            sa.Column("manager_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("member_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.UniqueConstraint("business_id", "member_user_id", name="uq_crm_manager_member"),
        )
    if "crm_lead_queues" not in _tables(sa.inspect(conn)):
        op.create_table(
            "crm_lead_queues",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
            sa.Column("name", sa.String(120), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("business_id", "name", name="uq_crm_lead_queues_name"),
        )
    if "crm_lead_queue_members" not in _tables(sa.inspect(conn)):
        op.create_table(
            "crm_lead_queue_members",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("queue_id", sa.Integer(), sa.ForeignKey("crm_lead_queues.id", ondelete="CASCADE"), nullable=False),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.UniqueConstraint("queue_id", "user_id", name="uq_crm_queue_member"),
        )
    if "crm_record_acl" not in _tables(sa.inspect(conn)):
        op.create_table(
            "crm_record_acl",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
            sa.Column("entity_type", sa.String(20), nullable=False),
            sa.Column("entity_id", sa.Integer(), nullable=False),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("access", sa.String(10), nullable=False, server_default="view"),
            sa.UniqueConstraint("business_id", "entity_type", "entity_id", "user_id", name="uq_crm_record_acl"),
        )
    inspector = sa.inspect(conn)
    if "business_crm_settings" in _tables(inspector):
        columns = {col["name"] for col in inspector.get_columns("business_crm_settings")}
        if "record_acl_enabled" not in columns:
            op.add_column("business_crm_settings", sa.Column("record_acl_enabled", sa.Boolean(), nullable=False, server_default=sa.false()))
    for table, column, fk in (
        ("crm_leads", "organization_id", "crm_organizations.id"),
        ("crm_leads", "queue_id", "crm_lead_queues.id"),
        ("crm_deals", "organization_id", "crm_organizations.id"),
    ):
        inspector = sa.inspect(conn)
        if table not in _tables(inspector):
            continue
        columns = {col["name"] for col in inspector.get_columns(table)}
        if column not in columns:
            op.add_column(table, sa.Column(column, sa.Integer(), sa.ForeignKey(fk, ondelete="SET NULL"), nullable=True))
    inspector = sa.inspect(conn)
    if "crm_deals" in _tables(inspector):
        columns = {col["name"] for col in inspector.get_columns("crm_deals")}
        if "forecast_category" not in columns:
            op.add_column("crm_deals", sa.Column("forecast_category", sa.String(20), nullable=True))


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if "crm_deals" in _tables(inspector) and "forecast_category" in {col["name"] for col in inspector.get_columns("crm_deals")}:
        op.drop_column("crm_deals", "forecast_category")
    for table, column in (("crm_deals", "organization_id"), ("crm_leads", "queue_id"), ("crm_leads", "organization_id")):
        inspector = sa.inspect(conn)
        if table in _tables(inspector) and column in {col["name"] for col in inspector.get_columns(table)}:
            op.drop_column(table, column)
    inspector = sa.inspect(conn)
    if "business_crm_settings" in _tables(inspector) and "record_acl_enabled" in {col["name"] for col in inspector.get_columns("business_crm_settings")}:
        op.drop_column("business_crm_settings", "record_acl_enabled")
    for table in ("crm_record_acl", "crm_lead_queue_members", "crm_lead_queues", "crm_manager_links", "crm_quotas", "crm_organization_contacts", "crm_organizations"):
        if table in _tables(sa.inspect(conn)):
            op.drop_table(table)
