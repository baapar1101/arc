"""ثبت حسابداری خرید: تنظیم کسب‌وکار + حساب GRNI 10107

Revision ID: 20260622_000001_invoice_purchase_accounting_mode
Revises: 20260621_000002_merge_heads_backup_import_security_and_public_catalog_price_flag
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260622_000001_invoice_purchase_accounting_mode"
down_revision = "20260621_000002_merge_heads_backup_import_security_and_public_catalog_price_flag"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_purchase_accounting_mode",
			sa.String(length=40),
			nullable=False,
			server_default=sa.text("'direct_inventory'"),
			comment="direct_inventory | grni_two_step | grni_legacy",
		),
	)
	conn = op.get_bind()
	parent_id = conn.execute(
		sa.text("SELECT id FROM accounts WHERE business_id IS NULL AND code = '101' LIMIT 1")
	).scalar()
	if parent_id is None:
		raise RuntimeError("حساب والد 101 در accounts یافت نشد.")
	conn.execute(
		sa.text(
			"""
			INSERT INTO accounts (name, business_id, account_type, code, parent_id, created_at, updated_at)
			SELECT :name, NULL, 'accounting_document', :code, :pid, NOW(), NOW()
			WHERE NOT EXISTS (
				SELECT 1 FROM accounts WHERE business_id IS NULL AND code = :code
			)
			"""
		),
		{
			"name": "کالای خریداری‌شده در انتظار رسید انبار",
			"code": "10107",
			"pid": parent_id,
		},
	)
	# اسناد خرید قبلی: snapshot روش legacy تا ویرایش ناخواسته خطوط را عوض نکند
	if conn.dialect.name == "postgresql":
		conn.execute(
			sa.text(
				"""
				UPDATE documents
				SET extra_info = jsonb_set(
					COALESCE(extra_info::jsonb, '{}'::jsonb),
					'{purchase_accounting_mode}',
					'"grni_legacy"'::jsonb,
					true
				)::json
				WHERE document_type IN ('invoice_purchase', 'invoice_purchase_return')
				  AND (
					extra_info IS NULL
					OR extra_info::jsonb->>'purchase_accounting_mode' IS NULL
				  )
				"""
			)
		)


def downgrade() -> None:
	conn = op.get_bind()
	conn.execute(
		sa.text("DELETE FROM accounts WHERE business_id IS NULL AND code = '10107'")
	)
	op.drop_column("businesses", "invoice_purchase_accounting_mode")
