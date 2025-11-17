from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision: str = "20250116_000001_add_storage_plans_and_subscriptions"
down_revision: Union[str, None] = "20251114_000010_add_business_print_settings"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
	bind = op.get_bind()
	inspector = sa.inspect(bind)
	tables = inspector.get_table_names()

	# ایجاد جدول storage_plans
	if "storage_plans" not in tables:
		op.create_table(
			"storage_plans",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("name", sa.String(length=200), nullable=False),
			sa.Column("code", sa.String(length=100), nullable=False),
			sa.Column("storage_limit_gb", sa.Numeric(10, 3), nullable=False),
			sa.Column("period", sa.String(length=20), nullable=False),  # monthly, yearly, lifetime
			sa.Column("period_months", sa.Integer(), nullable=True),
			sa.Column("price", sa.Numeric(18, 2), nullable=False, server_default="0"),
			sa.Column("price_per_gb", sa.Numeric(18, 2), nullable=True),
			sa.Column("is_free", sa.Boolean(), nullable=False, server_default=sa.text("0")),
			sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("1")),
			sa.Column("currency_id", sa.Integer(), sa.ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("description", sa.Text(), nullable=True),
			sa.Column("grace_period_days", sa.Integer(), nullable=False, server_default="30"),
			sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
			sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now(), onupdate=sa.func.now()),
			sa.UniqueConstraint("code", name="uq_storage_plans_code"),
			mysql_charset="utf8mb4",
		)
		op.create_index("ix_storage_plans_code", "storage_plans", ["code"])

	# ایجاد جدول business_storage_subscriptions
	if "business_storage_subscriptions" not in tables:
		op.create_table(
			"business_storage_subscriptions",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("plan_id", sa.Integer(), sa.ForeignKey("storage_plans.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("status", sa.String(length=20), nullable=False, server_default="active"),
			sa.Column("starts_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
			sa.Column("ends_at", sa.DateTime(), nullable=True),
			sa.Column("auto_renew", sa.Boolean(), nullable=False, server_default=sa.text("0")),
			sa.Column("grace_period_ends_at", sa.DateTime(), nullable=True),
			sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
			sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now(), onupdate=sa.func.now()),
			mysql_charset="utf8mb4",
		)
		op.create_index("ix_business_storage_subscriptions_business_id", "business_storage_subscriptions", ["business_id"])
		op.create_index("ix_business_storage_subscriptions_plan_id", "business_storage_subscriptions", ["plan_id"])

	# ایجاد جدول storage_invoices
	if "storage_invoices" not in tables:
		op.create_table(
			"storage_invoices",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("subscription_id", sa.Integer(), sa.ForeignKey("business_storage_subscriptions.id", ondelete="SET NULL"), nullable=True),
			sa.Column("code", sa.String(length=50), nullable=False),
			sa.Column("invoice_type", sa.String(length=20), nullable=False),  # subscription, over_usage, renewal
			sa.Column("total", sa.Numeric(18, 2), nullable=False, server_default="0"),
			sa.Column("currency_id", sa.Integer(), sa.ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("status", sa.String(length=20), nullable=False, server_default="issued"),
			sa.Column("issued_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
			sa.Column("paid_at", sa.DateTime(), nullable=True),
			sa.Column("wallet_transaction_id", sa.Integer(), sa.ForeignKey("wallet_transactions.id", ondelete="SET NULL"), nullable=True),
			sa.Column("extra_info", sa.JSON(), nullable=True),
			sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
			sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now(), onupdate=sa.func.now()),
			mysql_charset="utf8mb4",
		)
		op.create_index("ix_storage_invoices_business_id", "storage_invoices", ["business_id"])
		op.create_index("ix_storage_invoices_subscription_id", "storage_invoices", ["subscription_id"])
		op.create_index("ix_storage_invoices_code", "storage_invoices", ["code"])
		op.create_index("ix_storage_invoices_wallet_transaction_id", "storage_invoices", ["wallet_transaction_id"])

	# ایجاد جدول storage_usage_transactions
	if "storage_usage_transactions" not in tables:
		op.create_table(
			"storage_usage_transactions",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("file_storage_id", mysql.VARCHAR(length=36, charset='utf8mb4', collation='utf8mb4_general_ci'), sa.ForeignKey("file_storage.id", ondelete="SET NULL"), nullable=True),
			sa.Column("usage_gb", sa.Numeric(10, 6), nullable=False),
			sa.Column("transaction_type", sa.String(length=20), nullable=False),  # upload, delete
			sa.Column("subscription_id", sa.Integer(), sa.ForeignKey("business_storage_subscriptions.id", ondelete="SET NULL"), nullable=True),
			sa.Column("invoice_id", sa.Integer(), sa.ForeignKey("storage_invoices.id", ondelete="SET NULL"), nullable=True),
			sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
			mysql_charset="utf8mb4",
		)
		op.create_index("ix_storage_usage_transactions_business_id", "storage_usage_transactions", ["business_id"])
		op.create_index("ix_storage_usage_transactions_file_storage_id", "storage_usage_transactions", ["file_storage_id"])
		op.create_index("ix_storage_usage_transactions_subscription_id", "storage_usage_transactions", ["subscription_id"])
		op.create_index("ix_storage_usage_transactions_invoice_id", "storage_usage_transactions", ["invoice_id"])

	# اضافه کردن فیلدهای جدید به file_storage
	if "file_storage" in tables:
		columns = [col["name"] for col in inspector.get_columns("file_storage")]
		
		if "business_id" not in columns:
			op.add_column("file_storage", sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=True))
			op.create_index("ix_file_storage_business_id", "file_storage", ["business_id"])
		
		if "subscription_id" not in columns:
			op.add_column("file_storage", sa.Column("subscription_id", sa.Integer(), sa.ForeignKey("business_storage_subscriptions.id", ondelete="SET NULL"), nullable=True))
			op.create_index("ix_file_storage_subscription_id", "file_storage", ["subscription_id"])
		
		if "is_marked_for_deletion" not in columns:
			op.add_column("file_storage", sa.Column("is_marked_for_deletion", sa.Boolean(), nullable=False, server_default=sa.text("0")))
		
		if "marked_for_deletion_at" not in columns:
			op.add_column("file_storage", sa.Column("marked_for_deletion_at", sa.DateTime(timezone=True), nullable=True))

	# ایجاد پلن رایگان پیش‌فرض
	conn = op.get_bind()
	# بررسی اینکه آیا ارز IRR وجود دارد
	irr_currency = conn.execute(sa.text("SELECT id FROM currencies WHERE code = 'IRR' LIMIT 1")).fetchone()
	if irr_currency:
		currency_id = irr_currency[0]
		# بررسی اینکه آیا پلن رایگان قبلاً ایجاد شده
		existing = conn.execute(sa.text("SELECT id FROM storage_plans WHERE code = 'free_1gb_lifetime' LIMIT 1")).fetchone()
		if not existing:
			conn.execute(sa.text("""
				INSERT INTO storage_plans (name, code, storage_limit_gb, period, period_months, price, is_free, is_active, currency_id, description, grace_period_days, created_at, updated_at)
				VALUES ('پلن رایگان', 'free_1gb_lifetime', 1.0, 'lifetime', NULL, 0, 1, 1, :currency_id, 'پلن رایگان پیش‌فرض - 1 گیگابایت مادام‌العمر', 30, NOW(), NOW())
			"""), {"currency_id": currency_id})
			conn.commit()


def downgrade() -> None:
	# حذف فیلدهای اضافه شده به file_storage
	try:
		op.drop_index("ix_file_storage_subscription_id", table_name="file_storage")
		op.drop_column("file_storage", "subscription_id")
	except Exception:
		pass
	
	try:
		op.drop_index("ix_file_storage_business_id", table_name="file_storage")
		op.drop_column("file_storage", "business_id")
	except Exception:
		pass
	
	try:
		op.drop_column("file_storage", "marked_for_deletion_at")
	except Exception:
		pass
	
	try:
		op.drop_column("file_storage", "is_marked_for_deletion")
	except Exception:
		pass

	# حذف جداول
	try:
		op.drop_table("storage_usage_transactions")
	except Exception:
		pass
	
	try:
		op.drop_table("storage_invoices")
	except Exception:
		pass
	
	try:
		op.drop_table("business_storage_subscriptions")
	except Exception:
		pass
	
	try:
		op.drop_table("storage_plans")
	except Exception:
		pass

