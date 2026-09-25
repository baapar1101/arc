"""ارتقای بزرگ CRM: اتوماسیون فروش، وظایف، برچسب‌ها، خطوط معامله، توالی‌ها و ...

Revision ID: 20260731_000001_crm_sales_automation_upgrade
Revises: 20260727_000001_business_print_settings_tax_discount_display
Create Date: 2026-07-31
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260731_000001_crm_sales_automation_upgrade"
down_revision = "20260727_000001_business_print_settings_tax_discount_display"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # --- crm_activities: وظایف/پیگیری ---
    op.add_column("crm_activities", sa.Column("is_task", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    op.add_column("crm_activities", sa.Column("due_at", sa.DateTime(), nullable=True))
    op.add_column("crm_activities", sa.Column("status", sa.String(length=20), nullable=False, server_default=sa.text("'open'")))
    op.add_column("crm_activities", sa.Column("completed_at", sa.DateTime(), nullable=True))
    op.add_column("crm_activities", sa.Column("assigned_to_user_id", sa.Integer(), nullable=True))
    op.add_column("crm_activities", sa.Column("outcome", sa.String(length=100), nullable=True))
    op.add_column("crm_activities", sa.Column("priority", sa.String(length=20), nullable=False, server_default=sa.text("'normal'")))
    op.create_index("ix_crm_activities_due_at", "crm_activities", ["due_at"])
    op.create_index("ix_crm_activities_assigned_to_user_id", "crm_activities", ["assigned_to_user_id"])
    op.create_foreign_key(
        "fk_crm_activities_assigned_to_user",
        "crm_activities",
        "users",
        ["assigned_to_user_id"],
        ["id"],
        ondelete="SET NULL",
    )

    # --- crm_deals: دلایل برد/باخت ---
    op.add_column("crm_deals", sa.Column("won_reason_code", sa.String(length=50), nullable=True))
    op.add_column("crm_deals", sa.Column("lost_reason_code", sa.String(length=50), nullable=True))
    op.add_column("crm_deals", sa.Column("competitor_name", sa.String(length=255), nullable=True))
    op.add_column("crm_deals", sa.Column("stage_entered_at", sa.DateTime(), nullable=True))

    # --- crm_leads: امتیاز و SLA ---
    op.add_column("crm_leads", sa.Column("score", sa.Integer(), nullable=False, server_default=sa.text("0")))
    op.add_column("crm_leads", sa.Column("sla_due_at", sa.DateTime(), nullable=True))
    op.add_column("crm_leads", sa.Column("first_touched_at", sa.DateTime(), nullable=True))
    op.add_column("crm_leads", sa.Column("last_activity_at", sa.DateTime(), nullable=True))
    op.create_index("ix_crm_leads_sla_due_at", "crm_leads", ["sla_due_at"])

    # --- business_crm_settings: تنظیمات اتوماسیون ---
    op.add_column("business_crm_settings", sa.Column("lead_sla_hours", sa.Integer(), nullable=False, server_default=sa.text("24")))
    op.add_column("business_crm_settings", sa.Column("auto_assign_enabled", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    op.add_column("business_crm_settings", sa.Column("auto_assign_user_ids", sa.JSON(), nullable=True))
    op.add_column("business_crm_settings", sa.Column("auto_assign_cursor", sa.Integer(), nullable=False, server_default=sa.text("0")))
    op.add_column("business_crm_settings", sa.Column("follow_up_notify_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")))
    op.add_column("business_crm_settings", sa.Column("stale_deal_days", sa.Integer(), nullable=False, server_default=sa.text("14")))
    op.add_column("business_crm_settings", sa.Column("score_rules", sa.JSON(), nullable=True))

    # --- crm_close_reasons ---
    op.create_table(
        "crm_close_reasons",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("reason_type", sa.String(length=20), nullable=False),
        sa.Column("code", sa.String(length=50), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "reason_type", "code", name="uq_crm_close_reasons_business_type_code"),
    )
    op.create_index("ix_crm_close_reasons_business_id", "crm_close_reasons", ["business_id"])
    op.create_index("idx_crm_close_reasons_business_type", "crm_close_reasons", ["business_id", "reason_type"])

    # --- crm_deal_lines ---
    op.create_table(
        "crm_deal_lines",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("deal_id", sa.Integer(), nullable=False),
        sa.Column("product_id", sa.Integer(), nullable=True),
        sa.Column("description", sa.String(length=500), nullable=True),
        sa.Column("quantity", sa.Numeric(18, 4), nullable=False, server_default=sa.text("1")),
        sa.Column("unit_price", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
        sa.Column("discount_percent", sa.Numeric(8, 2), nullable=False, server_default=sa.text("0")),
        sa.Column("line_total", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["deal_id"], ["crm_deals.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_crm_deal_lines_business_id", "crm_deal_lines", ["business_id"])
    op.create_index("idx_crm_deal_lines_deal", "crm_deal_lines", ["deal_id"])
    op.create_index("ix_crm_deal_lines_product_id", "crm_deal_lines", ["product_id"])

    # --- crm_tags ---
    op.create_table(
        "crm_tags",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("color", sa.String(length=20), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "name", name="uq_crm_tags_business_name"),
    )
    op.create_index("ix_crm_tags_business_id", "crm_tags", ["business_id"])
    op.create_index("idx_crm_tags_business", "crm_tags", ["business_id"])

    op.create_table(
        "crm_lead_tag_links",
        sa.Column("lead_id", sa.Integer(), nullable=False),
        sa.Column("tag_id", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(["lead_id"], ["crm_leads.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tag_id"], ["crm_tags.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("lead_id", "tag_id"),
    )
    op.create_table(
        "crm_deal_tag_links",
        sa.Column("deal_id", sa.Integer(), nullable=False),
        sa.Column("tag_id", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(["deal_id"], ["crm_deals.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tag_id"], ["crm_tags.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("deal_id", "tag_id"),
    )

    # --- crm_custom_field_definitions ---
    op.create_table(
        "crm_custom_field_definitions",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("entity_type", sa.String(length=20), nullable=False),
        sa.Column("field_key", sa.String(length=80), nullable=False),
        sa.Column("label", sa.String(length=255), nullable=False),
        sa.Column("field_type", sa.String(length=20), nullable=False),
        sa.Column("options", sa.JSON(), nullable=True),
        sa.Column("is_required", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "entity_type", "field_key", name="uq_crm_custom_field_business_entity_key"),
    )
    op.create_index("ix_crm_custom_field_definitions_business_id", "crm_custom_field_definitions", ["business_id"])
    op.create_index("idx_crm_custom_field_business_entity", "crm_custom_field_definitions", ["business_id", "entity_type"])

    # --- crm_sequences ---
    op.create_table(
        "crm_sequences",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("created_by_user_id", sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_crm_sequences_business_id", "crm_sequences", ["business_id"])
    op.create_index("idx_crm_sequences_business", "crm_sequences", ["business_id"])
    op.create_index("ix_crm_sequences_created_by_user_id", "crm_sequences", ["created_by_user_id"])

    op.create_table(
        "crm_sequence_steps",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("sequence_id", sa.Integer(), nullable=False),
        sa.Column("step_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("delay_hours", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("action_type", sa.String(length=50), nullable=False),
        sa.Column("action_config", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["sequence_id"], ["crm_sequences.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_crm_sequence_steps_sequence_id", "crm_sequence_steps", ["sequence_id"])
    op.create_index("idx_crm_sequence_steps_seq", "crm_sequence_steps", ["sequence_id"])

    op.create_table(
        "crm_sequence_enrollments",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("sequence_id", sa.Integer(), nullable=False),
        sa.Column("entity_type", sa.String(length=20), nullable=False),
        sa.Column("entity_id", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False, server_default=sa.text("'active'")),
        sa.Column("current_step_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("next_run_at", sa.DateTime(), nullable=True),
        sa.Column("enrolled_at", sa.DateTime(), nullable=False),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sequence_id"], ["crm_sequences.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_crm_sequence_enrollments_business_id", "crm_sequence_enrollments", ["business_id"])
    op.create_index("ix_crm_sequence_enrollments_sequence_id", "crm_sequence_enrollments", ["sequence_id"])
    op.create_index("ix_crm_sequence_enrollments_next_run_at", "crm_sequence_enrollments", ["next_run_at"])
    op.create_index("idx_crm_seq_enroll_business", "crm_sequence_enrollments", ["business_id"])
    op.create_index("idx_crm_seq_enroll_entity", "crm_sequence_enrollments", ["business_id", "entity_type", "entity_id"])

    # --- crm_reminder_dedup ---
    op.create_table(
        "crm_reminder_dedup",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("entity_type", sa.String(length=20), nullable=False),
        sa.Column("entity_id", sa.Integer(), nullable=False),
        sa.Column("reminder_key", sa.String(length=80), nullable=False),
        sa.Column("sent_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "entity_type", "entity_id", "reminder_key", name="uq_crm_reminder_dedup_key"),
    )
    op.create_index("ix_crm_reminder_dedup_business_id", "crm_reminder_dedup", ["business_id"])
    op.create_index("idx_crm_reminder_dedup_business", "crm_reminder_dedup", ["business_id"])

    # --- seed رویدادهای نوتیفیکیشن CRM (اختیاری/در صورت وجود جدول) ---
    _seed_notification_event_types()


def _seed_notification_event_types() -> None:
    """درج کدهای رویداد یادآوری CRM در صورت وجود جدول notification_event_types."""
    conn = op.get_bind()
    insp = sa.inspect(conn)
    if "notification_event_types" not in insp.get_table_names():
        return

    import json

    rows = [
        {
            "code": "crm.follow_up_due",
            "name": "یادآوری پیگیری CRM",
            "description": "زمان پیگیری سرنخ یا فرصت فروش فرا رسیده است.",
            "category": "crm",
        },
        {
            "code": "crm.task_overdue",
            "name": "وظیفه CRM سررسید گذشته",
            "description": "یک وظیفه CRM از موعد گذشته و هنوز انجام نشده است.",
            "category": "crm",
        },
        {
            "code": "crm.lead_sla_breach",
            "name": "نقض SLA سرنخ",
            "description": "مهلت اولین تماس با سرنخ نقض شده است.",
            "category": "crm",
        },
        {
            "code": "crm.deal_stale",
            "name": "فرصت فروش راکد",
            "description": "فرصت فروش مدت طولانی در یک مرحله باقی مانده است.",
            "category": "crm",
        },
    ]
    variables = [
        {"key": "entity_type", "type": "string", "description": "نوع موجودیت (lead|deal|task)"},
        {"key": "entity_id", "type": "number", "description": "شناسه موجودیت"},
        {"key": "title", "type": "string", "description": "عنوان"},
        {"key": "message", "type": "string", "description": "متن پیام"},
        {"key": "business_id", "type": "number", "description": "شناسه کسب‌وکار"},
    ]
    for row in rows:
        conn.execute(
            sa.text(
                """
                INSERT INTO notification_event_types (
                    code, name, description, category, available_variables,
                    default_sms_template, default_email_template, default_email_subject,
                    is_active, requires_approval, created_at, updated_at
                ) VALUES (
                    :code, :name, :description, :category, CAST(:vars AS JSONB),
                    :dst, :det, :des,
                    true, false, NOW(), NOW()
                )
                ON CONFLICT (code) DO NOTHING
                """
            ),
            {
                "code": row["code"],
                "name": row["name"],
                "description": row["description"],
                "category": row["category"],
                "vars": json.dumps(variables, ensure_ascii=False),
                "dst": "{{ message }}",
                "det": "{{ message }}",
                "des": "{{ title }}",
            },
        )

    # قالب داخل‌برنامه‌ای فارسی ساده (در صورت وجود جدول قالب‌ها)
    if "notification_templates" not in insp.get_table_names():
        return
    template_cols = {c["name"] for c in insp.get_columns("notification_templates")}
    if not {"event_key", "channel", "locale", "body"}.issubset(template_cols):
        return
    has_subject = "subject" in template_cols
    for row in rows:
        params = {
            "event_key": row["code"],
            "channel": "inapp",
            "locale": "fa",
            "body": "{{ message }}",
        }
        cols = ["event_key", "channel", "locale", "body"]
        vals = [":event_key", ":channel", ":locale", ":body"]
        if has_subject:
            cols.append("subject")
            vals.append(":subject")
            params["subject"] = row["name"]
        if "created_at" in template_cols:
            cols.append("created_at")
            vals.append("NOW()")
        if "updated_at" in template_cols:
            cols.append("updated_at")
            vals.append("NOW()")
        try:
            conn.execute(
                sa.text(
                    f"INSERT INTO notification_templates ({', '.join(cols)}) "
                    f"VALUES ({', '.join(vals)}) ON CONFLICT DO NOTHING"
                ),
                params,
            )
        except Exception:
            # قالب اختیاری است؛ سرویس نوتیفیکیشن در نبود قالب هم کار می‌کند
            pass


def downgrade() -> None:
    op.drop_table("crm_reminder_dedup")
    op.drop_table("crm_sequence_enrollments")
    op.drop_table("crm_sequence_steps")
    op.drop_table("crm_sequences")
    op.drop_table("crm_custom_field_definitions")
    op.drop_table("crm_deal_tag_links")
    op.drop_table("crm_lead_tag_links")
    op.drop_table("crm_tags")
    op.drop_table("crm_deal_lines")
    op.drop_table("crm_close_reasons")

    for col in ("score_rules", "stale_deal_days", "follow_up_notify_enabled",
                "auto_assign_cursor", "auto_assign_user_ids", "auto_assign_enabled", "lead_sla_hours"):
        op.drop_column("business_crm_settings", col)

    op.drop_index("ix_crm_leads_sla_due_at", table_name="crm_leads")
    for col in ("last_activity_at", "first_touched_at", "sla_due_at", "score"):
        op.drop_column("crm_leads", col)

    for col in ("stage_entered_at", "competitor_name", "lost_reason_code", "won_reason_code"):
        op.drop_column("crm_deals", col)

    op.drop_constraint("fk_crm_activities_assigned_to_user", "crm_activities", type_="foreignkey")
    op.drop_index("ix_crm_activities_assigned_to_user_id", table_name="crm_activities")
    op.drop_index("ix_crm_activities_due_at", table_name="crm_activities")
    for col in ("priority", "outcome", "assigned_to_user_id", "completed_at", "status", "due_at", "is_task"):
        op.drop_column("crm_activities", col)

    # حذف رویدادهای نوتیفیکیشن CRM
    conn = op.get_bind()
    insp = sa.inspect(conn)
    if "notification_event_types" in insp.get_table_names():
        for code in ("crm.follow_up_due", "crm.task_overdue", "crm.lead_sla_breach", "crm.deal_stale"):
            conn.execute(sa.text("DELETE FROM notification_event_types WHERE code = :c"), {"c": code})
